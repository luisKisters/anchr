import AnchrKit
import Foundation
import XCTest
@testable import AnchrCore

final class OpenRouterClassifierTests: XCTestCase {
    func testEnvironmentKeyWinsOverTheFileSoTestsNeverReadTheRealOne() throws {
        let directory = try temporaryDirectory()
        let fileURL = directory.appendingPathComponent("openrouter-key")
        try OpenRouterKey.store("sk-or-from-file", at: fileURL)

        XCTAssertEqual(
            OpenRouterKey.load(
                environment: [OpenRouterKey.environmentVariable: "sk-or-from-env"],
                fileURL: fileURL
            ),
            "sk-or-from-env"
        )
        XCTAssertEqual(OpenRouterKey.load(environment: [:], fileURL: fileURL), "sk-or-from-file")
    }

    func testAStoredKeyIsNotReadableByOtherUsers() throws {
        let directory = try temporaryDirectory()
        let fileURL = directory.appendingPathComponent("openrouter-key")
        try OpenRouterKey.store("  sk-or-padded  \n", at: fileURL)

        XCTAssertEqual(OpenRouterKey.load(environment: [:], fileURL: fileURL), "sk-or-padded")
        let permissions = try FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.int16Value, 0o600)
    }

    func testBlankAndMissingKeysReadAsNoKeyRatherThanAnEmptyBearerToken() throws {
        let directory = try temporaryDirectory()
        let fileURL = directory.appendingPathComponent("openrouter-key")
        XCTAssertNil(OpenRouterKey.load(environment: [:], fileURL: fileURL))

        try OpenRouterKey.store("\n   \n", at: fileURL)
        XCTAssertNil(OpenRouterKey.load(environment: [:], fileURL: fileURL))
        XCTAssertNil(
            OpenRouterKey.load(
                environment: [OpenRouterKey.environmentVariable: "   "],
                fileURL: fileURL
            )
        )
    }

    func testUITestOverrideRedirectsEveryFileAwayFromTheRealList() {
        let redirected = AppSupportRoot.resolve(
            environment: [AppSupportRoot.environmentVariable: "/tmp/anchr-ui-fixture"]
        )
        XCTAssertEqual(redirected.path, "/tmp/anchr-ui-fixture")

        let real = AppSupportRoot.resolve(environment: [:])
        XCTAssertEqual(real.lastPathComponent, "Anchr")
        XCTAssertTrue(real.path.contains("Application Support"))
    }

    /// Opt-in: the only test that spends money. Everything else is offline.
    func testLiveOpenRouterClassification() async throws {
        guard ProcessInfo.processInfo.environment["ANCHR_LIVE_MODEL"] == "1" else {
            throw XCTSkip("Set ANCHR_LIVE_MODEL=1 and OPENROUTER_API_KEY to call the real model")
        }
        let classifier = try OpenRouterClassifier(timeout: 45)
        let result = try await classifier.classify(Observation(
            anchor: "Write the OpenRouter classifier tests",
            parentChain: ["Anchr V1"],
            projectContext: "A native macOS app that judges the frontmost window.",
            openItems: ["Write the OpenRouter classifier tests"],
            accessibilityText: "Window: OpenRouterClassifierTests.swift — Xcode\nStaticText: func testLive"
        ))
        XCTAssertFalse(result.evidence.isEmpty)
        XCTAssertFalse(result.smallerStep.isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnchrOpenRouterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
