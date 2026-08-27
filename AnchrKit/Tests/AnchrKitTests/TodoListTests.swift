import Foundation
import XCTest
@testable import AnchrKit

final class TodoListTests: XCTestCase {
    func testRealDayFixtureRoundTripsByteForByte() throws {
        let fixtureURL = Self.fixtureURL
        let markdown = try String(contentsOf: fixtureURL, encoding: .utf8)

        let list = TodoList(markdown: markdown)

        XCTAssertEqual(list.markdown, markdown)
    }

    func testEditingOneItemChangesOnlyOneLine() throws {
        let fixtureURL = Self.fixtureURL
        let markdown = try String(contentsOf: fixtureURL, encoding: .utf8)
        var list = TodoList(markdown: markdown)

        list.items[3].text = "Review the final analysis draft in Notion"

        let before = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        let after = list.markdown.split(separator: "\n", omittingEmptySubsequences: false)
        let changedLines = zip(before, after).filter { $0 != $1 }
        XCTAssertEqual(changedLines.count, 1)
        XCTAssertEqual(changedLines.first?.1, "- [ ] Review the final analysis draft in Notion")
    }

    func testEmptyBlankAndSingleItemDocumentsSurvive() {
        let cases = [
            "",
            "\n\n",
            "- [ ] One item",
            "- [x] Done item\n",
            "\n- [ ] One item\n\n",
        ]

        for markdown in cases {
            XCTAssertEqual(TodoList(markdown: markdown).markdown, markdown, "Failed for \(String(reflecting: markdown))")
        }
    }

    func testParseClampsDepthToOneMoreThanPreviousItem() {
        let list = TodoList(markdown: "      - [ ] Too deep\n        - [ ] Still too deep\n- [ ] Root\n      - [ ] Child\n")

        XCTAssertEqual(list.items.map(\.depth), [0, 1, 0, 1])
    }

    func testNormalizeMixedGermanPlan() {
        let pasted = """
        # Launch vorbereiten
          * [x] **Briefing lesen**
          2) [[Kundenakte|Notizen öffnen]]
              • Zahlen prüfen
        – Rückfrage senden
        \t+ Antwort dokumentieren

        """

        XCTAssertEqual(
            TodoList.normalize(pasted: pasted),
            [
                Item(text: "Launch vorbereiten", depth: 0, done: false),
                Item(text: "Briefing lesen", depth: 1, done: true),
                Item(text: "Notizen öffnen", depth: 1, done: false),
                Item(text: "Zahlen prüfen", depth: 2, done: false),
                Item(text: "Rückfrage senden", depth: 0, done: false),
                Item(text: "Antwort dokumentieren", depth: 1, done: false),
            ]
        )
    }

    func testNormalizeClampsIndentJumpsAndSupportsNumberedParentheses() {
        let pasted = """
        1) First
                2. Jumped child
        Plain line
        """

        XCTAssertEqual(
            TodoList.normalize(pasted: pasted),
            [
                Item(text: "First", depth: 0, done: false),
                Item(text: "Jumped child", depth: 1, done: false),
                Item(text: "Plain line", depth: 0, done: false),
            ]
        )
    }

    private static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/lists/real-day.md")
    }
}
