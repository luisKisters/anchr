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

    func applicationDidFinishLaunching(_ notification: Notification) {
        E2EFixture.seedIfRequested()
        overlayController = OverlayWindowController()
        installGlobalHotKey()
        startObservationLoop()

        // XCUITest cannot press a system-wide hotkey, so the UI tests ask for the
        // overlay at launch instead. Nothing else about the app changes.
        if ProcessInfo.processInfo.environment["ANCHR_E2E_SHOW_OVERLAY"] == "1" {
            showOverlay()
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
        guard let classifier = try? OpenRouterClassifier() else { return }
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
                    fputs("observation check failed: \(error)\n", stderr)
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
