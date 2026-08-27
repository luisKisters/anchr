import Foundation

public enum SwitcherKey: Equatable, Sendable {
    case moveUp
    case moveDown
    case open
    case editContext
    case newList
    case escape
}

public enum SwitcherEffect: Equatable, Sendable {
    case openList(String)
    case editContext(String)
    case createList
    case back
}

public struct SwitcherState: Equatable, Sendable {
    public var lists: [ListSummary]
    public fileprivate(set) var selection: Int

    public init(lists: [ListSummary], selectedSlug: String?) {
        self.lists = lists
        selection = selectedSlug.flatMap { slug in lists.firstIndex { $0.slug == slug } } ?? 0
    }
}

public enum Switcher {
    public static func reduce(_ state: inout SwitcherState, key: SwitcherKey) -> SwitcherEffect? {
        switch key {
        case .moveUp:
            state.selection = max(0, state.selection - 1)
        case .moveDown:
            state.selection = min(max(0, state.lists.count - 1), state.selection + 1)
        case .open:
            return selected(in: state).map { .openList($0.slug) }
        case .editContext:
            return selected(in: state).map { .editContext($0.slug) }
        case .newList:
            return .createList
        case .escape:
            return .back
        }
        return nil
    }

    private static func selected(in state: SwitcherState) -> ListSummary? {
        guard state.lists.indices.contains(state.selection) else { return nil }
        return state.lists[state.selection]
    }
}

public enum InterventionInputKind: Equatable, Sendable {
    case smaller
    case newAnchor
}

public enum InterventionStage: Equatable, Sendable {
    case asking
    case editing(InterventionInputKind, text: String)
}

public enum InterventionKey: Equatable, Sendable {
    case answerBack
    case answerSmaller
    case answerNewAnchor
    case replaceText(String)
    case submit
    case escape
}

public enum InterventionEffect: Equatable, Sendable {
    /// "Back to it" closes the overlay and nothing else.
    ///
    /// It used to buy ten minutes of silence, which had the rule exactly backwards: the
    /// answer is a claim about what happens next, and the right response to a claim is to
    /// check it, not to stop looking. Someone who really did go back is judged `on_task`
    /// at the next check anyway; someone who did not would have bought their way out by
    /// telling Anchr what it wanted to hear. The policy cooldown is the only quiet period,
    /// and it is the same length whatever you answer.
    case dismiss
    case goSmaller(String)
    case setNewAnchor(String)
}

public struct InterventionState: Equatable, Sendable {
    public let anchor: String
    public let evidence: String
    public let smallerStep: String
    public fileprivate(set) var stage: InterventionStage

    public init(anchor: String, evidence: String, smallerStep: String) {
        self.anchor = anchor
        self.evidence = evidence
        self.smallerStep = smallerStep
        stage = .asking
    }
}

public enum Intervention {
    public static func reduce(
        _ state: inout InterventionState,
        key: InterventionKey
    ) -> InterventionEffect? {
        switch (state.stage, key) {
        case (.asking, .answerBack):
            return .dismiss
        case (.asking, .answerSmaller):
            state.stage = .editing(.smaller, text: state.smallerStep)
        case (.asking, .answerNewAnchor):
            state.stage = .editing(.newAnchor, text: "")
        case let (.editing(kind, _), .replaceText(text)):
            state.stage = .editing(kind, text: text)
        case let (.editing(kind, text), .submit):
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return kind == .smaller ? .goSmaller(text) : .setNewAnchor(text)
        case (_, .escape), (.asking, .replaceText), (.asking, .submit),
             (.editing, .answerBack), (.editing, .answerSmaller), (.editing, .answerNewAnchor):
            break
        }
        return nil
    }
}
