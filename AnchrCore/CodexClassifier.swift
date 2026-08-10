import Foundation
import AnchrKit

public actor CodexClassifier: DriftClassifier {
    public enum Error: Swift.Error, Equatable {
        case launchFailed(String)
        case nonZeroExit(Int32)
        case timedOut
        case missingOutput
        case invalidOutput
    }

    private let executableURL: URL
    private let executableArgumentsPrefix: [String]
    private let timeout: TimeInterval

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        executableArgumentsPrefix: [String] = ["codex"],
        timeout: TimeInterval = 30
    ) {
        self.executableURL = executableURL
        self.executableArgumentsPrefix = executableArgumentsPrefix
        self.timeout = timeout
    }

    public func classify(_ observation: Observation) async throws -> Verdict {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("AnchrCodex-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let schemaURL = directory.appendingPathComponent("schema.json")
        let outputURL = directory.appendingPathComponent("verdict.json")
        try ObservationPrompt.jsonSchema.write(to: schemaURL, options: .atomic)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = executableArgumentsPrefix + [
            "exec",
            "--ephemeral",
            "--skip-git-repo-check",
            "-s", "read-only",
            "-c", "model_reasoning_effort=low",
            "--output-schema", schemaURL.path,
            "-o", outputURL.path,
            ObservationPrompt.text(for: observation),
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw Error.launchFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                process.waitUntilExit()
                throw Error.timedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        guard process.terminationStatus == 0 else {
            throw Error.nonZeroExit(process.terminationStatus)
        }
        guard let data = try? Data(contentsOf: outputURL) else {
            throw Error.missingOutput
        }
        guard let verdict = try? JSONDecoder().decode(Verdict.self, from: data),
              !verdict.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !verdict.smallerStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw Error.invalidOutput
        }
        return verdict
    }
}
