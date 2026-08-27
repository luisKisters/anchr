import Foundation

/// A small append-only log next to the lists.
///
/// The app is a menu bar process launched by Finder, so `stderr` goes nowhere a user can
/// find. Without a file on disk there is no way to answer the only question that matters
/// when Anchr stays silent: did it look, what did it see, and what did the model say.
///
/// It records decisions, never content: bundle identifiers, character counts and
/// verdicts. The window text itself and the API key never reach it.
public enum Log {
    public static var fileURL: URL {
        AppSupportRoot.url.appendingPathComponent("anchr.log")
    }

    private static let queue = DispatchQueue(label: "com.anchr.log")
    // Only ever touched inside `queue`, which is what makes the unchecked annotation
    // true rather than convenient.
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func write(_ message: String) {
        let date = Date()
        queue.async {
            let line = "\(formatter.string(from: date)) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            let url = fileURL
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
