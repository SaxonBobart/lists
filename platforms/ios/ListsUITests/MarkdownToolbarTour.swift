import XCTest

/// L3 tour: walk every accessory-toolbar button on a fresh editor
/// and assert the source delta lands. UI-side complement to the
/// L1 `MarkdownToolbarTests` corpus.
final class MarkdownToolbarTour: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openEditor() -> MarkdownEditorScreen {
        let app = MarkdownEditorScreen.launchApp()
        return MarkdownEditorScreen.openFromNewItemSheet(in: app)
    }

    // MARK: Line markers

    @MainActor
    func testBulletButtonInsertsListMarkerOnEmptyLine() {
        let screen = openEditor()
        screen.tapToolbar("markdown.toolbar.bullet")
        XCTAssertEqual(screen.source, "- ")
        XCTAssertEqual(screen.cursor.location, 2)
    }

    @MainActor
    func testNumberedButtonInsertsListMarker() {
        let screen = openEditor()
        screen.tapToolbar("markdown.toolbar.numbered")
        XCTAssertEqual(screen.source, "1. ")
        XCTAssertEqual(screen.cursor.location, 3)
    }

    @MainActor
    func testTaskButtonInsertsCheckboxMarker() {
        let screen = openEditor()
        screen.tapToolbar("markdown.toolbar.task")
        XCTAssertEqual(screen.source, "- [ ] ")
        XCTAssertEqual(screen.cursor.location, 6)
    }

    @MainActor
    func testBlockquoteButtonInsertsMarker() {
        let screen = openEditor()
        screen.tapToolbar("markdown.toolbar.quote")
        XCTAssertEqual(screen.source, "> ")
    }

    // MARK: Inline wrap

    @MainActor
    func testBoldButtonOnEmptyInsertsWrap() {
        let screen = openEditor()
        screen.tapToolbar("markdown.toolbar.bold")
        XCTAssertEqual(screen.source, "****")
        XCTAssertEqual(screen.cursor.location, 2,
                       "Caret should sit between the two `**` pairs")
    }

    @MainActor
    func testItalicButtonOnEmptyInsertsWrap() {
        let screen = openEditor()
        screen.tapToolbar("markdown.toolbar.italic")
        XCTAssertEqual(screen.source, "**")
        XCTAssertEqual(screen.cursor.location, 1)
    }

    @MainActor
    func testCodeButtonOnEmptyInsertsBackticks() {
        let screen = openEditor()
        screen.tapToolbar("markdown.toolbar.code")
        XCTAssertEqual(screen.source, "``")
        XCTAssertEqual(screen.cursor.location, 1)
    }

    @MainActor
    func testHighlightButtonOnEmptyInsertsWrap() {
        let screen = openEditor()
        screen.tapToolbar("markdown.toolbar.highlight")
        XCTAssertEqual(screen.source, "====")
        XCTAssertEqual(screen.cursor.location, 2)
    }

    @MainActor
    func testStrikethroughButtonOnEmptyInsertsWrap() {
        let screen = openEditor()
        screen.tapToolbar("markdown.toolbar.strike")
        XCTAssertEqual(screen.source, "~~~~")
        XCTAssertEqual(screen.cursor.location, 2)
    }

    // MARK: Inserts

    @MainActor
    func testLinkButtonInsertsTemplate() {
        let screen = openEditor()
        screen.tapToolbar("markdown.toolbar.link")
        XCTAssertEqual(screen.source, "[](url)")
        XCTAssertEqual(screen.cursor.location, 1, "Caret sits inside the empty `[]`")
    }

    @MainActor
    func testWikilinkButtonInsertsTemplate() {
        let screen = openEditor()
        screen.tapToolbar("markdown.toolbar.wikilink")
        XCTAssertEqual(screen.source, "[[]]")
        XCTAssertEqual(screen.cursor.location, 2)
    }

    @MainActor
    func testHorizontalRuleButtonInsertsLine() {
        let screen = openEditor()
        screen.tapToolbar("markdown.toolbar.hr")
        XCTAssertEqual(screen.source, "---\n")
    }

    // MARK: Indent / Outdent (via toolbar id, unchanged)

    @MainActor
    func testToolbarIndentMatchesHardwareTab() {
        let screen = openEditor()
        screen.type("- one")
        screen.tapToolbar("markdown.indent")
        XCTAssertEqual(screen.source, "    - one")
    }

    @MainActor
    func testToolbarOutdentReversesIndent() {
        let screen = openEditor()
        screen.type("    - nested")
        screen.tapToolbar("markdown.outdent")
        XCTAssertEqual(screen.source, "- nested")
    }
}
