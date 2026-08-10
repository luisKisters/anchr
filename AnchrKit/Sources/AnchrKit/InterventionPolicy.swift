import Foundation

public enum InterventionPolicy {
    public enum Event: Sendable {
        case verdict(Verdict.Kind, at: Date)
        case intervention(at: Date)

        fileprivate var date: Date {
            switch self {
            case let .verdict(_, date), let .intervention(date):
                date
            }
        }
    }

    public static func shouldIntervene(events: [Event], now: Date) -> Bool {
        let elapsedEvents = events.enumerated().filter { $0.element.date <= now }
        let interventions = elapsedEvents.compactMap { entry -> (offset: Int, date: Date)? in
            guard case let .intervention(date) = entry.element else { return nil }
            return (entry.offset, date)
        }

        if let lastIntervention = interventions.last,
           now.timeIntervalSince(lastIntervention.date) < 600 {
            return false
        }

        let hourStart = now.addingTimeInterval(-3_600)
        guard interventions.filter({ $0.date > hourStart }).count < 4 else {
            return false
        }

        let lastInterventionOffset = interventions.last?.offset ?? -1
        let verdictsAfterIntervention = elapsedEvents.compactMap { entry -> Verdict.Kind? in
            guard entry.offset > lastInterventionOffset,
                  case let .verdict(kind, _) = entry.element
            else { return nil }
            return kind
        }

        return verdictsAfterIntervention.suffix(2) == [.offTask, .offTask]
    }
}
