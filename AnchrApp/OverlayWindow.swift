import AnchrKit
import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let window: NSWindow
    private let model: OverlayFlowModel

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
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        window.contentViewController = NSHostingController(
            rootView: OverlayFlowView(model: model, snapshotMode: false) { [weak window] in
                window?.orderOut(nil)
            }
        )
    }

    var isVisible: Bool {
        window.isVisible
    }

    func show() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        window.setFrame(screen.frame, display: true)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
        NSApplication.shared.hide(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func showIntervention(_ verdict: Verdict) {
        show()
        withAnimation(.easeOut(duration: 0.42)) {
            model.showIntervention(verdict)
        }
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
