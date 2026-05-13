import Foundation
import Testing
@testable import Lists

/// L1 corpus: paste-handler matrix. Pasteboard-source-type ×
/// destination-line-type. UIKit-side tests live in
/// `MarkdownPasteTour` (L3).
@Suite("L1 — Paste handling")
struct MarkdownPasteHandlerTests {

    @Test func plainSingleLinePasteInsertsVerbatim() {
        EditorFixture.expect(.paste("inserted"),
                             from: "before |after",
                             produces: "before inserted|after")
    }

    @Test func multiLinePastePreservesNewlines() {
        EditorFixture.expect(.paste("line1\nline2"),
                             from: "before |after",
                             produces: "before line1\nline2|after")
    }

    @Test func pasteInsideListDoesNotTriggerAutoContinuation() {
        EditorFixture.expect(.paste("extra"),
                             from: "- before |after",
                             produces: "- before extra|after")
    }

    @Test func pastePreservesDoubleHyphen() {
        EditorFixture.expect(.paste("foo -- bar"),
                             from: "|",
                             produces: "foo -- bar|")
    }

    @Test func pastePreservesTripleDots() {
        EditorFixture.expect(.paste("Wait..."),
                             from: "|",
                             produces: "Wait...|")
    }

    @Test func pastePreservesStraightQuotes() {
        EditorFixture.expect(.paste("\"hello\""),
                             from: "|",
                             produces: "\"hello\"|")
    }

    @Test func pasteCRLFNormalisesToLF() {
        EditorFixture.expect(.paste("a\r\nb"),
                             from: "|",
                             produces: "a\nb|")
    }

    @Test func pasteBareCRNormalisesToLF() {
        EditorFixture.expect(.paste("a\rb"),
                             from: "|",
                             produces: "a\nb|")
    }

    @Test func pasteTabConvertsToFourSpaces() {
        EditorFixture.expect(.paste("a\tb"),
                             from: "|",
                             produces: "a    b|")
    }

    @Test func pasteLeadingBOMIsStripped() {
        EditorFixture.expect(.paste("\u{FEFF}hello"),
                             from: "|",
                             produces: "hello|")
    }

    @Test func pasteReplacesSelection() {
        EditorFixture.expect(.paste("X"),
                             from: "a«bc»d",
                             produces: "aX|d")
    }

    @Test func pasteMarkdownStructureIsLiteralInsert() {
        // Pasted markdown-shaped text inserts verbatim; no re-parsing.
        EditorFixture.expect(.paste("- a\n- b"),
                             from: "|",
                             produces: "- a\n- b|")
    }
}
