import Foundation

/// Every decision about how Anchr talks to OpenRouter lives here, in Kit: the request
/// body, the structured-output schema and the answer decoding. `AnchrCore` owns only
/// the URLSession call. So the wire format is table-tested with no network.
public enum OpenRouterRequest {
    /// Override with `ANCHR_OPENROUTER_MODEL`; the id is never read from a config file
    /// Anchr does not own. That is the mistake that made every call fail silently under
    /// the old Codex path.
    public static let defaultModel = "openai/gpt-5.6-luna"

    /// Measured against a real 3,000-character window: `low` answers in about 3 seconds,
    /// `medium` in 11, for the same verdict at the same price. At a 15-second tick,
    /// `medium` would spend a third of every cycle waiting.
    public static let defaultReasoningEffort = "low"

    public static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    public enum DecodingError: Swift.Error, Equatable {
        /// OpenRouter answers 200 with an error object in the body often enough
        /// that treating a parse failure as "no verdict" would hide real outages.
        case remote(String)
        case malformedEnvelope
        case malformedVerdict
        case emptyField(String)
    }

    public static func body(for observation: Observation, model: String) throws -> Data {
        let schema = try JSONSerialization.jsonObject(with: ObservationPrompt.jsonSchema)

        let payload: [String: Any] = [
            "model": model,
            // Deterministic: the same window twice must not flip the verdict.
            "temperature": 0,
            // Reasoning tokens are billed as output and are invisible in the answer, so
            // the ceiling has to leave room for them or the reply arrives truncated.
            "max_tokens": 2_000,
            "reasoning": ["effort": defaultReasoningEffort],
            "messages": [
                ["role": "user", "content": ObservationPrompt.text(for: observation)],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "anchr_verdict",
                    "strict": true,
                    "schema": schema,
                ],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    public static func verdict(from data: Data) throws -> Verdict {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodingError.malformedEnvelope
        }

        if let error = envelope["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "unknown OpenRouter error"
            throw DecodingError.remote(message)
        }

        guard let choices = envelope["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let contentData = content.data(using: .utf8)
        else {
            throw DecodingError.malformedEnvelope
        }

        guard let verdict = try? JSONDecoder().decode(Verdict.self, from: contentData) else {
            throw DecodingError.malformedVerdict
        }

        // A blank smaller_step is the one failure that would break the intervention,
        // so it is rejected here rather than surfacing as an empty screen.
        guard !verdict.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.emptyField("evidence")
        }
        guard !verdict.smallerStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.emptyField("smaller_step")
        }
        return verdict
    }
}
