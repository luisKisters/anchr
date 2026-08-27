import XCTest
@testable import AnchrKit

final class ListEditorTests: XCTestCase {
    func testMovingTogglingAndAnchoring() {
        let list = TodoList(items: [
            Item(text: "Parent", depth: 0, done: false),
            Item(text: "Child", depth: 1, done: false),
            Item(text: "Next", depth: 0, done: false),
        ])
        var state = ListEditorState(list: list, selection: 0, anchorIndex: nil)

        state = ListEditor.reduce(state, key: .moveDown)
        state = ListEditor.reduce(state, key: .toggleDone)
        state = ListEditor.reduce(state, key: .setAnchor)

        XCTAssertEqual(state.selection, 1)
        XCTAssertTrue(state.list.items[1].done)
        XCTAssertEqual(state.anchorIndex, 1)
    }

    func testIndentAndUnindentMoveTheSelectedSubtree() {
        let list = TodoList(items: [
            Item(text: "First", depth: 0, done: false),
            Item(text: "Parent", depth: 0, done: false),
            Item(text: "Child", depth: 1, done: false),
            Item(text: "Last", depth: 0, done: false),
        ])
        var state = ListEditorState(list: list, selection: 1, anchorIndex: 1)

        state = ListEditor.reduce(state, key: .indent)
        XCTAssertEqual(state.list.items.map(\.depth), [0, 1, 2, 0])

        state = ListEditor.reduce(state, key: .unindent)
        XCTAssertEqual(state.list.items.map(\.depth), [0, 0, 1, 0])
        XCTAssertEqual(state.anchorIndex, 1)
    }

    func testInvalidIndentAndRootUnindentAreNoOps() {
        let list = TodoList(items: [
            Item(text: "Root", depth: 0, done: false),
            Item(text: "Child", depth: 1, done: false),
        ])

        let root = ListEditorState(list: list, selection: 0, anchorIndex: nil)
        XCTAssertEqual(ListEditor.reduce(root, key: .unindent), root)

        let child = ListEditorState(list: list, selection: 1, anchorIndex: nil)
        XCTAssertEqual(ListEditor.reduce(child, key: .indent), child)
    }

    func testReturnOpensASiblingBelowTheWholeSubtree() {
        let list = TodoList(items: [
            Item(text: "Parent", depth: 0, done: false),
            Item(text: "Child", depth: 1, done: false),
            Item(text: "Last", depth: 0, done: false),
        ])
        var state = ListEditorState(list: list, selection: 0, anchorIndex: 2)

        state = ListEditor.reduce(state, key: .newLine)

        // After the child, not between parent and child.
        XCTAssertEqual(state.selection, 2)
        XCTAssertEqual(state.editingText, "")
        XCTAssertEqual(state.list.items.map(\.text), ["Parent", "Child", "", "Last"])
        XCTAssertEqual(state.list.items.map(\.depth), [0, 1, 0, 0])
        XCTAssertEqual(state.anchorIndex, 3)
    }

    func testTypingGoesStraightIntoTheItem() {
        let list = TodoList(items: [Item(text: "", depth: 0, done: false)])
        var state = ListEditorState(list: list, selection: 0, anchorIndex: nil)

        state = ListEditor.reduce(state, key: .replaceText("Write the thing"))

        XCTAssertEqual(state.list.items.map(\.text), ["Write the thing"])
        XCTAssertEqual(state.editingText, "Write the thing")
    }

    /// The Markdown habit: Return on an empty nested line climbs back out instead of
    /// stacking more blank rows.
    func testReturnOnAnEmptyLineOutdentsAndThenDoesNothing() {
        let list = TodoList(items: [
            Item(text: "Parent", depth: 0, done: false),
            Item(text: "", depth: 1, done: false),
        ])
        var state = ListEditorState(list: list, selection: 1, anchorIndex: nil)

        state = ListEditor.reduce(state, key: .newLine)
        XCTAssertEqual(state.list.items.map(\.depth), [0, 0])
        XCTAssertEqual(state.list.items.count, 2)

        let settled = ListEditor.reduce(state, key: .newLine)
        XCTAssertEqual(settled.list.items.count, 2, "An empty root line must not multiply.")
    }

    /// Backspace goes back, at any depth. Outdenting first meant a nested blank line took
    /// several presses to disappear.
    func testBackspaceOnAnEmptyLineJumpsToTheLineAbove() {
        let list = TodoList(items: [
            Item(text: "Parent", depth: 0, done: false),
            Item(text: "", depth: 1, done: false),
        ])
        var state = ListEditorState(list: list, selection: 1, anchorIndex: 0)

        state = ListEditor.reduce(state, key: .deleteBackward)

        XCTAssertEqual(state.list.items.map(\.text), ["Parent"])
        XCTAssertEqual(state.selection, 0)
        XCTAssertEqual(state.anchorIndex, 0)
    }

    /// Deleting the last task used to leave the overlay with no text field, and therefore
    /// no keyboard at all: no typing, no Return, no ⌘K.
    func testTheEditorAlwaysKeepsOneLineToTypeIn() {
        let empty = ListEditorState(list: TodoList(items: []), selection: nil, anchorIndex: nil)
        XCTAssertEqual(empty.list.items.count, 1)
        XCTAssertEqual(empty.selection, 0)
        XCTAssertEqual(empty.editingText, "")

        let single = ListEditorState(
            list: TodoList(items: [Item(text: "", depth: 0, done: false)]),
            selection: 0,
            anchorIndex: nil
        )
        let afterBackspace = ListEditor.reduce(single, key: .deleteBackward)
        XCTAssertEqual(afterBackspace.list.items.count, 1)
        XCTAssertEqual(afterBackspace.selection, 0)

        // And typing into that line works, which is the whole point of keeping it.
        let typed = ListEditor.reduce(afterBackspace, key: .replaceText("First task"))
        XCTAssertEqual(typed.list.items.map(\.text), ["First task"])
    }

    func testDeletingTheOnlyRemainingTaskLeavesABlankLineNotAVoid() {
        let list = TodoList(items: [Item(text: "Last one", depth: 0, done: false)])
        var state = ListEditorState(list: list, selection: 0, anchorIndex: 0)

        state = ListEditor.reduce(state, key: .replaceText(""))
        state = ListEditor.reduce(state, key: .deleteBackward)

        XCTAssertEqual(state.list.items.count, 1)
        XCTAssertEqual(state.editingText, "")
    }

    func testBackspaceOnALineWithTextIsLeftToTheTextField() {
        let list = TodoList(items: [Item(text: "Keep", depth: 0, done: false)])
        let state = ListEditorState(list: list, selection: 0, anchorIndex: nil)

        XCTAssertEqual(ListEditor.reduce(state, key: .deleteBackward), state)
    }

    /// An empty line is scratch space, not content. It used to survive into the saved file
    /// as a stray `- [ ]` row.
    func testAnEmptyLineIsDroppedWhenTheCaretLeavesIt() {
        let list = TodoList(items: [
            Item(text: "First", depth: 0, done: false),
            Item(text: "", depth: 0, done: false),
            Item(text: "Third", depth: 0, done: false),
        ])
        var state = ListEditorState(list: list, selection: 1, anchorIndex: 2)

        state = ListEditor.reduce(state, key: .moveDown)

        XCTAssertEqual(state.list.items.map(\.text), ["First", "Third"])
        XCTAssertEqual(state.selection, 1)
        XCTAssertEqual(state.anchorIndex, 1)
    }

    func testEmptyLinesDoNotSurviveClosingOrSwitching() {
        let list = TodoList(items: [
            Item(text: "Keep", depth: 0, done: false),
            Item(text: "", depth: 0, done: false),
        ])

        let closed = ListEditor.reduce(
            ListEditorState(list: list, selection: 1, anchorIndex: 0),
            key: .escape
        )
        XCTAssertEqual(closed.list.items.map(\.text), ["Keep"])
        XCTAssertTrue(closed.shouldClose)

        let switched = ListEditor.reduce(
            ListEditorState(list: list, selection: 1, anchorIndex: 0),
            key: .openSwitcher
        )
        XCTAssertEqual(switched.list.items.map(\.text), ["Keep"])
        XCTAssertTrue(switched.shouldOpenSwitcher)
    }

    func testAnchorRefusesAnEmptyLine() {
        let list = TodoList(items: [Item(text: "", depth: 0, done: false)])
        let state = ListEditorState(list: list, selection: 0, anchorIndex: nil)

        XCTAssertNil(ListEditor.reduce(state, key: .setAnchor).anchorIndex)
    }

    func testDeletingTheLastItemLeavesAValidSelection() {
        let list = TodoList(items: [
            Item(text: "First", depth: 0, done: false),
            Item(text: "Last", depth: 0, done: false),
        ])
        var state = ListEditorState(list: list, selection: 1, anchorIndex: 0)

        state = ListEditor.reduce(state, key: .replaceText(""))
        state = ListEditor.reduce(state, key: .deleteBackward)

        XCTAssertEqual(state.list.items.map(\.text), ["First"])
        XCTAssertEqual(state.selection, 0)
        XCTAssertEqual(state.anchorIndex, 0)
    }
}
