import XCTest

@MainActor
final class ListsUITestsPreflight: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing-reset-data"]
        app.launch()

        XCTAssert(app.buttons["floating.add"].waitForExistence(timeout: 10),
                  "FAB never appeared — bootstrap may have failed")
    }
}
