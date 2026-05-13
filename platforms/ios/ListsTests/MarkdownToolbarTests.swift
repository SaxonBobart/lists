import Foundation
import Testing
@testable import Lists

/// L1 corpus: every Apple Reminders-style toolbar action ×
/// (no selection / wraps selection / toggles off if already
/// wrapped) matrix. Lands as `ToolbarAction.apply` is filled in
/// during P4.
@Suite("L1 — Toolbar actions")
struct MarkdownToolbarTests {

    @Suite("Bold")
    struct BoldTests {
        @Test func wrapsSelection() {
            EditorFixture.expect(
                .toolbar(.bold),
                from: "a «word» b",
                produces: "a **«word»** b"
            )
        }

        @Test func togglesOffWrappedSelection() {
            EditorFixture.expect(
                .toolbar(.bold),
                from: "a **«word»** b",
                produces: "a «word» b"
            )
        }
    }

    @Suite("Italic")
    struct ItalicTests {
        @Test func wrapsSelectionWithSingleAsterisk() {
            EditorFixture.expect(
                .toolbar(.italic),
                from: "a «word» b",
                produces: "a *«word»* b"
            )
        }
    }

    @Suite("Heading dropdown")
    struct HeadingTests {
        @Test func togglesParagraphToH1() {
            EditorFixture.expect(
                .toolbar(.heading(1)),
                from: "Some line|",
                produces: "# Some line|"
            )
        }
    }

    @Suite("Lists")
    struct ListTests {
        @Test func bulletToggleAddsMarkerToParagraph() {
            EditorFixture.expect(
                .toolbar(.bullet),
                from: "Plain line|",
                produces: "- Plain line|"
            )
        }
    }
}
