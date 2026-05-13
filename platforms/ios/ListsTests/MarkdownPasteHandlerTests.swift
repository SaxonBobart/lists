import Foundation
import Testing
@testable import Lists

/// L1 corpus: paste handling matrix. Pasteboard-source-type ×
/// destination-line-type. Lands in P5.
///
/// The pure path takes a `String` payload — `UIPasteboard` resolution
/// (URL, image, rich text) is converted to a `String` first, then
/// dispatched into `PasteHandler.apply`. UIKit-side tests live in
/// `MarkdownPasteTour` (L3).
@Suite("L1 — Paste handling")
struct MarkdownPasteHandlerTests {

    @Test func plainSingleLinePasteInsertsVerbatim() {
        EditorFixture.expect(
            .paste("inserted"),
            from: "before |after",
            produces: "before inserted|after"
        )
    }

    @Test func multiLinePastePreservesNewlines() {
        EditorFixture.expect(
            .paste("line1\nline2"),
            from: "before |after",
            produces: "before line1\nline2|after"
        )
    }

    @Test func pasteInsideListDoesNotTriggerAutoContinuation() {
        // Pasting `extra` into the middle of a bullet item must NOT
        // run the smart-Return path. The list marker stays as-is.
        EditorFixture.expect(
            .paste("extra"),
            from: "- before |after",
            produces: "- before extra|after"
        )
    }

    @Test func pastePreservesDoubleHyphen() {
        // Smart-typography must NOT mutate `--` → `—`.
        EditorFixture.expect(
            .paste("foo -- bar"),
            from: "|",
            produces: "foo -- bar|"
        )
    }
}
