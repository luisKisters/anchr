import Foundation
import XCTest
import AnchrKit
import AnchrKitTestSupport
@testable import AnchrCore

@MainActor
final class ObservationLoopE2ETests: XCTestCase {
    func testScriptedSequenceAppendsOneChildAndMovesAnchorInsideBoundRoot() async throws {
        let sandboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ObservationLoopE2E-\(UUID().uuidString)", isDirectory: true)
        let supportURL = sandboxURL.appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        let outsideURL = sandboxURL.appendingPathComponent("outside.txt")
        try Data("unchanged".utf8).write(to: outsideURL)
        defer { try? FileManager.default.removeItem(at: sandboxURL) }

        let store = ListStore(rootURL: supportURL)
        let slug = try store.create(
            name: "Build",
            items: [Item(text: "Implement observation loop", depth: 0, done: false)],
            context: "Native macOS focus app"
        )
        try store.saveState(AppState(activeListSlug: slug, anchorIndex: 0, snoozeDeadline: nil))

        let clock = TestClock(now: Date(timeIntervalSince1970: 10_000))
        let focusSource = ManualLoopFocusSource()
        let snapshotter = StubSnapshotter(result: AXSnapshotResult(
            text: "Window: ObservationLoop.swift\nStaticText: func checkIfDue",
            visitedNodeCount: 2,
            lineCount: 2,
            usefulCharacterCount: 59
        ))
        let classifier = ScriptedClassifier(verdicts: [
            Verdict(verdict: .onTask, evidence: "Editing loop", smallerStep: "Keep editing"),
            Verdict(verdict: .offTask, evidence: "Reading news", smallerStep: "Write one test"),
            Verdict(verdict: .offTask, evidence: "Still reading news", smallerStep: "Run focused test"),
        ])
        var interventions: [Verdict] = []
        let loop = ObservationLoop(
            clock: clock,
            focusSource: focusSource,
            snapshotter: snapshotter,
            classifier: classifier,
            store: store
        ) { verdict in
            interventions.append(verdict)
            _ = try store.goSmaller(text: verdict.smallerStep)
        }

        loop.start()
        focusSource.send(FocusContext(
            bundleIdentifier: "com.apple.dt.Xcode",
            processIdentifier: 42,
            windowTitle: "ObservationLoop.swift"
        ))

        for elapsed in [8.0, 98.0, 188.0] {
            clock.now = Date(timeIntervalSince1970: 10_000 + elapsed)
            let verdict = try await loop.checkIfDue()
            XCTAssertNotNil(verdict)
        }
        loop.stop()

        XCTAssertEqual(interventions.count, 1)
        XCTAssertEqual(try store.loadState().anchorIndex, 1)
        XCTAssertEqual(
            try store.loadList(slug: slug).items,
            [
                Item(text: "Implement observation loop", depth: 0, done: false),
                Item(text: "Run focused test", depth: 1, done: false),
            ]
        )
        XCTAssertEqual(snapshotter.preparedProcessIdentifiers, [42])
        XCTAssertEqual(snapshotter.readProcessIdentifiers, [42, 42, 42])
        XCTAssertEqual(try String(contentsOf: outsideURL, encoding: .utf8), "unchanged")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: sandboxURL.path).sorted(),
            ["Application Support", "outside.txt"]
        )
    }

    func testEmptySnapshotFallsBackToPushedAppAndWindowTitle() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ObservationFallback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ListStore(rootURL: rootURL)
        let slug = try store.create(
            name: "Fallback",
            items: [Item(text: "Use title", depth: 0, done: false)],
            context: ""
        )
        try store.saveState(AppState(activeListSlug: slug, anchorIndex: 0, snoozeDeadline: nil))
        let clock = TestClock(now: Date(timeIntervalSince1970: 20_000))
        let source = ManualLoopFocusSource()
        let classifier = RecordingClassifier()
        let loop = ObservationLoop(
            clock: clock,
            focusSource: source,
            snapshotter: StubSnapshotter(result: AXSnapshotResult(
                text: "",
                visitedNodeCount: 3,
                lineCount: 0,
                usefulCharacterCount: 0
            )),
            classifier: classifier,
            store: store,
            onIntervention: { _ in }
        )
        loop.start()
        source.send(FocusContext(
            bundleIdentifier: "com.example.Browser",
            processIdentifier: 7,
            windowTitle: "Swift Accessibility Documentation"
        ))
        clock.now = clock.now.addingTimeInterval(8)

        _ = try await loop.checkIfDue()

        let observation = await classifier.observations.first
        XCTAssertEqual(
            observation?.accessibilityText,
            "App: com.example.Browser\nWindow: Swift Accessibility Documentation"
        )
    }

    func testActivationPreparationFailureDoesNotPoisonLaterChecks() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ObservationPermission-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = ListStore(rootURL: rootURL)
        let slug = try store.create(
            name: "Permission",
            items: [Item(text: "Resume observation", depth: 0, done: false)],
            context: ""
        )
        try store.saveState(AppState(activeListSlug: slug, anchorIndex: 0, snoozeDeadline: nil))
        let clock = TestClock(now: Date(timeIntervalSince1970: 30_000))
        let source = ManualLoopFocusSource()
        let snapshotter = RecoveringSnapshotter()
        let classifier = RecordingClassifier()
        let loop = ObservationLoop(
            clock: clock,
            focusSource: source,
            snapshotter: snapshotter,
            classifier: classifier,
            store: store,
            onIntervention: { _ in }
        )
        loop.start()
        source.send(FocusContext(
            bundleIdentifier: "com.example.Editor",
            processIdentifier: 99,
            windowTitle: "Permission restored"
        ))
        clock.now = clock.now.addingTimeInterval(8)

        let verdict = try await loop.checkIfDue()

        XCTAssertEqual(verdict?.verdict, .onTask)
        XCTAssertEqual(snapshotter.readProcessIdentifiers, [99])
    }
}

@MainActor
private final class TestClock: ObservationClock {
    var now: Date
    init(now: Date) { self.now = now }
}

@MainActor
private final class ManualLoopFocusSource: FocusContextSource {
    private var handler: ((FocusContext) -> Void)?
    func start(handler: @escaping (FocusContext) -> Void) { self.handler = handler }
    func stop() { handler = nil }
    func send(_ context: FocusContext) { handler?(context) }
}

@MainActor
private final class StubSnapshotter: ObservationSnapshotting {
    let result: AXSnapshotResult
    private(set) var preparedProcessIdentifiers: [Int32] = []
    private(set) var readProcessIdentifiers: [Int32] = []

    init(result: AXSnapshotResult) { self.result = result }

    func applicationDidBecomeFrontmost(processIdentifier: Int32) throws {
        preparedProcessIdentifiers.append(processIdentifier)
    }

    func snapshotForCheck(processIdentifier: Int32) throws -> AXSnapshotResult? {
        readProcessIdentifiers.append(processIdentifier)
        return result
    }
}

@MainActor
private final class RecoveringSnapshotter: ObservationSnapshotting {
    enum Failure: Error {
        case permissionNotGranted
    }

    private(set) var readProcessIdentifiers: [Int32] = []

    func applicationDidBecomeFrontmost(processIdentifier: Int32) throws {
        throw Failure.permissionNotGranted
    }

    func snapshotForCheck(processIdentifier: Int32) throws -> AXSnapshotResult? {
        readProcessIdentifiers.append(processIdentifier)
        return nil
    }
}

private actor RecordingClassifier: DriftClassifier {
    private(set) var observations: [Observation] = []

    func classify(_ observation: Observation) async throws -> Verdict {
        observations.append(observation)
        return Verdict(verdict: .onTask, evidence: "Title matches", smallerStep: "Continue")
    }
}
