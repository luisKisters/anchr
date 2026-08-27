import AppKit
import ApplicationServices
import Foundation

public struct FocusContext: Equatable, Sendable {
    public let bundleIdentifier: String
    public let processIdentifier: Int32
    public let windowTitle: String?

    /// The address of the page in front, when the front window is a browser.
    ///
    /// Worth its own field rather than being buried in the flattened text: `youtube.com`
    /// is a far sharper signal than three thousand characters of navigation chrome, and
    /// it changes on every page switch — including in single-page apps, where the
    /// surrounding text does not change at all.
    public let url: String?

    public init(
        bundleIdentifier: String,
        processIdentifier: Int32,
        windowTitle: String?,
        url: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.windowTitle = windowTitle
        self.url = url
    }
}

@MainActor
public protocol FocusContextSource: AnyObject {
    func start(handler: @escaping (FocusContext) -> Void)
    func stop()
}

@MainActor
final class FocusContextRelay: FocusContextSource {
    private var handler: ((FocusContext) -> Void)?
    private var lastContext: FocusContext?

    func start(handler: @escaping (FocusContext) -> Void) {
        self.handler = handler
    }

    func stop() {
        handler = nil
    }

    func publish(_ context: FocusContext) {
        guard context != lastContext else { return }
        lastContext = context
        handler?(context)
    }
}

@MainActor
public final class FocusContextMonitor: NSObject, FocusContextSource {
    private let workspace: NSWorkspace
    private let relay = FocusContextRelay()
    private var observer: AXObserver?
    private var observedApplication: NSRunningApplication?
    private var observedWindow: AXUIElement?
    private var isStarted = false

    public override convenience init() {
        self.init(workspace: .shared)
    }

    init(workspace: NSWorkspace) {
        self.workspace = workspace
        super.init()
    }

    public func start(handler: @escaping (FocusContext) -> Void) {
        relay.start(handler: handler)
        guard !isStarted else { return }
        isStarted = true
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        if let application = workspace.frontmostApplication {
            observe(application)
        }
    }

    public func stop() {
        relay.stop()
        guard isStarted else { return }
        isStarted = false
        workspace.notificationCenter.removeObserver(self)
        removeAccessibilityObserver()
        observedApplication = nil
    }

    @objc
    private func applicationDidActivate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        else { return }
        observe(application)
    }

    private func observe(_ application: NSRunningApplication) {
        observedApplication = application
        installAccessibilityObserver(processIdentifier: application.processIdentifier)
        publishCurrentContext()
    }

    fileprivate func accessibilityValueDidChange() {
        guard let application = observedApplication else { return }
        installWindowTitleObservation(processIdentifier: application.processIdentifier)
        publishCurrentContext()
    }

    private func publishCurrentContext() {
        guard let application = observedApplication else { return }
        relay.publish(FocusContext(
            bundleIdentifier: application.bundleIdentifier ?? application.localizedName ?? "unknown",
            processIdentifier: application.processIdentifier,
            windowTitle: focusedWindowTitle(processIdentifier: application.processIdentifier),
            url: BrowserURL.read(processIdentifier: application.processIdentifier)
        ))
    }

    private func installAccessibilityObserver(processIdentifier: Int32) {
        removeAccessibilityObserver()
        guard AccessibilityPermission.currentStatus == .granted else { return }

        var newObserver: AXObserver?
        guard AXObserverCreate(
            processIdentifier,
            focusContextObserverCallback,
            &newObserver
        ) == .success, let newObserver else { return }

        observer = newObserver
        let application = AXUIElementCreateApplication(processIdentifier)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        _ = AXObserverAddNotification(
            newObserver,
            application,
            kAXFocusedWindowChangedNotification as CFString,
            refcon
        )
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .defaultMode
        )
        installWindowTitleObservation(processIdentifier: processIdentifier)
    }

    private func installWindowTitleObservation(processIdentifier: Int32) {
        guard let observer else { return }
        if let observedWindow {
            _ = AXObserverRemoveNotification(
                observer,
                observedWindow,
                kAXTitleChangedNotification as CFString
            )
        }
        observedWindow = focusedWindow(processIdentifier: processIdentifier)
        if let observedWindow {
            _ = AXObserverAddNotification(
                observer,
                observedWindow,
                kAXTitleChangedNotification as CFString,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }

    private func removeAccessibilityObserver() {
        guard let observer else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        self.observer = nil
        observedWindow = nil
    }

    private func focusedWindow(processIdentifier: Int32) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &value
        ) == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private func focusedWindowTitle(processIdentifier: Int32) -> String? {
        guard let window = focusedWindow(processIdentifier: processIdentifier) else {
            return nil
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXTitleAttribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? String
    }
}

private func focusContextObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let monitor = Unmanaged<FocusContextMonitor>.fromOpaque(refcon).takeUnretainedValue()
    Task { @MainActor in
        monitor.accessibilityValueDidChange()
    }
}
