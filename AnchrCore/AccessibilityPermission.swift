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

    @MainActor
    @discardableResult
    public static func openSystemSettings() -> Bool {
        NSWorkspace.shared.open(systemSettingsURL)
    }
}
