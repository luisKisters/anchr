import XCTest
@testable import AnchrCore

@MainActor
final class FocusContextTests: XCTestCase {
    func testSourcePushesOnlyChangedContext() {
        let source = FocusContextRelay()
        var received: [FocusContext] = []
        source.start { received.append($0) }

        source.publish(FocusContext(
            bundleIdentifier: "com.example.Editor",
            processIdentifier: 42,
            windowTitle: "Plan.md"
        ))
        source.publish(FocusContext(
            bundleIdentifier: "com.example.Editor",
            processIdentifier: 42,
            windowTitle: "Plan.md"
        ))
        source.publish(FocusContext(
            bundleIdentifier: "com.example.Editor",
            processIdentifier: 42,
            windowTitle: "Tests"
        ))

        XCTAssertEqual(received.map(\.windowTitle), ["Plan.md", "Tests"])
    }
}
