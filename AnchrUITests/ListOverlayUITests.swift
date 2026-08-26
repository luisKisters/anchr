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

    func testSpaceChecksTheSelectedItem() {
        launch(seedList: seed)
        XCTAssertTrue(element("listCheckbox_0_open").waitForExistence(timeout: 20))

        app.typeText(" ")

        XCTAssertTrue(
            element("listCheckbox_0_done").waitForExistence(timeout: 5),
            "Space should check the selected item."
        )
        XCTAssertFalse(element("listCheckbox_0_open").exists)
    }
}
