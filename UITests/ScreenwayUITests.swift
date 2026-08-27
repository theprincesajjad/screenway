import XCTest

/// The UI-test target stays intentionally minimal; flows are covered by unit
/// tests against the mock clients. UI tests always launch the app with the
/// mock-adapter argument so no test ever opens a real socket.
final class ScreenwayUITests: XCTestCase {
    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-screenway-mock-adapters"]
        app.launch()
        XCTAssertTrue(app.state == .runningForeground)
    }
}
