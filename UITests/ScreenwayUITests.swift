import XCTest

/// Launch smoke test. CI runs this on every PR against an unsigned simulator
/// build; it fails if the app crashes at launch or never reaches its first
/// screen (the regression that shipped a device build crashing on tap).
///
/// UI tests always launch the app with the mock-adapter argument so no test
/// ever opens a real socket.
final class ScreenwayUITests: XCTestCase {
    @MainActor
    func testLaunchReachesWelcomeOrMacsList() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-screenway-mock-adapters"]
        app.launch()

        // First launch shows Welcome; if UserDefaults survived a rerun the
        // app goes straight to the Macs list. Either proves a healthy launch.
        let welcomeTitle = app.staticTexts["Control your Mac privately."]
        let macsNavigationBar = app.navigationBars["Macs"]

        let reachedFirstScreen = welcomeTitle.waitForExistence(timeout: 60)
            || macsNavigationBar.waitForExistence(timeout: 10)
        XCTAssertTrue(
            reachedFirstScreen,
            "App launched but neither the Welcome screen nor the Macs list appeared"
        )
        XCTAssertEqual(app.state, .runningForeground, "App is not in the foreground after launch")
    }
}
