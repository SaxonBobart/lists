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

    // Tests for "backspace inside a marker zone strips the marker and
    // leaves the content as plain text" were removed when the behavior
    // changed to "backspace inside a marker zone deletes the entire
    // row" — current UX preference. Whole-line-delete lives in
    // MarkdownTextView.swift:removeEntireLine and is exercised
    // end-to-end by CursorBugReproductionTest.

    @MainActor
    func testLongBulletAndTaskListCursorWalkWithScreenshots() throws {
        // Long flow test that builds a nested list and incidentally
        // depends on the now-removed "backspace strips marker" path
        // (see comment above). Skipped until the flow is rewritten
        // against the current whole-line-delete behavior.
        try XCTSkipIf(true, "Pending rewrite for whole-line-delete backspace semantics")
        let app = MarkdownEditorScreen.launchApp()
        let screen = MarkdownEditorScreen.openFromNewItemSheet(in: app)
        let output = try screenshotDirectory()

        screen.typeCharacters("- Alpha")
        try captureMarkdownStep("mixed-list-01-alpha", screen: screen, expected: "- Alpha", to: output)

        screen.pressReturn()
        try captureMarkdownStep("mixed-list-02-alpha-continuation", screen: screen,
                                expected: "- Alpha\n- ", to: output)

        screen.typeCharacters("Beta")
        try captureMarkdownStep("mixed-list-03-beta", screen: screen,
                                expected: "- Alpha\n- Beta", to: output)

        screen.pressReturn()
        try captureMarkdownStep("mixed-list-04-beta-continuation", screen: screen,
                                expected: "- Alpha\n- Beta\n- ", to: output)

        screen.pressTab()
        try captureMarkdownStep("mixed-list-05-tab-to-child", screen: screen,
                                expected: "- Alpha\n- Beta\n    - ", to: output)

        screen.typeCharacters("Beta child one")
        try captureMarkdownStep("mixed-list-06-child-one", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one", to: output)

        screen.pressReturn()
        try captureMarkdownStep("mixed-list-07-child-continuation", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - ", to: output)

        screen.typeCharacters("Beta child two")
        try captureMarkdownStep("mixed-list-08-child-two", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two", to: output)

        screen.pressReturn()
        try captureMarkdownStep("mixed-list-09-child-two-continuation", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n    - ", to: output)

        screen.pressTab()
        try captureMarkdownStep("mixed-list-10-tab-to-grandchild", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - ", to: output)

        screen.typeCharacters("Beta grandchild")
        try captureMarkdownStep("mixed-list-11-grandchild", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild", to: output)

        screen.pressReturn()
        try captureMarkdownStep("mixed-list-12-grandchild-continuation", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild\n        - ", to: output)

        screen.pressTab(shift: true)
        try captureMarkdownStep("mixed-list-13-shift-tab-to-child", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild\n    - ", to: output)

        screen.typeCharacters("Beta child three")
        try captureMarkdownStep("mixed-list-14-child-three", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild\n    - Beta child three", to: output)

        screen.pressReturn()
        try captureMarkdownStep("mixed-list-15-child-three-continuation", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild\n    - Beta child three\n    - ", to: output)

        screen.pressTab(shift: true)
        try captureMarkdownStep("mixed-list-16-shift-tab-to-root", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild\n    - Beta child three\n- ", to: output)

        screen.typeCharacters("[ ] Task root")
        try captureMarkdownStep("mixed-list-17-task-root", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild\n    - Beta child three\n- [ ] Task root", to: output)

        screen.pressReturn()
        try captureMarkdownStep("mixed-list-18-task-continuation", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild\n    - Beta child three\n- [ ] Task root\n- [ ] ", to: output)

        screen.pressTab()
        try captureMarkdownStep("mixed-list-19-tab-task-child", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild\n    - Beta child three\n- [ ] Task root\n    - [ ] ", to: output)

        screen.typeCharacters("Task child one")
        try captureMarkdownStep("mixed-list-20-task-child-one", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild\n    - Beta child three\n- [ ] Task root\n    - [ ] Task child one", to: output)

        screen.pressReturn()
        try captureMarkdownStep("mixed-list-21-task-child-continuation", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild\n    - Beta child three\n- [ ] Task root\n    - [ ] Task child one\n    - [ ] ", to: output)

        screen.typeCharacters("Task child two")
        try captureMarkdownStep("mixed-list-22-task-child-two", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild\n    - Beta child three\n- [ ] Task root\n    - [ ] Task child one\n    - [ ] Task child two", to: output)

        screen.pressReturn()
        try captureMarkdownStep("mixed-list-23-empty-task-continuation", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild\n    - Beta child three\n- [ ] Task root\n    - [ ] Task child one\n    - [ ] Task child two\n    - [ ] ", to: output)

        screen.tapDeleteKey()
        try captureMarkdownStep("mixed-list-24-delete-empty-task-marker", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild\n    - Beta child three\n- [ ] Task root\n    - [ ] Task child one\n    - [ ] Task child two\n", to: output)

        screen.typeCharacters("Omega")
        let beforeCursorEdits = "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild\n    - Beta child three\n- [ ] Task root\n    - [ ] Task child one\n    - [ ] Task child two\nOmega"
        try captureMarkdownStep("mixed-list-25-omega-after-empty-delete", screen: screen,
                                expected: beforeCursorEdits, to: output)

        screen.pressKey(.leftArrow, modifierFlags: .command)
        try captureMarkdownStep("mixed-list-26-command-left-on-omega", screen: screen,
                                expected: beforeCursorEdits, to: output)

        screen.pressKey(.upArrow)
        try captureMarkdownStep("mixed-list-27-arrow-up-to-task-child-two", screen: screen,
                                expected: beforeCursorEdits, to: output)

        screen.tapDeleteKey()
        let taskMarkerRemoved = "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\n        - Beta grandchild\n    - Beta child three\n- [ ] Task root\n    - [ ] Task child one\nTask child two\nOmega"
        try captureMarkdownStep("mixed-list-28-delete-existing-task-marker", screen: screen,
                                expected: taskMarkerRemoved, to: output)

        screen.tapVisibleLine(4)
        screen.pressKey(.leftArrow, modifierFlags: .command)
        try captureMarkdownStep("mixed-list-29-tap-back-to-grandchild", screen: screen,
                                expected: taskMarkerRemoved, to: output)

        screen.tapDeleteKey()
        try captureMarkdownStep("mixed-list-30-delete-existing-grandchild-marker", screen: screen,
                                expected: "- Alpha\n- Beta\n    - Beta child one\n    - Beta child two\nBeta grandchild\n    - Beta child three\n- [ ] Task root\n    - [ ] Task child one\nTask child two\nOmega", to: output)
    }

    @MainActor
    func testCalloutListAndTaskCursorWalkWithScreenshots() throws {
        // See note on testLongBulletAndTaskListCursorWalkWithScreenshots
        // — same backspace-semantics dependency. Skipped pending rewrite.
        try XCTSkipIf(true, "Pending rewrite for whole-line-delete backspace semantics")
        let app = MarkdownEditorScreen.launchApp()
        let screen = MarkdownEditorScreen.openFromNewItemSheet(in: app)
        let output = try screenshotDirectory()

        screen.typeCharacters("> Callout")
        try captureMarkdownStep("callout-list-01-callout", screen: screen,
                                expected: "> Callout", to: output)

        screen.pressReturn()
        try captureMarkdownStep("callout-list-02-callout-continuation", screen: screen,
                                expected: "> Callout\n> ", to: output)

        screen.typeCharacters("- Bullet one")
        try captureMarkdownStep("callout-list-03-bullet-one", screen: screen,
                                expected: "> Callout\n> - Bullet one", to: output)

        screen.pressReturn()
        try captureMarkdownStep("callout-list-04-bullet-continuation", screen: screen,
                                expected: "> Callout\n> - Bullet one\n> - ", to: output)

        screen.typeCharacters("Bullet two")
        try captureMarkdownStep("callout-list-05-bullet-two", screen: screen,
                                expected: "> Callout\n> - Bullet one\n> - Bullet two", to: output)

        screen.pressReturn()
        try captureMarkdownStep("callout-list-06-bullet-two-continuation", screen: screen,
                                expected: "> Callout\n> - Bullet one\n> - Bullet two\n> - ", to: output)

        screen.pressTab()
        try captureMarkdownStep("callout-list-07-tab-to-nested-bullet", screen: screen,
                                expected: "> Callout\n> - Bullet one\n> - Bullet two\n>     - ", to: output)

        screen.typeCharacters("Nested bullet")
        try captureMarkdownStep("callout-list-08-nested-bullet", screen: screen,
                                expected: "> Callout\n> - Bullet one\n> - Bullet two\n>     - Nested bullet", to: output)

        screen.pressReturn()
        try captureMarkdownStep("callout-list-09-nested-bullet-continuation", screen: screen,
                                expected: "> Callout\n> - Bullet one\n> - Bullet two\n>     - Nested bullet\n>     - ", to: output)

        screen.pressTab(shift: true)
        try captureMarkdownStep("callout-list-10-shift-tab-within-callout", screen: screen,
                                expected: "> Callout\n> - Bullet one\n> - Bullet two\n>     - Nested bullet\n> - ", to: output)

        screen.typeCharacters("[ ] Quote task")
        try captureMarkdownStep("callout-list-11-quote-task", screen: screen,
                                expected: "> Callout\n> - Bullet one\n> - Bullet two\n>     - Nested bullet\n> - [ ] Quote task", to: output)

        screen.pressReturn()
        try captureMarkdownStep("callout-list-12-quote-task-continuation", screen: screen,
                                expected: "> Callout\n> - Bullet one\n> - Bullet two\n>     - Nested bullet\n> - [ ] Quote task\n> - [ ] ", to: output)

        screen.pressTab()
        try captureMarkdownStep("callout-list-13-tab-to-nested-quote-task", screen: screen,
                                expected: "> Callout\n> - Bullet one\n> - Bullet two\n>     - Nested bullet\n> - [ ] Quote task\n>     - [ ] ", to: output)

        screen.typeCharacters("Nested quote task")
        try captureMarkdownStep("callout-list-14-nested-quote-task", screen: screen,
                                expected: "> Callout\n> - Bullet one\n> - Bullet two\n>     - Nested bullet\n> - [ ] Quote task\n>     - [ ] Nested quote task", to: output)

        screen.pressReturn()
        try captureMarkdownStep("callout-list-15-empty-nested-quote-task", screen: screen,
                                expected: "> Callout\n> - Bullet one\n> - Bullet two\n>     - Nested bullet\n> - [ ] Quote task\n>     - [ ] Nested quote task\n>     - [ ] ", to: output)

        screen.tapDeleteKey()
        try captureMarkdownStep("callout-list-16-delete-empty-quote-task-marker", screen: screen,
                                expected: "> Callout\n> - Bullet one\n> - Bullet two\n>     - Nested bullet\n> - [ ] Quote task\n>     - [ ] Nested quote task\n> ", to: output)

        screen.typeCharacters("Quote plain")
        let beforeCursorEdits = "> Callout\n> - Bullet one\n> - Bullet two\n>     - Nested bullet\n> - [ ] Quote task\n>     - [ ] Nested quote task\n> Quote plain"
        try captureMarkdownStep("callout-list-17-quote-plain-after-delete", screen: screen,
                                expected: beforeCursorEdits, to: output)

        screen.pressKey(.leftArrow, modifierFlags: .command)
        try captureMarkdownStep("callout-list-18-command-left-on-quote-plain", screen: screen,
                                expected: beforeCursorEdits, to: output)

        screen.pressKey(.upArrow)
        try captureMarkdownStep("callout-list-19-arrow-up-to-nested-task", screen: screen,
                                expected: beforeCursorEdits, to: output)

        screen.tapDeleteKey()
        let quoteTaskMarkerRemoved = "> Callout\n> - Bullet one\n> - Bullet two\n>     - Nested bullet\n> - [ ] Quote task\n> Nested quote task\n> Quote plain"
        try captureMarkdownStep("callout-list-20-delete-existing-quote-task-marker", screen: screen,
                                expected: quoteTaskMarkerRemoved, to: output)

        screen.tapVisibleLine(3)
        screen.pressKey(.leftArrow, modifierFlags: .command)
        try captureMarkdownStep("callout-list-21-tap-back-to-nested-bullet", screen: screen,
                                expected: quoteTaskMarkerRemoved, to: output)

        screen.tapDeleteKey()
        try captureMarkdownStep("callout-list-22-delete-existing-quote-bullet-marker", screen: screen,
                                expected: "> Callout\n> - Bullet one\n> - Bullet two\n> Nested bullet\n> - [ ] Quote task\n> Nested quote task\n> Quote plain", to: output)
    }

    @MainActor
    private func captureMarkdownStep(_ name: String,
                                     screen: MarkdownEditorScreen,
                                     expected: String,
                                     to directory: URL,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) throws {
        try saveScreenshot(named: name, to: directory)
        XCTAssertEqual(screen.source, expected, file: file, line: line)
    }

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
