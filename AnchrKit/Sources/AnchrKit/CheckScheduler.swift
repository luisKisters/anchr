import Foundation

public enum CheckScheduler {
    public enum Event: Sendable {
        case focusChanged(at: Date)
        case userInput(at: Date)
        case screenLockChanged(isLocked: Bool, at: Date)
        case anchrFrontmostChanged(isFrontmost: Bool, at: Date)

        fileprivate var date: Date {
            switch self {
            case let .focusChanged(date), let .userInput(date):
                date
            case let .screenLockChanged(_, date), let .anchrFrontmostChanged(_, date):
                date
            }
        }
    }

    public static func shouldCheck(
        events: [Event],
        now: Date,
        lastCall: Date?
    ) -> Bool {
        var latestFocusChange: Date?
        var latestInput: Date?
        var isScreenLocked = false
        var isAnchrFrontmost = false

        for event in events where event.date <= now {
            switch event {
            case let .focusChanged(date):
                latestFocusChange = date
            case let .userInput(date):
                latestInput = date
            case let .screenLockChanged(isLocked, _):
                isScreenLocked = isLocked
            case let .anchrFrontmostChanged(isFrontmost, _):
                isAnchrFrontmost = isFrontmost
            }
        }

        guard !isScreenLocked, !isAnchrFrontmost else { return false }
        if let latestInput, now.timeIntervalSince(latestInput) > 180 {
            return false
        }
        if let lastCall, now.timeIntervalSince(lastCall) < 45 {
            return false
        }

        let focusChangeIsNew: Bool
        if let latestFocusChange {
            focusChangeIsNew = lastCall.map { latestFocusChange > $0 } ?? true
        } else {
            focusChangeIsNew = false
        }
        if focusChangeIsNew,
           let latestFocusChange,
           now.timeIntervalSince(latestFocusChange) < 8 {
            return false
        }
        let focusDebounceElapsed = latestFocusChange.map {
            focusChangeIsNew && now.timeIntervalSince($0) >= 8
        } ?? false
        let heartbeatElapsed = lastCall.map { now.timeIntervalSince($0) >= 90 } ?? false

        return focusDebounceElapsed || heartbeatElapsed
    }
}
