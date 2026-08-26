import AnchrKit
import Foundation

/// Lets a GUI test hand the app a starting list.
///
/// The app writes the fixture itself because the XCUITest runner is sandboxed: it can
/// name a directory outside its container but never create one. Inert unless
/// `ANCHR_E2E_SEED_LIST` is set, so a normal launch never reaches this code.
public enum E2EFixture {
    public static let seedVariable = "ANCHR_E2E_SEED_LIST"
    public static let seedSlug = "seed"

    @discardableResult
    public static func seedIfRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        root: URL = AppSupportRoot.url
    ) -> Bool {
        guard let markdown = environment[seedVariable], !markdown.isEmpty else { return false }

        let listDirectory = root
            .appendingPathComponent("lists", isDirectory: true)
            .appendingPathComponent(seedSlug, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: listDirectory,
                withIntermediateDirectories: true
            )
            try Data(markdown.utf8).write(to: listDirectory.appendingPathComponent("list.md"))
            try Data("Seed list".utf8).write(to: listDirectory.appendingPathComponent("name.txt"))
            try Data(Data()).write(to: listDirectory.appendingPathComponent("context.md"))

            let state = AppState(
                activeListSlug: seedSlug,
                anchorIndex: 0,
                snoozeDeadline: nil
            )
            let encoded = try JSONEncoder().encode(state)
            try encoded.write(to: root.appendingPathComponent("state.json"))
            return true
        } catch {
            return false
        }
    }
}
