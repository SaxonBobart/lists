import XCTest

/// XCUITest coverage for **inline** markdown elements driven through
/// the iOS keyboard / touch pipeline. We deliberately test the
/// source-level outcomes here (what does the text view contain after
/// the user typed X?) — visual attribute checks (color, font traits,
/// glyph hiding) belong in `MarkdownStylerTests` where they can be
/// asserted directly.
final class MarkdownInlineTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openEditor() -> MarkdownEditorScreen {
        let app = MarkdownEditorScreen.launchApp()
        return MarkdownEditorScreen.openFromNewItemSheet(in: app)
    }

    // MARK: Headings

    @MainActor
    func testTypingHeadingPreservesSource() {
        let screen = openEditor()
        screen.type("# Heading")
        XCTAssertEqual(screen.source, "# Heading")
    }

    @MainActor
    func testHeadingLevelsOneThroughFour() {
        let screen = openEditor()
        for level in 1...4 {
            let hashes = String(repeating: "#", count: level)
            screen.clear()
            screen.type("\(hashes) H\(level)")
            XCTAssertEqual(screen.source, "\(hashes) H\(level)",
                           "H\(level) source mismatch")
        }
    }

    // MARK: Bold / italic / bold-italic / strikethrough

    @MainActor
    func testBoldRoundTripsSource() {
        let screen = openEditor()
        screen.type("a **bold** word")
        XCTAssertEqual(screen.source, "a **bold** word")
    }

    @MainActor
    func testItalicAsteriskRoundTripsSource() {
        let screen = openEditor()
        screen.type("a *slanted* word")
        XCTAssertEqual(screen.source, "a *slanted* word")
    }

    @MainActor
    func testBoldItalicTripleAsteriskRoundTripsSource() {
        let screen = openEditor()
        screen.type("***both***")
        XCTAssertEqual(screen.source, "***both***")
    }

    @MainActor
    func testStrikethroughRoundTripsSource() {
        let screen = openEditor()
        screen.type("~~gone~~")
        XCTAssertEqual(screen.source, "~~gone~~")
    }

    // MARK: Inline code / highlight

    @MainActor
    func testInlineCodeRoundTripsSource() {
        let screen = openEditor()
        screen.type("call `npm test` now")
        XCTAssertEqual(screen.source, "call `npm test` now")
    }

    @MainActor
    func testHighlightRoundTripsSource() {
        let screen = openEditor()
        screen.type("see ==this== bit")
        XCTAssertEqual(screen.source, "see ==this== bit")
    }

    // MARK: Links

    @MainActor
    func testLinkRoundTripsSource() {
        let screen = openEditor()
        screen.type("see [Apple](https://apple.com) for more")
        XCTAssertEqual(screen.source, "see [Apple](https://apple.com) for more")
    }

    @MainActor
    func testBareUrlRoundTripsSource() {
        let screen = openEditor()
        screen.type("at https://apple.com here")
        XCTAssertEqual(screen.source, "at https://apple.com here")
    }

    // MARK: Inline tag

    @MainActor
    func testInlineTagRoundTripsSource() {
        let screen = openEditor()
        screen.type("about #work today")
        XCTAssertEqual(screen.source, "about #work today")
    }
}
