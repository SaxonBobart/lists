import Foundation
import Testing
import UIKit
@testable import Lists

/// The editor applies a transform's full new source as the *minimal* changed
/// range via the text input layer (so native Undo works). TextDiff.minimal
/// computes that range in UTF-16 / NSString space.
struct MinimalDiffTests {

    @Test func identicalStringsAreNoOp() {
        let diff = TextDiff.minimal(from: "hello", to: "hello")
        #expect(diff.range.length == 0)
        #expect(diff.replacement == "")
    }

    @Test func insertInMiddle() {
        let diff = TextDiff.minimal(from: "ac", to: "abc")
        #expect(diff.range == NSRange(location: 1, length: 0))
        #expect(diff.replacement == "b")
    }

    @Test func deleteSingleChar() {
        let diff = TextDiff.minimal(from: "abc", to: "ac")
        #expect(diff.range == NSRange(location: 1, length: 1))
        #expect(diff.replacement == "")
    }

    @Test func replaceRun() {
        let diff = TextDiff.minimal(from: "abXYZcd", to: "abPQcd")
        #expect(diff.range == NSRange(location: 2, length: 3))
        #expect(diff.replacement == "PQ")
    }

    @Test func appendAtEnd() {
        let diff = TextDiff.minimal(from: "ab", to: "abc")
        #expect(diff.range == NSRange(location: 2, length: 0))
        #expect(diff.replacement == "c")
    }

    @Test func emojiInsertUsesUTF16Units() {
        // Inserting before a family emoji: the range must be in UTF-16 units.
        let emoji = "👨‍👩‍👧‍👦"
        let diff = TextDiff.minimal(from: emoji, to: "X" + emoji)
        #expect(diff.range == NSRange(location: 0, length: 0))
        #expect(diff.replacement == "X")
    }

    @Test func emojiAppendUsesUTF16Units() {
        let emoji = "👨‍👩‍👧‍👦"
        let diff = TextDiff.minimal(from: emoji, to: emoji + "!")
        #expect(diff.range == NSRange(location: (emoji as NSString).length, length: 0))
        #expect(diff.replacement == "!")
    }

    @Test func highlightWrapsSelectionAsPortableMarkdown() {
        let result = ToolbarAction.highlight.apply(
            to: "alpha beta",
            selection: NSRange(location: 6, length: 4)
        )

        #expect(result.source == "alpha ==beta==")
        #expect(result.selection == NSRange(location: 8, length: 4))
        #expect(!result.source.contains("<mark"))
    }

    @Test func highlightEmptySelectionInsertsMarkersAroundCaret() {
        let result = ToolbarAction.highlight.apply(
            to: "ab",
            selection: NSRange(location: 1, length: 0)
        )

        #expect(result.source == "a====b")
        #expect(result.selection == NSRange(location: 3, length: 0))
    }

    @Test func highlightTogglesOffExistingMarkedSelection() {
        let result = ToolbarAction.highlight.apply(
            to: "==beta==",
            selection: NSRange(location: 2, length: 4)
        )

        #expect(result.source == "beta")
        #expect(result.selection == NSRange(location: 0, length: 4))
    }

    @MainActor
    @Test func markdownToolbarOrderMatchesPagedPlan() {
        #expect(MarkdownReminderToolbar.toolbarAccessibilityIdentifiers == [
            "markdown.toolbar.heading",
            "markdown.toolbar.task",
            "markdown.toolbar.link",
            "markdown.toolbar.image",
            "markdown.toolbar.table",
            "markdown.toolbar.bold",
            "markdown.toolbar.italic",
            "markdown.toolbar.strike",
            "markdown.toolbar.highlight",
            "markdown.toolbar.bullet",
            "markdown.toolbar.numbered",
            "markdown.toolbar.quote",
            "markdown.outdent",
            "markdown.indent",
            "markdown.toolbar.code",
            "markdown.toolbar.codeBlock",
            "markdown.toolbar.hr",
            "markdown.toolbar.footnote",
            "markdown.toolbar.wikilink",
            "markdown.toolbar.math",
            "markdown.toolbar.math.display",
            "markdown.toolbar.mermaid"
        ])
        #expect(!MarkdownReminderToolbar.toolbarAccessibilityIdentifiers.contains("markdown.toolbar.more"))
        #expect(!MarkdownReminderToolbar.toolbarAccessibilityIdentifiers.contains("markdown.toolbar.documentLink"))
    }

    @MainActor
    @Test func markdownFormatMenuOrderMatchesFormattingHub() {
        #expect(MarkdownFormatInputView.formatAccessibilityIdentifiers == [
            "markdown.toolbar.heading.0",
            "markdown.toolbar.heading.1",
            "markdown.toolbar.heading.2",
            "markdown.toolbar.heading.3",
            "markdown.toolbar.heading.4",
            "markdown.toolbar.heading.5",
            "markdown.toolbar.heading.6",
            "markdown.toolbar.bold",
            "markdown.toolbar.italic",
            "markdown.toolbar.strike",
            "markdown.toolbar.code",
            "markdown.toolbar.highlight",
            "markdown.toolbar.bullet",
            "markdown.toolbar.numbered",
            "markdown.toolbar.task",
            "markdown.toolbar.quote",
            "markdown.outdent",
            "markdown.indent"
        ])
    }

    @MainActor
    @Test func markdownToolbarSnapOffsetUsesFiveItemPages() {
        let slotWidth: CGFloat = 60

        #expect(MarkdownReminderToolbar.snapOffset(proposedOffset: 1.0 * slotWidth, slotWidth: slotWidth) == 0)
        #expect(MarkdownReminderToolbar.snapOffset(proposedOffset: 1.3 * slotWidth, slotWidth: slotWidth) == 5 * slotWidth)
        #expect(MarkdownReminderToolbar.snapOffset(
            currentOffset: 0,
            proposedOffset: 0.8 * slotWidth,
            velocityX: 0.2,
            slotWidth: slotWidth
        ) == 5 * slotWidth)
        #expect(MarkdownReminderToolbar.snapOffset(proposedOffset: 9999, slotWidth: slotWidth) == 20 * slotWidth)
    }

    @MainActor
    @Test func liveHighlightStylingUsesSemanticToken() throws {
        let styler = MarkdownStyler()
        styler.mode = .live
        styler.replaceCharacters(in: NSRange(location: 0, length: 0), with: "==marked==")

        let attributes = styler.attributes(at: 2, effectiveRange: nil)
        let highlightSpan = try #require(attributes[.highlightSpan])
        let foreground = try #require(attributes[.foregroundColor] as? UIColor)

        #expect(highlightSpan as? Bool == true)
        #expect(colorsApproximatelyEqual(foreground, ListsTokens.Markdown.highlightForegroundUIColor))
        #expect(attributes[.backgroundColor] == nil)
    }

    @MainActor
    @Test func readOnlyBodyUsesSemanticRendererOnlyForHighlights() {
        #expect(MarkdownBodyView.usesSemanticHighlightRenderer("plain **markdown**") == false)
        #expect(MarkdownBodyView.usesSemanticHighlightRenderer("plain ==marked== text"))
        #expect(MarkdownBodyView.usesSemanticHighlightRenderer(#"<mark data-color="orange">legacy</mark>"#))
        #expect(MarkdownBodyView.usesSemanticHighlightRenderer("$x$"))
        #expect(MarkdownBodyView.usesSemanticHighlightRenderer("```mermaid\ngraph TD\n```"))
        #expect(MarkdownBodyView.usesSemanticHighlightRenderer("| A | B |\n| --- | --- |\n| C | D |"))
        #expect(MarkdownBodyView.usesSemanticHighlightRenderer("> [!NOTE]\n> Heads up"))
        #expect(MarkdownBodyView.usesSemanticHighlightRenderer("[OpenAI](https://openai.com)"))
    }

    @Test func urlLinkBuilderNormalizesAndInsertsMarkdownLinks() throws {
        let normalized = try #require(DocumentMarkdownLinkBuilder.normalizedURL(from: "example.com/path"))
        #expect(normalized.absoluteString == "https://example.com/path")
        #expect(DocumentMarkdownLinkBuilder.markdownLink(label: "Read [this]", url: normalized) == #"[Read \[this\]](https://example.com/path)"#)

        let body = "See this"
        let selection = DocumentLinkEditorSelection(
            range: NSRange(location: 4, length: 4),
            selectedText: "this"
        )
        #expect(DocumentMarkdownLinkBuilder.replacingSelection(selection,
                                                               in: body,
                                                               label: "Example",
                                                               url: normalized) == "See [Example](https://example.com/path)")
    }

    @Test func headingAndParagraphTransformsShareLinePrefixSlot() {
        let heading = ToolbarAction.heading(2).apply(
            to: "Roadmap",
            selection: NSRange(location: 0, length: 0)
        )
        #expect(heading.source == "## Roadmap")

        let paragraph = ToolbarAction.paragraph.apply(
            to: heading.source,
            selection: NSRange(location: 3, length: 0)
        )
        #expect(paragraph.source == "Roadmap")
    }

    @Test func inlineCodeWrapsSelection() {
        let result = ToolbarAction.code.apply(
            to: "Use code here",
            selection: NSRange(location: 4, length: 4)
        )

        #expect(result.source == "Use `code` here")
        #expect(result.selection == NSRange(location: 5, length: 4))
    }

    @Test func formatMenuLineActionsApplyExpectedPrefixes() {
        #expect(ToolbarAction.bullet.apply(
            to: "Thing",
            selection: NSRange(location: 0, length: 0)
        ).source == "- Thing")
        #expect(ToolbarAction.numbered.apply(
            to: "Thing",
            selection: NSRange(location: 0, length: 0)
        ).source == "1. Thing")
        #expect(ToolbarAction.task.apply(
            to: "Thing",
            selection: NSRange(location: 0, length: 0)
        ).source == "- [ ] Thing")
        #expect(ToolbarAction.blockquote.apply(
            to: "Thing",
            selection: NSRange(location: 0, length: 0)
        ).source == "> Thing")
    }

    @Test func indentAndOutdentRoundTripLinePrefix() {
        let indented = ToolbarAction.indent.apply(
            to: "- Thing",
            selection: NSRange(location: 0, length: 0)
        )
        #expect(indented.source == "    - Thing")

        let outdented = ToolbarAction.outdent.apply(
            to: indented.source,
            selection: NSRange(location: 4, length: 0)
        )
        #expect(outdented.source == "- Thing")
    }

    @Test func multilineLineActionsApplyEveryTouchedLine() {
        let result = ToolbarAction.task.apply(
            to: "one\ntwo",
            selection: NSRange(location: 0, length: 7)
        )

        #expect(result.source == "- [ ] one\n- [ ] two")
    }

    @Test func nestedInlineStateDetectsOuterFormattingInsideCode() {
        let source = "***~~==`text`==~~***"
        let selectedText = (source as NSString).range(of: "text")
        let state = MarkdownFormatState.detect(in: source, selection: selectedText)

        #expect(state.isActive(.bold))
        #expect(state.isActive(.italic))
        #expect(state.isActive(.strikethrough))
        #expect(state.isActive(.code))
        #expect(state.isActive(.highlight))
    }

    @Test func nestedInlineTogglesRemoveOnlyRequestedFormat() {
        let source = "***~~==`text`==~~***"
        let selectedText = (source as NSString).range(of: "text")

        let withoutBold = ToolbarAction.bold.apply(to: source, selection: selectedText)
        #expect(withoutBold.source == "*~~==`text`==~~*")

        let withoutItalic = ToolbarAction.italic.apply(to: source, selection: selectedText)
        #expect(withoutItalic.source == "**~~==`text`==~~**")

        let withoutStrike = ToolbarAction.strikethrough.apply(to: source, selection: selectedText)
        #expect(withoutStrike.source == "***==`text`==***")

        let withoutHighlight = ToolbarAction.highlight.apply(to: source, selection: selectedText)
        #expect(withoutHighlight.source == "***~~`text`~~***")

        let withoutCode = ToolbarAction.code.apply(to: source, selection: selectedText)
        #expect(withoutCode.source == "***~~==text==~~***")
    }

    @Test func caretInsideNestedInlineTogglesContainingFormatOff() {
        let source = "***~~==`hello`==~~***"
        let caretInsideHello = NSRange(location: (source as NSString).range(of: "hello").location + 2,
                                       length: 0)

        let withoutBold = ToolbarAction.bold.apply(to: source, selection: caretInsideHello)
        #expect(withoutBold.source == "*~~==`hello`==~~*")

        let withoutItalic = ToolbarAction.italic.apply(to: source, selection: caretInsideHello)
        #expect(withoutItalic.source == "**~~==`hello`==~~**")

        let withoutStrike = ToolbarAction.strikethrough.apply(to: source, selection: caretInsideHello)
        #expect(withoutStrike.source == "***==`hello`==***")

        let withoutHighlight = ToolbarAction.highlight.apply(to: source, selection: caretInsideHello)
        #expect(withoutHighlight.source == "***~~`hello`~~***")

        let withoutCode = ToolbarAction.code.apply(to: source, selection: caretInsideHello)
        #expect(withoutCode.source == "***~~==hello==~~***")
    }

    @Test func sequentialInlineFormattingBuildsNestedPortableMarkdown() {
        let plain = "text"
        let bold = ToolbarAction.bold.apply(to: plain, selection: NSRange(location: 0, length: 4))
        #expect(bold.source == "**text**")

        let italic = ToolbarAction.italic.apply(to: bold.source, selection: bold.selection)
        #expect(italic.source == "***text***")

        let strike = ToolbarAction.strikethrough.apply(to: italic.source, selection: italic.selection)
        #expect(strike.source == "***~~text~~***")

        let code = ToolbarAction.code.apply(to: strike.source, selection: strike.selection)
        #expect(code.source == "***~~`text`~~***")

        let highlight = ToolbarAction.highlight.apply(to: code.source, selection: code.selection)
        #expect(highlight.source == "***~~==`text`==~~***")
    }

    @Test func mixedInlineSelectionsDoNotShowFalseActiveState() {
        let source = "**bold** plain"
        let selection = NSRange(location: 2, length: 11)
        let state = MarkdownFormatState.detect(in: source, selection: selection)

        #expect(!state.isActive(.bold))
    }

    @Test func addingFormatInsideInlineCodeWrapsTheCodeSpan() {
        let source = "`text`"
        let selectedText = (source as NSString).range(of: "text")

        let result = ToolbarAction.bold.apply(to: source, selection: selectedText)

        #expect(result.source == "**`text`**")
        #expect(result.selection == NSRange(location: 3, length: 4))
    }

    @Test func toolbarInsertionsUseEditablePlaceholders() {
        #expect(ToolbarAction.link.apply(
            to: "",
            selection: NSRange(location: 0, length: 0)
        ).source == "[link text](url)")

        let image = ToolbarAction.image.apply(
            to: "diagram",
            selection: NSRange(location: 0, length: 7)
        )
        #expect(image.source == "![diagram](path)")
        #expect(image.selection == NSRange(location: 11, length: 4))

        let wikilink = ToolbarAction.wikilink.apply(
            to: "",
            selection: NSRange(location: 0, length: 0)
        )
        #expect(wikilink.source == "[[Page]]")
        #expect(wikilink.selection == NSRange(location: 2, length: 4))
    }

    @Test func blockInsertionsUseReadableMarkdownTemplates() {
        let code = ToolbarAction.codeBlock.apply(
            to: "",
            selection: NSRange(location: 0, length: 0)
        )
        #expect(code.source == "```\ncode\n```")
        #expect(code.selection == NSRange(location: 4, length: 4))

        let math = ToolbarAction.mathDisplay.apply(
            to: "",
            selection: NSRange(location: 0, length: 0)
        )
        #expect(math.source == "$$\nx = y\n$$")
        #expect(math.selection == NSRange(location: 3, length: 5))

        let mermaid = ToolbarAction.mermaid.apply(
            to: "",
            selection: NSRange(location: 0, length: 0)
        )
        #expect(mermaid.source.contains("```mermaid\n"))
        #expect(mermaid.source.contains("graph TD"))
        #expect(mermaid.selection.length > 0)
    }

    @Test func inlineMathAndTableInsertionsSelectFirstEditableContent() {
        let inline = ToolbarAction.mathInline.apply(
            to: "",
            selection: NSRange(location: 0, length: 0)
        )
        #expect(inline.source == "$x$")
        #expect(inline.selection == NSRange(location: 1, length: 1))

        let table = ToolbarAction.table.apply(
            to: "",
            selection: NSRange(location: 0, length: 0)
        )
        #expect(table.source == "| Column 1 | Column 2 |\n| --- | --- |\n| Cell A | Cell B |\n")
        #expect(table.selection == NSRange(location: 2, length: 8))
    }

    @Test func footnotesPreserveSelectionAndPickNextAvailableId() {
        let first = ToolbarAction.footnote.apply(
            to: "hello",
            selection: NSRange(location: 0, length: 5)
        )
        #expect(first.source == "hello[^1]\n\n[^1]: ")
        #expect(first.selection == NSRange(location: 9, length: 0))

        let second = ToolbarAction.footnote.apply(
            to: first.source,
            selection: NSRange(location: 0, length: 0)
        )
        #expect(second.source.contains("[^2]"))
        #expect(second.source.contains("[^2]: "))
    }

    @Test func tableTabAndReturnMoveThroughCells() {
        let source = "| A | B |\n| --- | --- |\n|  |  |"
        let ns = source as NSString
        let tabbed = IndentHandler.indent(
            source: source,
            selection: NSRange(location: ns.range(of: "A").location, length: 0)
        )
        #expect(tabbed.source == source)
        #expect(tabbed.selection == ns.range(of: "B"))

        let tabbedToBody = IndentHandler.indent(
            source: source,
            selection: NSRange(location: ns.range(of: "B").location, length: 0)
        )
        #expect(tabbedToBody.source == source)
        #expect(tabbedToBody.selection == NSRange(location: 27, length: 0))

        let returned = ListContinuation.apply(
            to: source,
            selection: NSRange(location: ns.range(of: "B").location + 1, length: 0)
        )
        #expect(returned.source == source)
        #expect(returned.selection == NSRange(location: 30, length: 0))

        let returnedAtEnd = ListContinuation.apply(
            to: source,
            selection: NSRange(location: source.count, length: 0)
        )
        #expect(returnedAtEnd.source == "| A | B |\n| --- | --- |\n|  |  |\n|  |  |")
        #expect(returnedAtEnd.selection == NSRange(location: 34, length: 0))
    }

    @Test func tableParserSupportsAlignmentAndEscapedPipes() {
        let source = "| Left | Middle | Right |\n| :--- | :---: | ---: |\n| A\\|B | C | D |\n"
        let tables = MarkdownTableParser.tables(in: source)
        #expect(tables.count == 1)
        let table = tables[0]
        #expect(table.columnCount == 3)
        #expect(table.alignments == [.left, .center, .right])
        #expect(table.bodyRows.first?.cells.first?.text == "A|B")
    }

    @Test func tableCommandsEditPortableMarkdown() {
        let source = "| A | B |\n| --- | --- |\n| C | D |\n"
        let selectedC = (source as NSString).range(of: "C")

        let addedColumn = ToolbarAction.tableAddColumn.apply(to: source, selection: selectedC)
        #expect(addedColumn.source == "| A |  | B |\n| --- | --- | --- |\n| C |  | D |\n")
        #expect(addedColumn.selection == NSRange(location: 39, length: 0))

        let addedRow = ToolbarAction.tableAddRow.apply(to: source, selection: selectedC)
        #expect(addedRow.source == "| A | B |\n| --- | --- |\n| C | D |\n|  |  |\n")
        #expect(addedRow.selection == NSRange(location: 36, length: 0))

        let addedRowAbove = MarkdownTableCommand.addRowAbove.apply(to: source, selection: selectedC)
        #expect(addedRowAbove.source == "| A | B |\n| --- | --- |\n|  |  |\n| C | D |\n")

        let addedColumnBefore = MarkdownTableCommand.addColumnBefore.apply(to: source, selection: selectedC)
        #expect(addedColumnBefore.source == "|  | A | B |\n| --- | --- | --- |\n|  | C | D |\n")

        let aligned = ToolbarAction.tableAlign.apply(to: source, selection: selectedC)
        #expect(aligned.source == "| A | B |\n| :--- | --- |\n| C | D |\n")

        let rightAligned = MarkdownTableCommand.setAlignment(.right).apply(to: source, selection: selectedC)
        #expect(rightAligned.source == "| A | B |\n| ---: | --- |\n| C | D |\n")

        let deletedColumn = ToolbarAction.tableDeleteColumn.apply(to: source, selection: selectedC)
        #expect(deletedColumn.source == "| B |\n| --- |\n| D |\n")

        let deletedRow = ToolbarAction.tableDeleteRow.apply(to: source, selection: selectedC)
        #expect(deletedRow.source == "| A | B |\n| --- | --- |\n|  |  |\n")
    }

    private func colorsApproximatelyEqual(_ lhs: UIColor, _ rhs: UIColor) -> Bool {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        var lhsRed: CGFloat = 0
        var lhsGreen: CGFloat = 0
        var lhsBlue: CGFloat = 0
        var lhsAlpha: CGFloat = 0
        var rhsRed: CGFloat = 0
        var rhsGreen: CGFloat = 0
        var rhsBlue: CGFloat = 0
        var rhsAlpha: CGFloat = 0

        lhs.resolvedColor(with: traits).getRed(&lhsRed, green: &lhsGreen, blue: &lhsBlue, alpha: &lhsAlpha)
        rhs.resolvedColor(with: traits).getRed(&rhsRed, green: &rhsGreen, blue: &rhsBlue, alpha: &rhsAlpha)

        return abs(lhsRed - rhsRed) < 0.001
            && abs(lhsGreen - rhsGreen) < 0.001
            && abs(lhsBlue - rhsBlue) < 0.001
            && abs(lhsAlpha - rhsAlpha) < 0.001
    }
}
