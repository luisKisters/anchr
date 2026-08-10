import Foundation
import XCTest
@testable import AnchrKit

final class ObservationPromptTests: XCTestCase {
    func testVerdictDecodingRequiresEveryField() throws {
        let valid = Data(#"{"verdict":"off_task","evidence":"A video is open.","smaller_step":"Open the source file"}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(Verdict.self, from: valid),
            Verdict(verdict: .offTask, evidence: "A video is open.", smallerStep: "Open the source file")
        )

        let missingSmallerStep = Data(#"{"verdict":"off_task","evidence":"A video is open."}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Verdict.self, from: missingSmallerStep))
    }

    func testSchemaIsStrictAndRequiresVerdictFields() throws {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: ObservationPrompt.jsonSchema) as? [String: Any]
        )
        XCTAssertEqual(object["type"] as? String, "object")
        XCTAssertEqual(object["additionalProperties"] as? Bool, false)
        XCTAssertEqual(
            Set(object["required"] as? [String] ?? []),
            Set(["verdict", "evidence", "smaller_step"])
        )

        let properties = try XCTUnwrap(object["properties"] as? [String: Any])
        let verdict = try XCTUnwrap(properties["verdict"] as? [String: Any])
        XCTAssertEqual(
            verdict["enum"] as? [String],
            ["on_task", "unclear", "off_task"]
        )
    }

    func testPromptContainsAllObservationFieldsAndDecisionRules() {
        let observation = Observation(
            anchor: "Build the classifier",
            parentChain: ["Anchr V1", "The judgement"],
            projectContext: "A native macOS focus app.",
            openItems: ["Build the classifier", "Test the loop"],
            accessibilityText: "Window: Apple Developer Documentation"
        )

        let prompt = ObservationPrompt.text(for: observation)

        for expected in [
            "ANCHOR: Build the classifier",
            "PARENT CHAIN: Anchr V1 > The judgement",
            "PROJECT CONTEXT: A native macOS focus app.",
            "- [ ] Build the classifier",
            "- [ ] Test the loop",
            "OBSERVATION:\nWindow: Apple Developer Documentation",
            "when in doubt use unclear, not off_task",
            "smaller_step: always required",
            "Answer with the JSON object only.",
        ] {
            XCTAssertTrue(prompt.contains(expected), "Missing: \(expected)")
        }
    }
}
