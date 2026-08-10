import Foundation
import AnchrKit

public actor ScriptedClassifier: DriftClassifier {
    public enum Error: Swift.Error, Equatable {
        case exhausted
    }

    private let verdicts: [Verdict]
    private var nextIndex = 0

    public init(verdicts: [Verdict]) {
        self.verdicts = verdicts
    }

    public init(fixtureURL: URL) throws {
        let data = try Data(contentsOf: fixtureURL)
        verdicts = try JSONDecoder().decode([Verdict].self, from: data)
    }

    public func classify(_ observation: Observation) async throws -> Verdict {
        guard verdicts.indices.contains(nextIndex) else { throw Error.exhausted }
        defer { nextIndex += 1 }
        return verdicts[nextIndex]
    }
}
