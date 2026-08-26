import AnchrKit
import Foundation

/// Where the OpenRouter key comes from, and where it must never come from.
///
/// Deliberately not the Keychain in V1: Anchr is ad-hoc signed, so its code identity
/// changes on every rebuild and macOS would raise a keychain dialog mid-run. A dialog
/// nobody is there to answer is worse than a 0600 file. Moving to the Keychain is a
/// post-V1 task, once the app is signed with a stable identity.
public enum OpenRouterKey {
    public static let environmentVariable = "OPENROUTER_API_KEY"

    /// `~/Library/Application Support/Anchr/openrouter-key`, written 0600 by onboarding.
    public static var fileURL: URL {
        applicationSupportDirectory.appendingPathComponent("openrouter-key", isDirectory: false)
    }

    public static var configuredModel: String {
        ProcessInfo.processInfo.environment["ANCHR_OPENROUTER_MODEL"]
            ?? OpenRouterRequest.defaultModel
    }

    /// Environment first, so a test or a script can override without touching the file
    /// the real app reads.
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileURL: URL? = nil
    ) -> String? {
        if let fromEnvironment = environment[environmentVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !fromEnvironment.isEmpty
        {
            return fromEnvironment
        }

        let url = fileURL ?? self.fileURL
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Used by onboarding. Writes 0600 and never logs the value.
    public static func store(_ key: String, at fileURL: URL? = nil) throws {
        let url = fileURL ?? self.fileURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
            .write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static var applicationSupportDirectory: URL { AppSupportRoot.url }
}
