import XCTest
@testable import AnchrKit

final class ListEditorTests: XCTestCase {
    func testBrowseKeySequenceMovesTogglesAndSetsAnchor() {
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

    func testNewItemIsInsertedAfterSubtreeAndEmptySaveDeletesIt() {
        let list = TodoList(items: [
            Item(text: "Parent", depth: 0, done: false),
            Item(text: "Child", depth: 1, done: false),
            Item(text: "Last", depth: 0, done: false),
        ])
        var state = ListEditorState(list: list, selection: 0, anchorIndex: 2)

        state = ListEditor.reduce(state, key: .newItem)
        XCTAssertEqual(state.selection, 2)
        XCTAssertEqual(state.editingText, "")
        XCTAssertEqual(state.list.items.map(\.text), ["Parent", "Child", "", "Last"])
        XCTAssertEqual(state.anchorIndex, 3)

        state = ListEditor.reduce(state, key: .enter)
        XCTAssertEqual(state.list.items.map(\.text), ["Parent", "Child", "Last"])
        XCTAssertEqual(state.selection, 1)
        XCTAssertEqual(state.anchorIndex, 2)
        XCTAssertNil(state.editingText)
    }

    func testDeletingLastItemLeavesAValidSelection() {
        let list = TodoList(items: [
            Item(text: "First", depth: 0, done: false),
            Item(text: "Last", depth: 0, done: false),
        ])
        var state = ListEditorState(list: list, selection: 1, anchorIndex: 0)

        state = ListEditor.reduce(state, key: .enter)
        state = ListEditor.reduce(state, key: .replaceEditingText("  "))
        state = ListEditor.reduce(state, key: .enter)

        XCTAssertEqual(state.list.items.map(\.text), ["First"])
        XCTAssertEqual(state.selection, 0)
        XCTAssertEqual(state.anchorIndex, 0)
    }

    func testEscapeCancelsNewItemAndClosesOnlyFromBrowseMode() {
        let list = TodoList(items: [Item(text: "Keep", depth: 0, done: false)])
        var state = ListEditorState(list: list, selection: 0, anchorIndex: 0)

        state = ListEditor.reduce(state, key: .newItem)
        state = ListEditor.reduce(state, key: .replaceEditingText("Discard"))
        state = ListEditor.reduce(state, key: .escape)

        XCTAssertEqual(state.list.items.map(\.text), ["Keep"])
        XCTAssertFalse(state.shouldClose)

        state = ListEditor.reduce(state, key: .escape)
        XCTAssertTrue(state.shouldClose)
    }

    func testCommandKRequestsSwitcherOnlyFromBrowseMode() {
        let list = TodoList(items: [Item(text: "Keep", depth: 0, done: false)])
        var state = ListEditorState(list: list, selection: 0, anchorIndex: 0)

        state = ListEditor.reduce(state, key: .openSwitcher)
        XCTAssertTrue(state.shouldOpenSwitcher)

        var editing = ListEditor.reduce(
            ListEditorState(list: list, selection: 0, anchorIndex: 0),
            key: .enter
        )
        editing = ListEditor.reduce(editing, key: .openSwitcher)
        XCTAssertFalse(editing.shouldOpenSwitcher)
    }
}
