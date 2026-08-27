import Foundation

public struct Verdict: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case onTask = "on_task"
        case unclear
        case offTask = "off_task"
    }

    public let verdict: Kind
    public let evidence: String
    public let smallerStep: String

    public init(verdict: Kind, evidence: String, smallerStep: String) {
        self.verdict = verdict
        self.evidence = evidence
        self.smallerStep = smallerStep
    }

    private enum CodingKeys: String, CodingKey {
        case verdict
        case evidence
        case smallerStep = "smaller_step"
    }
}

public struct Observation: Equatable, Sendable {
    public let anchor: String
    public let parentChain: [String]
    public let projectContext: String
    public let openItems: [String]
    public let accessibilityText: String

    public init(
        anchor: String,
        parentChain: [String],
        projectContext: String,
        openItems: [String],
        accessibilityText: String
    ) {
        self.anchor = anchor
        self.parentChain = parentChain
        self.projectContext = projectContext
        self.openItems = openItems
        self.accessibilityText = accessibilityText
    }
}

public protocol DriftClassifier: Sendable {
    func classify(_ observation: Observation) async throws -> Verdict
}
