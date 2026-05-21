import XCTest

@MainActor
final class AddItemTests: XCTestCase {

    func testTapFABOpensQuickCapture() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["floating.add"].tap()

        XCTAssert(app.textFields["quickcapture.title"].waitForExistence(timeout: 5))
    }

    func testFillTitleAndSaveCreatesItem() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["floating.add"].tap()

        let titleField = app.textFields["quickcapture.title"]
        XCTAssert(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Buy oat milk")

        let saveButton = app.buttons["quickcapture.save"]
        XCTAssert(saveButton.waitForExistence(timeout: 3))
        XCTAssert(saveButton.isHittable)
        saveButton.tap()

        let inboxRow = app.buttons["sidebar.list.inbox"]
        XCTAssert(inboxRow.waitForExistence(timeout: 5))
        inboxRow.tap()

        let createdItem = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Buy oat milk'")
        ).firstMatch
        XCTAssert(createdItem.waitForExistence(timeout: 5))
    }

    func testCancelDiscardsItem() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["floating.add"].tap()

        let titleField = app.textFields["quickcapture.title"]
        XCTAssert(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Discard me")

        let cancelButton = app.buttons["quickcapture.cancel"]
        XCTAssert(cancelButton.waitForExistence(timeout: 3))
        XCTAssert(cancelButton.isHittable)
        cancelButton.tap()

        let discardedItem = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Discard me'")
        ).firstMatch
        XCTAssertFalse(discardedItem.waitForExistence(timeout: 2))
    }

    func testTypePickerSwitchesToHabit() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["floating.add"].tap()

        XCTAssert(app.textFields["quickcapture.title"].waitForExistence(timeout: 5))

        let habitTab = app.buttons["quickcapture.type.habit"]
        if !habitTab.exists {
            XCTAssert(app.staticTexts["quickcapture.type.habit"].waitForExistence(timeout: 3))
            app.staticTexts["quickcapture.type.habit"].tap()
        } else {
            habitTab.tap()
        }

        let habitFreqHeader = app.staticTexts["Habit"]
        XCTAssert(habitFreqHeader.waitForExistence(timeout: 3))

        let frequencyRow = app.staticTexts["Frequency"]
        XCTAssert(frequencyRow.waitForExistence(timeout: 3))
    }
}
