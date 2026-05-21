import XCTest

@MainActor
final class SmartListNavigationTests: XCTestCase {

    func testTapTodayTileShowsTodayView() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.smartlist.today"].tap()

        XCTAssert(app.buttons["today.menu"].waitForExistence(timeout: 5))
    }

    func testTapScheduledTileShowsScheduled() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.smartlist.scheduled"].tap()

        XCTAssert(app.buttons["smartlist.scheduled.menu"].waitForExistence(timeout: 5))
    }

    func testTapFlaggedTileShowsFlaggedItems() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.smartlist.flagged"].tap()

        let payPhoneBill = app.buttons["item.row.task.\(XCUIApplication.SeedId.payPhoneBill)"]
        XCTAssert(payPhoneBill.waitForExistence(timeout: 5))
        XCTAssert(payPhoneBill.isHittable)
    }

    func testSmartListDragIsDisabled() throws {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.smartlist.today"].tap()

        let payPhoneBill = app.buttons["item.row.task.\(XCUIApplication.SeedId.payPhoneBill)"]
        XCTAssert(payPhoneBill.waitForExistence(timeout: 5))

        let initialY = payPhoneBill.frame.midY
        let start = payPhoneBill.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = payPhoneBill.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -3.0))
        app.pressAndDrag(from: start, to: end, pressDuration: 0.8)
        app.commitDrag(near: end)

        XCTAssert(payPhoneBill.waitForExistence(timeout: 3))
        XCTAssertEqual(payPhoneBill.frame.midY, initialY, accuracy: 4,
                       "Smart list rows should not reorder via long-press drag")
    }
}
