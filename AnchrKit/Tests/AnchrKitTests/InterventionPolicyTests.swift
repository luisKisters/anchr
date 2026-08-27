import Foundation
import XCTest
@testable import AnchrKit

final class InterventionPolicyTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 2_000)

    func testVerdictSequenceTable() {
        struct Case {
            let name: String
            let kinds: [Verdict.Kind]
            let expected: Bool
        }

        let cases = [
            Case(name: "one off-task", kinds: [.offTask], expected: false),
            Case(name: "two off-task", kinds: [.offTask, .offTask], expected: true),
            // These two used to expect false, under a rule that wanted the off_task
            // verdicts consecutive. Real use showed what that meant: dipping back into the
            // work app for one check bought unlimited time in the wrong one.
            Case(name: "on-task in between does not clear it", kinds: [.offTask, .onTask, .offTask], expected: true),
            Case(name: "unclear in between does not clear it", kinds: [.offTask, .unclear, .offTask], expected: true),
            Case(name: "unclear never acts alone", kinds: [.unclear, .unclear], expected: false),
            Case(name: "on-task alone is silent", kinds: [.onTask, .onTask, .onTask], expected: false),
        ]

        for testCase in cases {
            let events = testCase.kinds.enumerated().map {
                InterventionPolicy.Event.verdict($0.element, at: date(TimeInterval($0.offset)))
            }
            XCTAssertEqual(
                InterventionPolicy.shouldIntervene(events: events, now: date(10)),
                testCase.expected,
                testCase.name
            )
        }
    }

    func testVerdictsFromBeforeAnInterruptionDoNotTriggerTheNextOne() {
        let events: [InterventionPolicy.Event] = [
            .verdict(.offTask, at: date(0)),
            .verdict(.offTask, at: date(1)),
            .intervention(at: date(1)),
        ]

        XCTAssertFalse(InterventionPolicy.shouldIntervene(events: events, now: date(60)))
    }

    /// With no cooldown left, the pace is set only by "two fresh off_task verdicts each
    /// time". One verdict a minute for an hour therefore yields one interruption every two
    /// minutes — and the hourly ceiling never comes near, which is the point of it.
    func testPaceIsSetByTheVerdictCountNotByACeiling() {
        var events: [InterventionPolicy.Event] = []
        var interventionCount = 0

        for minute in 0...60 {
            let now = date(TimeInterval(minute * 60))
            events.append(.verdict(.offTask, at: now))
            if InterventionPolicy.shouldIntervene(events: events, now: now) {
                events.append(.intervention(at: now))
                interventionCount += 1
            }
        }

        XCTAssertEqual(interventionCount, 30)
        XCTAssertLessThan(
            interventionCount,
            InterventionPolicy.maximumPerHour,
            "The ceiling is a runaway guard and must not shape normal use."
        )
    }

    /// The rule the user insisted on: no answer buys quiet. Say "Back to it", keep
    /// drifting, and the next two verdicts bring the next interruption.
    func testNoAnswerBuysAnyQuiet() {
        for answer in [InterventionPolicy.Answer.backToIt, .changedTheTask] {
            let events: [InterventionPolicy.Event] = [
                .verdict(.offTask, at: date(0)),
                .verdict(.offTask, at: date(15)),
                .intervention(at: date(15)),
                .answered(answer, at: date(18)),
                .verdict(.offTask, at: date(30)),
                .verdict(.offTask, at: date(45)),
            ]

            XCTAssertTrue(
                InterventionPolicy.shouldIntervene(events: events, now: date(45)),
                "\(answer) must not suppress the next interruption."
            )
        }
    }

    /// The only thing that still paces interruptions: the count restarts after each one.
    func testOneFreshOffTaskIsNotEnoughAfterAnInterruption() {
        let events: [InterventionPolicy.Event] = [
            .verdict(.offTask, at: date(0)),
            .verdict(.offTask, at: date(15)),
            .intervention(at: date(15)),
            .verdict(.offTask, at: date(30)),
        ]

        XCTAssertFalse(InterventionPolicy.shouldIntervene(events: events, now: date(30)))
    }

    private func date(_ seconds: TimeInterval) -> Date {
        origin.addingTimeInterval(seconds)
    }
}
