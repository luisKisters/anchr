import Foundation
import XCTest
@testable import AnchrKit

final class OpenRouterRequestTests: XCTestCase {
    private let observation = Observation(
        anchor: "Implement the OpenRouter classifier",
        parentChain: ["Anchr V1", "The judgement"],
        projectContext: "A native macOS app that classifies frontmost window text.",
        openItems: ["Implement the OpenRouter classifier"],
        accessibilityText: "Window: OpenRouterClassifier.swift — Xcode"
    )

    func testBodyAsksForStrictStructuredOutputOfTheVerdictSchema() throws {
        let data = try OpenRouterRequest.body(for: observation, model: "test/model")
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(body["model"] as? String, "test/model")
        // A drifting window must not produce a different verdict on a retry.
        XCTAssertEqual(body["temperature"] as? Int, 0)

        let format = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let jsonSchema = try XCTUnwrap(format["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)

        // The schema Anchr sends must be the one Kit owns, not a second copy.
        let sent = try XCTUnwrap(jsonSchema["schema"] as? [String: Any])
        let owned = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: ObservationPrompt.jsonSchema) as? [String: Any]
        )
        XCTAssertEqual(
            try JSONSerialization.data(withJSONObject: sent, options: [.sortedKeys]),
            try JSONSerialization.data(withJSONObject: owned, options: [.sortedKeys])
        )

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(content.contains("Implement the OpenRouter classifier"))
        XCTAssertTrue(content.contains("Window: OpenRouterClassifier.swift"))
    }

    func testDecodesAVerdictFromACompletionEnvelope() throws {
        let verdict = try OpenRouterRequest.verdict(from: envelope(
            content: #"{"verdict":"off_task","evidence":"A music video is playing.","smaller_step":"Open the schema file"}"#
        ))
        XCTAssertEqual(
            verdict,
            Verdict(
                verdict: .offTask,
                evidence: "A music video is playing.",
                smallerStep: "Open the schema file"
            )
        )
    }

    func testRemoteErrorSurfacesInsteadOfLookingLikeNoDrift() throws {
        let data = Data(#"{"error":{"code":402,"message":"Insufficient credits"}}"#.utf8)
        XCTAssertThrowsError(try OpenRouterRequest.verdict(from: data)) { error in
            XCTAssertEqual(
                error as? OpenRouterRequest.DecodingError,
                .remote("Insufficient credits")
            )
        }
    }

    func testAMissingSmallerStepIsRejected() throws {
        let data = envelope(
            content: #"{"verdict":"off_task","evidence":"Something else is open.","smaller_step":"   "}"#
        )
        XCTAssertThrowsError(try OpenRouterRequest.verdict(from: data)) { error in
            XCTAssertEqual(
                error as? OpenRouterRequest.DecodingError,
                .emptyField("smaller_step")
            )
        }
    }

    func testAnUnparsableAnswerThrowsRatherThanDefaultingToOnTask() throws {
        XCTAssertThrowsError(try OpenRouterRequest.verdict(from: envelope(content: "not json"))) {
            XCTAssertEqual($0 as? OpenRouterRequest.DecodingError, .malformedVerdict)
        }
        XCTAssertThrowsError(try OpenRouterRequest.verdict(from: Data("{}".utf8))) {
            XCTAssertEqual($0 as? OpenRouterRequest.DecodingError, .malformedEnvelope)
        }
    }

    private func envelope(content: String) -> Data {
        let payload: [String: Any] = [
            "choices": [["message": ["role": "assistant", "content": content]]],
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }
}
