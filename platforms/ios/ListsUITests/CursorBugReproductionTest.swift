import XCTest

/// Cursor-position regression tests for the markdown editor.
///
/// Originally print()-based diagnostic scaffolding. Now asserts on
/// `screen.cursor` via the hidden `markdown.editor.cursor` accessibility
/// element so failures pinpoint specific cursor-navigation bugs in
/// `MarkdownStyler` / `MarkdownLayoutManager`.
final class CursorBugReproductionTest: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openEditor() -> MarkdownEditorScreen {
        let app = MarkdownEditorScreen.launchApp()
        return MarkdownEditorScreen.openFromNewItemSheet(in: app)
    }

    @MainActor
    func testBulletListAutoContinuationAndArrowKeyNavigation() {
        let screen = openEditor()

        screen.typeCharacters("- first")
        XCTAssertEqual(screen.source, "- first")
        XCTAssertEqual(screen.cursor.location, 7,
                       "Cursor should sit at end of '- first'")

        // Return auto-continues the bullet: text becomes "- first\n- "
        // (10 chars) with the cursor parked after the new "- ".
        screen.pressReturn()
        XCTAssertEqual(screen.source, "- first\n- ",
                       "Return should auto-continue the bullet")
        XCTAssertEqual(screen.cursor.location, 10,
                       "Cursor should sit just after the continued '- '")

        screen.typeCharacters("second")
        XCTAssertEqual(screen.source, "- first\n- second")
        XCTAssertEqual(screen.cursor.location, 16,
                       "Cursor should sit at end of '- second'")

        // Left x6 walks back through "second" to the position right
        // after the second "- " marker on line 2 (positions 15 → 10).
        for _ in 1...6 { screen.pressKey(.leftArrow) }
        XCTAssertEqual(screen.cursor.location, 10,
                       "After 6 left presses, cursor should sit between '- ' and 's' on line 2")

        // Up should land at the same column on line 1. Column = 10 - 8 = 2
        // (line 2 starts at 8). Column 2 of "- first" is position 2 — the 'f'.
        screen.pressKey(.upArrow)
        XCTAssertEqual(screen.cursor.location, 2,
                       "Up arrow should land at column 2 of '- first' (before 'f')")

        screen.pressKey(.leftArrow)
        XCTAssertEqual(screen.cursor.location, 1,
                       "Left from column 2 should land at column 1 (between '-' and ' ')")

        screen.pressKey(.rightArrow)
        XCTAssertEqual(screen.cursor.location, 2,
                       "Right from column 1 should return to column 2")
    }

    @MainActor
    func testTaskCheckboxAutoContinuationAndArrowKeyNavigation() {
        let screen = openEditor()

        screen.typeCharacters("- [ ] task")
        XCTAssertEqual(screen.source, "- [ ] task")
        XCTAssertEqual(screen.cursor.location, 10,
                       "Cursor should sit at end of '- [ ] task'")

        // Return auto-continues the task. Text becomes "- [ ] task\n- [ ] "
        // (17 chars) with the cursor parked after the new "- [ ] ".
        screen.pressReturn()
        XCTAssertEqual(screen.source, "- [ ] task\n- [ ] ",
                       "Return should auto-continue with a new task marker")
        XCTAssertEqual(screen.cursor.location, 17,
                       "Cursor should sit just after the continued '- [ ] '")

        screen.typeCharacters("new")
        XCTAssertEqual(screen.source, "- [ ] task\n- [ ] new")
        XCTAssertEqual(screen.cursor.location, 20,
                       "Cursor should sit at end of '- [ ] new'")

        // Left x3 walks back through "new" to just before 'n'.
        for _ in 1...3 { screen.pressKey(.leftArrow) }
        XCTAssertEqual(screen.cursor.location, 17,
                       "After 3 left presses, cursor should sit just before 'n' of 'new'")

        // Up should land at column 6 on line 1. Column = 17 - 11 = 6.
        // Position 6 in "- [ ] task" is the 't' of "task".
        screen.pressKey(.upArrow)
        XCTAssertEqual(screen.cursor.location, 6,
                       "Up arrow should land just before 't' of 'task' on line 1")
    }
}
