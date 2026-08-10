import Foundation
import XCTest
import AnchrKit
@testable import AnchrCore

final class CodexClassifierTests: XCTestCase {
    func testParsesValidCodexOutput() async throws {
        let executable = try makeExecutable(
            name: "success",
            source: #"""
            #!/bin/sh
            while [ "$#" -gt 0 ]; do
              if [ "$1" = "-o" ]; then
                shift
                output="$1"
              fi
              shift
            done
            printf '%s' '{"verdict":"on_task","evidence":"The source is open.","smaller_step":"Run the test"}' > "$output"
            """#
        )
        let classifier = CodexClassifier(executableURL: executable, timeout: 2)

        let result = try await classifier.classify(observation)

        XCTAssertEqual(
            result,
            Verdict(verdict: .onTask, evidence: "The source is open.", smallerStep: "Run the test")
        )
    }

    func testNonZeroExitThrowsInsteadOfReturningOnTask() async throws {
        let executable = try makeExecutable(name: "failure", source: "#!/bin/sh\nexit 7\n")
        let classifier = CodexClassifier(executableURL: executable, timeout: 2)

        do {
            _ = try await classifier.classify(observation)
            XCTFail("Expected a non-zero exit error")
        } catch {
            XCTAssertEqual(error as? CodexClassifier.Error, .nonZeroExit(7))
        }
    }

    func testTimeoutThrowsInsteadOfReturningOnTask() async throws {
        let executable = try makeExecutable(name: "timeout", source: "#!/bin/sh\nsleep 2\n")
        let classifier = CodexClassifier(executableURL: executable, timeout: 0.05)

        do {
            _ = try await classifier.classify(observation)
            XCTFail("Expected a timeout error")
        } catch {
            XCTAssertEqual(error as? CodexClassifier.Error, .timedOut)
        }
    }

    func testLiveCodexClassification() async throws {
        guard ProcessInfo.processInfo.environment["ANCHR_LIVE_CODEX"] == "1" else {
            throw XCTSkip("Set ANCHR_LIVE_CODEX=1 to use the authenticated Codex CLI")
        }

        let result = try await CodexClassifier(timeout: 30).classify(observation)
        XCTAssertFalse(result.evidence.isEmpty)
        XCTAssertFalse(result.smallerStep.isEmpty)
    }

    private let observation = Observation(
        anchor: "Implement the Codex classifier",
        parentChain: ["Anchr V1", "The judgement"],
        projectContext: "A native macOS app that classifies frontmost window text.",
        openItems: ["Implement the Codex classifier"],
        accessibilityText: "Window: CodexClassifier.swift — Xcode\nStaticText: func classify"
    )

    private func makeExecutable(name: String, source: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnchrCodexClassifierTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(name)
        try Data(source.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
