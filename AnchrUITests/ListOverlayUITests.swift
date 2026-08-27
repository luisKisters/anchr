import XCTest

/// The GUI smoke: proves the real app renders a real list and that a real key press
/// moves through it.
///
/// The reducer in `AnchrKit/ListEditor.swift` is where key handling is proven
/// exhaustively. These cases prove only the wiring — that SwiftUI is actually bound to
/// that reducer, which no unit test can show.
final class ListOverlayUITests: AnchrUITestCase {
    private let seed = """
    - [ ] Ship the OpenRouter classifier
      - [ ] Write the request builder
    - [ ] Update the plan
    """

    func testOverlayShowsTheSeededList() {
        launch(seedList: seed)

        let firstItem = element("listItem_0")
        XCTAssertTrue(
            firstItem.waitForExistence(timeout: 20),
            "The overlay should render the seeded list after launch."
        )
        XCTAssertEqual(accessibleText(firstItem), "Ship the OpenRouter classifier")
        XCTAssertEqual(accessibleText(element("listItem_1")), "Write the request builder")
        XCTAssertEqual(accessibleText(element("listItem_2")), "Update the plan")
    }

    func testArrowKeyMovesTheSelectionThroughTheRealView() {
        launch(seedList: seed)
        XCTAssertTrue(element("listItem_0").waitForExistence(timeout: 20))

        // The selection starts on the anchor, which the fixture puts on the first row.
        XCTAssertTrue(element("listRow_selected").exists)
        XCTAssertFalse(element("listRow_0").exists)

        app.typeKey(.downArrow, modifierFlags: [])

        // Row 0 becomes an ordinary row once the selection has moved off it.
        XCTAssertTrue(
            element("listRow_0").waitForExistence(timeout: 5),
            "Pressing down should move the selection off the first row."
        )
        XCTAssertTrue(element("listRow_selected").exists)
    }

    func testCommandDChecksTheSelectedItem() {
        launch(seedList: seed)
        XCTAssertTrue(element("listCheckbox_0_open").waitForExistence(timeout: 20))

        app.typeKey("d", modifierFlags: .command)

        XCTAssertTrue(
            element("listCheckbox_0_done").waitForExistence(timeout: 5),
            "Command-D should check the selected item."
        )
        XCTAssertFalse(element("listCheckbox_0_open").exists)
    }

    /// The reason every command took a modifier: a plain letter has to reach the line.
    func testTypingALetterEditsTheSelectedLineInsteadOfActingAsAShortcut() {
        launch(seedList: seed)
        let first = element("listItem_0")
        XCTAssertTrue(first.waitForExistence(timeout: 20))

        app.typeText("!")

        XCTAssertTrue(
            accessibleText(element("listItem_0")).contains("!"),
            "A typed character belongs in the task, not in a shortcut."
        )
    }

    /// The path that kept shipping broken: press Return, then type. Nothing before this
    /// test covered it — the other cases type into a row that was already selected at
    /// launch, so a caret that never follows the selection still passed.
    func testReturnThenTypingLandsInTheNewLine() {
        launch(seedList: seed)
        XCTAssertTrue(element("listItem_0").waitForExistence(timeout: 20))

        app.typeKey(.enter, modifierFlags: [])
        app.typeText("fresh line")

        let rows = (0...3).map { accessibleText(element("listItem_\($0)")) }
        XCTAssertTrue(
            rows.contains { $0.contains("fresh line") },
            "After Return the caret must be in the new line. Rows were: \(rows)"
        )
    }

    func testShiftTabOutdentsWithoutTheMouse() {
        launch(seedList: seed)
        XCTAssertTrue(element("listItem_0").waitForExistence(timeout: 20))

        // Row 1 is seeded as a child of row 0.
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey("\t", modifierFlags: .shift)
        app.typeText("!")

        XCTAssertTrue(
            accessibleText(element("listItem_1")).contains("!"),
            "Shift-Tab must not move focus out of the line."
        )
    }

    /// The dead-app case: delete every task and the overlay used to lose its keyboard
    /// entirely — no typing, no Return, no ⌘K, nothing but quitting.
    func testAnEmptyListCanStillBeTypedIn() {
        launch(seedList: "- [ ] Only task")
        XCTAssertTrue(element("listItem_0").waitForExistence(timeout: 20))

        // Clear the only line, then delete it.
        for _ in 0..<"Only task".count {
            app.typeKey(.delete, modifierFlags: [])
        }
        app.typeKey(.delete, modifierFlags: [])

        app.typeText("brand new task")

        XCTAssertTrue(
            accessibleText(element("listItem_0")).contains("brand new task"),
            "An empty list must still hold the caret."
        )
    }

    /// Moving between lines used to select the whole task, so the next keystroke replaced
    /// it. The caret belongs at the end of the text.
    func testMovingToAnotherLineDoesNotSelectItsText() {
        launch(seedList: seed)
        XCTAssertTrue(element("listItem_0").waitForExistence(timeout: 20))

        app.typeKey(.downArrow, modifierFlags: [])
        app.typeText("X")

        XCTAssertEqual(
            accessibleText(element("listItem_1")),
            "Write the request builderX",
            "Typing after a move must append, not overwrite."
        )
    }

    /// ⌘K opens the switcher, so ⌘K has to close it again.
    func testCommandKTogglesTheSwitcher() {
        launch(seedList: seed)
        XCTAssertTrue(element("listItem_0").waitForExistence(timeout: 20))

        app.typeKey("k", modifierFlags: .command)
        XCTAssertFalse(
            element("listItem_0").waitForExistence(timeout: 3),
            "The switcher should have replaced the list."
        )

        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(
            element("listItem_0").waitForExistence(timeout: 5),
            "⌘K must close the switcher the same way it opened it."
        )
    }
}
