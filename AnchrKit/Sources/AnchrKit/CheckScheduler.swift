import Foundation

/// Decides when Anchr is allowed to spend a model call.
///
/// The cadence is split in two on purpose. Reading the accessibility tree is local and
/// free; asking the model costs money and takes seconds. So `shouldSample` answers "is it
/// worth looking at the screen at all", and `shouldCall` answers "is what I saw worth
/// judging". Everything that can be decided without the model is decided first.
public enum CheckScheduler {
    /// A window switch is the strongest signal that something changed, but it arrives
    /// before the new window has drawn its content, so the read waits this long.
    public static let focusDebounce: TimeInterval = 3

    /// The fixed tick. Nothing is judged more often than this.
    public static let minimumCallGap: TimeInterval = 15

    /// The backstop for a screen whose text barely moves — a playing video, a scrolled
    /// image feed. Without it, change detection alone would let that drift run forever.
    public static let forcedInterval: TimeInterval = 180

    /// No input for this long means the person left, and there is nothing to judge.
    public static let idleTimeout: TimeInterval = 180

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

    /// Why a call was made. Worth returning rather than a bare `true`, because it is the
    /// first thing anyone reading the log wants to know.
    public enum Reason: String, Sendable, Equatable {
        case appSwitch
        case contentChanged
        case forced
        /// Chasing a screen that already looked wrong.
        case followUp
    }

    private struct State {
        var latestFocusChange: Date?
        var latestInput: Date?
        var isScreenLocked = false
        var isAnchrFrontmost = false
    }

    private static func state(from events: [Event], now: Date) -> State {
        var state = State()
        for event in events where event.date <= now {
            switch event {
            case let .focusChanged(date):
                state.latestFocusChange = date
            case let .userInput(date):
                state.latestInput = date
            case let .screenLockChanged(isLocked, _):
                state.isScreenLocked = isLocked
            case let .anchrFrontmostChanged(isFrontmost, _):
                state.isAnchrFrontmost = isFrontmost
            }
        }
        return state
    }

    /// The cheap gate, decided before touching the screen.
    public static func shouldSample(
        events: [Event],
        now: Date,
        lastCall: Date?
    ) -> Bool {
        let state = state(from: events, now: now)

        guard !state.isScreenLocked, !state.isAnchrFrontmost else { return false }
        if let latestInput = state.latestInput,
           now.timeIntervalSince(latestInput) > idleTimeout {
            return false
        }
        if let lastCall, now.timeIntervalSince(lastCall) < minimumCallGap {
            return false
        }
        // A window switch suppresses the read until its content has settled.
        if isFocusChangeNew(state: state, lastCall: lastCall),
           let latestFocusChange = state.latestFocusChange,
           now.timeIntervalSince(latestFocusChange) < focusDebounce {
            return false
        }
        return true
    }

    /// The decision that spends money. Call only after `shouldSample` passed and the
    /// screen has actually been read.
    ///
    /// - Parameter contentChanged: whether the window text differs from the last judged
    ///   one. Staying in the same app on the same page is the common case, and it is free.
    /// - Parameter isSuspicious: whether the last verdict was `off_task`. A playing video
    ///   barely changes its accessibility text, so change detection alone would check it
    ///   once and then go quiet for three minutes — long enough to miss the drift
    ///   entirely. Once a screen looks wrong, it is worth every tick until it looks right.
    public static func shouldCall(
        events: [Event],
        now: Date,
        lastCall: Date?,
        contentChanged: Bool,
        isSuspicious: Bool = false
    ) -> Reason? {
        guard shouldSample(events: events, now: now, lastCall: lastCall) else { return nil }
        let state = state(from: events, now: now)

        if isFocusChangeNew(state: state, lastCall: lastCall),
           let latestFocusChange = state.latestFocusChange,
           now.timeIntervalSince(latestFocusChange) >= focusDebounce {
            return .appSwitch
        }
        if contentChanged { return .contentChanged }
        if isSuspicious { return .followUp }
        // Never judged at all, or nothing has moved for a long time.
        guard let lastCall else { return .forced }
        return now.timeIntervalSince(lastCall) >= forcedInterval ? .forced : nil
    }

    private static func isFocusChangeNew(state: State, lastCall: Date?) -> Bool {
        guard let latestFocusChange = state.latestFocusChange else { return false }
        return lastCall.map { latestFocusChange > $0 } ?? true
    }
}
