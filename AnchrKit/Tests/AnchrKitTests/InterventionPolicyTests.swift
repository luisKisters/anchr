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
            Case(name: "on-task resets", kinds: [.offTask, .onTask, .offTask], expected: false),
            Case(name: "unclear resets", kinds: [.offTask, .unclear, .offTask], expected: false),
            Case(name: "unclear never acts alone", kinds: [.unclear, .unclear], expected: false),
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

    func testTenMinuteSilenceRequiresNewConsecutiveVerdicts() {
        let events: [InterventionPolicy.Event] = [
            .verdict(.offTask, at: date(0)),
            .verdict(.offTask, at: date(1)),
            .intervention(at: date(1)),
            .verdict(.offTask, at: date(590)),
            .verdict(.offTask, at: date(599)),
        ]

        XCTAssertFalse(InterventionPolicy.shouldIntervene(events: events, now: date(600)))
        XCTAssertTrue(InterventionPolicy.shouldIntervene(events: events, now: date(601)))
        XCTAssertFalse(
            InterventionPolicy.shouldIntervene(
                events: Array(events.prefix(3)),
                now: date(601)
            ),
            "Old verdicts must not trigger a second intervention"
        )
    }

    func testFourPerRollingHourCeilingWithContinuousOffTaskVerdicts() {
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

        XCTAssertEqual(interventionCount, 4)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        origin.addingTimeInterval(seconds)
    }
}
