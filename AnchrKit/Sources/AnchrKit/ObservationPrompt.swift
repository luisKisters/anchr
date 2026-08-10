import Foundation

public enum ObservationPrompt {
    public static let jsonSchema = Data(
        #"""
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["verdict", "evidence", "smaller_step"],
          "properties": {
            "verdict": { "type": "string", "enum": ["on_task", "unclear", "off_task"] },
            "evidence": { "type": "string" },
            "smaller_step": { "type": "string" }
          }
        }
        """#.utf8
    )

    public static func text(for observation: Observation) -> String {
        let parentChain = observation.parentChain.isEmpty
            ? "(none)"
            : observation.parentChain.joined(separator: " > ")
        let openItems = observation.openItems.isEmpty
            ? "(none)"
            : observation.openItems.map { "- [ ] \($0)" }.joined(separator: "\n")

        return """
        You judge whether a person is working on their stated task.

        You get: their ANCHOR (the task they said they are on), its PARENT CHAIN, the
        PROJECT CONTEXT, the OPEN ITEMS of their list, and OBSERVATION — a flattened
        accessibility tree of the window that is in front of them right now.

        Rules:
        - "on_task" means the observation plausibly serves the anchor, including reading,
          research, and tooling that the anchor needs.
        - "unclear" means you cannot tell, or the window is too thin to judge. Research
          and reading look like drift; when in doubt use unclear, not off_task.
        - "off_task" means the observation clearly serves something other than the anchor
          and the list.
        - evidence: one sentence naming what is actually on screen.
        - smaller_step: always required, even when on_task. The next, more specific action
          toward the anchor, phrased in the user vocabulary of the list.
        Answer with the JSON object only.

        ANCHOR: \(observation.anchor)
        PARENT CHAIN: \(parentChain)
        PROJECT CONTEXT: \(observation.projectContext)
        OPEN ITEMS:
        \(openItems)

        OBSERVATION:
        \(observation.accessibilityText)
        """
    }
}
