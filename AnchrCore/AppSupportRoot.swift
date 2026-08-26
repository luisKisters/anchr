import Foundation

/// The single place that answers "where does Anchr keep its files".
///
/// `ANCHR_E2E_APP_SUPPORT_ROOT` redirects everything into a temporary directory. The
/// UI tests set it through `XCUIApplication.launchEnvironment`, which is how a GUI
/// test run can never touch the real list you depend on.
public enum AppSupportRoot {
    public static let environmentVariable = "ANCHR_E2E_APP_SUPPORT_ROOT"

    public static var url: URL {
        resolve(environment: ProcessInfo.processInfo.environment)
    }

    public static func resolve(environment: [String: String]) -> URL {
        if let override = environment[environmentVariable], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Anchr", isDirectory: true)
    }
}
