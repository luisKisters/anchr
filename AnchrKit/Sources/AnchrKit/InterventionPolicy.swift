import Foundation

/// Decides when an `off_task` verdict becomes an interruption.
///
/// There is no cooldown, by explicit decision. Every quiet period turned out to be a way
/// to buy your way out: answer something, get minutes of silence, keep doing the wrong
/// thing. First it was a snooze, then a cooldown that applied to every answer alike.
/// Neither made anyone more focused; both made Anchr easier to defeat than to obey. The
/// tick keeps running, and drift keeps being drift.
///
/// What paces the interruptions instead is `offTaskVerdictsRequired`: after each one the
/// count restarts at zero, so the next needs two fresh `off_task` verdicts — about thirty
/// seconds at the current tick.
public enum InterventionPolicy {
    /// How many `off_task` verdicts inside `driftWindow` it takes to interrupt.
    ///
    /// Deliberately *not* consecutive. The earlier rule asked for two in a row, and real
    /// use defeated it: a glance back at the work app between two YouTube visits reset the
    /// count, so the drift could run all evening. Counting inside a window means a short
    /// look at the right window no longer buys an unlimited licence for the wrong one.
    public static let offTaskVerdictsRequired = 2

    /// The window the count is taken over.
    public static let driftWindow: TimeInterval = 180

    /// A ceiling this high is a runaway guard, not a quiet period. Reaching it means
    /// something is wrong with the loop, not that the user has been interrupted enough.
    public static let maximumPerHour = 120

    /// What the person did with an interruption. Kept for the log — it is the only record
    /// of how often "Back to it" is answered and then not done.
    public enum Answer: Sendable, Equatable {
        case backToIt
        case changedTheTask
    }

    public enum Event: Sendable {
        case verdict(Verdict.Kind, at: Date)
        case intervention(at: Date)
        case answered(Answer, at: Date)

        fileprivate var date: Date {
            switch self {
            case let .verdict(_, date), let .intervention(date), let .answered(_, date):
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

        let hourStart = now.addingTimeInterval(-3_600)
        guard interventions.filter({ $0.date > hourStart }).count < maximumPerHour else {
            return false
        }

        // Only verdicts since the last interruption count, so one drift is not punished
        // twice, and only recent ones, so this morning's distraction cannot fire tonight.
        let lastInterventionOffset = interventions.last?.offset ?? -1
        let windowStart = now.addingTimeInterval(-driftWindow)
        let offTaskCount = elapsedEvents.filter { entry in
            guard entry.offset > lastInterventionOffset,
                  case let .verdict(kind, date) = entry.element
            else { return false }
            return kind == .offTask && date > windowStart
        }.count

        return offTaskCount >= offTaskVerdictsRequired
    }
}
