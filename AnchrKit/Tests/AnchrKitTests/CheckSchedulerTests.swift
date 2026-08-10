import Foundation
import XCTest
@testable import AnchrKit

final class CheckSchedulerTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_000)

    func testScheduleTable() {
        struct Case {
            let name: String
            let events: [CheckScheduler.Event]
            let seconds: TimeInterval
            let lastCall: TimeInterval?
            let expected: Bool
        }

        let cases = [
            Case(name: "focus debounce pending", events: [.focusChanged(at: date(0))], seconds: 7, lastCall: nil, expected: false),
            Case(name: "focus debounce elapsed", events: [.focusChanged(at: date(0))], seconds: 8, lastCall: nil, expected: true),
            Case(name: "minimum call gap", events: [.focusChanged(at: date(1))], seconds: 44, lastCall: 0, expected: false),
            Case(name: "minimum call gap elapsed", events: [.focusChanged(at: date(1))], seconds: 45, lastCall: 0, expected: true),
            Case(name: "heartbeat pending", events: [], seconds: 89, lastCall: 0, expected: false),
            Case(name: "heartbeat elapsed", events: [], seconds: 90, lastCall: 0, expected: true),
            Case(name: "focus change delays due heartbeat", events: [.focusChanged(at: date(89))], seconds: 90, lastCall: 0, expected: false),
            Case(name: "delayed heartbeat runs after focus debounce", events: [.focusChanged(at: date(89))], seconds: 97, lastCall: 0, expected: true),
            Case(name: "idle at boundary", events: [.focusChanged(at: date(0)), .userInput(at: date(0))], seconds: 180, lastCall: nil, expected: true),
            Case(name: "idle over limit", events: [.focusChanged(at: date(0)), .userInput(at: date(0))], seconds: 181, lastCall: nil, expected: false),
            Case(name: "screen locked", events: [.focusChanged(at: date(0)), .screenLockChanged(isLocked: true, at: date(1))], seconds: 20, lastCall: nil, expected: false),
            Case(name: "screen unlocked", events: [.focusChanged(at: date(0)), .screenLockChanged(isLocked: true, at: date(1)), .screenLockChanged(isLocked: false, at: date(2))], seconds: 20, lastCall: nil, expected: true),
            Case(name: "Anchr frontmost", events: [.focusChanged(at: date(0)), .anchrFrontmostChanged(isFrontmost: true, at: date(1))], seconds: 20, lastCall: nil, expected: false),
            Case(name: "another app frontmost", events: [.focusChanged(at: date(0)), .anchrFrontmostChanged(isFrontmost: true, at: date(1)), .anchrFrontmostChanged(isFrontmost: false, at: date(2))], seconds: 20, lastCall: nil, expected: true),
        ]

        for testCase in cases {
            XCTAssertEqual(
                CheckScheduler.shouldCheck(
                    events: testCase.events,
                    now: date(testCase.seconds),
                    lastCall: testCase.lastCall.map(date)
                ),
                testCase.expected,
                testCase.name
            )
        }
    }

    private func date(_ seconds: TimeInterval) -> Date {
        origin.addingTimeInterval(seconds)
    }
}
