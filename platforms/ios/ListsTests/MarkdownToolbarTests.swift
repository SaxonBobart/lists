import Foundation
import Testing
@testable import Lists

/// L1 corpus: Apple Reminders-style toolbar actions.
@Suite("L1 — Toolbar actions")
struct MarkdownToolbarTests {

    @Suite("Inline wrap")
    struct InlineWrapTests {
        @Test func boldWrapsSelection() {
            EditorFixture.expect(.toolbar(.bold),
                                 from: "a «word» b",
                                 produces: "a **«word»** b")
        }
        @Test func boldTogglesOffWrappedSelection() {
            EditorFixture.expect(.toolbar(.bold),
                                 from: "a **«word»** b",
                                 produces: "a «word» b")
        }
        @Test func boldEmptyInsertsWrapWithCaretInside() {
            EditorFixture.expect(.toolbar(.bold),
                                 from: "a |b",
                                 produces: "a **|**b")
        }
        @Test func italicWrapsWithSingleAsterisk() {
            EditorFixture.expect(.toolbar(.italic),
                                 from: "a «word» b",
                                 produces: "a *«word»* b")
        }
        @Test func italicTogglesOffSingleAsterisk() {
            EditorFixture.expect(.toolbar(.italic),
                                 from: "a *«word»* b",
                                 produces: "a «word» b")
        }
        @Test func italicDoesNotToggleInsideBold() {
            // `*«word»*` inside the bold `**…**` — applying italic should
            // ADD a wrap, not strip the bold's asterisks.
            EditorFixture.expect(.toolbar(.italic),
                                 from: "a **«word»** b",
                                 produces: "a ***«word»*** b")
        }
        @Test func strikethroughWrapsSelection() {
            EditorFixture.expect(.toolbar(.strikethrough),
                                 from: "a «word» b",
                                 produces: "a ~~«word»~~ b")
        }
        @Test func highlightWrapsSelection() {
            EditorFixture.expect(.toolbar(.highlight),
                                 from: "a «word» b",
                                 produces: "a ==«word»== b")
        }
        @Test func inlineCodeWrapsSelection() {
            EditorFixture.expect(.toolbar(.code),
                                 from: "call «foo()» now",
                                 produces: "call `«foo()»` now")
        }
        @Test func mathInlineWrapsSelection() {
            EditorFixture.expect(.toolbar(.mathInline),
                                 from: "see «x+1»",
                                 produces: "see $«x+1»$")
        }
    }

    @Suite("Headings")
    struct HeadingTests {
        @Test func headingOneTogglesOnPlainLine() {
            EditorFixture.expect(.toolbar(.heading(1)),
                                 from: "Plain|",
                                 produces: "# Plain|")
        }
        @Test func headingTwoTogglesFromHeadingOne() {
            EditorFixture.expect(.toolbar(.heading(2)),
                                 from: "# Heading|",
                                 produces: "## Heading|")
        }
        @Test func headingOneTogglesOff() {
            // Applying heading(1) to an H1 line strips back to paragraph.
            EditorFixture.expect(.toolbar(.heading(1)),
                                 from: "# Heading|",
                                 produces: "Heading|")
        }
        @Test func paragraphStripsHeading() {
            EditorFixture.expect(.toolbar(.paragraph),
                                 from: "### Sub|",
                                 produces: "Sub|")
        }
    }

    @Suite("Line markers")
    struct LineMarkerTests {
        @Test func bulletAddsMarkerToParagraph() {
            EditorFixture.expect(.toolbar(.bullet),
                                 from: "Plain line|",
                                 produces: "- Plain line|")
        }
        @Test func bulletTogglesOff() {
            EditorFixture.expect(.toolbar(.bullet),
                                 from: "- bullet|",
                                 produces: "bullet|")
        }
        @Test func numberedAddsMarker() {
            EditorFixture.expect(.toolbar(.numbered),
                                 from: "Plain|",
                                 produces: "1. Plain|")
        }
        @Test func taskAddsMarker() {
            EditorFixture.expect(.toolbar(.task),
                                 from: "Plain|",
                                 produces: "- [ ] Plain|")
        }
        @Test func taskFromBulletReplacesMarker() {
            EditorFixture.expect(.toolbar(.task),
                                 from: "- bullet|",
                                 produces: "- [ ] bullet|")
        }
        @Test func blockquoteAddsMarker() {
            EditorFixture.expect(.toolbar(.blockquote),
                                 from: "Plain|",
                                 produces: "> Plain|")
        }
    }

    @Suite("Indent / Outdent (toolbar variants)")
    struct ToolbarIndentTests {
        @Test func toolbarIndentSameAsTab() {
            EditorFixture.expect(.toolbar(.indent),
                                 from: "- one|",
                                 produces: "    - one|")
        }
        @Test func toolbarOutdentSameAsShiftTab() {
            EditorFixture.expect(.toolbar(.outdent),
                                 from: "    - one|",
                                 produces: "- one|")
        }
    }

    @Suite("Inserts")
    struct InsertTests {
        @Test func linkInsertsTemplateWhenNoSelection() {
            EditorFixture.expect(.toolbar(.link),
                                 from: "see |",
                                 produces: "see [|](url)")
        }
        @Test func linkWrapsSelectionAndSelectsUrl() {
            EditorFixture.expect(.toolbar(.link),
                                 from: "see «Apple»",
                                 produces: "see [Apple](«url»)")
        }
        @Test func imageInsertsTemplate() {
            EditorFixture.expect(.toolbar(.image),
                                 from: "see |",
                                 produces: "see ![|](path)")
        }
        @Test func horizontalRuleInsertsLine() {
            EditorFixture.expect(.toolbar(.horizontalRule),
                                 from: "a|",
                                 produces: "a\n---\n|")
        }
        @Test func wikilinkInsertsEmptyTemplate() {
            EditorFixture.expect(.toolbar(.wikilink),
                                 from: "see |",
                                 produces: "see [[|]]")
        }
    }

    @Suite("Block wraps")
    struct BlockWrapTests {
        @Test func codeBlockInsertsFences() {
            EditorFixture.expect(.toolbar(.codeBlock),
                                 from: "before|after",
                                 produces: "before\n```\n|\n```\nafter")
        }
        @Test func mathDisplayInsertsBlockFence() {
            EditorFixture.expect(.toolbar(.mathDisplay),
                                 from: "before|after",
                                 produces: "before\n$$\n|\n$$\nafter")
        }
        @Test func mermaidInsertsLabeledFence() {
            EditorFixture.expect(.toolbar(.mermaid),
                                 from: "before|after",
                                 produces: "before\n```mermaid\n|\n```\nafter")
        }
    }
}
