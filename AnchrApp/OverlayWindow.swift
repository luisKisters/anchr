import AnchrCore
import AnchrKit
import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let window: NSWindow
    private let model: OverlayFlowModel
    private var modeObserver: AnyCancellable?

    init() {
        let window = KeyableOverlayWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        self.window = window
        model = OverlayFlowModel()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        // Fill, explicitly. A hosting controller sizes its window to the fitting size of
        // its content, so switching from the list to the much smaller intervention card
        // made AppKit shrink a full-screen window down to the card — the backdrop stopped
        // covering the screen and the card ended up pinned in the corner.
        window.contentViewController = NSHostingController(
            rootView: OverlayFlowView(model: model, snapshotMode: false) { [weak self] in
                self?.hide()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )

        applyLevel(for: model.mode)
        modeObserver = model.$mode.sink { [weak self] mode in
            self?.applyLevel(for: mode)
            self?.fillScreen()
            // Which screen is on top, and when. Every UI report so far has come down to
            // "it opened, but showed the wrong thing", and the log had nothing to say.
            Log.write("overlay mode=\(String(describing: mode))")
        }
    }

    var isVisible: Bool {
        window.isVisible
    }

    /// The overlay normally floats above everything, which is the point of it. The one
    /// exception is a missing Accessibility grant: macOS draws its permission dialog below
    /// `.screenSaver`, so at that level Anchr hides the very dialog it is asking the user
    /// to approve, and the app becomes impossible to grant.
    ///
    /// Keyed on the permission, not on the screen being shown. Tying it to the onboarding
    /// screen was wrong: a user who already has a list starts in `.list`, and the dialog
    /// stayed hidden behind it.
    private func applyLevel(for _: OverlayMode) {
        window.level = AccessibilityPermission.currentStatus == .granted ? .screenSaver : .normal
    }

    private func fillScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        guard window.frame != screen.frame else { return }
        window.setFrame(screen.frame, display: true)
    }

    func show() {
        fillScreen()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Log.write("overlay shown mode=\(String(describing: model.mode))")
    }

    func hide() {
        // Before the Accessibility grant exists the global hotkey cannot work — macOS
        // refuses the event monitor — so dismissing an unfinished onboarding would lock
        // the user out of their own app with no way back in.
        guard model.canDismiss else {
            Log.write("overlay dismiss refused mode=\(String(describing: model.mode))")
            return
        }
        window.orderOut(nil)
        NSApplication.shared.hide(nil)
        Log.write("overlay hidden")
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    var onInterventionAnswer: ((InterventionPolicy.Answer) -> Void)? {
        get { model.onInterventionAnswer }
        set { model.onInterventionAnswer = newValue }
    }

    func accessibilityDidBecomeGranted() {
        applyLevel(for: model.mode)
        model.accessibilityDidBecomeGranted()
    }

    func showIntervention(_ verdict: Verdict) {
        Log.write("overlay intervention requested verdict=\(verdict.verdict)")
        // Mode first, then show. The other order put the list on screen for a moment
        // before the card replaced it, which is what "it opened with my to-do list
        // instead of an intervention" was.
        withAnimation(.easeOut(duration: 0.42)) {
            model.showIntervention(verdict)
        }
        show()
    }
}

/// A borderless `NSWindow` answers `false` to `canBecomeKey`, so it never receives a
/// key press — the whole overlay is keyboard-driven, so without this override every
/// binding is dead. Found by `ListOverlayUITests`, which is exactly the class of bug a
/// unit test over the reducer cannot see.
final class KeyableOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
