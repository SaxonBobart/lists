import XCTest

@MainActor
final class SidebarReorderTests: XCTestCase {

    func testTapReorderToggleEntersReorderMode() {
        let app = XCUIApplication()
        app.launchClean()

        let toggle = app.buttons["sidebar.reorder.toggle"]
        XCTAssert(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "Reorder Lists",
                       "Toggle should advertise 'Reorder Lists' while inactive")
        toggle.tap()

        let activeToggle = app.buttons["sidebar.reorder.toggle"]
        XCTAssert(activeToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(activeToggle.label, "Done Reordering",
                       "Toggle should advertise 'Done Reordering' while active")
    }

    func testReorderListsWithOnMove() {
        let app = XCUIApplication()
        app.launchClean()

        let toggle = app.buttons["sidebar.reorder.toggle"]
        XCTAssert(toggle.waitForExistence(timeout: 5))
        toggle.tap()

        let work = app.buttons["sidebar.list.work"]
        let personal = app.buttons["sidebar.list.personal"]
        XCTAssert(work.waitForExistence(timeout: 5))
        XCTAssert(personal.waitForExistence(timeout: 5))

        let initialWorkY = work.frame.midY
        let initialPersonalY = personal.frame.midY
        XCTAssertLessThan(initialWorkY, initialPersonalY,
                          "Precondition: Work is above Personal initially")

        let start = work.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        let end = personal.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 1.0))
        app.pressAndDrag(from: start, to: end, pressDuration: 0.8)
        app.commitDrag(near: end)

        XCTAssert(work.waitForExistence(timeout: 3))
        XCTAssert(personal.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(work.frame.midY, personal.frame.midY,
                             "Work should sit below Personal after reorder")
    }

    func testExitReorderModeWithToggle() {
        let app = XCUIApplication()
        app.launchClean()

        let toggle = app.buttons["sidebar.reorder.toggle"]
        XCTAssert(toggle.waitForExistence(timeout: 5))
        toggle.tap()

        XCTAssertEqual(app.buttons["sidebar.reorder.toggle"].label, "Done Reordering")

        app.buttons["sidebar.reorder.toggle"].tap()

        let finalToggle = app.buttons["sidebar.reorder.toggle"]
        XCTAssert(finalToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(finalToggle.label, "Reorder Lists",
                       "Toggle should revert to 'Reorder Lists' after exit")
    }
}
