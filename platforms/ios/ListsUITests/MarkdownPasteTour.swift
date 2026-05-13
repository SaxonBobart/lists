import XCTest

/// L3 tour: drive `UIPasteboard.general` + Cmd-V and verify the
/// markdown source comes out normalised + verbatim. Complements
/// `MarkdownPasteHandlerTests` (L1).
final class MarkdownPasteTour: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openEditor() -> MarkdownEditorScreen {
        let app = MarkdownEditorScreen.launchApp()
        return MarkdownEditorScreen.openFromNewItemSheet(in: app)
    }

    @MainActor
    func testPasteSingleLinePlainTextInsertsVerbatim() {
        let screen = openEditor()
        screen.paste("hello world")
        XCTAssertEqual(screen.source, "hello world")
    }

    @MainActor
    func testPasteMultiLinePreservesNewlines() {
        let screen = openEditor()
        screen.paste("line one\nline two")
        XCTAssertEqual(screen.source, "line one\nline two")
    }

    @MainActor
    func testPastePreservesDoubleHyphen() {
        let screen = openEditor()
        screen.paste("dash--dash")
        XCTAssertEqual(screen.source, "dash--dash",
                       "Smart-dash mutation must not apply to pasted text")
    }

    @MainActor
    func testPastePreservesTripleDots() {
        let screen = openEditor()
        screen.paste("wait...")
        XCTAssertEqual(screen.source, "wait...",
                       "Ellipsis substitution must not apply to pasted text")
    }

    @MainActor
    func testPastePreservesStraightQuotes() {
        let screen = openEditor()
        screen.paste("\"hello\"")
        XCTAssertEqual(screen.source, "\"hello\"",
                       "Smart-quote substitution must not apply to pasted text")
    }

    @MainActor
    func testPasteMarkdownStructureIsLiteral() {
        let screen = openEditor()
        screen.paste("- a\n- b\n- c")
        XCTAssertEqual(screen.source, "- a\n- b\n- c",
                       "Pasted markdown should land verbatim, no list-marker re-parse")
    }
}
