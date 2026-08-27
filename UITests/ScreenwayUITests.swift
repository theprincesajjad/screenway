import XCTest

/// Gate 1 keeps the UI-test target intentionally minimal; flows are covered
/// by unit tests against the mock clients.
final class ScreenwayUITests: XCTestCase {
    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.state == .runningForeground)
    }
}
