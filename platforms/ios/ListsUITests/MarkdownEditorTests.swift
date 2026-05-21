import XCTest

@MainActor
final class MarkdownEditorTests: XCTestCase {

    func testOpenEditorFromItemDetail() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.list.personal"].tap()

        let run5km = app.buttons["item.row.task.\(XCUIApplication.SeedId.run5km)"]
        XCTAssert(run5km.waitForExistence(timeout: 5))
        run5km.tap()

        let expand = app.buttons["item.notes.expand"]
        XCTAssert(expand.waitForExistence(timeout: 5))
        expand.tap()

        let editor = app.textViews["markdown.editor"]
        XCTAssert(editor.waitForExistence(timeout: 5))
    }

    func testTypeAndVerifyCursor() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.list.personal"].tap()

        let run5km = app.buttons["item.row.task.\(XCUIApplication.SeedId.run5km)"]
        XCTAssert(run5km.waitForExistence(timeout: 5))
        run5km.tap()

        let expand = app.buttons["item.notes.expand"]
        XCTAssert(expand.waitForExistence(timeout: 5))
        expand.tap()

        let editor = app.textViews["markdown.editor"]
        XCTAssert(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Hello world")

        let descendants = app.descendants(matching: .any).matching(identifier: "markdown.editor.cursor")
        let cursor = descendants.firstMatch
        XCTAssert(cursor.waitForExistence(timeout: 5),
                  "markdown.editor.cursor element should expose selectedRange")
        XCTAssertEqual(cursor.value as? String, "11-0",
                       "Cursor indicator should reflect location 11, length 0 after typing 'Hello world'")
    }

    func testModePickerSwitchesToRaw() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.list.personal"].tap()

        let run5km = app.buttons["item.row.task.\(XCUIApplication.SeedId.run5km)"]
        XCTAssert(run5km.waitForExistence(timeout: 5))
        run5km.tap()

        let expand = app.buttons["item.notes.expand"]
        XCTAssert(expand.waitForExistence(timeout: 5))
        expand.tap()

        XCTAssert(app.textViews["markdown.editor"].waitForExistence(timeout: 5))

        let rawSegment = app.buttons["markdown.mode.raw"]
        XCTAssert(rawSegment.waitForExistence(timeout: 5))
        rawSegment.tap()

        XCTAssert(app.textViews["markdown.editor"].waitForExistence(timeout: 3),
                  "Markdown editor stays visible after switching to raw mode")
    }

    func testDoneButtonSaves() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.list.personal"].tap()

        let run5km = app.buttons["item.row.task.\(XCUIApplication.SeedId.run5km)"]
        XCTAssert(run5km.waitForExistence(timeout: 5))
        run5km.tap()

        let expand = app.buttons["item.notes.expand"]
        XCTAssert(expand.waitForExistence(timeout: 5))
        expand.tap()

        let editor = app.textViews["markdown.editor"]
        XCTAssert(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("note text")

        let done = app.buttons["markdown.done"]
        XCTAssert(done.waitForExistence(timeout: 5))
        done.tap()

        XCTAssertFalse(app.textViews["markdown.editor"].waitForExistence(timeout: 3),
                       "Markdown editor should be dismissed after Done")
        XCTAssert(app.textFields["itemdetail.title"].waitForExistence(timeout: 5),
                  "Should return to item detail sheet after Done")
    }

    func testCloseButtonDiscards() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.list.personal"].tap()

        let run5km = app.buttons["item.row.task.\(XCUIApplication.SeedId.run5km)"]
        XCTAssert(run5km.waitForExistence(timeout: 5))
        run5km.tap()

        let expand = app.buttons["item.notes.expand"]
        XCTAssert(expand.waitForExistence(timeout: 5))
        expand.tap()

        let editor = app.textViews["markdown.editor"]
        XCTAssert(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("discardable")

        let close = app.buttons["markdown.close"]
        XCTAssert(close.waitForExistence(timeout: 5))
        close.tap()

        XCTAssertFalse(app.textViews["markdown.editor"].waitForExistence(timeout: 3),
                       "Markdown editor should be dismissed after Close")
    }
}
