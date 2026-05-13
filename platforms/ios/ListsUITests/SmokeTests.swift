import XCTest

/// First-light coverage that the XCUITest target works and the page
/// object can drive the live markdown editor. Real feature tests live
/// in the per-element files (`MarkdownInlineTests`, `MarkdownBlockTests`,
/// `MarkdownCursorTests`).
final class SmokeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() throws {
        let app = MarkdownEditorScreen.launchApp()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5),
                      "Lists home screen never appeared")
    }

    @MainActor
    func testCanOpenMarkdownEditorFromTodayItem() throws {
        let app = MarkdownEditorScreen.launchApp()
        let screen = MarkdownEditorScreen.openFromNewItemSheet(in: app)
        // Type one character — proves the editor is focused and receiving keystrokes.
        screen.type("x")
        XCTAssertEqual(screen.source, "x", "Typing one char should produce a one-char source")
    }

    @MainActor
    func testTaskContinuationAfterBatchedTypingKeepsFinalCharacter() throws {
        let app = MarkdownEditorScreen.launchApp()
        let screen = MarkdownEditorScreen.openFromNewItemSheet(in: app)
        let rawMode = app.buttons["markdown.mode.raw"]
        XCTAssertTrue(rawMode.waitForExistence(timeout: 3), "Raw mode control never appeared")
        rawMode.tap()

        screen.type("- [ ] Follow up")
        XCTAssertEqual(screen.source, "- [ ] Follow up")

        screen.pressReturn()
        XCTAssertEqual(screen.source, "- [ ] Follow up\n- [ ] ")
    }

    @MainActor
    func testBareCheckboxMarkerReturnExitsTaskList() throws {
        let app = MarkdownEditorScreen.launchApp()
        let screen = MarkdownEditorScreen.openFromNewItemSheet(in: app)

        screen.type("- [ ]")
        screen.pressReturn()
        XCTAssertEqual(screen.source, "")
    }

    @MainActor
    func testNestedBulletContinuationAfterBatchedTyping() throws {
        let app = MarkdownEditorScreen.launchApp()
        let screen = MarkdownEditorScreen.openFromNewItemSheet(in: app)

        screen.type("- Parent")
        screen.pressReturn()
        screen.pressTab()
        screen.type("Child")
        screen.pressReturn()
        XCTAssertEqual(screen.source, "- Parent\n    - Child\n    - ")
    }

    @MainActor
    func testMarkdownEditorScreenshotsAndCursorMovement() throws {
        let app = MarkdownEditorScreen.launchApp()
        let screen = MarkdownEditorScreen.openFromNewItemSheet(in: app)
        let output = try screenshotDirectory()

        screen.type("""
        # Markdown cursor check

        This line has **bold** and *italic* text.

        - First item
        - Second item

        Final line.
        """)
        try saveScreenshot(named: "01-editor-after-typing", to: output)

        screen.pressKey(.leftArrow, modifierFlags: .command)
        try saveScreenshot(named: "02-cursor-command-left", to: output)

        screen.pressKey(.upArrow)
        screen.pressKey(.upArrow)
        screen.pressKey(.rightArrow)
        screen.pressKey(.rightArrow)
        try saveScreenshot(named: "03-cursor-moved-up-and-right", to: output)

        screen.type(" [cursor]")
        try saveScreenshot(named: "04-cursor-insertion-marker", to: output)
    }

    // Long nested-list / callout walks formerly lived here as
    // `testLongBulletAndTaskListCursorWalkWithScreenshots` and
    // `testCalloutListAndTaskCursorWalkWithScreenshots`. Both depended
    // on the strip-marker backspace behaviour that the rebuild
    // replaces with whole-line delete, and both were already skipped.
    // They are now superseded by `MarkdownCursorNavigationTour` plus
    // the L1 behaviour corpus in `MarkdownEditorBehaviorTests`.

    private func screenshotDirectory() throws -> URL {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dir = repoRoot.appendingPathComponent("artifacts/markdown-editor-screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private func saveScreenshot(named name: String, to directory: URL) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let url = directory.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: url, options: .atomic)

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
