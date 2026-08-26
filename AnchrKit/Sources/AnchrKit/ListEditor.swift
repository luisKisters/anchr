import Foundation

public enum ListEditorKey: Equatable, Sendable {
    case moveUp
    case moveDown
    case toggleDone
    case enter
    case indent
    case unindent
    case newItem
    case setAnchor
    case openSwitcher
    case escape
    case replaceEditingText(String)
    case select(Int)
}

public struct ListEditorState: Equatable, Sendable {
    public var list: TodoList
    public fileprivate(set) var selection: Int?
    public fileprivate(set) var anchorIndex: Int?
    public fileprivate(set) var editingText: String?
    public fileprivate(set) var shouldClose: Bool
    public fileprivate(set) var shouldOpenSwitcher: Bool

    fileprivate var isNewItem: Bool

    public init(list: TodoList, selection: Int?, anchorIndex: Int?) {
        self.list = list
        if list.items.isEmpty {
            self.selection = nil
        } else {
            self.selection = min(max(selection ?? 0, 0), list.items.count - 1)
        }
        self.anchorIndex = anchorIndex.flatMap { list.items.indices.contains($0) ? $0 : nil }
        editingText = nil
        shouldClose = false
        shouldOpenSwitcher = false
        isNewItem = false
    }

    public var isEditing: Bool {
        editingText != nil
    }
}

public enum ListEditor {
    public static func reduce(_ state: ListEditorState, key: ListEditorKey) -> ListEditorState {
        var next = state
        next.shouldClose = false
        next.shouldOpenSwitcher = false

        if next.isEditing {
            reduceEditing(&next, key: key)
        } else {
            reduceBrowsing(&next, key: key)
        }
        return next
    }

    private static func reduceBrowsing(_ state: inout ListEditorState, key: ListEditorKey) {
        switch key {
        case .moveUp:
            guard let selection = state.selection else { return }
            state.selection = max(0, selection - 1)

        case .moveDown:
            guard let selection = state.selection else { return }
            state.selection = min(state.list.items.count - 1, selection + 1)

        case .toggleDone:
            guard let selection = validSelection(in: state) else { return }
            state.list.items[selection].done.toggle()

        case .enter:
            guard let selection = validSelection(in: state) else { return }
            state.editingText = state.list.items[selection].text
            state.isNewItem = false

        case .indent:
            shiftSubtree(in: &state.list, at: state.selection, by: 1)

        case .unindent:
            shiftSubtree(in: &state.list, at: state.selection, by: -1)

        case .newItem:
            insertNewItem(in: &state)

        case .setAnchor:
            guard let selection = validSelection(in: state) else { return }
            state.anchorIndex = selection

        case .openSwitcher:
            state.shouldOpenSwitcher = true

        case .escape:
            state.shouldClose = true

        case let .select(index):
            guard state.list.items.indices.contains(index) else { return }
            state.selection = index

        case .replaceEditingText:
            return
        }
    }

    private static func reduceEditing(_ state: inout ListEditorState, key: ListEditorKey) {
        switch key {
        case let .replaceEditingText(text):
            state.editingText = text

        case .enter:
            saveEditing(in: &state)

        case .escape:
            if state.isNewItem, let selection = validSelection(in: state) {
                removeItem(at: selection, from: &state)
            }
            state.editingText = nil
            state.isNewItem = false

        case .indent:
            preserveEditingText(in: &state)
            shiftSubtree(in: &state.list, at: state.selection, by: 1)

        case .unindent:
            preserveEditingText(in: &state)
            shiftSubtree(in: &state.list, at: state.selection, by: -1)

        case .moveUp, .moveDown, .toggleDone, .newItem, .setAnchor, .openSwitcher, .select:
            return
        }
    }

    private static func insertNewItem(in state: inout ListEditorState) {
        let insertionIndex: Int
        let depth: Int
        if let selection = validSelection(in: state) {
            insertionIndex = selection + 1 + descendantCount(in: state.list, at: selection)
            depth = state.list.items[selection].depth
        } else {
            insertionIndex = 0
            depth = 0
        }

        state.list.insert(Item(text: "", depth: depth, done: false), at: insertionIndex)
        if let anchorIndex = state.anchorIndex, anchorIndex >= insertionIndex {
            state.anchorIndex = anchorIndex + 1
        }
        state.selection = insertionIndex
        state.editingText = ""
        state.isNewItem = true
    }

    private static func saveEditing(in state: inout ListEditorState) {
        guard let selection = validSelection(in: state), let editingText = state.editingText else {
            state.editingText = nil
            state.isNewItem = false
            return
        }

        let text = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            removeItem(at: selection, from: &state)
        } else {
            state.list.items[selection].text = text
        }
        state.editingText = nil
        state.isNewItem = false
    }

    private static func preserveEditingText(in state: inout ListEditorState) {
        guard let selection = validSelection(in: state),
              let text = state.editingText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return }
        state.list.items[selection].text = text
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
            state.selection = nil
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
