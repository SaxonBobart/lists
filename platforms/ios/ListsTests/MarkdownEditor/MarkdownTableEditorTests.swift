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

    @Test func rowAndColumnMoveCommandsPreserveCellsAndAlignment() {
        let source = "| First | Second |\n| :--- | ---: |\n| A1 | A2 |\n| B1 | B2 |\n"
        let ns = source as NSString

        let movedRow = MarkdownTableCommand.moveRowDown.apply(
            to: source,
            selection: ns.range(of: "A1")
        ).source
        #expect(movedRow == "| First | Second |\n| :--- | ---: |\n| B1 | B2 |\n| A1 | A2 |\n")

        let movedColumn = MarkdownTableCommand.moveColumnRight.apply(
            to: source,
            selection: ns.range(of: "First")
        ).source
        #expect(movedColumn == "| Second | First |\n| ---: | :--- |\n| A2 | A1 |\n| B2 | B1 |\n")
    }

    @Test func rangeCommandsUseSelectionEdgesAndApplyAtomically() throws {
        let source = "| A | B | C | D |\n| :--- | :---: | ---: | --- |\n| A1 | B1 | C1 | D1 |\n| A2 | B2 | C2 | D2 |\n| A3 | B3 | C3 | D3 |\n"
        let ns = source as NSString

        let addedAfter = MarkdownTableCommand.addColumnAfter.apply(
            to: source,
            selection: ns.range(of: "A"),
            selectedRange: 0...1
        ).source
        #expect(addedAfter.hasPrefix("| A | B |  | C | D |"))

        let addedBelow = MarkdownTableCommand.addRowBelow.apply(
            to: source,
            selection: ns.range(of: "A1"),
            selectedRange: 1...2
        ).source
        let addedBelowTable = try #require(MarkdownTableParser.tables(in: addedBelow).first)
        #expect(addedBelowTable.bodyRows.map { $0.cells.first?.text } == ["A1", "A2", "", "A3"])

        let aligned = MarkdownTableCommand.setAlignment(.right).apply(
            to: source,
            selection: ns.range(of: "A"),
            selectedRange: 0...1
        ).source
        let alignedTable = try #require(MarkdownTableParser.tables(in: aligned).first)
        #expect(alignedTable.alignments == [.right, .right, .right, .none])

        let deleted = MarkdownTableCommand.deleteColumn.apply(
            to: source,
            selection: ns.range(of: "B"),
            selectedRange: 1...2
        ).source
        let deletedTable = try #require(MarkdownTableParser.tables(in: deleted).first)
        #expect(deletedTable.header.cells.map(\.text) == ["A", "D"])
        #expect(deletedTable.bodyRows.first?.cells.map(\.text) == ["A1", "D1"])
    }

    @Test func rangeMoveCommandsMoveWholeBandsOnePosition() throws {
        let source = "| A | B | C | D |\n| --- | --- | --- | --- |\n| A1 | B1 | C1 | D1 |\n| A2 | B2 | C2 | D2 |\n| A3 | B3 | C3 | D3 |\n| A4 | B4 | C4 | D4 |\n"
        let ns = source as NSString

        let columns = MarkdownTableCommand.moveColumnRight.apply(
            to: source,
            selection: ns.range(of: "A"),
            selectedRange: 0...1
        ).source
        let columnTable = try #require(MarkdownTableParser.tables(in: columns).first)
        #expect(columnTable.header.cells.map(\.text) == ["C", "A", "B", "D"])

        let rows = MarkdownTableCommand.moveRowDown.apply(
            to: source,
            selection: ns.range(of: "A1"),
            selectedRange: 1...2
        ).source
        let rowTable = try #require(MarkdownTableParser.tables(in: rows).first)
        #expect(rowTable.bodyRows.map { $0.cells.first?.text } == ["A3", "A1", "A2", "A4"])
    }

    @Test func dragReorderMovesRowsAndColumnsDirectlyToTheirDestination() throws {
        let source = "| A | B | C |\n| :--- | :---: | ---: |\n| A1 | B1 | C1 |\n| A2 | B2 | C2 |\n| A3 | B3 | C3 |"
        let table = try #require(MarkdownTableParser.tables(in: source).first)

        let movedRow = MarkdownTableReorder.apply(
            axis: .row,
            from: 3,
            to: 1,
            selectedAddress: MarkdownTableCellAddress(row: 3, column: 1),
            table: table,
            source: source
        )
        let rowTable = try #require(MarkdownTableParser.tables(in: movedRow.source).first)
        #expect(rowTable.bodyRows.map { $0.cells.map(\.text) } == [
            ["A3", "B3", "C3"],
            ["A1", "B1", "C1"],
            ["A2", "B2", "C2"]
        ])

        let movedColumn = MarkdownTableReorder.apply(
            axis: .column,
            from: 2,
            to: 0,
            selectedAddress: MarkdownTableCellAddress(row: 1, column: 2),
            table: rowTable,
            source: movedRow.source
        )
        let columnTable = try #require(MarkdownTableParser.tables(in: movedColumn.source).first)
        #expect(columnTable.header.cells.map(\.text) == ["C", "A", "B"])
        #expect(columnTable.alignments == [.right, .left, .center])
        #expect(columnTable.bodyRows.first?.cells.map(\.text) == ["C3", "A3", "B3"])
    }

    @Test func dragReorderCanMoveTheMarkdownHeaderRow() throws {
        let source = "| Header A | Header B |\n| --- | --- |\n| Body A | Body B |"
        let table = try #require(MarkdownTableParser.tables(in: source).first)

        let moved = MarkdownTableReorder.apply(
            axis: .row,
            from: 0,
            to: 1,
            selectedAddress: MarkdownTableCellAddress(row: 0, column: 0),
            table: table,
            source: source
        )
        let movedTable = try #require(MarkdownTableParser.tables(in: moved.source).first)
        #expect(movedTable.header.cells.map(\.text) == ["Body A", "Body B"])
        #expect(movedTable.bodyRows.first?.cells.map(\.text) == ["Header A", "Header B"])
    }

    @Test func dragReorderMovesContiguousRowAndColumnSelectionsAtomically() throws {
        let source = "| A | B | C | D |\n| :--- | :---: | ---: | --- |\n| A1 | B1 | C1 | D1 |\n| A2 | B2 | C2 | D2 |\n| A3 | B3 | C3 | D3 |\n| A4 | B4 | C4 | D4 |"
        let table = try #require(MarkdownTableParser.tables(in: source).first)

        let movedRows = MarkdownTableReorder.apply(
            axis: .row,
            range: 1...2,
            to: 3,
            selectedAddress: MarkdownTableCellAddress(row: 1, column: 0),
            table: table,
            source: source
        )
        let rowTable = try #require(MarkdownTableParser.tables(in: movedRows.source).first)
        #expect(rowTable.bodyRows.map { $0.cells.first?.text } == ["A3", "A4", "A1", "A2"])

        let movedColumns = MarkdownTableReorder.apply(
            axis: .column,
            range: 0...1,
            to: 2,
            selectedAddress: MarkdownTableCellAddress(row: 1, column: 0),
            table: rowTable,
            source: movedRows.source
        )
        let columnTable = try #require(MarkdownTableParser.tables(in: movedColumns.source).first)
        #expect(columnTable.header.cells.map(\.text) == ["C", "D", "A", "B"])
        #expect(columnTable.alignments == [.right, .none, .left, .center])
        #expect(columnTable.bodyRows.first?.cells.map(\.text) == ["C3", "D3", "A3", "B3"])
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

    @Test func csvExportQuotesOnlyCellsThatNeedIt() throws {
        let source = "| Name | Notes |\n| --- | --- |\n| Lists | One, two |\n| Quote | Said \"hello\"<br>twice |\n"
        let table = try #require(MarkdownTableParser.tables(in: source).first)

        #expect(MarkdownTableExport.csv(table) == "Name,Notes\nLists,\"One, two\"\nQuote,\"Said \"\"hello\"\"\ntwice\"")
    }

    @Test func liveStylingHidesPipeSyntaxAndUsesStableRowMetrics() throws {
        let styler = configuredStyler(width: 360)
        let source = "| Column 1 | Column 2 |\n| --- | --- |\n| Cell A | Cell B |\n"
        styler.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)

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
        let font = UIFont.preferredFont(forTextStyle: .body)
        let table = try #require(MarkdownTableParser.tables(in: source).first)
        let expectedHeight = MarkdownTableVisualMetrics.blockHeight(
            for: table,
            font: font,
            editorWidth: 167
        )
        #expect(abs(headerParagraph.minimumLineHeight - expectedHeight) < 0.5)
        #expect(abs(headerParagraph.maximumLineHeight - expectedHeight) < 0.5)

        let dividerLocation = ("| Column 1 | Column 2 |\n" as NSString).length
        let dividerParagraph = try #require(styler.attribute(.paragraphStyle,
                                                             at: dividerLocation,
                                                             effectiveRange: nil) as? NSParagraphStyle)
        #expect(dividerParagraph.maximumLineHeight < 1)
        let bodyLocation = ("| Column 1 | Column 2 |\n| --- | --- |\n" as NSString).length
        let bodyParagraph = try #require(styler.attribute(
            .paragraphStyle,
            at: bodyLocation,
            effectiveRange: nil
        ) as? NSParagraphStyle)
        #expect(bodyParagraph.maximumLineHeight < 1)
    }

    @Test func inlineOnlyStylingRendersCellMarkdownWithoutBlockFormatting() throws {
        let styler = MarkdownStyler(scope: .inlineOnly, textRole: .body)
        let layout = MarkdownLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude)
        )
        let layoutDelegate = MarkdownLayoutDelegate()
        layoutDelegate.styler = styler
        layout.delegate = layoutDelegate
        layout.addTextContainer(container)
        styler.addLayoutManager(layout)
        styler.glyphInvalidatable = layout
        let source = "**Bold** *italic* `code` ==mark== [Link](https://example.com) [[Note]] $x$"
        styler.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        styler.cursorRange = NSRange(location: NSNotFound, length: 0)

        let ns = source as NSString
        let bold = ns.range(of: "Bold")
        let boldFont = try #require(
            styler.attribute(.font, at: bold.location, effectiveRange: nil) as? UIFont
        )
        #expect(boldFont.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(styler.glyphProperty(at: 0) == .null)

        let code = ns.range(of: "code")
        #expect(styler.attribute(.inlineCodeSpan, at: code.location, effectiveRange: nil) != nil)
        let link = ns.range(of: "Link")
        #expect(
            styler.attribute(.link, at: link.location, effectiveRange: nil) as? URL
                == URL(string: "https://example.com")
        )
        let note = ns.range(of: "Note")
        #expect(
            styler.attribute(.underlineStyle, at: note.location, effectiveRange: nil)
                as? Int == NSUnderlineStyle.single.rawValue
        )

        styler.cursorRange = NSRange(location: bold.location + 1, length: 0)
        #expect(styler.glyphProperty(at: 0) == nil)

        let blockLike = MarkdownStyler(scope: .inlineOnly, textRole: .body)
        blockLike.replaceCharacters(
            in: NSRange(location: 0, length: 0),
            with: "# Not a heading"
        )
        let blockFont = try #require(
            blockLike.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        )
        #expect(blockFont.fontDescriptor.symbolicTraits.contains(.traitBold) == false)
    }

    @Test func formattedCellMeasurementKeepsTrailingEditableLineStable() {
        let oneLine = MarkdownTableVisualMetrics.inlineCellMeasurement(
            text: "**Bold**",
            textRole: .body,
            editorWidth: 180
        )
        let trailingNewline = MarkdownTableVisualMetrics.inlineCellMeasurement(
            text: "**Bold**\n",
            textRole: .body,
            editorWidth: 180
        )
        let populatedSecondLine = MarkdownTableVisualMetrics.inlineCellMeasurement(
            text: "**Bold**\nX",
            textRole: .body,
            editorWidth: 180
        )

        #expect(trailingNewline.requiredEditorHeight > oneLine.requiredEditorHeight)
        #expect(
            MarkdownTableVisualMetrics.rowHeight(for: trailingNewline)
                == MarkdownTableVisualMetrics.rowHeight(for: populatedSecondLine)
        )
        #expect(trailingNewline.text == "**Bold**\n")
    }

    @Test func liveStylingAllocatesMultilineCellHeightInDocumentLayout() throws {
        let styler = configuredStyler(width: 360)
        let source = "| Line 1<br>Line 2<br>Line 3 | Header |\n| --- | --- |\n| Body | Cell |\n"
        styler.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)

        let headerParagraph = try #require(styler.attribute(
            .paragraphStyle,
            at: 2,
            effectiveRange: nil
        ) as? NSParagraphStyle)
        let bodyLocation = (source as NSString).range(of: "| Body |").location
        let bodyParagraph = try #require(styler.attribute(
            .paragraphStyle,
            at: bodyLocation,
            effectiveRange: nil
        ) as? NSParagraphStyle)
        let font = UIFont.preferredFont(forTextStyle: .body)

        let table = try #require(MarkdownTableParser.tables(in: source).first)
        let expectedBlockHeight = MarkdownTableVisualMetrics.blockHeight(
            for: table,
            font: font,
            editorWidth: 167
        )
        #expect(abs(headerParagraph.minimumLineHeight - expectedBlockHeight) < 0.5)
        #expect(bodyParagraph.minimumLineHeight < 1)
        #expect(headerParagraph.minimumLineHeight > bodyParagraph.minimumLineHeight)
        #expect(
            headerParagraph.paragraphSpacingBefore
                == MarkdownTableVisualMetrics.spacingBeforeTable
        )
    }

    @Test func atomicTableCaretSkipsHiddenMarkdownSource() throws {
        let source = "Before\n| A | B |\n| --- | --- |\n| C | D |\nAfter"
        let table = try #require(MarkdownTableParser.tables(in: source).first)
        let inside = table.header.cells[0].contentRange.location

        #expect(MarkdownTableAtomicEditing.snappedCaret(
            inside,
            previous: table.fullRange.location,
            in: source
        ) == NSMaxRange(table.fullRange))
        #expect(MarkdownTableAtomicEditing.snappedCaret(
            inside,
            previous: NSMaxRange(table.fullRange),
            in: source
        ) == table.fullRange.location)
        #expect(MarkdownTableAtomicEditing.snappedCaret(
            table.fullRange.location,
            previous: 0,
            in: source
        ) == table.fullRange.location)
        #expect(MarkdownTableAtomicEditing.snappedCaret(
            NSMaxRange(table.fullRange),
            previous: source.utf16.count,
            in: source
        ) == NSMaxRange(table.fullRange))
    }

    @Test func atomicTableSelectionAndDeletionExpandToWholeBlock() throws {
        let source = "Before\n| A | B |\n| --- | --- |\n| C | D |\nAfter"
        let table = try #require(MarkdownTableParser.tables(in: source).first)
        let partial = NSRange(
            location: table.header.cells[0].contentRange.location,
            length: 1
        )

        #expect(
            MarkdownTableParser.expandedAtomicSelection(partial, in: source)
                == table.fullRange
        )
        #expect(MarkdownTableAtomicEditing.deletionRange(
            NSRange(location: NSMaxRange(table.fullRange) - 1, length: 1),
            caret: NSMaxRange(table.fullRange),
            in: source
        ) == table.fullRange)
    }

    @Test func tableInsertionUsesRealBlankBlocksInsteadOfVisualSpacing() {
        let source = "AboveBelow"
        let result = ToolbarAction.table.apply(
            to: source,
            selection: NSRange(location: 5, length: 0)
        )

        #expect(result.source.hasPrefix("Above\n\n| Column 1 | Column 2 |"))
        #expect(result.source.hasSuffix("| Cell A | Cell B |\n\nBelow"))
        #expect(MarkdownTableVisualMetrics.spacingBeforeTable == 0)
    }

    @Test func liveTableSpacingNormalizationEnforcesBlankSourceBlocks() {
        let source = "Above\n| A | B |\n| --- | --- |\n| C | D |\nBelow"
        let originalCaret = NSRange(location: (source as NSString).length, length: 0)
        let result = MarkdownTableBlockSpacing.normalized(
            source: source,
            selection: originalCaret
        )

        #expect(result.source == "Above\n\n| A | B |\n| --- | --- |\n| C | D |\n\nBelow")
        #expect(result.selection.location == originalCaret.location + 2)

        let stable = MarkdownTableBlockSpacing.normalized(
            source: result.source,
            selection: result.selection
        )
        #expect(stable.source == result.source)
        #expect(stable.selection == result.selection)
    }

    @Test func tableBoundaryCaretsSpanTheAtomicBlockHeight() throws {
        let source = "| Column 1 | Column 2 |\n| --- | --- |\n| Cell A | Cell B |\n"
        let textView = configuredTextView(width: 360)
        let storage = try #require(textView.textStorage as? MarkdownStyler)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        textView.layoutIfNeeded()

        let before = try #require(textView.position(
            from: textView.beginningOfDocument,
            offset: 0
        ))
        let after = try #require(textView.position(
            from: textView.beginningOfDocument,
            offset: (source as NSString).length
        ))
        let beforeCaret = textView.caretRect(for: before)
        let afterCaret = textView.caretRect(for: after)
        let font = UIFont.preferredFont(forTextStyle: .body)
        let table = try #require(MarkdownTableParser.tables(in: source).first)
        let expected = MarkdownTableVisualMetrics.blockHeight(
            for: table,
            font: font,
            editorWidth: 167
        )

        #expect(abs(beforeCaret.height - expected) < 1)
        #expect(abs(afterCaret.height - expected) < 1)
        #expect(beforeCaret.minX < afterCaret.minX)
    }

    @Test func blankParagraphAfterTableKeepsItsNormalEditableCaret() throws {
        let source = "| A | B |\n| --- | --- |\n| C | D |\n\nAfter"
        let textView = configuredTextView(width: 360)
        let storage = try #require(textView.textStorage as? MarkdownStyler)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        textView.layoutIfNeeded()
        let table = try #require(MarkdownTableParser.tables(in: source).first)
        let blankPosition = try #require(textView.position(
            from: textView.beginningOfDocument,
            offset: NSMaxRange(table.fullRange)
        ))
        let blankCaret = textView.caretRect(for: blankPosition)

        #expect(blankCaret.height < MarkdownTableVisualMetrics.rowHeight(
            for: UIFont.preferredFont(forTextStyle: .body)
        ))
    }

    @Test func pointDrivenCaretNavigationTreatsLiveTableAsAtomicBlock() throws {
        let source = "Before\n\n| A | B |\n| --- | --- |\n| C | D |\n\nAfter"
        let textView = configuredTextView(width: 360)
        let storage = try #require(textView.textStorage as? MarkdownStyler)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        textView.layoutIfNeeded()
        let table = try #require(MarkdownTableParser.tables(in: source).first)

        let beforePosition = try #require(textView.position(
            from: textView.beginningOfDocument,
            offset: table.fullRange.location
        ))
        let beforeCaret = textView.caretRect(for: beforePosition)
        let blockMidY = beforeCaret.midY

        let left = try #require(textView.closestPosition(to: CGPoint(
            x: beforeCaret.minX + 4,
            y: blockMidY
        )))
        let right = try #require(textView.closestPosition(to: CGPoint(
            x: textView.bounds.maxX - textView.textContainerInset.right - 4,
            y: blockMidY
        )))

        #expect(
            textView.offset(from: textView.beginningOfDocument, to: left)
                == table.fullRange.location
        )
        #expect(
            textView.offset(from: textView.beginningOfDocument, to: right)
                == NSMaxRange(table.fullRange)
        )
        #expect(textView.caretRect(for: left).height == beforeCaret.height)
        #expect(textView.caretRect(for: right).height == beforeCaret.height)
    }

    @Test func trailingNewlineReservesTheActiveEmptyLineImmediately() {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let oneLine = MarkdownTableVisualMetrics.cellMeasurement(
            text: "Cell A",
            font: font,
            editorWidth: 167
        )
        let trailingNewline = MarkdownTableVisualMetrics.cellMeasurement(
            text: "Cell A\n",
            font: font,
            editorWidth: 167
        )
        let populatedSecondLine = MarkdownTableVisualMetrics.cellMeasurement(
            text: "Cell A\nX",
            font: font,
            editorWidth: 167
        )

        #expect(trailingNewline.requiredEditorHeight > oneLine.requiredEditorHeight)
        #expect(
            trailingNewline.requiredEditorHeight
                == populatedSecondLine.requiredEditorHeight
        )
        #expect(
            MarkdownTableVisualMetrics.rowHeight(for: trailingNewline)
                == MarkdownTableVisualMetrics.rowHeight(for: populatedSecondLine)
        )
    }

    @Test func activeCaretBottomCanExpandBeyondStaticTextBounds() {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let staticMeasurement = MarkdownTableVisualMetrics.cellMeasurement(
            text: "Cell A\nX",
            font: font,
            editorWidth: 167
        )
        let caretBottom = staticMeasurement.textHeight + 6
        let activeMeasurement = MarkdownTableVisualMetrics.cellMeasurement(
            text: "Cell A\nX",
            font: font,
            editorWidth: 167,
            caretBottom: caretBottom
        )

        #expect(activeMeasurement.caretBottom == caretBottom)
        #expect(
            activeMeasurement.requiredEditorHeight
                >= ceil(caretBottom + MarkdownTableVisualMetrics.editorBottomAllowance)
        )
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
        coordinator.focusTableCell(
            tableLocation: 0,
            address: MarkdownTableCellAddress(row: 1, column: 0),
            range: NSRange(location: 0, length: 0)
        )
        coordinator.refreshTableControls()
        textView.layoutIfNeeded()

        #expect(textView.descendant(withAccessibilityIdentifier: "markdown.table.0") != nil)
        #expect(textView.descendant(withAccessibilityIdentifier: "markdown.table.cell.0.0") != nil)
        #expect(textView.descendant(withAccessibilityIdentifier: "markdown.table.cell.1.1") != nil)
        #expect(textView.descendant(withAccessibilityIdentifier: "markdown.table.row.menu") != nil)
        #expect(textView.descendant(withAccessibilityIdentifier: "markdown.table.column.menu") != nil)
        let rowHandle = try #require(textView.descendant(
            withAccessibilityIdentifier: "markdown.table.row.menu"
        ))
        let columnHandle = try #require(textView.descendant(
            withAccessibilityIdentifier: "markdown.table.column.menu"
        ))
        #expect(rowHandle.backgroundColor == UIColor.clear)
        #expect(rowHandle.isAccessibilityElement)
        #expect(rowHandle.accessibilityTraits.contains(.button))
        #expect((rowHandle.gestureRecognizers ?? []).isEmpty)
        #expect(textView.gestureRecognizers?.contains(where: {
            $0.name == "markdown.table.interaction.handle"
        }) == true)
        #expect(rowHandle.accessibilityHint == "Tap to select, drag to reorder, or tap again for table actions")
        let rowHandleCenter = textView.convert(
            CGPoint(x: rowHandle.bounds.midX, y: rowHandle.bounds.midY),
            from: rowHandle
        )
        let columnHandleCenter = textView.convert(
            CGPoint(x: columnHandle.bounds.midX, y: columnHandle.bounds.midY),
            from: columnHandle
        )
        #expect(textView.hitTest(rowHandleCenter, with: nil) === rowHandle)
        #expect(textView.hitTest(columnHandleCenter, with: nil) === columnHandle)
        let cell = try #require(textView.descendant(
            withAccessibilityIdentifier: "markdown.table.cell.0.0"
        ) as? UITextView)
        cell.superview?.layoutIfNeeded()
        #expect(cell.font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        #expect((cell.textStorage as? MarkdownStyler)?.scope == .inlineOnly)
    }

    @Test func cellLinkReplacementTargetsOnlyTheSelectedTableCell() throws {
        let source = "Before\n\n| Name | Notes |\n| --- | --- |\n| Lists | A\\|B |\n\nAfter"
        let table = try #require(MarkdownTableParser.tables(in: source).first)
        let address = MarkdownTableCellAddress(row: 1, column: 1)
        let selection = DocumentLinkEditorSelection(
            tableLocation: table.fullRange.location,
            address: address,
            range: NSRange(location: 0, length: 1),
            selectedText: "A"
        )
        let replacement = DocumentMarkdownLinkBuilder.replacement(
            selection,
            in: source,
            label: "Docs",
            url: try #require(URL(string: "https://example.com"))
        )
        let updated = try #require(
            MarkdownTableParser.tables(in: replacement.body).first
        )

        #expect(
            updated.bodyRows.first?.cells[1].text
                == "[Docs](https://example.com)|B"
        )
        #expect(replacement.body.hasPrefix("Before\n\n"))
        #expect(replacement.body.hasSuffix("\nAfter"))
        guard case .tableCell(
            let tableLocation,
            let focusedAddress,
            let range
        ) = replacement.focusTarget else {
            Issue.record("Expected table-cell focus restoration")
            return
        }
        #expect(tableLocation == table.fullRange.location)
        #expect(focusedAddress == address)
        #expect(range.location == ("[Docs](https://example.com)" as NSString).length)
    }

    @Test func tableCellToolbarScopeContainsOnlyInlineActions() {
        #expect(ToolbarAction.bold.isSupportedInTableCell)
        #expect(ToolbarAction.italic.isSupportedInTableCell)
        #expect(ToolbarAction.strikethrough.isSupportedInTableCell)
        #expect(ToolbarAction.code.isSupportedInTableCell)
        #expect(ToolbarAction.highlight.isSupportedInTableCell)
        #expect(ToolbarAction.link.isSupportedInTableCell)
        #expect(ToolbarAction.wikilink.isSupportedInTableCell)
        #expect(ToolbarAction.mathInline.isSupportedInTableCell)
        #expect(ToolbarAction.heading(1).isSupportedInTableCell == false)
        #expect(ToolbarAction.task.isSupportedInTableCell == false)
        #expect(ToolbarAction.image.isSupportedInTableCell == false)
        #expect(ToolbarAction.table.isSupportedInTableCell == false)
        #expect(ToolbarAction.mathDisplay.isSupportedInTableCell == false)
    }

    @Test func dragDirectionSeparatesReorderFromMenuPressAndCrossAxisMovement() {
        #expect(MarkdownTableDragDirection.accepts(CGPoint(x: 4, y: 80), for: .row))
        #expect(!MarkdownTableDragDirection.accepts(CGPoint(x: 80, y: 4), for: .row))
        #expect(MarkdownTableDragDirection.accepts(CGPoint(x: 80, y: 4), for: .column))
        #expect(!MarkdownTableDragDirection.accepts(CGPoint(x: 4, y: 80), for: .column))
        #expect(!MarkdownTableDragDirection.accepts(.zero, for: .row))
        #expect(!MarkdownTableDragDirection.accepts(.zero, for: .column))
        #expect(MarkdownTableDragDirection.accepts(CGPoint(x: 0.2, y: 1), for: .row))
        #expect(MarkdownTableDragDirection.accepts(CGPoint(x: 1, y: 0.2), for: .column))
    }

    @Test func dragSelectionPolicySeparatesTransientAndPersistentSelection() {
        let transient = MarkdownTableDragSelectionPolicy.resolve(
            axis: .column,
            selectedIndex: 1,
            selectedAxis: nil,
            selectedRange: nil
        )
        #expect(transient.source == 1...1)
        #expect(!transient.preservesSelection)

        let persistent = MarkdownTableDragSelectionPolicy.resolve(
            axis: .column,
            selectedIndex: 1,
            selectedAxis: .column,
            selectedRange: 0...2
        )
        #expect(persistent.source == 0...2)
        #expect(persistent.preservesSelection)

        let otherAxis = MarkdownTableDragSelectionPolicy.resolve(
            axis: .row,
            selectedIndex: 2,
            selectedAxis: .column,
            selectedRange: 0...2
        )
        #expect(otherAxis.source == 2...2)
        #expect(!otherAxis.preservesSelection)
    }

    @Test func selectionGripKeepsItsOriginalAnchorWhileCrossingBands() {
        #expect(MarkdownTableBandSelectionRange.resolved(anchor: 0, candidate: 1) == 0...1)
        #expect(MarkdownTableBandSelectionRange.resolved(anchor: 2, candidate: 0) == 0...2)
        #expect(MarkdownTableBandSelectionRange.resolved(anchor: 1, candidate: 1) == 1...1)
    }

    @Test func neighboringBandsStayPutUntilDestinationSnapsPastHalfway() {
        #expect(MarkdownTableNeighborSnap.offset(
            for: 1,
            source: 0...0,
            destination: 0,
            sourceExtent: 44
        ) == 0)
        #expect(MarkdownTableNeighborSnap.offset(
            for: 1,
            source: 0...0,
            destination: 1,
            sourceExtent: 44
        ) == -44)
        #expect(MarkdownTableNeighborSnap.offset(
            for: 2,
            source: 0...0,
            destination: 1,
            sourceExtent: 44
        ) == 0)
        #expect(MarkdownTableNeighborSnap.offset(
            for: 0,
            source: 1...1,
            destination: 0,
            sourceExtent: 44
        ) == 44)
    }

    @Test func selectionGripWaitsUntilItCrossesTheAdjacentBandMidpoint() {
        #expect(MarkdownTableSelectionGripCandidate.column(
            at: 200,
            isStart: false,
            gridMinX: 0,
            columnWidth: 100,
            columnCount: 3
        ) == 1)
        #expect(MarkdownTableSelectionGripCandidate.column(
            at: 249,
            isStart: false,
            gridMinX: 0,
            columnWidth: 100,
            columnCount: 3
        ) == 1)
        #expect(MarkdownTableSelectionGripCandidate.column(
            at: 251,
            isStart: false,
            gridMinX: 0,
            columnWidth: 100,
            columnCount: 3
        ) == 2)

        let rows = [
            CGRect(x: 0, y: 0, width: 300, height: 40),
            CGRect(x: 0, y: 40, width: 300, height: 60),
            CGRect(x: 0, y: 100, width: 300, height: 40)
        ]
        #expect(MarkdownTableSelectionGripCandidate.row(
            at: 100,
            isStart: false,
            rowRects: rows
        ) == 1)
        #expect(MarkdownTableSelectionGripCandidate.row(
            at: 121,
            isStart: false,
            rowRects: rows
        ) == 2)
    }

    @Test func tableKeepsFullWidthWhileEditingHandlesFloatAtItsEdges() {
        let inactive = MarkdownTableVisualMetrics.gridHorizontalFrame(
            outerX: 16,
            outerWidth: 328,
            isEditing: false
        )
        let editing = MarkdownTableVisualMetrics.gridHorizontalFrame(
            outerX: 16,
            outerWidth: 328,
            isEditing: true
        )

        #expect(inactive.minX == 16)
        #expect(inactive.width == 328)
        #expect(editing.minX == 16)
        #expect(editing.width == 328)
        #expect(MarkdownTableVisualMetrics.handleVisualSize == 20)
        #expect(MarkdownTableVisualMetrics.handleHitSize == 44)
        let rowGlyphCenter = MarkdownTableVisualMetrics.rowHandleGlyphCenterX(
            gridMinX: 21
        )
        #expect(rowGlyphCenter == 10.5)
        #expect(
            MarkdownTableVisualMetrics.columnHandleGlyphCenterY(gridMinY: 24)
                == 13.5
        )
        #expect(
            rowGlyphCenter + MarkdownTableVisualMetrics.handleDotDiameter / 2
                < 21
        )
        #expect(
            rowGlyphCenter - MarkdownTableVisualMetrics.handleDotDiameter / 2
                >= 0
        )
        #expect(
            MarkdownTableVisualMetrics.rowHeight(for: UIFont.preferredFont(forTextStyle: .body))
                == MarkdownTableVisualMetrics.rowHeight(
                    for: UIFont.preferredFont(forTextStyle: .body),
                    lineCount: 1
                )
        )
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
