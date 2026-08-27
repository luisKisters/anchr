import Foundation
import XCTest
@testable import AnchrKit

final class CheckSchedulerTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_000)

    private var debounce: TimeInterval { CheckScheduler.focusDebounce }
    private var gap: TimeInterval { CheckScheduler.minimumCallGap }
    private var forced: TimeInterval { CheckScheduler.forcedInterval }
    private var idle: TimeInterval { CheckScheduler.idleTimeout }

    /// The cadence is a product promise, not an implementation detail: someone who
    /// switches windows every few seconds has to be noticed in seconds.
    func testCadenceStaysFastEnoughToNoticeAWindowSwitch() {
        XCTAssertLessThanOrEqual(gap, 15)
        XCTAssertLessThanOrEqual(debounce, 5)
        XCTAssertLessThanOrEqual(
            gap * Double(InterventionPolicy.offTaskVerdictsRequired),
            35,
            "Drift must reach an intervention within about half a minute."
        )
    }

    func testSampleGateTable() {
        struct Case {
            let name: String
            let events: [CheckScheduler.Event]
            let seconds: TimeInterval
            let lastCall: TimeInterval?
            let expected: Bool
        }

        let cases = [
            Case(name: "nothing observed yet", events: [], seconds: 0, lastCall: nil, expected: true),
            Case(name: "inside the fixed tick", events: [], seconds: gap - 1, lastCall: 0, expected: false),
            Case(name: "tick elapsed", events: [], seconds: gap, lastCall: 0, expected: true),
            Case(name: "focus change still settling", events: [.focusChanged(at: date(0))], seconds: debounce - 1, lastCall: nil, expected: false),
            Case(name: "focus change settled", events: [.focusChanged(at: date(0))], seconds: debounce, lastCall: nil, expected: true),
            Case(name: "idle at boundary", events: [.userInput(at: date(0))], seconds: idle, lastCall: nil, expected: true),
            Case(name: "idle over limit", events: [.userInput(at: date(0))], seconds: idle + 1, lastCall: nil, expected: false),
            Case(name: "screen locked", events: [.screenLockChanged(isLocked: true, at: date(1))], seconds: gap, lastCall: nil, expected: false),
            Case(name: "screen unlocked", events: [.screenLockChanged(isLocked: true, at: date(1)), .screenLockChanged(isLocked: false, at: date(2))], seconds: gap, lastCall: nil, expected: true),
            Case(name: "Anchr frontmost", events: [.anchrFrontmostChanged(isFrontmost: true, at: date(1))], seconds: gap, lastCall: nil, expected: false),
            Case(name: "another app frontmost", events: [.anchrFrontmostChanged(isFrontmost: true, at: date(1)), .anchrFrontmostChanged(isFrontmost: false, at: date(2))], seconds: gap, lastCall: nil, expected: true),
        ]

        for testCase in cases {
            XCTAssertEqual(
                CheckScheduler.shouldSample(
                    events: testCase.events,
                    now: date(testCase.seconds),
                    lastCall: testCase.lastCall.map(date)
                ),
                testCase.expected,
                testCase.name
            )
        }
    }

    func testCallReasonTable() {
        struct Case {
            let name: String
            let events: [CheckScheduler.Event]
            let seconds: TimeInterval
            let lastCall: TimeInterval?
            let contentChanged: Bool
            let expected: CheckScheduler.Reason?
        }

        let cases = [
            Case(name: "app switch wins over everything", events: [.focusChanged(at: date(gap))], seconds: gap + debounce, lastCall: 0, contentChanged: false, expected: .appSwitch),
            Case(name: "changed screen in the same app", events: [], seconds: gap, lastCall: 0, contentChanged: true, expected: .contentChanged),
            // The saving that pays for a 15-second tick: sitting in one document is free.
            Case(name: "unchanged screen costs nothing", events: [], seconds: gap, lastCall: 0, contentChanged: false, expected: nil),
            Case(name: "unchanged screen still forced eventually", events: [], seconds: forced, lastCall: 0, contentChanged: false, expected: .forced),
            Case(name: "first ever check is forced", events: [], seconds: 0, lastCall: nil, contentChanged: false, expected: .forced),
            Case(name: "inside the tick, nothing at all", events: [], seconds: gap - 1, lastCall: 0, contentChanged: true, expected: nil),
            Case(name: "idle beats a changed screen", events: [.userInput(at: date(0))], seconds: idle + 1, lastCall: 0, contentChanged: true, expected: nil),
        ]

        for testCase in cases {
            XCTAssertEqual(
                CheckScheduler.shouldCall(
                    events: testCase.events,
                    now: date(testCase.seconds),
                    lastCall: testCase.lastCall.map(date),
                    contentChanged: testCase.contentChanged
                ),
                testCase.expected,
                testCase.name
            )
        }
    }

    /// Staying in one app while the page changes is the case the user named: change
    /// detection has to catch it, because no app switch ever fires.
    func testSamePageSwitchInsideOneAppIsCaught() {
        let events: [CheckScheduler.Event] = [.focusChanged(at: date(0))]
        XCTAssertEqual(
            CheckScheduler.shouldCall(
                events: events,
                now: date(gap * 4),
                lastCall: date(gap * 3),
                contentChanged: true
            ),
            .contentChanged
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        origin.addingTimeInterval(seconds)
    }
}
