import AppKit
import ApplicationServices
import Foundation

public enum AccessibilityPermission {
    public enum Status: Equatable, Sendable {
        case granted
        case notGranted
    }

    public static let systemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    public static var currentStatus: Status {
        status(isTrusted: AXIsProcessTrusted())
    }

    public static func status(isTrusted: Bool) -> Status {
        isTrusted ? .granted : .notGranted
    }

    /// Asks macOS for the grant.
    ///
    /// This is the only call that puts Anchr into the Accessibility list. A bare
    /// `AXIsProcessTrusted()` reads the answer but never registers the app, so a user
    /// who opens System Settings finds nothing to switch on. Prompting once at launch
    /// is what makes the row appear.
    @discardableResult
    public static func request() -> Status {
        // The literal, not `kAXTrustedCheckOptionPrompt`: the imported symbol is a
        // mutable global, which Swift 6 rejects as not concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": true]
        return status(isTrusted: AXIsProcessTrustedWithOptions(options as CFDictionary))
    }

    @MainActor
    @discardableResult
    public static func openSystemSettings() -> Bool {
        NSWorkspace.shared.open(systemSettingsURL)
    }
}
