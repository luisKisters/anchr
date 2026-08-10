import XCTest
@testable import AnchrCore

final class AXSnapshotTests: XCTestCase {
    func testFlattenerDropsDecorativeNodesDeduplicatesTextAndCapsOutput() {
        let tree = AXSnapshotNode(
            role: "AXWindow",
            title: "Editor",
            children: [
                AXSnapshotNode(
                    role: "AXGroup",
                    children: [
                        AXSnapshotNode(
                            role: "AXButton",
                            title: "Save",
                            value: "Save",
                            description: "Save document"
                        )
                    ]
                ),
                AXSnapshotNode(role: "AXStaticText", value: "Draft body")
            ]
        )

        let result = AXSnapshotWalker.flatten(tree, maximumCharacters: 45)

        XCTAssertEqual(
            result.text,
            "Window: Editor\n  Button: Save | Save document"
        )
        XCTAssertEqual(result.visitedNodeCount, 4)
        XCTAssertEqual(result.lineCount, 3)
        XCTAssertEqual(result.usefulCharacterCount, 69)
    }

    func testActivationPreparesFlagsAndFirstLaterCheckReadsSnapshot() throws {
        let access = RecordingSnapshotAccess()
        let reader = DelayedAXSnapshotReader(access: access)

        try reader.applicationDidBecomeFrontmost(processIdentifier: 42)

        XCTAssertEqual(access.events, [.prepare(42)])
        XCTAssertEqual(
            try reader.snapshotForCheck(processIdentifier: 42),
            AXSnapshotResult(
                text: "Window: Ready",
                visitedNodeCount: 1,
                lineCount: 1,
                usefulCharacterCount: 13
            )
        )
        XCTAssertEqual(access.events, [.prepare(42), .read(42)])
    }

    func testFirstCheckForUnpreparedApplicationOnlyPreparesIt() throws {
        let access = RecordingSnapshotAccess()
        let reader = DelayedAXSnapshotReader(access: access)

        XCTAssertNil(try reader.snapshotForCheck(processIdentifier: 7))
        XCTAssertEqual(access.events, [.prepare(7)])

        XCTAssertNotNil(try reader.snapshotForCheck(processIdentifier: 7))
        XCTAssertEqual(access.events, [.prepare(7), .read(7)])
    }

    func testFailedActivationClearsPreviouslyPreparedApplication() throws {
        let access = RecordingSnapshotAccess()
        let reader = DelayedAXSnapshotReader(access: access)

        try reader.applicationDidBecomeFrontmost(processIdentifier: 42)
        access.failingPreparationProcessIdentifier = 7

        XCTAssertThrowsError(
            try reader.applicationDidBecomeFrontmost(processIdentifier: 7)
        )

        access.failingPreparationProcessIdentifier = nil
        XCTAssertNil(try reader.snapshotForCheck(processIdentifier: 42))
        XCTAssertEqual(access.events, [.prepare(42), .prepare(7), .prepare(42)])
    }
}

private final class RecordingSnapshotAccess: AXSnapshotAccess {
    enum Failure: Error {
        case preparationFailed
    }

    enum Event: Equatable {
        case prepare(Int32)
        case read(Int32)
    }

    private(set) var events: [Event] = []
    var failingPreparationProcessIdentifier: Int32?

    func prepare(processIdentifier: Int32) throws {
        events.append(.prepare(processIdentifier))
        if processIdentifier == failingPreparationProcessIdentifier {
            throw Failure.preparationFailed
        }
    }

    func read(processIdentifier: Int32) throws -> AXSnapshotResult {
        events.append(.read(processIdentifier))
        return AXSnapshotResult(
            text: "Window: Ready",
            visitedNodeCount: 1,
            lineCount: 1,
            usefulCharacterCount: 13
        )
    }
}
