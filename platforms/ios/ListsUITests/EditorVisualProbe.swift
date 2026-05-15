import XCTest

/// Visual evidence probe: tests pass on source/cursor but the editor
/// fails visually. This file captures screenshots at the failure
/// moments so we can SEE what the source-level tests can't see.
///
/// Run with:
///   xcodebuild test -scheme Lists -only-testing:ListsUITests/EditorVisualProbe
/// Then extract attachments from the .xcresult bundle.
final class EditorVisualProbe: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    private func capture(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    @MainActor
    private func record(_ name: String, _ string: String) {
        let att = XCTAttachment(string: string)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    /// Scenario 1 — sibling top-level bullets. Source says "- a\n- b\n- c"
    /// but the user reports the rendered bullets/lines drift in x.
    @MainActor
    func testSiblingBulletAlignment() throws {
        let app = MarkdownEditorScreen.launchApp()
        let screen = MarkdownEditorScreen.openFromNewItemSheet(in: app)
        screen.type("- a")
        screen.pressReturn()
        screen.type("b")
        screen.pressReturn()
        screen.type("c")
        record("source", screen.source)
        record("cursor", "\(screen.cursor.location)-\(screen.cursor.length)")
        capture("01-three-sibling-bullets-cursor-on-last-line")

        // Move cursor to line 1 (top bullet) — sibling rows should NOT
        // shift. The user reports they do.
        screen.pressKey(.upArrow)
        screen.pressKey(.upArrow)
        capture("02-three-sibling-bullets-cursor-on-first-line")

        // Move back to middle line.
        screen.pressKey(.downArrow)
        capture("03-three-sibling-bullets-cursor-on-middle-line")
    }

    /// Scenario 2 — exact reproduction of Saxon's reported sibling-drift
    /// bug. Four top-level task items + an empty line + typing a letter
    /// (A) on the empty line. He reports rows 2, 3, 4 drift right by
    /// ~one indent unit when the cursor is below them.
    @MainActor
    func testTaskRowsHoldIndentAfterTypingBelowList() throws {
        let app = MarkdownEditorScreen.launchApp()
        let screen = MarkdownEditorScreen.openFromNewItemSheet(in: app)
        screen.tapToolbar("markdown.toolbar.task")
        screen.type("1")
        screen.pressReturn()
        screen.type("2")
        screen.pressReturn()
        screen.type("3")
        screen.pressReturn()
        screen.type("4")
        screen.pressReturn()
        capture("00-four-tasks-cursor-on-empty-trailing-line")
        screen.type("A")
        record("source-after-A", screen.source)
        capture("01-after-typing-A-on-empty-line")

        // Move cursor up onto task 4 — bug claim: task 4 stays right,
        // others drift.
        screen.pressKey(.upArrow)
        capture("02-cursor-on-task-4")
        screen.pressKey(.upArrow)
        capture("03-cursor-on-task-3")
        screen.pressKey(.upArrow)
        capture("04-cursor-on-task-2")
        screen.pressKey(.upArrow)
        capture("05-cursor-on-task-1")
    }

    /// Regression: tapping the rendered checkbox glyph must toggle the
    /// task state. The marker chars are zero-width-fonted so the gesture
    /// recognizer cannot use `glyphIndex(for:)` to find the bracket —
    /// it has to derive the state char position from `ListMarker`.
    /// This is the only UI test that exercises the geometric tap path;
    /// `CheckboxTests` in ListsTests calls the intent directly.
    @MainActor
    func testCheckboxTapTogglesViaGesture() throws {
        let app = MarkdownEditorScreen.launchApp()
        let screen = MarkdownEditorScreen.openFromNewItemSheet(in: app)
        screen.tapToolbar("markdown.toolbar.task")
        screen.type("todo")
        XCTAssertEqual(screen.source, "- [ ] todo")
        capture("01-unchecked-task")

        // Tap on the checkbox glyph region. The SF Symbol overlay sits
        // around x = insetLeft (16) + lfPadding (5) ≈ 21pt from the
        // editor's left edge. xOffset 30 lands solidly on the symbol.
        screen.tapVisibleLine(0, xOffset: 30)
        capture("02-after-tap-checkbox")
        XCTAssertEqual(screen.source, "- [x] todo",
                       "Tapping the rendered checkbox at x=30 should toggle [ ] → [x]")

        // Tap again — should toggle back.
        screen.tapVisibleLine(0, xOffset: 30)
        capture("03-after-second-tap")
        XCTAssertEqual(screen.source, "- [ ] todo",
                       "Second tap should toggle [x] → [ ]")

        // Tap further left, still inside the marker zone (x=18).
        screen.tapVisibleLine(0, xOffset: 18)
        capture("04-after-leftward-tap")
        XCTAssertEqual(screen.source, "- [x] todo",
                       "Tap near the left edge of the marker zone should still toggle")
    }
}
