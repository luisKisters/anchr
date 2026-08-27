import Foundation
import XCTest

/// Shared process and storage boundary for the GUI cases, after NoteTakr's
/// `NoteTakrUITestCase`.
///
/// The rule it enforces: a UI test never touches the real list. Every run gets its own
/// Application Support root under `/private/tmp`.
///
/// The app creates that directory, not the test. The XCUITest runner is sandboxed on
/// macOS, so it can name a path outside its container but cannot write one — which is
/// also why these cases assert what is on screen rather than what is on disk. The
/// bytes written to `list.md` are proven headlessly by `ObservationLoopE2ETests` and by
/// the Kit round-trip tests.
class AnchrUITestCase: XCTestCase {
    var app: XCUIApplication!
    var appSupportRoot: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        appSupportRoot = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("AnchrUITests-\(UUID().uuidString)", isDirectory: true)
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if testRun?.failureCount ?? 0 > 0 {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "Anchr UI failure"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app?.terminate()
        app = nil
        appSupportRoot = nil
    }

    /// Launches with the overlay already open, because XCUITest cannot press the
    /// system-wide option-space hotkey.
    func launch(seedList: String? = nil) {
        app.launchEnvironment["ANCHR_E2E_APP_SUPPORT_ROOT"] = appSupportRoot.path
        app.launchEnvironment["ANCHR_E2E_SHOW_OVERLAY"] = "1"
        if let seedList {
            app.launchEnvironment["ANCHR_E2E_SEED_LIST"] = seedList
        }
        // No key: the judging loop stays off, so a GUI test never spends money and
        // never depends on the network.
        app.launchEnvironment["OPENROUTER_API_KEY"] = ""
        app.launch()
        app.activate()
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func accessibleText(_ element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }
}
