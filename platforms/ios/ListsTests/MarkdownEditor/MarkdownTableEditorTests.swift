import Testing
import UIKit
import SwiftUI
@testable import Lists

@MainActor
struct MarkdownTableEditorTests {
    @Test func parserRecognizesGFMTablesAndEscapedPipes() {
        let source = """
        | Left | Center | Right |
        | :--- | :---: | ---: |
        | A\\|B | C | D |
        """

        let table = MarkdownTableParser.tables(in: source).first

        #expect(table?.columnCount == 3)
        #expect(table?.alignments == [.left, .center, .right])
        #expect(table?.bodyRows.first?.cells.first?.text == "A|B")
    }

    @Test func parserIgnoresMalformedPipeRows() {
        #expect(MarkdownTableParser.tables(in: "| A | B |\nnot a divider\n| C | D |").isEmpty)
        #expect(MarkdownTableParser.tables(in: "A | B\n--- | ---").isEmpty)
    }

    @Test func caretSnapsOutOfHiddenPipeAndPaddingRanges() {
        let source = "| Column 1 | Column 2 |\n| --- | --- |\n| Cell A | Cell B |\n"
        let ns = source as NSString

        #expect(MarkdownTableParser.snappedSelection(
            NSRange(location: ns.range(of: "|").location, length: 0),
            in: source
        ) == NSRange(location: ns.range(of: "Column 1").location, length: 0))

        #expect(MarkdownTableParser.snappedSelection(
            NSRange(location: ns.range(of: " | Column 2").location, length: 0),
            in: source
        ) == NSRange(location: NSMaxRange(ns.range(of: "Column 1")), length: 0))

        #expect(MarkdownTableParser.snappedSelection(
            NSRange(location: ns.range(of: "| Column 2").location + 1, length: 0),
            in: source
        ) == NSRange(location: ns.range(of: "Column 2").location, length: 0))
    }

    @Test func caretSnapsToEmptyCellContentInsteadOfColumnGap() {
        let source = "| A | B |\n| --- | --- |\n|  | B |\n"
        let ns = source as NSString
        let bodyRowStart = ns.range(of: "|  | B |").location

        #expect(MarkdownTableParser.snappedSelection(
            NSRange(location: bodyRowStart, length: 0),
            in: source
        ) == NSRange(location: bodyRowStart + 3, length: 0))
    }

    @Test func rowAndColumnCommandsKeepPortableMarkdown() {
        let source = "| A | B |\n| --- | --- |\n| C | D |\n"
        let selection = (source as NSString).range(of: "C")

        #expect(MarkdownTableCommand.addRowAbove.apply(to: source, selection: selection).source
                == "| A | B |\n| --- | --- |\n|  |  |\n| C | D |\n")
        #expect(MarkdownTableCommand.addRowBelow.apply(to: source, selection: selection).source
                == "| A | B |\n| --- | --- |\n| C | D |\n|  |  |\n")
        #expect(MarkdownTableCommand.addColumnBefore.apply(to: source, selection: selection).source
                == "|  | A | B |\n| --- | --- | --- |\n|  | C | D |\n")
        #expect(MarkdownTableCommand.addColumnAfter.apply(to: source, selection: selection).source
                == "| A |  | B |\n| --- | --- | --- |\n| C |  | D |\n")
        #expect(MarkdownTableCommand.setAlignment(.right).apply(to: source, selection: selection).source
                == "| A | B |\n| ---: | --- |\n| C | D |\n")
    }

    @Test func cellEditUpdatesOnlyTargetCellAndEscapesPipes() throws {
        let source = "| A | B |\n| --- | --- |\n| C | D |\n"
        let table = try #require(MarkdownTableParser.tables(in: source).first)

        let result = MarkdownTableCellEdit.apply(
            to: source,
            table: table,
            address: MarkdownTableCellAddress(row: 1, column: 0),
            text: "Left | Right"
        )

        #expect(result.source == "| A | B |\n| --- | --- |\n| Left \\| Right | D |\n")
        #expect((result.source as NSString).substring(with: NSRange(location: result.selection.location - 5, length: 5)) == "Right")
    }

    @Test func cellEditStoresCellNewlinesAsMarkdownLineBreaks() throws {
        let source = "| A | B |\n| --- | --- |\n| C | D |\n"
        let table = try #require(MarkdownTableParser.tables(in: source).first)

        let result = MarkdownTableCellEdit.apply(
            to: source,
            table: table,
            address: MarkdownTableCellAddress(row: 1, column: 0),
            text: "Line 1\nLine 2"
        )

        #expect(result.source == "| A | B |\n| --- | --- |\n| Line 1<br>Line 2 | D |\n")
        let parsed = try #require(MarkdownTableParser.tables(in: result.source).first)
        #expect(parsed.bodyRows.first?.cells.first?.text == "Line 1\nLine 2")
    }

    @Test func liveStylingHidesPipeSyntaxAndUsesStableRowMetrics() throws {
        let styler = configuredStyler(width: 360)
        styler.replaceCharacters(in: NSRange(location: 0, length: 0),
                                 with: "| Column 1 | Column 2 |\n| --- | --- |\n| Cell A | Cell B |\n")

        let pipeColor = try #require(styler.attribute(.foregroundColor,
                                                      at: 0,
                                                      effectiveRange: nil) as? UIColor)
        #expect(pipeColor == UIColor.clear)

        let contentLocation = ("| " as NSString).length
        let contentColor = try #require(styler.attribute(.foregroundColor,
                                                         at: contentLocation,
                                                         effectiveRange: nil) as? UIColor)
        #expect(contentColor == UIColor.clear)

        let headerParagraph = try #require(styler.attribute(.paragraphStyle,
                                                            at: 2,
                                                            effectiveRange: nil) as? NSParagraphStyle)
        let expectedHeight = MarkdownTableVisualMetrics.rowHeight(for: UIFont.preferredFont(forTextStyle: .body))
        #expect(abs(headerParagraph.minimumLineHeight - expectedHeight) < 0.5)
        #expect(abs(headerParagraph.maximumLineHeight - expectedHeight) < 0.5)

        let dividerLocation = ("| Column 1 | Column 2 |\n" as NSString).length
        let dividerParagraph = try #require(styler.attribute(.paragraphStyle,
                                                             at: dividerLocation,
                                                             effectiveRange: nil) as? NSParagraphStyle)
        #expect(dividerParagraph.maximumLineHeight < 1)
    }

    @Test func tableCaretRectUsesTextHeightNotFullRowHeight() throws {
        let source = "| Column 1 | Column 2 |\n| --- | --- |\n| Cell A | Cell B |\n"
        let textView = configuredTextView(width: 360)
        let storage = try #require(textView.textStorage as? MarkdownStyler)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        textView.layoutIfNeeded()

        let location = (source as NSString).range(of: "Column 1").location + 4
        let position = try #require(textView.position(from: textView.beginningOfDocument,
                                                      offset: location))
        let caret = textView.caretRect(for: position)
        let font = UIFont.preferredFont(forTextStyle: .body)

        #expect(caret.height <= MarkdownTableVisualMetrics.caretHeight(
            for: font,
            rowHeight: MarkdownTableVisualMetrics.rowHeight(for: font)
        ) + 1)
        #expect(caret.height < MarkdownTableVisualMetrics.rowHeight(for: font))
    }

    @Test func tableOverlayInstallsCellsAndSeparateMenusOnFirstRefresh() throws {
        var bindingText = "| Column 1 | Column 2 |\n| --- | --- |\n| Cell A | Cell B |\n"
        let textView = configuredTextView(width: 360)
        let storage = try #require(textView.textStorage as? MarkdownStyler)
        let coordinator = EditorCoordinator(text: Binding(
            get: { bindingText },
            set: { bindingText = $0 }
        ))
        coordinator.textViewRef = textView
        coordinator.installTableControls(in: textView)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: bindingText)
        textView.layoutIfNeeded()

        coordinator.refreshTableControls()

        #expect(textView.descendant(withAccessibilityIdentifier: "markdown.table.0") != nil)
        #expect(textView.descendant(withAccessibilityIdentifier: "markdown.table.cell.0.0") != nil)
        #expect(textView.descendant(withAccessibilityIdentifier: "markdown.table.cell.1.1") != nil)
        #expect(textView.descendant(withAccessibilityIdentifier: "markdown.table.row.menu") != nil)
        #expect(textView.descendant(withAccessibilityIdentifier: "markdown.table.column.menu") != nil)
    }

    private func configuredStyler(width: CGFloat) -> MarkdownStyler {
        let styler = MarkdownStyler()
        let layout = MarkdownLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layout.addTextContainer(container)
        styler.addLayoutManager(layout)
        styler.glyphInvalidatable = layout
        styler.mode = .live
        return styler
    }

    private func configuredTextView(width: CGFloat) -> MarkdownInternalTextView {
        let styler = MarkdownStyler()
        let layout = MarkdownLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layout.addTextContainer(container)
        styler.addLayoutManager(layout)
        styler.glyphInvalidatable = layout

        let textView = MarkdownInternalTextView(
            frame: CGRect(x: 0, y: 0, width: width, height: 240),
            textContainer: container
        )
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        MarkdownTypingStyle.apply(to: textView)
        return textView
    }
}

private extension UIView {
    func descendant(withAccessibilityIdentifier identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier {
            return self
        }
        for subview in subviews {
            if let found = subview.descendant(withAccessibilityIdentifier: identifier) {
                return found
            }
        }
        return nil
    }
}
