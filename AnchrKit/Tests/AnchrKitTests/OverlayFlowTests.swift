import XCTest
@testable import AnchrKit

final class OverlayFlowTests: XCTestCase {
    func testSwitcherKeysMoveAndReturnTheSelectedAction() {
        let summaries = [
            ListSummary(slug: "first", name: "First", openItemCount: 2, hasContext: false),
            ListSummary(slug: "second", name: "Second", openItemCount: 1, hasContext: true),
        ]
        var state = SwitcherState(lists: summaries, selectedSlug: "first")

        XCTAssertNil(Switcher.reduce(&state, key: .moveDown))
        XCTAssertEqual(state.selection, 1)
        XCTAssertEqual(Switcher.reduce(&state, key: .open), .openList("second"))
        XCTAssertEqual(Switcher.reduce(&state, key: .editContext), .editContext("second"))
        XCTAssertEqual(Switcher.reduce(&state, key: .newList), .createList)
        XCTAssertEqual(Switcher.reduce(&state, key: .escape), .back)
    }

    func testInterventionKeysHaveNoEscapeAndPrefillSmallerStep() {
        var state = InterventionState(
            anchor: "Send the extraction",
            evidence: "YOUTUBE · 4 MIN",
            smallerStep: "Export the sheet as CSV"
        )

        XCTAssertNil(Intervention.reduce(&state, key: .escape))
        XCTAssertEqual(state.stage, .asking)
        XCTAssertNil(Intervention.reduce(&state, key: .answerSmaller))
        XCTAssertEqual(state.stage, .editing(.smaller, text: "Export the sheet as CSV"))
        XCTAssertNil(Intervention.reduce(&state, key: .replaceText("Export v3")))
        XCTAssertEqual(Intervention.reduce(&state, key: .submit), .goSmaller("Export v3"))
    }

    func testInterventionBackAndNewAnchorActions() {
        var back = InterventionState(anchor: "Old", evidence: "Seen", smallerStep: "Small")
        XCTAssertEqual(Intervention.reduce(&back, key: .answerBack), .snooze)

        var newAnchor = InterventionState(anchor: "Old", evidence: "Seen", smallerStep: "Small")
        XCTAssertNil(Intervention.reduce(&newAnchor, key: .answerNewAnchor))
        XCTAssertEqual(newAnchor.stage, .editing(.newAnchor, text: ""))
        XCTAssertNil(Intervention.reduce(&newAnchor, key: .submit))
        XCTAssertNil(Intervention.reduce(&newAnchor, key: .replaceText("Write release notes")))
        XCTAssertEqual(Intervention.reduce(&newAnchor, key: .submit), .setNewAnchor("Write release notes"))
    }
}
