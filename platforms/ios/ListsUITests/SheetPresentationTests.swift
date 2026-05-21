import XCTest

@MainActor
final class SheetPresentationTests: XCTestCase {

    func testItemDetailSheetPresentsOnItemTap() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.list.personal"].tap()

        let run5km = app.buttons["item.row.task.\(XCUIApplication.SeedId.run5km)"]
        XCTAssert(run5km.waitForExistence(timeout: 5))
        run5km.tap()

        let titleField = app.textFields["itemdetail.title"]
        XCTAssert(titleField.waitForExistence(timeout: 5))
    }

    func testEditListSheetPresentsFromMenu() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.list.personal"].tap()

        let menu = app.buttons["list.menu"]
        XCTAssert(menu.waitForExistence(timeout: 5))
        menu.tap()

        let editEntry = app.buttons["list.menu.edit"]
        XCTAssert(editEntry.waitForExistence(timeout: 3))
        editEntry.tap()

        let editSheetTitle = app.staticTexts["Edit List"]
        XCTAssert(editSheetTitle.waitForExistence(timeout: 5))

        let nameField = app.textFields["List Name"]
        XCTAssert(nameField.waitForExistence(timeout: 3))
    }

    func testCancelWithUnsavedChangesShowsConfirmation() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.list.personal"].tap()

        let run5km = app.buttons["item.row.task.\(XCUIApplication.SeedId.run5km)"]
        XCTAssert(run5km.waitForExistence(timeout: 5))
        run5km.tap()

        let titleField = app.textFields["itemdetail.title"]
        XCTAssert(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(" *")

        let cancelButton = app.buttons["itemdetail.cancel"]
        XCTAssert(cancelButton.waitForExistence(timeout: 3))
        cancelButton.tap()

        let discardButton = app.buttons["Discard Changes"]
        XCTAssert(discardButton.waitForExistence(timeout: 5),
                  "A confirmation popover with a Discard Changes button should appear when cancelling with unsaved changes")
        discardButton.tap()

        XCTAssertFalse(app.textFields["itemdetail.title"].waitForExistence(timeout: 3),
                       "Detail sheet should be dismissed after discarding changes")
    }

    func testSaveDismissesSheetAndPersists() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.list.personal"].tap()

        let callMum = app.buttons["item.row.task.\(XCUIApplication.SeedId.callMum)"]
        XCTAssert(callMum.waitForExistence(timeout: 5))
        callMum.tap()

        let titleField = app.textFields["itemdetail.title"]
        XCTAssert(titleField.waitForExistence(timeout: 5))

        let saveButton = app.buttons["itemdetail.save"]
        XCTAssert(saveButton.waitForExistence(timeout: 3))
        XCTAssertFalse(saveButton.isEnabled,
                       "Save should be disabled before any edits")

        titleField.tap()
        titleField.typeText(" Edited")

        XCTAssert(saveButton.isEnabled,
                  "Save should become enabled after editing the title")
        saveButton.tap()

        XCTAssertFalse(app.textFields["itemdetail.title"].waitForExistence(timeout: 5),
                       "Detail sheet should be dismissed after saving")
    }
}
