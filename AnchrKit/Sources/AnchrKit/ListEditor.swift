import Foundation

/// Every key the list understands.
///
/// There is no browse mode and no edit mode. The list behaves like the Markdown document
/// it is stored as: the selected line is always the line you are typing in. The earlier
/// design had single-letter shortcuts, which meant typing a task called "new" was
/// impossible, and it needed an explicit step to start editing that nothing on screen
/// explained. Every command now takes a modifier, so no command can ever eat a letter.
public enum ListEditorKey: Equatable, Sendable {
    case moveUp
    case moveDown
    /// Return: split off a new line below, at the same depth.
    case newLine
    /// Tab.
    case indent
    /// Shift-Tab.
    case unindent
    /// Command-Return.
    case setAnchor
    /// Command-D.
    case toggleDone
    /// Backspace. Only does anything on a line that is already empty.
    case deleteBackward
    case openSwitcher
    case escape
    case replaceText(String)
    case select(Int)
}

public struct ListEditorState: Equatable, Sendable {
    public var list: TodoList
    public fileprivate(set) var selection: Int?
    public fileprivate(set) var anchorIndex: Int?
    public fileprivate(set) var shouldClose: Bool
    public fileprivate(set) var shouldOpenSwitcher: Bool

    public init(list: TodoList, selection: Int?, anchorIndex: Int?) {
        // An empty list still needs one line. Without it there is no text field, so nothing
        // holds the keyboard: deleting the last task left the whole overlay dead — no
        // typing, no Return, no ⌘K, no way back except quitting.
        let resolved = list.items.isEmpty
            ? TodoList(items: [Item(text: "", depth: 0, done: false)])
            : list
        self.list = resolved
        self.selection = min(max(selection ?? 0, 0), resolved.items.count - 1)
        self.anchorIndex = anchorIndex.flatMap { resolved.items.indices.contains($0) ? $0 : nil }
        shouldClose = false
        shouldOpenSwitcher = false
    }

    /// The text of the line being typed in, if there is one.
    public var editingText: String? {
        guard let selection, list.items.indices.contains(selection) else { return nil }
        return list.items[selection].text
    }
}

public enum ListEditor {
    public static func reduce(_ state: ListEditorState, key: ListEditorKey) -> ListEditorState {
        var next = state
        next.shouldClose = false
        next.shouldOpenSwitcher = false

        switch key {
        case .replaceText(let text):
            guard let selection = validSelection(in: next) else { return next }
            // Straight into the item. No separate buffer means no commit step, and no way
            // for what is on screen to disagree with what is in the list.
            next.list.items[selection].text = text

        case .moveUp:
            guard let selection = validSelection(in: next) else { return next }
            moveSelection(in: &next, to: selection - 1)

        case .moveDown:
            guard let selection = validSelection(in: next) else { return next }
            moveSelection(in: &next, to: selection + 1)

        case .select(let index):
            guard next.list.items.indices.contains(index) else { return next }
            moveSelection(in: &next, to: index)

        case .newLine:
            newLine(in: &next)

        case .indent:
            shiftSubtree(in: &next.list, at: next.selection, by: 1)

        case .unindent:
            shiftSubtree(in: &next.list, at: next.selection, by: -1)

        case .setAnchor:
            guard let selection = validSelection(in: next),
                  !next.list.items[selection].text.isEmpty
            else { return next }
            next.anchorIndex = selection

        case .toggleDone:
            guard let selection = validSelection(in: next) else { return next }
            next.list.items[selection].done.toggle()

        case .deleteBackward:
            deleteBackward(in: &next)

        case .openSwitcher:
            dropEmptySelectedLine(in: &next)
            next.shouldOpenSwitcher = true

        case .escape:
            dropEmptySelectedLine(in: &next)
            next.shouldClose = true
        }

        return next
    }

    /// Return behaves the way every Markdown editor does.
    ///
    /// On a line with text it opens a sibling below. On an empty indented line it outdents
    /// instead, which is how you climb back out of a nested list without reaching for Tab.
    /// On an empty top-level line it does nothing, because the alternative is an unbounded
    /// column of blank rows.
    private static func newLine(in state: inout ListEditorState) {
        guard let selection = validSelection(in: state) else {
            state.list.insert(Item(text: "", depth: 0, done: false), at: 0)
            state.selection = 0
            return
        }

        let item = state.list.items[selection]
        if item.text.isEmpty {
            if item.depth > 0 {
                shiftSubtree(in: &state.list, at: selection, by: -1)
            }
            return
        }

        // Below this line and everything nested under it, so a new sibling does not land
        // in the middle of its own children.
        let insertionIndex = selection + 1 + descendantCount(in: state.list, at: selection)
        state.list.insert(Item(text: "", depth: item.depth, done: false), at: insertionIndex)
        if let anchorIndex = state.anchorIndex, anchorIndex >= insertionIndex {
            state.anchorIndex = anchorIndex + 1
        }
        state.selection = insertionIndex
    }

    /// Backspace on an empty line removes it and puts the caret on the line above,
    /// whatever its depth. It used to outdent first, which meant a nested blank line took
    /// several presses to disappear — Backspace in a list is expected to go back, not to
    /// step sideways.
    private static func deleteBackward(in state: inout ListEditorState) {
        guard let selection = validSelection(in: state),
              state.list.items[selection].text.isEmpty,
              descendantCount(in: state.list, at: selection) == 0
        else { return }

        // The last line stays, because something has to hold the caret.
        guard state.list.items.count > 1 else { return }
        removeItem(at: selection, from: &state)
    }

    /// An empty line exists only while the caret is on it. Leaving it behind is what put
    /// stray `- [ ]` rows into the saved file.
    private static func dropEmptySelectedLine(in state: inout ListEditorState) {
        guard let selection = validSelection(in: state),
              state.list.items[selection].text.isEmpty,
              descendantCount(in: state.list, at: selection) == 0
        else { return }
        removeItem(at: selection, from: &state)
    }

    private static func moveSelection(in state: inout ListEditorState, to target: Int) {
        guard let current = validSelection(in: state) else { return }
        let clamped = min(max(target, 0), state.list.items.count - 1)
        guard clamped != current else { return }

        let wasEmpty = state.list.items[current].text.isEmpty
            && descendantCount(in: state.list, at: current) == 0
        state.selection = clamped
        guard wasEmpty else { return }

        // Removing the line the caret just left shifts everything after it.
        state.list.items.remove(at: current)
        if let anchorIndex = state.anchorIndex, anchorIndex > current {
            state.anchorIndex = anchorIndex - 1
        }
        state.selection = clamped > current ? clamped - 1 : clamped
    }

    private static func removeItem(at index: Int, from state: inout ListEditorState) {
        state.list.items.remove(at: index)

        if let anchorIndex = state.anchorIndex {
            if anchorIndex == index {
                state.anchorIndex = nil
            } else if anchorIndex > index {
                state.anchorIndex = anchorIndex - 1
            }
        }

        if state.list.items.isEmpty {
            state.list.insert(Item(text: "", depth: 0, done: false), at: 0)
            state.selection = 0
        } else {
            state.selection = max(0, index - 1)
        }
    }

    private static func shiftSubtree(in list: inout TodoList, at selection: Int?, by delta: Int) {
        guard let selection, list.items.indices.contains(selection) else { return }
        let currentDepth = list.items[selection].depth

        if delta > 0 {
            guard selection > 0, currentDepth <= list.items[selection - 1].depth else { return }
        } else {
            guard delta < 0, currentDepth > 0 else { return }
        }

        let end = selection + descendantCount(in: list, at: selection)
        for index in selection...end {
            list.items[index].depth += delta
        }
    }

    private static func descendantCount(in list: TodoList, at index: Int) -> Int {
        guard list.items.indices.contains(index) else { return 0 }
        let depth = list.items[index].depth
        var count = 0
        var candidate = index + 1
        while candidate < list.items.count, list.items[candidate].depth > depth {
            count += 1
            candidate += 1
        }
        return count
    }

    private static func validSelection(in state: ListEditorState) -> Int? {
        guard let selection = state.selection, state.list.items.indices.contains(selection) else {
            return nil
        }
        return selection
    }
}
