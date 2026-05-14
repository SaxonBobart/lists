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
    func testListIndentButtonsAreImmediatelyHittable() {
        let screen = openEditor()
        screen.focusEditor()

        XCTAssertTrue(screen.app.buttons["markdown.outdent"].firstMatch.isHittable)
        XCTAssertTrue(screen.app.buttons["markdown.indent"].firstMatch.isHittable)
    }

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

    @MainActor
    func testToolbarIndentAndOutdentAfterNavigatingLongLists() {
        let screen = openEditor()

        screen.type("- alpha")
        screen.pressReturn()
        screen.type("beta")
        screen.pressReturn()
        screen.type("gamma")
        screen.pressReturn()
        screen.type("delta")
        screen.pressReturn()
        screen.type("epsilon")
        screen.pressReturn()
        screen.pressReturn()

        screen.type("1. one")
        screen.pressReturn()
        screen.type("two")
        screen.pressReturn()
        screen.type("three")
        screen.pressReturn()
        screen.type("four")
        screen.pressReturn()
        screen.type("five")
        screen.pressReturn()
        screen.pressReturn()

        screen.type("- [ ] task one")
        screen.pressReturn()
        screen.type("task two")
        screen.pressReturn()
        screen.type("task three")
        screen.pressReturn()
        screen.type("task four")
        screen.pressReturn()
        screen.type("task five")

        screen.pressKey(.upArrow)
        screen.pressKey(.upArrow)
        screen.tapToolbar("markdown.indent")
        XCTAssertTrue(screen.source.contains("    - [ ] task three"), screen.source)

        screen.tapToolbar("markdown.outdent")
        XCTAssertTrue(screen.source.contains("\n- [ ] task three"), screen.source)

        screen.pressKey(.upArrow)
        screen.pressKey(.upArrow)
        screen.pressKey(.upArrow)
        screen.pressKey(.upArrow)
        screen.tapToolbar("markdown.indent")
        XCTAssertTrue(screen.source.contains("    4. four"), screen.source)

        screen.tapToolbar("markdown.outdent")
        XCTAssertTrue(screen.source.contains("\n4. four"), screen.source)
    }

    @MainActor
    func testHardwareTabIndentsWhileCreatingContinuedListItems() {
        let screen = openEditor()

        screen.tapToolbar("markdown.toolbar.bullet")
        screen.type("parent")
        screen.pressReturn()
        XCTAssertEqual(screen.source, "- parent\n- ")

        screen.pressTab()
        XCTAssertEqual(screen.source, "- parent\n    - ")

        screen.type("child")
        screen.pressReturn()
        XCTAssertEqual(screen.source, "- parent\n    - child\n    - ")

        screen.pressTab()
        XCTAssertEqual(screen.source, "- parent\n    - child\n        - ")
    }

    @MainActor
    func testReturnAfterNestedItemInMixedListContinuesNestedLevel() {
        let screen = openEditor()

        screen.tapToolbar("markdown.toolbar.bullet")
        screen.type("1")
        screen.pressReturn()
        screen.type("2")
        screen.pressReturn()
        screen.tapToolbar("markdown.indent")
        screen.type("3")

        XCTAssertEqual(screen.source, "- 1\n- 2\n    - 3")

        screen.pressReturn()

        XCTAssertEqual(screen.source, "- 1\n- 2\n    - 3\n    - ")
    }

    @MainActor
    func testReturnOnEmptyNestedBulletOutdentsOneLevel() {
        let screen = openEditor()

        screen.tapToolbar("markdown.toolbar.bullet")
        screen.type("parent")
        screen.pressReturn()
        screen.tapToolbar("markdown.indent")

        XCTAssertEqual(screen.source, "- parent\n    - ")

        screen.pressReturn()

        XCTAssertEqual(screen.source, "- parent\n- ")
        XCTAssertEqual(screen.cursor.location, 11)
    }

    @MainActor
    func testReturnOnEmptyNestedTaskOutdentsOneLevel() {
        let screen = openEditor()

        screen.tapToolbar("markdown.toolbar.task")
        screen.type("parent")
        screen.pressReturn()
        screen.tapToolbar("markdown.indent")

        XCTAssertEqual(screen.source, "- [ ] parent\n    - [ ] ")

        screen.pressReturn()

        XCTAssertEqual(screen.source, "- [ ] parent\n- [ ] ")
        XCTAssertEqual(screen.cursor.location, 19)
    }

    @MainActor
    func testNestedBulletAndTaskCurrentLineNavigationTour() {
        let screen = openEditor()

        screen.type("- parent")
        screen.pressReturn()
        screen.pressTab()
        screen.type("child")
        screen.pressReturn()
        screen.pressReturn()
        screen.pressReturn()

        screen.type("- [ ] task parent")
        screen.pressReturn()
        screen.pressTab()
        screen.type("task child")

        XCTAssertEqual(screen.source,
                       "- parent\n    - child\n- [ ] task parent\n    - [ ] task child")

        screen.pressKey(.upArrow)
        XCTAssertTrue(screen.cursor.location < screen.source.count)

        screen.pressKey(.downArrow)
        XCTAssertEqual(screen.cursor.location, screen.source.count)
    }
}
