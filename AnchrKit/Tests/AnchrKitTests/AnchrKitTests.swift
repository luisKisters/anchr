import XCTest
@testable import AnchrKit

final class AnchrKitTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertNotNil(AnchrKitModule.self)
    }
}
