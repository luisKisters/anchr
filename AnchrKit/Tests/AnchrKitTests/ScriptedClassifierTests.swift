import XCTest
@testable import AnchrKit
@testable import AnchrKitTestSupport

final class ScriptedClassifierTests: XCTestCase {
    func testReplaysFixtureInOrderAndThrowsWhenExhausted() async throws {
        let fixture = try XCTUnwrap(
            Bundle.module.url(
                forResource: "scripted-verdicts",
                withExtension: "json",
                subdirectory: "fixtures"
            )
        )
        let classifier = try ScriptedClassifier(fixtureURL: fixture)
        let observation = Observation(
            anchor: "Test",
            parentChain: [],
            projectContext: "",
            openItems: [],
            accessibilityText: "Window: Test"
        )

        let first = try await classifier.classify(observation)
        let second = try await classifier.classify(observation)

        XCTAssertEqual(first.verdict, .onTask)
        XCTAssertEqual(second.verdict, .offTask)
        do {
            _ = try await classifier.classify(observation)
            XCTFail("Expected fixture exhaustion")
        } catch {
            XCTAssertEqual(error as? ScriptedClassifier.Error, .exhausted)
        }
    }
}
