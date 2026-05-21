import XCTest

@MainActor
final class SwipeActionsTests: XCTestCase {

    func testSwipeLeftRevealsDeleteOnItem() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.list.work"].tap()

        let emailSarah = app.buttons["item.row.task.\(XCUIApplication.SeedId.emailSarah)"]
        XCTAssert(emailSarah.waitForExistence(timeout: 5))
        emailSarah.swipeLeft()

        let deleteButton = app.buttons["Delete"]
        XCTAssert(deleteButton.waitForExistence(timeout: 3))
        XCTAssert(deleteButton.isHittable)
    }

    func testTapDeleteSwipeRemovesItem() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.list.work"].tap()

        let emailSarah = app.buttons["item.row.task.\(XCUIApplication.SeedId.emailSarah)"]
        XCTAssert(emailSarah.waitForExistence(timeout: 5))
        emailSarah.swipeLeft()

        let deleteButton = app.buttons["Delete"]
        XCTAssert(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()

        XCTAssertFalse(emailSarah.waitForExistence(timeout: 3))
    }

    func testTapFlagSwipeFlagsItem() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.list.work"].tap()

        let emailSarah = app.buttons["item.row.task.\(XCUIApplication.SeedId.emailSarah)"]
        XCTAssert(emailSarah.waitForExistence(timeout: 5))
        emailSarah.swipeLeft()

        let flagButton = app.buttons["Flag"]
        XCTAssert(flagButton.waitForExistence(timeout: 3))
        flagButton.tap()

        XCTAssert(emailSarah.waitForExistence(timeout: 3))
        emailSarah.swipeLeft()

        let unflagButton = app.buttons["Unflag"]
        XCTAssert(unflagButton.waitForExistence(timeout: 3))
    }

    func testSwipeRightOutdentOnNestedItem() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.list.personal"].tap()

        let stretchFirst = app.buttons["item.row.task.\(XCUIApplication.SeedId.stretchFirst)"]
        let run5km = app.buttons["item.row.task.\(XCUIApplication.SeedId.run5km)"]
        XCTAssert(stretchFirst.waitForExistence(timeout: 5))
        XCTAssert(run5km.waitForExistence(timeout: 5))

        let initialChildMinX = stretchFirst.frame.minX
        let parentMinX = run5km.frame.minX
        XCTAssertGreaterThan(initialChildMinX, parentMinX,
                             "Stretch first should start indented under Run 5km")

        stretchFirst.swipeRight()

        let outdentButton = app.buttons["Outdent"]
        XCTAssert(outdentButton.waitForExistence(timeout: 3))
        outdentButton.tap()

        XCTAssert(stretchFirst.waitForExistence(timeout: 3))
        let afterMinX = stretchFirst.frame.minX
        XCTAssertEqual(afterMinX, parentMinX, accuracy: 4,
                       "Stretch first should sit at the same indent as Run 5km after outdent")
    }

    func testSwipeRightIndentOnSiblingItem() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.list.projects"].tap()

        let sideApp = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Side App'")).firstMatch
        XCTAssert(sideApp.waitForExistence(timeout: 5))
        sideApp.tap()

        let sprint1 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sprint 1'")).firstMatch
        XCTAssert(sprint1.waitForExistence(timeout: 5))
        sprint1.tap()

        let buildEditor = app.buttons["item.row.task.\(XCUIApplication.SeedId.buildEditor)"]
        let buildSync = app.buttons["item.row.task.\(XCUIApplication.SeedId.buildSync)"]
        XCTAssert(buildEditor.waitForExistence(timeout: 5))
        XCTAssert(buildSync.waitForExistence(timeout: 5))

        let initialMinX = buildEditor.frame.minX

        buildEditor.swipeRight()

        let indentButton = app.buttons["Indent"]
        XCTAssert(indentButton.waitForExistence(timeout: 3))
        indentButton.tap()

        XCTAssert(buildEditor.waitForExistence(timeout: 3))
        let afterMinX = buildEditor.frame.minX
        XCTAssertGreaterThan(afterMinX, initialMinX,
                             "Build editor should be indented after Indent swipe")
    }
}
