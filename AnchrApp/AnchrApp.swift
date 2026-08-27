import AnchrCore
import AnchrKit
import AppKit
import Darwin
import SwiftUI

@main
struct AnchrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        guard let snapshot = DesignSnapshotRequest.current else { return }
        do {
            try DesignSnapshotRenderer.render(snapshot)
            Darwin.exit(EXIT_SUCCESS)
        } catch {
            fputs("design snapshot failed: \(error)\n", stderr)
            Darwin.exit(EXIT_FAILURE)
        }
    }

    var body: some Scene {
        MenuBarExtra("Anchr", systemImage: "circle.fill") {
            Button("Show List") {
                appDelegate.showOverlay()
            }
            .keyboardShortcut(" ", modifiers: [.option])

            Button(appDelegate.isPaused ? "Resume" : "Pause") {
                appDelegate.togglePaused()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var isPaused = false

    private var overlayController: OverlayWindowController?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var inputMonitor: Any?
    private var observationLoop: ObservationLoop?
    private var checkTimer: Timer?
    private var permissionTimer: Timer?
    private var lastCheckError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        E2EFixture.seedIfRequested()

        // Ask on the first launch that is not trusted. Without this the app never
        // appears in the Accessibility list, so there is nothing for the user to switch
        // on — and the global hotkey, which needs the grant, stays silent forever.
        if AccessibilityPermission.currentStatus != .granted {
            AccessibilityPermission.request()
        }

        overlayController = OverlayWindowController()
        installGlobalHotKey()
        startObservationLoop()
        watchAccessibilityGrant()

        Log.write(
            "launch accessibility=\(AccessibilityPermission.currentStatus) "
                + "key=\(OpenRouterKey.load() == nil ? "missing" : "present")"
        )

        // Open at launch only while setup is unfinished. A first run must not wait for a
        // hotkey that needs a permission nobody has granted yet — but once there is a
        // list, an overlay that appears by itself is indistinguishable from an
        // intervention, and every later launch would read as a false alarm.
        //
        // The override exists because XCUITest cannot press a system-wide hotkey. Without
        // it the GUI suite only sees the overlay by accident, through its own unconfigured
        // fixture profile — passing for a reason that has nothing to do with the test.
        let forceOverlay = ProcessInfo.processInfo.environment["ANCHR_E2E_SHOW_OVERLAY"] == "1"
        if forceOverlay || !OverlayFlowModel.isSetUp {
            showOverlay()
        }
    }

    /// The Accessibility grant arrives minutes after launch, in System Settings, with no
    /// notification to the app. Polling is the only way to notice — and until it is
    /// noticed, the AX observers are not installed, so nothing is ever observed.
    private func watchAccessibilityGrant() {
        guard AccessibilityPermission.currentStatus != .granted else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard AccessibilityPermission.currentStatus == .granted else { return }
                self?.permissionTimer?.invalidate()
                self?.permissionTimer = nil
                Log.write("accessibility granted; restarting the observation loop")
                // Restart: the AX observers bail out early when untrusted, so the loop
                // started at launch is watching nothing.
                self?.observationLoop?.stop()
                self?.observationLoop?.start()
                self?.overlayController?.accessibilityDidBecomeGranted()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let inputMonitor {
            NSEvent.removeMonitor(inputMonitor)
        }
        checkTimer?.invalidate()
        permissionTimer?.invalidate()
        observationLoop?.stop()
    }

    func showOverlay() {
        guard !isPaused else { return }
        overlayController?.show()
    }

    func togglePaused() {
        isPaused.toggle()
        if isPaused {
            overlayController?.hide()
            observationLoop?.stop()
        } else {
            observationLoop?.start()
        }
    }

    private func installGlobalHotKey() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isOverlayShortcut(event) else { return }
            Task { @MainActor in
                self?.toggleOverlay()
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isOverlayShortcut(event) else { return event }
            self?.toggleOverlay()
            return nil
        }
    }

    private func startObservationLoop() {
        // No key yet means onboarding has not finished. The menu bar, the list and the
        // overlay all still work; only the judging is off, which is better than a crash.
        guard let classifier = try? OpenRouterClassifier() else {
            Log.write("observation loop off: no OpenRouter key")
            return
        }
        let loop = ObservationLoop(
            clock: SystemObservationClock(),
            focusSource: FocusContextMonitor(),
            snapshotter: DelayedAXSnapshotReader(),
            classifier: classifier,
            store: ListStore(rootURL: AppSupportRoot.url)
        ) { [weak self] verdict in
            self?.overlayController?.showIntervention(verdict)
        }
        observationLoop = loop
        overlayController?.onInterventionAnswer = { [weak loop] answer in
            loop?.recordInterventionAnswer(answer)
        }
        loop.start()
        loop.recordUserInput()

        let events: NSEvent.EventTypeMask = [
            .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .mouseMoved, .scrollWheel,
        ]
        inputMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            Task { @MainActor in self?.observationLoop?.recordUserInput() }
        }
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPaused, let loop = self.observationLoop else { return }
                do {
                    _ = try await loop.checkIfDue()
                } catch {
                    // Without the grant this throws once a second forever, and the log
                    // becomes unreadable exactly when someone needs to read it.
                    let description = "\(error)"
                    if description != self.lastCheckError {
                        self.lastCheckError = description
                        Log.write("check failed: \(description)")
                    }
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.observationLoop?.recordAnchrFrontmost(isFrontmost: true) }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.observationLoop?.recordAnchrFrontmost(isFrontmost: false) }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.observationLoop?.recordScreenLock(isLocked: true) }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.observationLoop?.recordScreenLock(isLocked: false) }
        }
    }

    private func toggleOverlay() {
        guard !isPaused else { return }
        overlayController?.toggle()
    }

    nonisolated private static func isOverlayShortcut(_ event: NSEvent) -> Bool {
        event.keyCode == 49 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
    }
}
