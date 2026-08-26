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

    func testCreateFromPasteWritesNormalizedListBytes() throws {
        let slug = try store.createFromPaste(
            name: "Launch",
            pasted: "# Launch\n  * [x] **Briefing lesen**\n  2) [[Kundenakte|Notizen öffnen]]",
            context: "Release context"
        )

        let bytes = try Data(contentsOf: rootURL
            .appendingPathComponent("lists")
            .appendingPathComponent(slug)
            .appendingPathComponent("list.md"))

        XCTAssertEqual(
            String(decoding: bytes, as: UTF8.self),
            "- [ ] Launch\n  - [x] Briefing lesen\n  - [ ] Notizen öffnen\n"
        )
        XCTAssertEqual(try store.loadContext(slug: slug), "Release context")
    }

    func testCreateFromPasteUsesFirstItemWhenNameIsEmpty() throws {
        let slug = try store.createFromPaste(
            name: "  ",
            pasted: "- A deliberately long first task name that is longer than forty characters\n- Next",
            context: ""
        )

        XCTAssertEqual(slug, "a-deliberately-long-first-task-name-that")
        XCTAssertEqual(try store.listSummaries().first?.name, "A deliberately long first task name that")
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

    func testSetNewAnchorWritesSiblingAfterCurrentSubtree() throws {
        let slug = try store.create(
            name: "Work",
            items: [
                Item(text: "Parent", depth: 0, done: false),
                Item(text: "Current", depth: 1, done: false),
                Item(text: "Current child", depth: 2, done: false),
                Item(text: "Later", depth: 1, done: false),
            ],
            context: ""
        )
        try store.saveState(AppState(activeListSlug: slug, anchorIndex: 1, snoozeDeadline: nil))

        let anchor = try store.setNewAnchor(text: "Different work")

        XCTAssertEqual(anchor.index, 3)
        XCTAssertEqual(try store.loadList(slug: slug).items[3], Item(text: "Different work", depth: 1, done: false))
        XCTAssertEqual(try store.loadState().anchorIndex, 3)
    }

    func testSnoozeOnlyUpdatesTheDeadline() throws {
        let slug = try store.create(
            name: "Work",
            items: [Item(text: "Keep working", depth: 0, done: false)],
            context: "Keep this context"
        )
        let original = AppState(activeListSlug: slug, anchorIndex: 0, snoozeDeadline: nil)
        try store.saveState(original)
        let deadline = Date(timeIntervalSince1970: 1_800_000_000)

        try store.snooze(until: deadline)

        XCTAssertEqual(
            try store.loadState(),
            AppState(activeListSlug: slug, anchorIndex: 0, snoozeDeadline: deadline)
        )
        XCTAssertEqual(try store.loadList(slug: slug).items, [
            Item(text: "Keep working", depth: 0, done: false),
        ])
        XCTAssertEqual(try store.loadContext(slug: slug), "Keep this context")
    }

    func testListSummariesPreserveNamesAndReportOpenItemsAndContext() throws {
        _ = try store.create(
            name: "Uni — Statistik",
            items: [
                Item(text: "Done", depth: 0, done: true),
                Item(text: "Open", depth: 0, done: false),
            ],
            context: "Exam preparation"
        )
        _ = try store.create(
            name: "Home",
            items: [Item(text: "Open", depth: 0, done: false)],
            context: "  "
        )

        XCTAssertEqual(try store.listSummaries(), [
            ListSummary(slug: "home", name: "Home", openItemCount: 1, hasContext: false),
            ListSummary(slug: "uni-statistik", name: "Uni — Statistik", openItemCount: 1, hasContext: true),
        ])
    }
}
