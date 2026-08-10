import Foundation
import XCTest
@testable import AnchrKit

final class ListStoreTests: XCTestCase {
    private var rootURL: URL!
    private var store: ListStore!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnchrKitTests-\(UUID().uuidString)", isDirectory: true)
        store = ListStore(rootURL: rootURL)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
        store = nil
    }

    func testCreateListSwitchAndDeletePersistFilesAndState() throws {
        let first = try store.create(
            name: "Work Plan",
            items: [Item(text: "First task", depth: 0, done: false)],
            context: "Work context"
        )
        let second = try store.create(
            name: "Uni — Statistik",
            items: [Item(text: "Übungsblatt 4", depth: 0, done: false)],
            context: ""
        )

        XCTAssertEqual(first, "work-plan")
        XCTAssertEqual(second, "uni-statistik")
        XCTAssertEqual(try store.listSlugs(), ["uni-statistik", "work-plan"])
        XCTAssertEqual(try store.loadState().activeListSlug, "work-plan")
        XCTAssertEqual(try store.loadList(slug: first).items.first?.text, "First task")
        XCTAssertEqual(try store.loadContext(slug: first), "Work context")
        try store.saveContext("Updated context", slug: first)
        XCTAssertEqual(try ListStore(rootURL: rootURL).loadContext(slug: first), "Updated context")

        try store.switchTo(slug: second)
        XCTAssertEqual(try ListStore(rootURL: rootURL).loadState().activeListSlug, second)

        try store.delete(slug: second)
        XCTAssertEqual(try store.listSlugs(), [first])
        XCTAssertEqual(try store.loadState().activeListSlug, first)
    }

    func testDuplicateNamesGetStableUniqueSlugs() throws {
        let first = try store.create(name: "Plan", items: [], context: "")
        let second = try store.create(name: "Plan", items: [], context: "")

        XCTAssertEqual(first, "plan")
        XCTAssertEqual(second, "plan-2")
    }

    func testCorruptStateFallsBackToFirstList() throws {
        _ = try store.create(name: "Zulu", items: [], context: "")
        _ = try store.create(name: "Alpha", items: [], context: "")
        try Data("not json".utf8).write(to: rootURL.appendingPathComponent("state.json"))

        let state = try ListStore(rootURL: rootURL).loadState()

        XCTAssertEqual(state.activeListSlug, "alpha")
        XCTAssertNil(state.anchorIndex)
        XCTAssertNil(state.snoozeDeadline)
    }

    func testStateRoundTripsAnchorAndSnoozeDeadline() throws {
        let deadline = Date(timeIntervalSince1970: 1_800_000_000)
        let slug = try store.create(name: "Work", items: [], context: "")
        let state = AppState(activeListSlug: slug, anchorIndex: 3, snoozeDeadline: deadline)

        try store.saveState(state)

        XCTAssertEqual(try ListStore(rootURL: rootURL).loadState(), state)
    }

    func testGoSmallerPersistsChildAfterAllExistingDescendants() throws {
        let slug = try store.create(
            name: "Work",
            items: [
                Item(text: "Anchor", depth: 0, done: false),
                Item(text: "Existing child", depth: 1, done: false),
                Item(text: "Existing grandchild", depth: 2, done: false),
                Item(text: "Next root", depth: 0, done: false),
            ],
            context: ""
        )
        try store.saveState(AppState(activeListSlug: slug, anchorIndex: 0, snoozeDeadline: nil))

        let anchor = try store.goSmaller(text: "Small next step")

        XCTAssertEqual(anchor.index, 3)
        XCTAssertEqual(anchor.parentIndices, [0])
        XCTAssertEqual(try store.loadState().anchorIndex, 3)
        XCTAssertEqual(
            try store.loadList(slug: slug).items,
            [
                Item(text: "Anchor", depth: 0, done: false),
                Item(text: "Existing child", depth: 1, done: false),
                Item(text: "Existing grandchild", depth: 2, done: false),
                Item(text: "Small next step", depth: 1, done: false),
                Item(text: "Next root", depth: 0, done: false),
            ]
        )
    }

    func testAnchorBuildsFullParentChain() throws {
        let list = TodoList(items: [
            Item(text: "Root", depth: 0, done: false),
            Item(text: "Child", depth: 1, done: false),
            Item(text: "Grandchild", depth: 2, done: false),
            Item(text: "Sibling", depth: 1, done: false),
        ])

        let anchor = try XCTUnwrap(Anchor(index: 2, in: list))

        XCTAssertEqual(anchor.parentIndices, [0, 1])
        XCTAssertEqual(anchor.parentItems(in: list).map(\.text), ["Root", "Child"])
    }
}
