import UIKit

enum MarkdownTableAlignment: Hashable, Sendable {
    case none
    case left
    case center
    case right

    init(dividerCell: String) {
        let trimmed = dividerCell.trimmingCharacters(in: .whitespaces)
        let starts = trimmed.hasPrefix(":")
        let ends = trimmed.hasSuffix(":")
        switch (starts, ends) {
        case (true, true): self = .center
        case (true, false): self = .left
        case (false, true): self = .right
        default: self = .none
        }
    }

    var dividerCell: String {
        switch self {
        case .none: return "---"
        case .left: return ":---"
        case .center: return ":---:"
        case .right: return "---:"
        }
    }

    var next: MarkdownTableAlignment {
        switch self {
        case .none: return .left
        case .left: return .center
        case .center: return .right
        case .right: return .none
        }
    }
}

struct MarkdownTableCell: Hashable, Sendable {
    let column: Int
    let segmentRange: NSRange
    let contentRange: NSRange
    let text: String
}

struct MarkdownTableRow: Hashable, Sendable {
    enum Role: Hashable, Sendable {
        case header
        case divider
        case body(Int)
    }

    let role: Role
    let lineRange: NSRange
    let cells: [MarkdownTableCell]
}

struct MarkdownTable: Hashable, Sendable {
    let fullRange: NSRange
    let header: MarkdownTableRow
    let divider: MarkdownTableRow
    let bodyRows: [MarkdownTableRow]
    let alignments: [MarkdownTableAlignment]

    var columnCount: Int {
        max(header.cells.count, alignments.count, bodyRows.map(\.cells.count).max() ?? 0)
    }

    var rows: [MarkdownTableRow] {
        [header, divider] + bodyRows
    }
}

enum MarkdownTableVisualMetrics {
    struct CellMeasurement: Equatable {
        let text: String
        let editorWidth: CGFloat
        let fontLineHeight: CGFloat
        let textHeight: CGFloat
        let caretBottom: CGFloat
        let requiredEditorHeight: CGFloat
    }

    static let handleHitSize: CGFloat = 44
    static let handleVisualSize: CGFloat = 20
    static let handleDotDiameter: CGFloat = 3.5
    static let handleEdgeOffset: CGFloat = 6
    static let selectionCapExtent: CGFloat = 24
    static let rowSelectionCapExtent: CGFloat = 16
    static let selectionStrokeWidth: CGFloat = 3
    static let selectionGripDiameter: CGFloat = 12
    static let topHandleHeight: CGFloat = 44
    static let spacingBeforeTable: CGFloat = 0
    static let cornerRadius: CGFloat = 0
    static let horizontalCellPadding: CGFloat = 4
    static let verticalCellPadding: CGFloat = 10
    static let editorBottomAllowance: CGFloat = 3

    static func rowHandleGlyphCenterX(gridMinX: CGFloat) -> CGFloat {
        gridMinX - (selectionCapExtent - selectionStrokeWidth) / 2
    }

    static func columnHandleGlyphCenterY(gridMinY: CGFloat) -> CGFloat {
        gridMinY - (selectionCapExtent - selectionStrokeWidth) / 2
    }

    static func gridHorizontalFrame(outerX: CGFloat,
                                    outerWidth: CGFloat,
                                    isEditing: Bool) -> CGRect {
        CGRect(x: outerX,
               y: 0,
               width: max(0, outerWidth),
               height: 0)
    }

    static func cellMeasurement(text: String,
                                font: UIFont,
                                editorWidth: CGFloat,
                                caretBottom: CGFloat = 0) -> CellMeasurement {
        let width = max(1, editorWidth)
        // TextKit's used rect does not include the empty trailing fragment
        // created by a final newline. A zero-width character forces that
        // fragment to participate in measurement without changing the cell.
        let measuredText = text.hasSuffix("\n") ? text + "\u{200B}" : text
        let storage = NSTextStorage(
            string: measuredText.isEmpty ? "\u{200B}" : measuredText,
            attributes: [.font: font]
        )
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        container.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        let glyphRange = layoutManager.glyphRange(for: container)
        var lineFragmentBottom: CGFloat = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
            lineRect, _, _, _, _ in
            lineFragmentBottom = max(lineFragmentBottom, lineRect.maxY)
        }
        // Line-fragment rectangles are stable between an empty trailing line
        // and that same line containing its first glyph. Glyph used-rects are
        // not, which caused the row to move by a pixel on the first character.
        let textBottom = max(font.lineHeight, lineFragmentBottom)
        let layoutBottom = caretBottom > textBottom + 1
            ? caretBottom
            : textBottom
        let required = ceil(
            layoutBottom + editorBottomAllowance
        )
        return CellMeasurement(
            text: text,
            editorWidth: width,
            fontLineHeight: font.lineHeight,
            textHeight: ceil(textBottom),
            caretBottom: caretBottom,
            requiredEditorHeight: required
        )
    }

    static func inlineCellMeasurement(
        text: String,
        textRole: MarkdownTextRole,
        editorWidth: CGFloat,
        caretBottom: CGFloat = 0
    ) -> CellMeasurement {
        let width = max(1, editorWidth)
        let storage = MarkdownStyler(scope: .inlineOnly, textRole: textRole)
        let layout = MarkdownLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        container.lineBreakMode = .byWordWrapping
        let layoutDelegate = MarkdownLayoutDelegate()
        layoutDelegate.styler = storage
        layout.delegate = layoutDelegate
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        storage.glyphInvalidatable = layout
        storage.mode = .live
        storage.cursorRange = NSRange(location: NSNotFound, length: 0)

        // Keep an inactive trailing editable line in layout even though
        // TextKit normally omits the final empty fragment from usedRect.
        let measuredText = text.hasSuffix("\n") ? text + "\u{200B}" : text
        storage.replaceCharacters(
            in: NSRange(location: 0, length: 0),
            with: measuredText.isEmpty ? "\u{200B}" : measuredText
        )
        layout.ensureLayout(for: container)
        let glyphRange = layout.glyphRange(for: container)
        var lineFragmentBottom: CGFloat = 0
        layout.enumerateLineFragments(forGlyphRange: glyphRange) {
            lineRect, _, _, _, _ in
            lineFragmentBottom = max(lineFragmentBottom, lineRect.maxY)
        }
        let preferred = UIFont.preferredFont(forTextStyle: .body)
        let baseFont = textRole == .tableHeader
            ? UIFont.systemFont(ofSize: preferred.pointSize, weight: .semibold)
            : preferred
        let textBottom = max(baseFont.lineHeight, lineFragmentBottom)
        return CellMeasurement(
            text: text,
            editorWidth: width,
            fontLineHeight: baseFont.lineHeight,
            textHeight: ceil(textBottom),
            caretBottom: caretBottom,
            requiredEditorHeight: ceil(
                max(textBottom, caretBottom) + editorBottomAllowance
            )
        )
    }

    static func rowHeight(for font: UIFont, lineCount: Int = 1) -> CGFloat {
        let text = Array(repeating: "X", count: max(1, lineCount))
            .joined(separator: "\n")
        return rowHeight(
            for: cellMeasurement(
                text: text,
                font: font,
                editorWidth: .greatestFiniteMagnitude
            )
        )
    }

    static func rowHeight(for measurement: CellMeasurement) -> CGFloat {
        max(
            44,
            ceil(measurement.requiredEditorHeight + 2 * verticalCellPadding)
        )
    }

    static func caretHeight(for font: UIFont, rowHeight: CGFloat) -> CGFloat {
        min(max(18, ceil(font.lineHeight)), max(18, rowHeight - 10))
    }

    static func rowHeights(
        for table: MarkdownTable,
        font: UIFont,
        editorWidth: CGFloat = .greatestFiniteMagnitude,
        liveMeasurements: [MarkdownTableCellAddress: CellMeasurement] = [:]
    ) -> [CGFloat] {
        let headerFont = UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        let compactHeight = max(
            rowHeight(for: cellMeasurement(text: "", font: font, editorWidth: editorWidth)),
            rowHeight(for: cellMeasurement(text: "", font: headerFont, editorWidth: editorWidth))
        )
        return ([table.header] + table.bodyRows).enumerated().map { rowIndex, row in
            let rowFont = rowIndex == 0
                ? headerFont
                : font
            let measurements = (0..<table.columnCount).map { column in
                let address = MarkdownTableCellAddress(row: rowIndex, column: column)
                let text = row.cells.first(where: { $0.column == column })?.text ?? ""
                if let live = liveMeasurements[address],
                   live.text == text,
                   abs(live.editorWidth - editorWidth) < 0.5,
                   abs(live.fontLineHeight - rowFont.lineHeight) < 0.5 {
                    return live
                }
                return inlineCellMeasurement(
                    text: text,
                    textRole: rowIndex == 0 ? .tableHeader : .body,
                    editorWidth: editorWidth
                )
            }
            return max(compactHeight, rowHeight(
                for: measurements.max {
                    $0.requiredEditorHeight < $1.requiredEditorHeight
                } ?? inlineCellMeasurement(
                    text: "",
                    textRole: rowIndex == 0 ? .tableHeader : .body,
                    editorWidth: editorWidth
                )
            ))
        }
    }

    static func blockHeight(for table: MarkdownTable,
                            font: UIFont,
                            editorWidth: CGFloat = .greatestFiniteMagnitude) -> CGFloat {
        rowHeights(
            for: table,
            font: font,
            editorWidth: editorWidth
        ).reduce(0, +)
    }
}

struct MarkdownTableCellAddress: Hashable, Sendable {
    /// Visible table row: `0` is the header row, `1...` are body rows.
    let row: Int
    let column: Int
}

enum MarkdownTableExport {
    static func csv(_ table: MarkdownTable) -> String {
        let count = max(1, table.columnCount)
        let rows = [table.header.cells.map(\.text)] + table.bodyRows.map { $0.cells.map(\.text) }
        return rows
            .map { row in
                row.padded(to: count).map(csvCell).joined(separator: ",")
            }
            .joined(separator: "\n")
    }

    private static func csvCell(_ text: String) -> String {
        guard text.contains(",") || text.contains("\"") || text.contains("\n") else {
            return text
        }
        return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum MarkdownTableParser {
    static func tables(in source: String) -> [MarkdownTable] {
        let ns = source as NSString
        guard ns.length > 0 else { return [] }

        var tables: [MarkdownTable] = []
        var cursor = 0
        while cursor < ns.length {
            let headerRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
            let headerLine = MarkdownSyntax.lineContent(in: ns, range: headerRange)
            guard let dividerRange = nextLineRange(after: headerRange, in: ns) else { break }
            let dividerLine = MarkdownSyntax.lineContent(in: ns, range: dividerRange)

            if isTableRow(headerLine), isDividerRow(dividerLine) {
                var rowRanges = [headerRange, dividerRange]
                var next = NSMaxRange(dividerRange)
                while next < ns.length {
                    let rowRange = ns.lineRange(for: NSRange(location: next, length: 0))
                    let rowLine = MarkdownSyntax.lineContent(in: ns, range: rowRange)
                    guard isTableRow(rowLine) else { break }
                    rowRanges.append(rowRange)
                    next = NSMaxRange(rowRange)
                }

                let header = MarkdownTableRow(
                    role: .header,
                    lineRange: headerRange,
                    cells: cells(in: headerLine, lineRange: headerRange)
                )
                let dividerCells = cells(in: dividerLine, lineRange: dividerRange)
                let divider = MarkdownTableRow(
                    role: .divider,
                    lineRange: dividerRange,
                    cells: dividerCells
                )
                let bodyRows = rowRanges.dropFirst(2).enumerated().map { offset, range in
                    MarkdownTableRow(
                        role: .body(offset),
                        lineRange: range,
                        cells: cells(in: MarkdownSyntax.lineContent(in: ns, range: range), lineRange: range)
                    )
                }
                let fullRange = NSRange(location: headerRange.location,
                                        length: NSMaxRange(rowRanges.last ?? dividerRange) - headerRange.location)
                tables.append(MarkdownTable(
                    fullRange: fullRange,
                    header: header,
                    divider: divider,
                    bodyRows: bodyRows,
                    alignments: dividerCells.map { MarkdownTableAlignment(dividerCell: $0.text) }
                ))
                cursor = NSMaxRange(rowRanges.last ?? dividerRange)
            } else {
                cursor = NSMaxRange(headerRange)
            }
        }

        return tables
    }

    static func table(containing selection: NSRange, in source: String) -> MarkdownTable? {
        let ns = source as NSString
        let selection = MarkdownSyntax.clamped(selection, length: ns.length)
        let probe = min(selection.location, max(0, ns.length - 1))
        return tables(in: source).first {
            probe >= $0.fullRange.location && probe < NSMaxRange($0.fullRange)
        }
    }

    static func row(containing selection: NSRange, in table: MarkdownTable) -> MarkdownTableRow? {
        let probe = selection.location
        return table.rows.first {
            probe >= $0.lineRange.location && probe < NSMaxRange($0.lineRange)
        }
    }

    static func address(for row: MarkdownTableRow,
                        cell: MarkdownTableCell,
                        in table: MarkdownTable) -> MarkdownTableCellAddress? {
        switch row.role {
        case .header:
            return MarkdownTableCellAddress(row: 0, column: cell.column)
        case .body(let index):
            return MarkdownTableCellAddress(row: index + 1, column: cell.column)
        case .divider:
            return nil
        }
    }

    static func cell(containing selection: NSRange, in table: MarkdownTable) -> MarkdownTableCell? {
        guard let row = row(containing: selection, in: table), row.role != .divider else {
            return nil
        }
        let probe = selection.location
        if let exact = row.cells.first(where: {
            probe >= $0.segmentRange.location && probe <= NSMaxRange($0.segmentRange)
        }) {
            return exact
        }
        return row.cells.min {
            abs($0.segmentRange.location - probe) < abs($1.segmentRange.location - probe)
        }
    }

    static func snappedSelection(_ selection: NSRange, in source: String) -> NSRange {
        guard selection.length == 0,
              let table = table(containing: selection, in: source) else {
            return selection
        }
        guard let row = row(containing: selection, in: table) else {
            return selection
        }

        if row.role == .divider {
            let fallback = table.bodyRows.first?.cells.first
                ?? table.header.cells.first
            return fallback.map { NSRange(location: $0.contentRange.location, length: 0) }
                ?? selection
        }

        let location = selection.location
        let cell = cell(containing: selection, in: table)
            ?? nearestCell(in: row, to: location)
        guard let cell else { return selection }

        let start = cell.contentRange.location
        let end = NSMaxRange(cell.contentRange)
        let snapped = min(max(location, start), end)
        return NSRange(location: snapped, length: 0)
    }

    static func table(strictlyContaining location: Int, in source: String) -> MarkdownTable? {
        tables(in: source).first {
            location > $0.fullRange.location && location < NSMaxRange($0.fullRange)
        }
    }

    static func table(intersecting range: NSRange, in source: String) -> MarkdownTable? {
        tables(in: source).first { table in
            if range.length == 0 {
                return range.location > table.fullRange.location
                    && range.location < NSMaxRange(table.fullRange)
            }
            return NSIntersectionRange(range, table.fullRange).length > 0
        }
    }

    static func expandedAtomicSelection(_ selection: NSRange, in source: String) -> NSRange {
        guard selection.length > 0 else { return selection }
        var lower = selection.location
        var upper = NSMaxRange(selection)
        for table in tables(in: source)
        where NSIntersectionRange(selection, table.fullRange).length > 0 {
            lower = min(lower, table.fullRange.location)
            upper = max(upper, NSMaxRange(table.fullRange))
        }
        return NSRange(location: lower, length: upper - lower)
    }

    static func isTableRow(_ line: String) -> Bool {
        unescapedPipeLocations(in: line).count >= 2
    }

    static func isDividerRow(_ line: String) -> Bool {
        guard isTableRow(line) else { return false }
        let cells = cellTexts(in: line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy(isDividerCell)
    }

    static func cellTexts(in line: String) -> [String] {
        cells(in: line, lineRange: NSRange(location: 0, length: (line as NSString).length))
            .map(\.text)
    }

    static func cells(in line: String, lineRange: NSRange) -> [MarkdownTableCell] {
        let ns = line as NSString
        let pipes = unescapedPipeLocations(in: line)
        guard pipes.count >= 2 else { return [] }

        var cells: [MarkdownTableCell] = []
        for column in 0..<(pipes.count - 1) {
            let segmentStart = pipes[column] + 1
            let segmentEnd = pipes[column + 1]
            var contentStart = segmentStart
            var contentEnd = segmentEnd

            while contentStart < contentEnd, ns.character(at: contentStart) == 0x20 {
                contentStart += 1
            }
            while contentEnd > contentStart, ns.character(at: contentEnd - 1) == 0x20 {
                contentEnd -= 1
            }

            let contentRange = NSRange(location: lineRange.location + contentStart,
                                       length: max(0, contentEnd - contentStart))
            let text = contentEnd > contentStart
                ? unescapeCellText(ns.substring(with: NSRange(location: contentStart,
                                                              length: contentEnd - contentStart)))
                : ""
            cells.append(MarkdownTableCell(
                column: column,
                segmentRange: NSRange(location: lineRange.location + segmentStart,
                                      length: max(0, segmentEnd - segmentStart)),
                contentRange: contentRange,
                text: text
            ))
        }
        return cells
    }

    static func render(header: [String],
                       alignments: [MarkdownTableAlignment],
                       bodyRows: [[String]]) -> (source: String, cellRanges: [[NSRange]]) {
        let columnCount = max(1, header.count, alignments.count, bodyRows.map(\.count).max() ?? 0)
        let normalizedHeader = padded(header, count: columnCount)
        let normalizedAlignments = padded(alignments, count: columnCount, fill: .none)
        let normalizedBody = bodyRows.isEmpty
            ? [Array(repeating: "", count: columnCount)]
            : bodyRows.map { padded($0, count: columnCount) }

        var source = ""
        var ranges: [[NSRange]] = []

        appendRow(normalizedHeader, to: &source, ranges: &ranges)
        source += "| " + normalizedAlignments.map(\.dividerCell).joined(separator: " | ") + " |\n"
        for row in normalizedBody {
            appendRow(row, to: &source, ranges: &ranges)
        }
        return (source, ranges)
    }

    static func escapeCellText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\|", with: "|")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func appendRow(_ row: [String], to source: inout String, ranges: inout [[NSRange]]) {
        var rowRanges: [NSRange] = []
        source += "|"
        for cell in row {
            source += " "
            let escaped = escapeCellText(cell)
            let start = (source as NSString).length
            source += escaped
            rowRanges.append(NSRange(location: start, length: (escaped as NSString).length))
            source += " |"
        }
        source += "\n"
        ranges.append(rowRanges)
    }

    private static func isDividerCell(_ cell: String) -> Bool {
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        var body = trimmed
        if body.first == ":" { body.removeFirst() }
        if body.last == ":" { body.removeLast() }
        return body.count >= 3 && body.allSatisfy { $0 == "-" }
    }

    private static func unescapeCellText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\|", with: "|")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
    }

    private static func unescapedPipeLocations(in line: String) -> [Int] {
        let ns = line as NSString
        var locations: [Int] = []
        var backslashRun = 0
        for index in 0..<ns.length {
            let char = ns.character(at: index)
            if char == 0x5C {
                backslashRun += 1
                continue
            }
            if char == 0x7C, backslashRun.isMultiple(of: 2) {
                locations.append(index)
            }
            backslashRun = 0
        }
        return locations
    }

    private static func nextLineRange(after lineRange: NSRange, in ns: NSString) -> NSRange? {
        let start = NSMaxRange(lineRange)
        guard start < ns.length else { return nil }
        return ns.lineRange(for: NSRange(location: start, length: 0))
    }

    private static func nearestCell(in row: MarkdownTableRow, to location: Int) -> MarkdownTableCell? {
        row.cells.min {
            distance(from: location, to: $0.contentRange) < distance(from: location, to: $1.contentRange)
        }
    }

    private static func distance(from location: Int, to range: NSRange) -> Int {
        if location < range.location { return range.location - location }
        if location > NSMaxRange(range) { return location - NSMaxRange(range) }
        return 0
    }

    private static func padded(_ values: [String], count: Int) -> [String] {
        values + Array(repeating: "", count: max(0, count - values.count))
    }

    private static func padded(_ values: [MarkdownTableAlignment],
                               count: Int,
                               fill: MarkdownTableAlignment) -> [MarkdownTableAlignment] {
        values + Array(repeating: fill, count: max(0, count - values.count))
    }
}

enum MarkdownTableCommand: Hashable, Sendable {
    case addRowAbove
    case addRowBelow
    case addColumnBefore
    case addColumnAfter
    case deleteRow
    case deleteColumn
    case moveRowUp
    case moveRowDown
    case moveColumnLeft
    case moveColumnRight
    case cycleAlignment
    case setAlignment(MarkdownTableAlignment)
    case deleteTable

    func apply(to source: String,
               selection: NSRange,
               selectedRange: ClosedRange<Int>? = nil) -> (source: String, selection: NSRange) {
        guard let table = MarkdownTableParser.table(containing: selection, in: source) else {
            return (source, selection)
        }

        let column = MarkdownTableParser.cell(containing: selection, in: table)?.column ?? 0
        let selectedRow = MarkdownTableParser.row(containing: selection, in: table)
        let bodyRowIndex: Int? = {
            if case .body(let index) = selectedRow?.role { return index }
            return nil
        }()
        let selectedVisibleRow = (bodyRowIndex ?? -1) + 1

        var header = table.header.cells.map(\.text)
        var alignments = table.alignments
        var body = table.bodyRows.map { $0.cells.map(\.text) }
        let columnCount = max(1, table.columnCount)
        header = header.padded(to: columnCount)
        alignments = alignments.padded(to: columnCount, fill: .none)
        body = body.isEmpty ? [Array(repeating: "", count: columnCount)] : body.map { $0.padded(to: columnCount) }

        let rowRange = clampedRange(selectedRange ?? selectedVisibleRow...selectedVisibleRow,
                                    lower: 0,
                                    upper: body.count)
        let columnRange = clampedRange(selectedRange ?? column...column,
                                       lower: 0,
                                       upper: columnCount - 1)
        let targetRow: Int
        let targetColumn: Int

        switch self {
        case .addRowAbove:
            var rows = [header] + body
            let insertIndex = min(max(0, rowRange.lowerBound), rows.count)
            rows.insert(Array(repeating: "", count: columnCount), at: insertIndex)
            header = rows.removeFirst()
            body = rows
            targetRow = insertIndex
            targetColumn = min(column, columnCount - 1)
        case .addRowBelow:
            var rows = [header] + body
            let insertIndex = min(rowRange.upperBound + 1, rows.count)
            rows.insert(Array(repeating: "", count: columnCount), at: insertIndex)
            header = rows.removeFirst()
            body = rows
            targetRow = insertIndex
            targetColumn = min(column, columnCount - 1)
        case .addColumnBefore:
            let insertColumn = columnRange.lowerBound
            header.insert("", at: insertColumn)
            alignments.insert(.none, at: insertColumn)
            for index in body.indices {
                body[index].insert("", at: insertColumn)
            }
            targetRow = (bodyRowIndex ?? -1) + 1
            targetColumn = insertColumn
        case .addColumnAfter:
            let insertColumn = min(columnRange.upperBound + 1, columnCount)
            header.insert("", at: insertColumn)
            alignments.insert(.none, at: insertColumn)
            for index in body.indices {
                body[index].insert("", at: insertColumn)
            }
            targetRow = (bodyRowIndex ?? -1) + 1
            targetColumn = insertColumn
        case .deleteRow:
            var rows = [header] + body
            if rowRange.count >= rows.count {
                return delete(table: table, from: source)
            }
            rows.removeSubrange(rowRange)
            header = rows.removeFirst()
            body = rows.isEmpty ? [Array(repeating: "", count: columnCount)] : rows
            targetRow = min(rowRange.lowerBound, body.count)
            targetColumn = min(column, max(0, columnCount - 1))
        case .deleteColumn:
            if columnRange.count >= columnCount {
                return delete(table: table, from: source)
            }
            header.removeSubrange(columnRange)
            alignments.removeSubrange(columnRange)
            for index in body.indices {
                body[index].removeSubrange(columnRange)
            }
            targetRow = (bodyRowIndex ?? -1) + 1
            targetColumn = min(columnRange.lowerBound, header.count - 1)
        case .moveRowUp:
            guard rowRange.lowerBound > 0 else {
                return (source, selection)
            }
            var rows = [header] + body
            let moved = Array(rows[rowRange])
            rows.removeSubrange(rowRange)
            let destination = rowRange.lowerBound - 1
            rows.insert(contentsOf: moved, at: destination)
            header = rows.removeFirst()
            body = rows
            targetRow = destination
            targetColumn = min(column, columnCount - 1)
        case .moveRowDown:
            var rows = [header] + body
            guard rowRange.upperBound + 1 < rows.count else {
                return (source, selection)
            }
            let moved = Array(rows[rowRange])
            rows.removeSubrange(rowRange)
            let destination = rowRange.lowerBound + 1
            rows.insert(contentsOf: moved, at: destination)
            header = rows.removeFirst()
            body = rows
            targetRow = destination
            targetColumn = min(column, columnCount - 1)
        case .moveColumnLeft:
            guard columnRange.lowerBound > 0 else {
                return (source, selection)
            }
            let destination = columnRange.lowerBound - 1
            let movedHeader = Array(header[columnRange])
            let movedAlignments = Array(alignments[columnRange])
            header.removeSubrange(columnRange)
            alignments.removeSubrange(columnRange)
            header.insert(contentsOf: movedHeader, at: destination)
            alignments.insert(contentsOf: movedAlignments, at: destination)
            for index in body.indices {
                let moved = Array(body[index][columnRange])
                body[index].removeSubrange(columnRange)
                body[index].insert(contentsOf: moved, at: destination)
            }
            targetRow = (bodyRowIndex ?? -1) + 1
            targetColumn = destination
        case .moveColumnRight:
            guard columnRange.upperBound + 1 < columnCount else {
                return (source, selection)
            }
            let destination = columnRange.lowerBound + 1
            let movedHeader = Array(header[columnRange])
            let movedAlignments = Array(alignments[columnRange])
            header.removeSubrange(columnRange)
            alignments.removeSubrange(columnRange)
            header.insert(contentsOf: movedHeader, at: destination)
            alignments.insert(contentsOf: movedAlignments, at: destination)
            for index in body.indices {
                let moved = Array(body[index][columnRange])
                body[index].removeSubrange(columnRange)
                body[index].insert(contentsOf: moved, at: destination)
            }
            targetRow = (bodyRowIndex ?? -1) + 1
            targetColumn = destination
        case .cycleAlignment:
            for index in columnRange {
                alignments[index] = alignments[index].next
            }
            targetRow = (bodyRowIndex ?? -1) + 1
            targetColumn = columnRange.lowerBound
        case .setAlignment(let alignment):
            for index in columnRange {
                alignments[index] = alignment
            }
            targetRow = (bodyRowIndex ?? -1) + 1
            targetColumn = columnRange.lowerBound
        case .deleteTable:
            return delete(table: table, from: source)
        }

        return replace(table: table,
                       in: source,
                       header: header,
                       alignments: alignments,
                       body: body,
                       targetRow: max(0, targetRow),
                       targetColumn: max(0, targetColumn))
    }

    private func clampedRange(_ range: ClosedRange<Int>,
                              lower: Int,
                              upper: Int) -> ClosedRange<Int> {
        let start = min(max(lower, range.lowerBound), upper)
        let end = min(max(start, range.upperBound), upper)
        return start...end
    }

    private func delete(table: MarkdownTable, from source: String) -> (source: String, selection: NSRange) {
        let ns = source as NSString
        let replacement = ns.replacingCharacters(in: table.fullRange, with: "")
        return (replacement, NSRange(location: table.fullRange.location, length: 0))
    }

    private func replace(table: MarkdownTable,
                         in source: String,
                         header: [String],
                         alignments: [MarkdownTableAlignment],
                         body: [[String]],
                         targetRow: Int,
                         targetColumn: Int) -> (source: String, selection: NSRange) {
        let ns = source as NSString
        let rendered = MarkdownTableParser.render(header: header, alignments: alignments, bodyRows: body)
        let replacement = ns.replacingCharacters(in: table.fullRange, with: rendered.source)
        let row = min(targetRow, rendered.cellRanges.count - 1)
        let column = min(targetColumn, rendered.cellRanges[row].count - 1)
        let relative = rendered.cellRanges[row][column]
        return (
            replacement,
            NSRange(location: table.fullRange.location + relative.location, length: relative.length)
        )
    }
}

enum MarkdownTableCellEdit {
    static func apply(to source: String,
                      table: MarkdownTable,
                      address: MarkdownTableCellAddress,
                      text: String) -> (source: String, selection: NSRange) {
        let columnCount = max(1, table.columnCount)
        var header = table.header.cells.map(\.text).padded(to: columnCount)
        let alignments = table.alignments.padded(to: columnCount, fill: .none)
        var body = table.bodyRows.map { $0.cells.map(\.text).padded(to: columnCount) }
        if body.isEmpty {
            body = [Array(repeating: "", count: columnCount)]
        }

        let column = min(max(0, address.column), columnCount - 1)
        if address.row == 0 {
            header[column] = text
        } else {
            let bodyRow = min(max(0, address.row - 1), body.count - 1)
            body[bodyRow][column] = text
        }

        let ns = source as NSString
        let rendered = MarkdownTableParser.render(header: header,
                                                  alignments: alignments,
                                                  bodyRows: body)
        let replacement = ns.replacingCharacters(in: table.fullRange, with: rendered.source)
        let row = min(max(0, address.row), rendered.cellRanges.count - 1)
        let range = rendered.cellRanges[row][column]
        return (
            replacement,
            NSRange(location: table.fullRange.location + NSMaxRange(range), length: 0)
        )
    }
}

enum MarkdownTableReorderAxis: Hashable, Sendable {
    case row
    case column
}

enum MarkdownTableDragDirection {
    static func accepts(_ velocity: CGPoint, for axis: MarkdownTableReorderAxis) -> Bool {
        let primary = axis == .row ? abs(velocity.y) : abs(velocity.x)
        let cross = axis == .row ? abs(velocity.x) : abs(velocity.y)
        return primary > 0 && primary >= cross
    }
}

enum MarkdownTableAtomicEditing {
    static func snappedCaret(_ proposed: Int,
                             previous: Int,
                             in source: String) -> Int {
        guard let table = MarkdownTableParser.table(
            strictlyContaining: proposed,
            in: source
        ) else { return proposed }
        return proposed >= previous
            ? NSMaxRange(table.fullRange)
            : table.fullRange.location
    }

    static func replacementRange(_ proposed: NSRange,
                                 in source: String) -> NSRange {
        guard proposed.location != NSNotFound else { return proposed }
        if proposed.length > 0 {
            return MarkdownTableParser.expandedAtomicSelection(proposed, in: source)
        }
        return proposed
    }

    static func deletionRange(_ proposed: NSRange,
                              caret: Int,
                              in source: String) -> NSRange {
        let expanded = MarkdownTableParser.expandedAtomicSelection(proposed, in: source)
        if expanded != proposed { return expanded }
        for table in MarkdownTableParser.tables(in: source) {
            let start = table.fullRange.location
            let end = NSMaxRange(table.fullRange)
            if caret == end,
               proposed.length == 1,
               NSMaxRange(proposed) == end {
                return table.fullRange
            }
            if caret == start,
               proposed.length == 1,
               proposed.location == start {
                return table.fullRange
            }
        }
        return proposed
    }
}

enum MarkdownTableBlockSpacing {
    static func normalized(source: String,
                           selection: NSRange) -> (source: String, selection: NSRange) {
        let ns = source as NSString
        let tables = MarkdownTableParser.tables(in: source)
        var insertionLocations: [Int] = []

        for table in tables {
            let start = table.fullRange.location
            let end = NSMaxRange(table.fullRange)
            if start > 0 {
                let hasBlankBefore = start >= 2
                    && ns.character(at: start - 1) == 0x0A
                    && ns.character(at: start - 2) == 0x0A
                if !hasBlankBefore {
                    insertionLocations.append(start)
                }
            }
            if end < ns.length {
                let hasBlankAfter = ns.character(at: end) == 0x0A
                if !hasBlankAfter {
                    insertionLocations.append(end)
                }
            }
        }

        guard !insertionLocations.isEmpty else { return (source, selection) }
        var normalized = source as NSString
        var mappedSelection = selection
        for location in insertionLocations.sorted(by: >) {
            normalized = normalized.replacingCharacters(
                in: NSRange(location: location, length: 0),
                with: "\n"
            ) as NSString
            if location <= mappedSelection.location {
                mappedSelection.location += 1
            } else if location < NSMaxRange(mappedSelection) {
                mappedSelection.length += 1
            }
        }
        return (normalized as String, mappedSelection)
    }
}

enum MarkdownTableDragSelectionPolicy {
    static func resolve(axis: MarkdownTableReorderAxis,
                        selectedIndex: Int,
                        selectedAxis: MarkdownTableReorderAxis?,
                        selectedRange: ClosedRange<Int>?) -> (source: ClosedRange<Int>, preservesSelection: Bool) {
        let preservesSelection = selectedAxis == axis
            && selectedRange?.contains(selectedIndex) == true
        return (
            preservesSelection ? (selectedRange ?? selectedIndex...selectedIndex) : selectedIndex...selectedIndex,
            preservesSelection
        )
    }
}

enum MarkdownTableBandSelectionRange {
    static func resolved(anchor: Int, candidate: Int) -> ClosedRange<Int> {
        min(anchor, candidate)...max(anchor, candidate)
    }
}

enum MarkdownTableNeighborSnap {
    static func offset(for index: Int,
                       source: ClosedRange<Int>,
                       destination: Int,
                       sourceExtent: CGFloat) -> CGFloat {
        if destination < source.lowerBound,
           index >= destination,
           index < source.lowerBound {
            return sourceExtent
        }
        if destination > source.lowerBound,
           index > source.upperBound,
           index < destination + source.count {
            return -sourceExtent
        }
        return 0
    }
}

enum MarkdownTableSelectionGripCandidate {
    static func column(at x: CGFloat,
                       isStart: Bool,
                       gridMinX: CGFloat,
                       columnWidth: CGFloat,
                       columnCount: Int) -> Int {
        guard columnCount > 0 else { return 0 }
        let adjustment = isStart ? columnWidth / 2 : -columnWidth / 2
        let proposed = Int(floor((x - gridMinX + adjustment) / max(1, columnWidth)))
        return min(max(0, proposed), columnCount - 1)
    }

    static func row(at y: CGFloat,
                    isStart: Bool,
                    rowRects: [CGRect]) -> Int {
        guard !rowRects.isEmpty else { return 0 }
        return rowRects.indices.min { lhs, rhs in
            let lhsEdge = isStart ? rowRects[lhs].minY : rowRects[lhs].maxY
            let rhsEdge = isStart ? rowRects[rhs].minY : rowRects[rhs].maxY
            return abs(lhsEdge - y) < abs(rhsEdge - y)
        } ?? 0
    }
}

enum MarkdownTableReorder {
    static func apply(axis: MarkdownTableReorderAxis,
                      from sourceIndex: Int,
                      to destinationIndex: Int,
                      selectedAddress: MarkdownTableCellAddress,
                      table: MarkdownTable,
                      source: String) -> (source: String, selection: NSRange) {
        apply(
            axis: axis,
            range: sourceIndex...sourceIndex,
            to: destinationIndex,
            selectedAddress: selectedAddress,
            table: table,
            source: source
        )
    }

    static func apply(axis: MarkdownTableReorderAxis,
                      range sourceRange: ClosedRange<Int>,
                      to destinationIndex: Int,
                      selectedAddress: MarkdownTableCellAddress,
                      table: MarkdownTable,
                      source: String) -> (source: String, selection: NSRange) {
        let columnCount = max(1, table.columnCount)
        var header = table.header.cells.map(\.text).padded(to: columnCount)
        let alignments = table.alignments.padded(to: columnCount, fill: .none)
        var reorderedAlignments = alignments
        var body = table.bodyRows.map { $0.cells.map(\.text).padded(to: columnCount) }
        guard !body.isEmpty else { return (source, selection(for: selectedAddress, in: table)) }

        let targetAddress: MarkdownTableCellAddress
        switch axis {
        case .row:
            var rows = [header] + body
            let lower = max(0, sourceRange.lowerBound)
            let upper = min(rows.count - 1, sourceRange.upperBound)
            guard lower <= upper else {
                return (source, selection(for: selectedAddress, in: table))
            }
            let count = upper - lower + 1
            let destination = min(max(0, destinationIndex), rows.count - count)
            guard lower != destination else {
                return (source, selection(for: selectedAddress, in: table))
            }
            let moved = Array(rows[lower...upper])
            rows.removeSubrange(lower...upper)
            rows.insert(contentsOf: moved, at: destination)
            header = rows.removeFirst()
            body = rows
            let selectedOffset = min(max(0, selectedAddress.row - lower), count - 1)
            targetAddress = MarkdownTableCellAddress(
                row: destination + selectedOffset,
                column: min(selectedAddress.column, columnCount - 1)
            )
        case .column:
            let lower = max(0, sourceRange.lowerBound)
            let upper = min(columnCount - 1, sourceRange.upperBound)
            guard lower <= upper else {
                return (source, selection(for: selectedAddress, in: table))
            }
            let count = upper - lower + 1
            let destination = min(max(0, destinationIndex), columnCount - count)
            guard lower != destination else {
                return (source, selection(for: selectedAddress, in: table))
            }
            let columns = lower...upper
            let movedHeader = Array(header[columns])
            let movedAlignments = Array(reorderedAlignments[columns])
            header.removeSubrange(columns)
            reorderedAlignments.removeSubrange(columns)
            header.insert(contentsOf: movedHeader, at: destination)
            reorderedAlignments.insert(contentsOf: movedAlignments, at: destination)
            for index in body.indices {
                let movedCells = Array(body[index][columns])
                body[index].removeSubrange(columns)
                body[index].insert(contentsOf: movedCells, at: destination)
            }
            let selectedOffset = min(max(0, selectedAddress.column - lower), count - 1)
            targetAddress = MarkdownTableCellAddress(
                row: min(selectedAddress.row, body.count),
                column: destination + selectedOffset
            )
        }

        let rendered = MarkdownTableParser.render(
            header: header,
            alignments: reorderedAlignments,
            bodyRows: body
        )
        let replacement = (source as NSString).replacingCharacters(
            in: table.fullRange,
            with: rendered.source
        )
        let targetRange = rendered.cellRanges[targetAddress.row][targetAddress.column]
        return (
            replacement,
            NSRange(
                location: table.fullRange.location + targetRange.location,
                length: targetRange.length
            )
        )
    }

    private static func selection(for address: MarkdownTableCellAddress,
                                  in table: MarkdownTable) -> NSRange {
        let visibleRows = [table.header] + table.bodyRows
        guard let row = visibleRows[safe: address.row],
              let cell = row.cells.first(where: { $0.column == address.column }) else {
            return NSRange(location: table.fullRange.location, length: 0)
        }
        return cell.contentRange
    }
}

private struct MarkdownTableOverlayGeometry {
    let frameRect: CGRect
    let gridRect: CGRect
    let rowRects: [CGRect]
    let rowHeights: [CGFloat]
    let columnCount: Int
}

private struct MarkdownTableFieldPayload {
    let table: MarkdownTable
    let address: MarkdownTableCellAddress
}

private final class MarkdownTableCellTextView: UITextView {
    var tablePayload: MarkdownTableFieldPayload?
    weak var tableController: MarkdownTableOverlayController?
    var isSynchronizingSource = false
    let markdownStorage: MarkdownStyler
    private let markdownLayoutDelegate: MarkdownLayoutDelegate
    let textRole: MarkdownTextRole

    init(textRole: MarkdownTextRole) {
        self.textRole = textRole
        let storage = MarkdownStyler(scope: .inlineOnly, textRole: textRole)
        let layout = MarkdownLayoutManager()
        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        let layoutDelegate = MarkdownLayoutDelegate()
        layoutDelegate.styler = storage
        layout.delegate = layoutDelegate
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        storage.glyphInvalidatable = layout
        markdownStorage = storage
        markdownLayoutDelegate = layoutDelegate
        super.init(frame: .zero, textContainer: container)
        linkTextAttributes = [
            .foregroundColor: UIColor(ListsTokens.accent),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: UIColor(ListsTokens.accent)
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    func currentMeasurement() -> MarkdownTableVisualMetrics.CellMeasurement {
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        var lineFragmentBottom: CGFloat = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
            lineRect, _, _, _, _ in
            lineFragmentBottom = max(lineFragmentBottom, lineRect.maxY)
        }
        let baseFont = textRole == .tableHeader
            ? UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                weight: .semibold
            )
            : UIFont.preferredFont(forTextStyle: .body)
        let caretBottom: CGFloat
        if isFirstResponder, let end = selectedTextRange?.end {
            caretBottom = caretRect(for: end).maxY
        } else {
            caretBottom = 0
        }
        let textBottom = max(baseFont.lineHeight, lineFragmentBottom)
        return MarkdownTableVisualMetrics.CellMeasurement(
            text: text ?? "",
            editorWidth: max(1, bounds.width),
            fontLineHeight: baseFont.lineHeight,
            textHeight: ceil(textBottom),
            caretBottom: caretBottom,
            requiredEditorHeight: ceil(
                max(textBottom, caretBottom)
                    + MarkdownTableVisualMetrics.editorBottomAllowance
            )
        )
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTab)),
            UIKeyCommand(input: "\t", modifierFlags: [.shift], action: #selector(handleShiftTab))
        ]
    }

    @objc private func handleTab() {
        tableController?.move(from: self, backward: false)
    }

    @objc private func handleShiftTab() {
        tableController?.move(from: self, backward: true)
    }
}

@MainActor
final class MarkdownTableOverlayController: NSObject,
                                            UITextViewDelegate,
                                            UIGestureRecognizerDelegate {
    private weak var textView: MarkdownInternalTextView?
    private weak var coordinator: EditorCoordinator?
    private var tableViews: [Int: MarkdownTableOverlayView] = [:]
    private var liveCellMeasurements:
        [Int: [MarkdownTableCellAddress: MarkdownTableVisualMetrics.CellMeasurement]] = [:]
    private var isApplyingCellEdit = false
    private lazy var outsideTableTapRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleOutsideTableTap(_:))
    )

    var hasActiveTableInteraction: Bool {
        tableViews.values.contains(where: \.hasActiveInteraction)
    }

    init(textView: MarkdownInternalTextView, coordinator: EditorCoordinator) {
        self.textView = textView
        self.coordinator = coordinator
        super.init()
    }

    func isAttached(to textView: MarkdownInternalTextView) -> Bool {
        self.textView === textView
    }

    func detach() {
        outsideTableTapRecognizer.view?.removeGestureRecognizer(
            outsideTableTapRecognizer
        )
        removeAll()
    }

    static func removeStaleOverlays(from textView: MarkdownInternalTextView) {
        for subview in textView.subviews where subview is MarkdownTableOverlayView {
            subview.removeFromSuperview()
        }
    }

    func refresh() {
        guard !isApplyingCellEdit else {
            return
        }
        guard let textView,
              let storage = textView.textStorage as? MarkdownStyler,
              storage.mode == .live else {
            removeAll()
            return
        }
        installOutsideTableTapRecognizer(in: textView)

        let tables = MarkdownTableParser.tables(in: storage.string)
        var activeKeys = Set<Int>()
        for (index, table) in tables.enumerated() {
            let existingOverlay = tableViews[index]
            let isEditing = existingOverlay?.isEditing ?? false
            guard let geometry = geometry(for: table,
                                          in: textView,
                                          isEditing: isEditing) else { continue }
            activeKeys.insert(index)
            let overlay = existingOverlay ?? makeOverlay(index: index, in: textView)
            overlay.configure(table: table,
                              geometry: geometry,
                              textView: textView,
                              target: self)
            overlay.frame = geometry.frameRect
            textView.bringSubviewToFront(overlay)
        }

        for (key, view) in tableViews where !activeKeys.contains(key) {
            view.removeFromSuperview()
            tableViews[key] = nil
        }
    }

    private func makeOverlay(index: Int, in textView: MarkdownInternalTextView) -> MarkdownTableOverlayView {
        let overlay = MarkdownTableOverlayView()
        overlay.accessibilityIdentifier = "markdown.table.\(index)"
        textView.addSubview(overlay)
        tableViews[index] = overlay
        return overlay
    }

    private func removeAll() {
        tableViews.values.forEach { $0.removeFromSuperview() }
        tableViews.removeAll()
        bandSelectionStateDidChange()
    }

    private func geometry(for table: MarkdownTable,
                          in textView: MarkdownInternalTextView,
                          isEditing: Bool) -> MarkdownTableOverlayGeometry? {
        let layout = textView.layoutManager
        let container = textView.textContainer
        layout.ensureLayout(for: container)

        let visibleRows = [table.header] + table.bodyRows
        let headerGlyphs = layout.glyphRange(
            forCharacterRange: table.header.lineRange,
            actualCharacterRange: nil
        )
        guard headerGlyphs.length > 0 else { return nil }
        var headerLineRect: CGRect?
        layout.enumerateLineFragments(forGlyphRange: headerGlyphs) {
            lineRect, _, _, _, stop in
            headerLineRect = lineRect.offsetBy(
                dx: textView.textContainerInset.left,
                dy: textView.textContainerInset.top
            )
            stop.pointee = true
        }
        guard let headerLineRect else { return nil }
        let font = textView.textStorage.attribute(
            .font,
            at: table.header.lineRange.location,
            effectiveRange: nil
        ) as? UIFont ?? UIFont.preferredFont(forTextStyle: .body)
        let pad = container.lineFragmentPadding
        let outerX = textView.textContainerInset.left + pad
        let outerWidth = max(0, container.size.width - 2 * pad)
        // Editing never changes table width. Handles float immediately beyond
        // the table edges, matching Apple Notes instead of creating a gutter.
        let horizontal = MarkdownTableVisualMetrics.gridHorizontalFrame(
            outerX: outerX,
            outerWidth: outerWidth,
            isEditing: isEditing
        )
        let x = horizontal.minX
        let width = horizontal.width
        guard width > 40 else { return nil }
        let editorWidth = max(
            1,
            width / CGFloat(table.columnCount)
                - 2 * MarkdownTableVisualMetrics.horizontalCellPadding
        )
        let rowHeights = MarkdownTableVisualMetrics.rowHeights(
            for: table,
            font: font,
            editorWidth: editorWidth,
            liveMeasurements: liveCellMeasurements[table.fullRange.location] ?? [:]
        )
        let blockHeight = rowHeights.reduce(0, +)
        let gridTop = headerLineRect.maxY - blockHeight
        var nextRowY = gridTop
        let rowData = zip(visibleRows, rowHeights).map {
            row, height -> (rect: CGRect, height: CGFloat) in
            defer { nextRowY += height }
            return (
                CGRect(
                    x: headerLineRect.minX,
                    y: nextRowY,
                    width: headerLineRect.width,
                    height: height
                ),
                height
            )
        }

        guard rowData.count == visibleRows.count,
              let first = rowData.first?.rect,
              let last = rowData.last?.rect else { return nil }

        let gridScreenRect = CGRect(x: x,
                                    y: first.minY,
                                    width: width,
                                    height: last.maxY - first.minY)
        // The overlay always includes the screen-edge handle lane. Keeping
        // this origin stable prevents the row handle from jumping inside the
        // first cell when editing state changes between layout passes.
        let frameX: CGFloat = 0
        let frameY = max(
            0,
            isEditing
                ? gridScreenRect.minY - MarkdownTableVisualMetrics.topHandleHeight
                : gridScreenRect.minY
        )
        let frameRect = CGRect(x: frameX,
                               y: frameY,
                               width: gridScreenRect.maxX - frameX,
                               height: gridScreenRect.maxY - frameY)
        let gridRect = CGRect(x: gridScreenRect.minX - frameRect.minX,
                              y: gridScreenRect.minY - frameRect.minY,
                              width: gridScreenRect.width,
                              height: gridScreenRect.height)
        let localRows = rowData.map {
            CGRect(x: gridRect.minX,
                   y: $0.rect.minY - frameRect.minY,
                   width: gridRect.width,
                   height: $0.rect.height)
        }
        return MarkdownTableOverlayGeometry(frameRect: frameRect,
                                            gridRect: gridRect,
                                            rowRects: localRows,
                                            rowHeights: rowData.map(\.height),
                                            columnCount: table.columnCount)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        guard let field = textView as? MarkdownTableCellTextView,
              let payload = field.tablePayload else { return }
        field.markdownStorage.cursorRange = field.selectedRange
        (field.inputAccessoryView as? MarkdownReminderToolbar)?
            .setEditingTableCell(true)
        tableViews.values.forEach { $0.deactivateTableSelection() }
        tableViews.values
            .first(where: { $0.represents(payload.table) })?
            .activateCell(payload.address)
        select(payload.table, address: payload.address)
        reveal(field)
        coordinator?.tableCellFormattingDidChange()
        coordinator?.copySelectionDidChange()
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        guard let field = textView as? MarkdownTableCellTextView else { return }
        field.markdownStorage.cursorRange = NSRange(location: NSNotFound, length: 0)
        (field.inputAccessoryView as? MarkdownReminderToolbar)?
            .setEditingTableCell(false)
        coordinator?.tableCellFormattingDidChange()
        coordinator?.copySelectionDidChange()
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
            self?.clearInactiveBandSelections()
        }
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard let field = textView as? MarkdownTableCellTextView,
              !field.isSynchronizingSource,
              let payload = field.tablePayload else { return }
        field.markdownStorage.cursorRange = field.selectedRange
        tableViews.values
            .first(where: { $0.represents(payload.table) })?
            .activateCell(payload.address)
        coordinator?.tableCellFormattingDidChange()
        coordinator?.copySelectionDidChange()
    }

    func clearInactiveBandSelections() {
        tableViews.values.forEach { $0.clearBandSelectionIfInactive() }
    }

    func deactivateTableSelections() {
        tableViews.values.forEach { $0.deactivateTableSelection() }
        bandSelectionStateDidChange()
        refresh()
    }

    func containsTable(at point: CGPoint) -> Bool {
        tableViews.values.contains { $0.containsGridPoint(point, in: textView) }
    }

    private func installOutsideTableTapRecognizer(
        in textView: MarkdownInternalTextView
    ) {
        let interactionView: UIView = textView.enclosingDocumentScrollView
            ?? textView.superview
            ?? textView
        guard outsideTableTapRecognizer.view !== interactionView else { return }
        outsideTableTapRecognizer.view?.removeGestureRecognizer(
            outsideTableTapRecognizer
        )
        outsideTableTapRecognizer.name = "markdown.table.exit"
        outsideTableTapRecognizer.cancelsTouchesInView = false
        outsideTableTapRecognizer.delegate = self
        interactionView.addGestureRecognizer(outsideTableTapRecognizer)
    }

    @objc private func handleOutsideTableTap(
        _ recognizer: UITapGestureRecognizer
    ) {
        guard recognizer.state == .ended,
              let textView else { return }
        let location = recognizer.location(in: textView)
        let caretOffset = textView.closestPosition(to: location).map {
            textView.offset(from: textView.beginningOfDocument, to: $0)
        }
        tableViews.values.forEach { $0.resignCellEditors() }
        deactivateTableSelections()
        guard textView.bounds.contains(location) else { return }
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            textView.isEditable = true
            textView.isSelectable = true
            textView.isUserInteractionEnabled = true
            textView.becomeFirstResponder()
            if let caretOffset {
                textView.selectedRange = NSRange(
                    location: min(max(0, caretOffset), textView.textStorage.length),
                    length: 0
                )
            }
            textView.setNeedsDisplay()
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === outsideTableTapRecognizer,
              tableViews.values.contains(where: \.hasActiveInteraction),
              let textView else { return false }
        return !containsTable(at: touch.location(in: textView))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === outsideTableTapRecognizer
            || otherGestureRecognizer === outsideTableTapRecognizer
    }

    func bandSelectionStateDidChange() {
        coordinator?.tableBandSelectionDidChange(
            tableViews.values.contains(where: \.hasBandSelection)
        )
    }

    func textView(_ textView: UITextView,
                  shouldChangeTextIn range: NSRange,
                  replacementText string: String) -> Bool {
        guard let field = textView as? MarkdownTableCellTextView else { return true }
        if string == "\t" {
            move(from: field, backward: false)
            return false
        }
        return true
    }

    func textView(
        _ textView: UITextView,
        primaryActionFor textItem: UITextItem,
        defaultAction: UIAction
    ) -> UIAction? {
        guard textView is MarkdownTableCellTextView,
              case .link(let url) = textItem.content else {
            return defaultAction
        }
        return coordinator?.primaryActionForMarkdownLink(
            url,
            defaultAction: defaultAction
        )
    }

    func textView(
        _ textView: UITextView,
        menuConfigurationFor textItem: UITextItem,
        defaultMenu: UIMenu
    ) -> UITextItem.MenuConfiguration? {
        guard textView is MarkdownTableCellTextView,
              case .link = textItem.content else {
            return .init(menu: defaultMenu)
        }
        return nil
    }

    func textViewDidChange(_ textView: UITextView) {
        cellTextDidChange(textView)
    }

    func cellTextDidChange(_ textView: UITextView) {
        guard let field = textView as? MarkdownTableCellTextView,
              let payload = field.tablePayload,
              let hostTextView = self.textView,
              let storage = hostTextView.textStorage as? MarkdownStyler,
              let table = MarkdownTableParser.tables(in: storage.string).first(where: {
                  $0.fullRange.location == payload.table.fullRange.location
              }) else { return }
        liveCellMeasurements[table.fullRange.location, default: [:]][payload.address] =
            field.currentMeasurement()
        isApplyingCellEdit = true
        let result = MarkdownTableCellEdit.apply(to: storage.string,
                                                 table: table,
                                                 address: payload.address,
                                                 text: field.text ?? "")
        coordinator?.applyExternalTableEdit(result, keepFirstResponder: field)
        isApplyingCellEdit = false
        coordinator?.tableCellFormattingDidChange()
        refresh()
    }

    func perform(_ command: MarkdownTableCommand,
                 table: MarkdownTable,
                 address: MarkdownTableCellAddress,
                 selectedRange: ClosedRange<Int>? = nil) {
        guard let textView,
              let storage = textView.textStorage as? MarkdownStyler else { return }
        let result = command.apply(to: storage.string,
                                   selection: selection(for: address, in: table),
                                   selectedRange: selectedRange)
        let target = targetCell(for: result.selection, in: result.source)
        coordinator?.applyExternalTableEdit(result, keepFirstResponder: nil)
        if let target {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refresh()
                _ = self.tableViews.values
                    .first(where: { $0.represents(target.table) })?
                    .focusCell(target.address)
            }
        }
    }

    func reorder(_ axis: MarkdownTableReorderAxis,
                 table: MarkdownTable,
                 address: MarkdownTableCellAddress,
                 destinationIndex: Int) {
        let sourceIndex = axis == .row ? address.row : address.column
        reorder(
            axis,
            range: sourceIndex...sourceIndex,
            table: table,
            address: address,
            destinationIndex: destinationIndex
        )
    }

    func reorder(_ axis: MarkdownTableReorderAxis,
                 range: ClosedRange<Int>,
                 table: MarkdownTable,
                 address: MarkdownTableCellAddress,
                 destinationIndex: Int,
                 selectedRangeAfterReorder: ClosedRange<Int>? = nil) {
        guard let textView,
              let storage = textView.textStorage as? MarkdownStyler else { return }
        let result = MarkdownTableReorder.apply(
            axis: axis,
            range: range,
            to: destinationIndex,
            selectedAddress: address,
            table: table,
            source: storage.string
        )
        guard result.source != storage.string else { return }
        let target = targetCell(for: result.selection, in: result.source)
        coordinator?.applyExternalTableEdit(result, keepFirstResponder: nil)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refresh()
            guard let target else { return }
            let overlay = self.tableViews.values
                .first(where: { $0.represents(target.table) })
            if let selectedRangeAfterReorder {
                overlay?.restoreBandSelection(
                    axis: axis,
                    range: selectedRangeAfterReorder,
                    address: target.address
                )
            } else {
                overlay?.deactivateTableSelection()
            }
            self.bandSelectionStateDidChange()
        }
    }

    func copyMarkdown(_ table: MarkdownTable) {
        guard let storage = textView?.textStorage,
              NSMaxRange(table.fullRange) <= storage.length else { return }
        UIPasteboard.general.string = (storage.string as NSString)
            .substring(with: table.fullRange)
            .trimmingCharacters(in: .newlines)
    }

    func copyCSV(_ table: MarkdownTable) {
        guard let storage = textView?.textStorage as? MarkdownStyler,
              let current = MarkdownTableParser.tables(in: storage.string).first(where: {
                  $0.fullRange.location == table.fullRange.location
              }) else { return }
        UIPasteboard.general.string = MarkdownTableExport.csv(current)
    }

    func select(_ table: MarkdownTable, address: MarkdownTableCellAddress) {
        coordinator?.selectTableCell(address, in: table)
    }

    var hasActiveCellEditor: Bool {
        activeCellEditor() != nil
    }

    func activeCellTextView() -> UITextView? {
        activeCellEditor()
    }

    func activeCellLinkSelection() -> DocumentLinkEditorSelection? {
        guard let field = activeCellEditor(),
              let payload = field.tablePayload else { return nil }
        let source = field.markdownStorage.string as NSString
        let range = MarkdownSyntax.clamped(
            field.selectedRange,
            length: source.length
        )
        return DocumentLinkEditorSelection(
            tableLocation: payload.table.fullRange.location,
            address: payload.address,
            range: range,
            selectedText: range.length > 0
                ? source.substring(with: range)
                : ""
        )
    }

    func focusCell(
        tableLocation: Int,
        address: MarkdownTableCellAddress,
        range: NSRange
    ) {
        refresh()
        guard let overlay = tableViews.values.first(where: {
            $0.representsTable(at: tableLocation)
        }),
        let field = overlay.focusCell(address) else { return }
        let selection = MarkdownSyntax.clamped(
            range,
            length: field.markdownStorage.length
        )
        field.selectedRange = selection
        field.markdownStorage.cursorRange = selection
        reveal(field)
    }

    @discardableResult
    func performToolbarActionInActiveCell(_ action: ToolbarAction) -> Bool {
        guard let field = activeCellEditor() else { return false }
        guard action.isSupportedInTableCell else { return true }
        let source = field.markdownStorage.string
        let result = action.apply(to: source, selection: field.selectedRange)
        guard result.source != source || result.selection != field.selectedRange else {
            return true
        }
        let diff = TextDiff.minimal(from: source, to: result.source)
        if let start = field.position(
            from: field.beginningOfDocument,
            offset: diff.range.location
        ),
        let end = field.position(from: start, offset: diff.range.length),
        let textRange = field.textRange(from: start, to: end) {
            field.replace(textRange, withText: diff.replacement)
        } else {
            field.markdownStorage.replaceCharacters(
                in: diff.range,
                with: diff.replacement
            )
        }
        field.selectedRange = result.selection
        field.markdownStorage.cursorRange = result.selection
        cellTextDidChange(field)
        return true
    }

    private func activeCellEditor() -> MarkdownTableCellTextView? {
        tableViews.values.lazy.compactMap { $0.activeCellEditor() }.first
    }

    fileprivate func move(from field: MarkdownTableCellTextView, backward: Bool) {
        guard let payload = field.tablePayload else { return }
        if let address = adjacentAddress(from: payload.address,
                                         table: payload.table,
                                         backward: backward) {
            focus(address: address, in: payload.table)
        } else if !backward {
            perform(.addRowBelow, table: payload.table, address: payload.address)
        }
    }

    private func focus(address: MarkdownTableCellAddress, in table: MarkdownTable) {
        select(table, address: address)
        let field = tableViews.values
            .first(where: { $0.represents(table) })?
            .focusCell(address)
        if let field {
            reveal(field)
        }
    }

    private func reveal(_ field: UIView) {
        DispatchQueue.main.async { [weak self, weak field] in
            guard let self,
                  let textView = self.textView,
                  let field,
                  let scrollView = textView.enclosingDocumentScrollView else { return }
            let rect = field.bounds.insetBy(dx: 0, dy: -120)
            scrollView.scrollRectToVisible(scrollView.convert(rect, from: field), animated: false)
        }
    }

    private func adjacentAddress(from address: MarkdownTableCellAddress,
                                 table: MarkdownTable,
                                 backward: Bool) -> MarkdownTableCellAddress? {
        let rowCount = table.bodyRows.count + 1
        guard rowCount > 0, table.columnCount > 0 else { return nil }
        if backward {
            if address.column > 0 {
                return MarkdownTableCellAddress(row: address.row, column: address.column - 1)
            }
            if address.row > 0 {
                return MarkdownTableCellAddress(row: address.row - 1, column: table.columnCount - 1)
            }
            return nil
        }
        if address.column + 1 < table.columnCount {
            return MarkdownTableCellAddress(row: address.row, column: address.column + 1)
        }
        if address.row + 1 < rowCount {
            return MarkdownTableCellAddress(row: address.row + 1, column: 0)
        }
        return nil
    }

    private func targetCell(for selection: NSRange,
                            in source: String) -> (table: MarkdownTable, address: MarkdownTableCellAddress)? {
        guard let table = MarkdownTableParser.table(containing: selection, in: source),
              let row = MarkdownTableParser.row(containing: selection, in: table),
              let cell = MarkdownTableParser.cell(containing: selection, in: table),
              let address = MarkdownTableParser.address(for: row, cell: cell, in: table) else {
            return nil
        }
        return (table, address)
    }

    private func selection(for address: MarkdownTableCellAddress, in table: MarkdownTable) -> NSRange {
        let row: MarkdownTableRow
        if address.row == 0 {
            row = table.header
        } else if !table.bodyRows.isEmpty {
            row = table.bodyRows[min(max(0, address.row - 1), table.bodyRows.count - 1)]
        } else {
            row = table.header
        }
        let cell = row.cells.first(where: { $0.column == address.column }) ?? row.cells.first
        return cell.map { NSRange(location: $0.contentRange.location, length: $0.contentRange.length) }
            ?? NSRange(location: table.fullRange.location, length: 0)
    }
}

private final class MarkdownTableHandleGestureRecognizer: UIGestureRecognizer {
    var axisResolver: ((CGPoint) -> MarkdownTableReorderAxis?)?
    private(set) var claimedAxis: MarkdownTableReorderAxis?
    private var trackedTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible,
              trackedTouch == nil,
              touches.count == 1,
              let touch = touches.first,
              let view else {
            state = .failed
            return
        }
        let point = touch.location(in: view)
        guard let axis = axisResolver?(point) else {
            state = .failed
            return
        }
        trackedTouch = touch
        claimedAxis = axis
        // Claim the handle touch synchronously. Timer-backed recognizers can
        // lose very fast taps to UITextView's selection gestures before their
        // state changes.
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = .cancelled
    }

    override func reset() {
        trackedTouch = nil
        claimedAxis = nil
        super.reset()
    }
}

private final class MarkdownTableHandleView: UIView {
    private let axis: MarkdownTableReorderAxis
    private let dotsLayer = CAShapeLayer()
    var onActivate: (() -> Void)?
    var foregroundColor: UIColor = .secondaryLabel {
        didSet {
            dotsLayer.fillColor = foregroundColor.cgColor
        }
    }

    init(axis: MarkdownTableReorderAxis) {
        self.axis = axis
        super.init(frame: .zero)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .button
        layer.addSublayer(dotsLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dotsLayer.frame = bounds
        let dotDiameter = MarkdownTableVisualMetrics.handleDotDiameter
        let spacing: CGFloat = 6
        let path = UIBezierPath()
        for offset in [-spacing, 0, spacing] {
            let center = axis == .row
                ? CGPoint(x: bounds.midX, y: bounds.midY + offset)
                : CGPoint(x: bounds.midX + offset, y: bounds.midY)
            path.append(UIBezierPath(
                ovalIn: CGRect(
                    x: center.x - dotDiameter / 2,
                    y: center.y - dotDiameter / 2,
                    width: dotDiameter,
                    height: dotDiameter
                )
            ))
        }
        dotsLayer.path = path.cgPath
        dotsLayer.fillColor = foregroundColor.cgColor
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return onActivate != nil
    }
}

private final class MarkdownTableSelectionGripButton: UIButton {
    private let dotLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.addSublayer(dotLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dotLayer.frame = bounds
        let dotRect = CGRect(
            x: bounds.midX - MarkdownTableVisualMetrics.selectionGripDiameter / 2,
            y: bounds.midY - MarkdownTableVisualMetrics.selectionGripDiameter / 2,
            width: MarkdownTableVisualMetrics.selectionGripDiameter,
            height: MarkdownTableVisualMetrics.selectionGripDiameter
        )
        dotLayer.path = UIBezierPath(ovalIn: dotRect).cgPath
        dotLayer.fillColor = tintColor.cgColor
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        dotLayer.fillColor = tintColor.cgColor
    }
}

@MainActor
private final class MarkdownTableOverlayView: UIView,
                                              @preconcurrency UIEditMenuInteractionDelegate,
                                              UIGestureRecognizerDelegate {
    private struct BandSelection: Equatable {
        let axis: MarkdownTableReorderAxis
        var range: ClosedRange<Int>
    }

    private struct ReorderPreview {
        let axis: MarkdownTableReorderAxis
        let source: ClosedRange<Int>
        let selectionBeforeDrag: BandSelection?
        let preservesSelection: Bool
        var destination: Int
    }

    private var table: MarkdownTable?
    private var geometry: MarkdownTableOverlayGeometry?
    private weak var target: MarkdownTableOverlayController?
    private var cellFields: [MarkdownTableCellAddress: MarkdownTableCellTextView] = [:]
    private let surfaceLayer = CAShapeLayer()
    private let headerLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()
    private let bandSelectionLayer = CAShapeLayer()
    private let rowSelectionCapLayer = CAShapeLayer()
    private let columnSelectionCapLayer = CAShapeLayer()
    private let gridLayer = CAShapeLayer()
    private let rowHandle = MarkdownTableHandleView(axis: .row)
    private let columnHandle = MarkdownTableHandleView(axis: .column)
    private lazy var handleInteractionRecognizer = MarkdownTableHandleGestureRecognizer(
        target: self,
        action: #selector(handleInteraction(_:))
    )
    private let selectionStartGrip = MarkdownTableSelectionGripButton(frame: .zero)
    private let selectionEndGrip = MarkdownTableSelectionGripButton(frame: .zero)
    private lazy var editMenuInteraction = UIEditMenuInteraction(delegate: self)
    private var pendingEditMenu: UIMenu?
    private var pendingEditMenuTargetRect: CGRect = .zero
    private var isEditMenuPresented = false
    private var isEditMenuDismissing = false
    private var documentGesturesEnabledBeforeMenu: [UIGestureRecognizer] = []
    private var bandSelection: BandSelection?
    private var reorderPreview: ReorderPreview?
    private weak var dragContainer: UIView?
    private weak var dragSnapshot: UIView?
    private weak var dragHandleSnapshot: UIView?
    private var dragNeighborSnapshots: [Int: UIView] = [:]
    private var dragStartFrame: CGRect = .zero
    private var selectionGripAnchor: Int?
    private var selectionBeforeGrip: BandSelection?
    private var activeAddress: MarkdownTableCellAddress?
    private var handleInteractionStart: CGPoint?
    private var handleInteractionAxis: MarkdownTableReorderAxis?
    private var handleInteractionBecameDrag = false
    private var handleInteractionRejected = false
    private weak var hostTextView: MarkdownInternalTextView?
    private var competingDocumentGestures: [UIGestureRecognizer] = []
    private var suspendedDocumentGestures: [UIGestureRecognizer] = []
    private var hostTextViewWasSelectable: Bool?

    var isEditing: Bool {
        selectedAddress() != nil
    }

    var hasActiveInteraction: Bool {
        selectedAddress() != nil || bandSelection != nil
    }

    var hasBandSelection: Bool {
        bandSelection != nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false
        layer.addSublayer(surfaceLayer)
        layer.addSublayer(headerLayer)
        layer.addSublayer(selectionLayer)
        layer.addSublayer(gridLayer)
        layer.addSublayer(rowSelectionCapLayer)
        layer.addSublayer(columnSelectionCapLayer)
        layer.addSublayer(bandSelectionLayer)
        configureHandle(rowHandle, id: "markdown.table.row.menu")
        configureHandle(columnHandle, id: "markdown.table.column.menu")
        rowHandle.onActivate = { [weak self] in
            self?.handleHandleTap(axis: .row)
        }
        columnHandle.onActivate = { [weak self] in
            self?.handleHandleTap(axis: .column)
        }
        handleInteractionRecognizer.name = "markdown.table.interaction.handle"
        handleInteractionRecognizer.cancelsTouchesInView = true
        handleInteractionRecognizer.delaysTouchesBegan = false
        configureSelectionGrip(selectionStartGrip,
                               id: "markdown.table.selection.start",
                               action: #selector(handleSelectionStartDrag(_:)))
        configureSelectionGrip(selectionEndGrip,
                               id: "markdown.table.selection.end",
                               action: #selector(handleSelectionEndDrag(_:)))
        addSubview(rowHandle)
        addSubview(columnHandle)
        addSubview(selectionStartGrip)
        addSubview(selectionEndGrip)
        addInteraction(editMenuInteraction)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func removeFromSuperview() {
        handleInteractionRecognizer.view?.removeGestureRecognizer(
            handleInteractionRecognizer
        )
        super.removeFromSuperview()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) {
            return true
        }
        let controls = [rowHandle, columnHandle, selectionStartGrip, selectionEndGrip]
        return controls.contains { control in
            !control.isHidden && control.alpha > 0.01 && control.frame.contains(point)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // UITextView installs ancestor selection gestures that otherwise win
        // stationary touches in the handle lanes. Route those lanes directly
        // to their controls before considering cell editors or the document.
        for control in [selectionEndGrip, selectionStartGrip, columnHandle, rowHandle]
            where !control.isHidden && control.alpha > 0.01 {
            let controlPoint = control.convert(point, from: self)
            if control.point(inside: controlPoint, with: event) {
                return control
            }
        }
        return super.hitTest(point, with: event)
    }

    func configure(table: MarkdownTable,
                   geometry: MarkdownTableOverlayGeometry,
                   textView: MarkdownInternalTextView,
                   target: MarkdownTableOverlayController) {
        self.table = table
        self.geometry = geometry
        self.target = target
        hostTextView = textView
        installHandleInteraction(in: textView)
        prioritizeTableDrags(over: textView.panGestureRecognizer)
        if let documentScrollPan = textView.enclosingDocumentScrollView?.panGestureRecognizer {
            prioritizeTableDrags(over: documentScrollPan)
        }
        rebuildCells(table: table, geometry: geometry, textView: textView, target: target)
        if let editingAddress = editingAddress() {
            activeAddress = editingAddress
        }
        normalizeBandSelection(for: table)
        updateHandles(table: table, geometry: geometry)
        setNeedsLayout()
    }

    private func prioritizeTableDrags(over scrollPan: UIPanGestureRecognizer) {
        scrollPan.require(toFail: handleInteractionRecognizer)
        for control in [selectionStartGrip, selectionEndGrip] {
            for gesture in control.gestureRecognizers ?? [] {
                scrollPan.require(toFail: gesture)
            }
        }
    }

    private func installHandleInteraction(in textView: MarkdownInternalTextView) {
        let interactionView: UIView = textView.enclosingDocumentScrollView
            ?? textView.superview
            ?? textView
        if handleInteractionRecognizer.view !== interactionView {
            handleInteractionRecognizer.view?.removeGestureRecognizer(
                handleInteractionRecognizer
            )
            interactionView.addGestureRecognizer(handleInteractionRecognizer)
        }
        var gestureOwner: UIView? = textView
        var competing: [UIGestureRecognizer] = []
        while let owner = gestureOwner {
            for documentGesture in owner.gestureRecognizers ?? []
            where documentGesture !== handleInteractionRecognizer
                && documentGesture.name != "markdown.table.interaction.handle" {
                documentGesture.require(toFail: handleInteractionRecognizer)
                competing.append(documentGesture)
            }
            if owner === interactionView {
                break
            }
            gestureOwner = owner.superview
        }
        competingDocumentGestures = competing
        handleInteractionRecognizer.axisResolver = { [weak self, weak interactionView] point in
            guard let self, let interactionView else { return nil }
            let overlayPoint = self.convert(point, from: interactionView)
            return self.handleAxis(at: overlayPoint)
        }
    }

    func clearBandSelectionIfInactive() {
        guard editingAddress() == nil, bandSelection == nil else { return }
        activeAddress = nil
        guard let table, let geometry else { return }
        updateHandles(table: table, geometry: geometry)
        drawGrid(geometry: geometry)
    }

    func activateCell(_ address: MarkdownTableCellAddress) {
        activeAddress = address
        clearBandSelection(deactivate: false)
    }

    func restoreBandSelection(axis: MarkdownTableReorderAxis,
                              range: ClosedRange<Int>,
                              address: MarkdownTableCellAddress) {
        activeAddress = address
        bandSelection = BandSelection(axis: axis, range: range)
        cellFields.values.forEach { $0.resignFirstResponder() }
        if let table {
            normalizeBandSelection(for: table)
        }
        guard let table, let geometry else {
            target?.bandSelectionStateDidChange()
            return
        }
        updateHandles(table: table, geometry: geometry)
        drawGrid(geometry: geometry)
        target?.bandSelectionStateDidChange()
    }

    func deactivateTableSelection() {
        activeAddress = nil
        clearBandSelection(deactivate: true)
    }

    func resignCellEditors() {
        cellFields.values.forEach { $0.resignFirstResponder() }
    }

    func containsGridPoint(_ point: CGPoint, in textView: UIView?) -> Bool {
        guard let textView, let geometry else { return false }
        return geometry.gridRect.contains(convert(point, from: textView))
    }

    private func clearBandSelection(deactivate: Bool) {
        if deactivate {
            activeAddress = nil
        }
        bandSelection = nil
        selectionGripAnchor = nil
        selectionBeforeGrip = nil
        pendingEditMenu = nil
        if isEditMenuPresented && !isEditMenuDismissing {
            editMenuInteraction.dismissMenu()
        }
        target?.bandSelectionStateDidChange()
        guard let table, let geometry else { return }
        updateHandles(table: table, geometry: geometry)
        drawGrid(geometry: geometry)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let table, let geometry else { return }
        drawGrid(geometry: geometry)
        layoutCells(geometry: geometry)
        updateHandles(table: table, geometry: geometry)
    }

    private func normalizeBandSelection(for table: MarkdownTable) {
        guard var selection = bandSelection else { return }
        let maximum = selection.axis == .row
            ? table.bodyRows.count
            : max(0, table.columnCount - 1)
        let minimum = selection.axis == .row ? 0 : 0
        let lower = min(max(minimum, selection.range.lowerBound), maximum)
        let upper = min(max(lower, selection.range.upperBound), maximum)
        selection.range = lower...upper
        bandSelection = selection
    }

    private func rebuildCells(table: MarkdownTable,
                              geometry: MarkdownTableOverlayGeometry,
                              textView: MarkdownInternalTextView,
                              target: MarkdownTableOverlayController) {
        let rows = [table.header] + table.bodyRows
        var live = Set<MarkdownTableCellAddress>()
        for (rowIndex, row) in rows.enumerated() {
            for column in 0..<geometry.columnCount {
                let address = MarkdownTableCellAddress(row: rowIndex, column: column)
                live.insert(address)
                let textRole: MarkdownTextRole = rowIndex == 0 ? .tableHeader : .body
                let field = cellFields[address]
                    ?? makeField(textRole: textRole, textView: textView, target: target)
                field.tablePayload = MarkdownTableFieldPayload(table: table, address: address)
                if !field.isFirstResponder {
                    let source = row.cells.first(where: { $0.column == column })?.text ?? ""
                    field.isSynchronizingSource = true
                    if field.text != source {
                        field.text = source
                    }
                    field.markdownStorage.cursorRange = NSRange(
                        location: NSNotFound,
                        length: 0
                    )
                    field.isSynchronizingSource = false
                }
                field.textAlignment = alignment(for: table.alignments[safe: column] ?? .none)
                field.accessibilityIdentifier = "markdown.table.cell.\(rowIndex).\(column)"
                cellFields[address] = field
            }
        }

        for (address, field) in cellFields where !live.contains(address) {
            field.removeFromSuperview()
            cellFields[address] = nil
        }
    }

    private func makeField(textRole: MarkdownTextRole,
                           textView: MarkdownInternalTextView,
                           target: MarkdownTableOverlayController) -> MarkdownTableCellTextView {
        let field = MarkdownTableCellTextView(textRole: textRole)
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        field.font = textRole == .tableHeader
            ? UIFont.systemFont(ofSize: bodyFont.pointSize, weight: .semibold)
            : bodyFont
        field.backgroundColor = .clear
        field.textContentType = nil
        field.autocorrectionType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .default
        field.adjustsFontForContentSizeCategory = true
        field.isScrollEnabled = false
        field.alwaysBounceVertical = false
        field.textContainerInset = .zero
        field.textContainer.lineFragmentPadding = 0
        field.showsVerticalScrollIndicator = false
        field.showsHorizontalScrollIndicator = false
        field.inputAccessoryView = textView.inputAccessoryView
        field.delegate = target
        field.tableController = target
        addSubview(field)
        return field
    }

    private func layoutCells(geometry: MarkdownTableOverlayGeometry) {
        let cellWidth = geometry.gridRect.width / CGFloat(max(1, geometry.columnCount))
        let inset = UIEdgeInsets(top: MarkdownTableVisualMetrics.verticalCellPadding,
                                 left: MarkdownTableVisualMetrics.horizontalCellPadding,
                                 bottom: MarkdownTableVisualMetrics.verticalCellPadding,
                                 right: MarkdownTableVisualMetrics.horizontalCellPadding)
        for (address, field) in cellFields {
            guard let row = geometry.rowRects[safe: address.row] else { continue }
            field.frame = CGRect(x: geometry.gridRect.minX + CGFloat(address.column) * cellWidth,
                                 y: row.minY,
                                 width: cellWidth,
                                 height: row.height)
                .inset(by: inset)
        }
    }

    private func updateHandles(table: MarkdownTable, geometry: MarkdownTableOverlayGeometry) {
        guard let address = selectedAddress() else {
            rowHandle.isHidden = true
            columnHandle.isHidden = true
            selectionStartGrip.isHidden = true
            selectionEndGrip.isHidden = true
            return
        }
        rowHandle.isHidden = false
        columnHandle.isHidden = false
        let rowRect = geometry.rowRects[safe: address.row] ?? geometry.rowRects.first ?? bounds
        let cellWidth = geometry.gridRect.width / CGFloat(max(1, geometry.columnCount))
        let hitSize = MarkdownTableVisualMetrics.handleHitSize
        var rowVisualCenter = CGPoint(
            x: MarkdownTableVisualMetrics.rowHandleGlyphCenterX(
                gridMinX: geometry.gridRect.minX
            ),
            y: rowRect.midY
        )
        var columnVisualCenter = CGPoint(
            x: geometry.gridRect.minX
                + CGFloat(address.column) * cellWidth
                + cellWidth / 2,
            y: MarkdownTableVisualMetrics.columnHandleGlyphCenterY(
                gridMinY: geometry.gridRect.minY
            )
        )
        if let selection = bandSelection,
           let selectedRect = selectionRect(for: selection, geometry: geometry) {
            switch selection.axis {
            case .row:
                rowVisualCenter.y = selectedRect.midY
            case .column:
                columnVisualCenter.x = selectedRect.midX
            }
        }
        rowHandle.frame = CGRect(
            x: rowVisualCenter.x - hitSize / 2,
            y: rowVisualCenter.y - hitSize / 2,
            width: hitSize,
            height: hitSize
        )
        columnHandle.frame = CGRect(
            x: columnVisualCenter.x - hitSize / 2,
            y: columnVisualCenter.y - hitSize / 2,
            width: hitSize,
            height: hitSize
        )
        styleHandle(rowHandle, selected: bandSelection?.axis == .row)
        styleHandle(columnHandle, selected: bandSelection?.axis == .column)
        rowHandle.accessibilityLabel = address.row == 0
            ? "Header row actions"
            : "Row \(address.row) actions and reorder"
        columnHandle.accessibilityLabel = "Column \(address.column + 1) actions and reorder"
        rowHandle.accessibilityHint = address.row == 0
            ? "Tap to select the header row"
            : "Tap to select, drag to reorder, or tap again for table actions"
        columnHandle.accessibilityHint = "Tap to select, drag to reorder, or tap again for table actions"
        bringSubviewToFront(rowHandle)
        bringSubviewToFront(columnHandle)
        bringSubviewToFront(selectionStartGrip)
        bringSubviewToFront(selectionEndGrip)
    }

    private func styleHandle(_ handle: MarkdownTableHandleView, selected: Bool) {
        handle.foregroundColor = selected ? .white : .secondaryLabel
        handle.setNeedsLayout()
    }

    private func selectionRect(for selection: BandSelection,
                               geometry: MarkdownTableOverlayGeometry) -> CGRect? {
        switch selection.axis {
        case .row:
            guard let first = geometry.rowRects[safe: selection.range.lowerBound],
                  let last = geometry.rowRects[safe: selection.range.upperBound] else { return nil }
            return CGRect(x: geometry.gridRect.minX,
                          y: first.minY,
                          width: geometry.gridRect.width,
                          height: last.maxY - first.minY)
        case .column:
            let width = geometry.gridRect.width / CGFloat(max(1, geometry.columnCount))
            return CGRect(
                x: geometry.gridRect.minX + CGFloat(selection.range.lowerBound) * width,
                y: geometry.gridRect.minY,
                width: CGFloat(selection.range.count) * width,
                height: geometry.gridRect.height
            )
        }
    }

    private func editingAddress() -> MarkdownTableCellAddress? {
        cellFields.first(where: { $0.value.isFirstResponder })?.key
    }

    private func selectedAddress() -> MarkdownTableCellAddress? {
        editingAddress() ?? activeAddress
    }

    func represents(_ table: MarkdownTable) -> Bool {
        self.table?.fullRange.location == table.fullRange.location
    }

    func representsTable(at location: Int) -> Bool {
        table?.fullRange.location == location
    }

    func focusCell(_ address: MarkdownTableCellAddress) -> MarkdownTableCellTextView? {
        activeAddress = address
        let field = cellFields[address]
        field?.becomeFirstResponder()
        return field
    }

    func activeCellEditor() -> MarkdownTableCellTextView? {
        cellFields.values.first(where: \.isFirstResponder)
    }

    private func drawGrid(geometry: MarkdownTableOverlayGeometry) {
        let roundedPath = UIBezierPath(
            roundedRect: geometry.gridRect,
            cornerRadius: MarkdownTableVisualMetrics.cornerRadius
        )
        surfaceLayer.frame = bounds
        surfaceLayer.path = roundedPath.cgPath
        surfaceLayer.fillColor = UIColor.clear.cgColor
        surfaceLayer.strokeColor = UIColor.separator.withAlphaComponent(0.75).cgColor
        surfaceLayer.lineWidth = 0.5

        headerLayer.frame = bounds
        headerLayer.path = UIBezierPath(rect: geometry.rowRects.first ?? .zero).cgPath
        headerLayer.fillColor = UIColor.clear.cgColor
        headerLayer.mask = shapeMask(path: roundedPath.cgPath)

        selectionLayer.frame = bounds
        if let preview = reorderPreview {
            let previewRect: CGRect?
            switch preview.axis {
            case .row:
                previewRect = geometry.rowRects[safe: preview.destination]
            case .column:
                let cellWidth = geometry.gridRect.width / CGFloat(max(1, geometry.columnCount))
                previewRect = CGRect(
                    x: geometry.gridRect.minX + CGFloat(preview.destination) * cellWidth,
                    y: geometry.gridRect.minY,
                    width: cellWidth,
                    height: geometry.gridRect.height
                )
            }
            selectionLayer.path = previewRect.map { UIBezierPath(rect: $0).cgPath }
            selectionLayer.fillColor = UIColor.tintColor.withAlphaComponent(0.18).cgColor
        } else if bandSelection == nil,
                  let address = editingAddress(),
                  let row = geometry.rowRects[safe: address.row] {
            let cellWidth = geometry.gridRect.width / CGFloat(max(1, geometry.columnCount))
            let cell = CGRect(x: geometry.gridRect.minX + CGFloat(address.column) * cellWidth,
                              y: row.minY,
                              width: cellWidth,
                              height: row.height)
            selectionLayer.path = UIBezierPath(rect: cell).cgPath
            selectionLayer.fillColor = UIColor.tintColor.withAlphaComponent(0.10).cgColor
        } else {
            selectionLayer.path = nil
        }
        selectionLayer.mask = shapeMask(path: roundedPath.cgPath)

        gridLayer.frame = bounds
        gridLayer.fillColor = UIColor.clear.cgColor
        gridLayer.strokeColor = UIColor.separator.withAlphaComponent(0.75).cgColor
        gridLayer.lineWidth = 0.5

        let path = UIBezierPath()
        for rect in geometry.rowRects {
            path.move(to: CGPoint(x: geometry.gridRect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: geometry.gridRect.maxX, y: rect.minY))
        }
        path.move(to: CGPoint(x: geometry.gridRect.minX, y: geometry.gridRect.maxY))
        path.addLine(to: CGPoint(x: geometry.gridRect.maxX, y: geometry.gridRect.maxY))

        let cellWidth = geometry.gridRect.width / CGFloat(max(1, geometry.columnCount))
        for column in 0...geometry.columnCount {
            let x = geometry.gridRect.minX + CGFloat(column) * cellWidth
            path.move(to: CGPoint(x: x, y: geometry.gridRect.minY))
            path.addLine(to: CGPoint(x: x, y: geometry.gridRect.maxY))
        }
        gridLayer.path = path.cgPath
        gridLayer.mask = shapeMask(path: roundedPath.cgPath)
        updateBandSelectionAppearance(geometry: geometry)
    }

    private func updateBandSelectionAppearance(geometry: MarkdownTableOverlayGeometry) {
        bandSelectionLayer.frame = bounds
        rowSelectionCapLayer.frame = bounds
        columnSelectionCapLayer.frame = bounds
        guard reorderPreview == nil,
              let selection = bandSelection,
              let rect = selectionRect(for: selection, geometry: geometry) else {
            bandSelectionLayer.path = nil
            rowSelectionCapLayer.path = nil
            columnSelectionCapLayer.path = nil
            selectionStartGrip.isHidden = true
            selectionEndGrip.isHidden = true
            return
        }

        let accent = UIColor(ListsTokens.accent)
        let strokeWidth = MarkdownTableVisualMetrics.selectionStrokeWidth
        let outlineRect = rect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
        bandSelectionLayer.path = UIBezierPath(rect: outlineRect).cgPath
        bandSelectionLayer.fillColor = UIColor.clear.cgColor
        bandSelectionLayer.strokeColor = accent.cgColor
        bandSelectionLayer.lineWidth = strokeWidth

        let capExtent = MarkdownTableVisualMetrics.selectionCapExtent
        switch selection.axis {
        case .row:
            let capRect = CGRect(
                x: geometry.gridRect.minX
                    - MarkdownTableVisualMetrics.rowSelectionCapExtent,
                y: rect.minY,
                width: MarkdownTableVisualMetrics.rowSelectionCapExtent,
                height: rect.height
            )
            rowSelectionCapLayer.path = UIBezierPath(
                roundedRect: capRect,
                byRoundingCorners: [.topLeft, .bottomLeft],
                cornerRadii: CGSize(width: 6, height: 6)
            ).cgPath
            rowSelectionCapLayer.fillColor = accent.cgColor
            columnSelectionCapLayer.path = nil
        case .column:
            let capRect = CGRect(
                x: rect.minX,
                y: geometry.gridRect.minY - capExtent,
                width: rect.width,
                height: capExtent + strokeWidth
            )
            columnSelectionCapLayer.path = UIBezierPath(
                roundedRect: capRect,
                byRoundingCorners: [.topLeft, .topRight],
                cornerRadii: CGSize(width: 6, height: 6)
            ).cgPath
            columnSelectionCapLayer.fillColor = accent.cgColor
            rowSelectionCapLayer.path = nil
        }

        selectionStartGrip.isHidden = false
        selectionEndGrip.isHidden = false
        let start: CGPoint
        let end: CGPoint
        switch selection.axis {
        case .row:
            start = CGPoint(x: outlineRect.midX, y: outlineRect.minY)
            end = CGPoint(x: outlineRect.midX, y: outlineRect.maxY)
        case .column:
            start = CGPoint(x: outlineRect.minX, y: outlineRect.midY)
            end = CGPoint(x: outlineRect.maxX, y: outlineRect.midY)
        }
        selectionStartGrip.frame = gripFrame(centeredAt: start)
        selectionEndGrip.frame = gripFrame(centeredAt: end)
        selectionStartGrip.accessibilityLabel = selection.axis == .row
            ? "Adjust first selected row"
            : "Adjust first selected column"
        selectionEndGrip.accessibilityLabel = selection.axis == .row
            ? "Adjust last selected row"
            : "Adjust last selected column"
    }

    private func gripFrame(centeredAt point: CGPoint) -> CGRect {
        CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
    }

    private func shapeMask(path: CGPath) -> CAShapeLayer {
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = path
        return mask
    }

    private func rowMenu(table: MarkdownTable,
                         address: MarkdownTableCellAddress,
                         range: ClosedRange<Int>) -> UIMenu {
        UIMenu(children: [
            action("Add Row Above", "arrow.up.to.line", .addRowAbove, table, address, range: range),
            action("Add Row Below", "arrow.down.to.line", .addRowBelow, table, address, range: range),
            UIMenu(options: .displayInline, children: [
                action("Move Row Up", "arrow.up", .moveRowUp, table, address,
                       range: range,
                       range.lowerBound == 0 ? .disabled : []),
                action("Move Row Down", "arrow.down", .moveRowDown, table, address,
                       range: range,
                       range.upperBound >= table.bodyRows.count ? .disabled : [])
            ]),
            action("Delete Row", "minus", .deleteRow, table, address,
                   range: range,
                   range.count >= table.bodyRows.count + 1 ? [.disabled, .destructive] : .destructive)
        ])
    }

    private func columnMenu(table: MarkdownTable,
                            address: MarkdownTableCellAddress,
                            range: ClosedRange<Int>) -> UIMenu {
        UIMenu(children: [
            UIMenu(options: .displayInline, children: [
                action("Add Column Before", "arrow.left.to.line", .addColumnBefore, table, address, range: range),
                action("Add Column After", "arrow.right.to.line", .addColumnAfter, table, address, range: range),
                action("Delete Column", "minus", .deleteColumn, table, address, range: range, .destructive)
            ]),
            UIMenu(options: .displayInline, children: [
                action("Move Column Left", "arrow.left", .moveColumnLeft, table, address,
                       range: range,
                       range.lowerBound == 0 ? .disabled : []),
                action("Move Column Right", "arrow.right", .moveColumnRight, table, address,
                       range: range,
                       range.upperBound + 1 >= table.columnCount ? .disabled : [])
            ]),
            UIMenu(title: "Copy Table", image: UIImage(systemName: "doc.on.doc"), children: [
                copyAction("Copy as Markdown", "text.badge.checkmark", table) { target, table in
                    target.copyMarkdown(table)
                },
                copyAction("Copy as CSV", "tablecells", table) { target, table in
                    target.copyCSV(table)
                }
            ]),
            UIMenu(title: "Alignment", image: UIImage(systemName: "text.alignleft"), children: [
                action("Default", "text.alignleft", .setAlignment(.none), table, address, range: range),
                action("Left", "text.alignleft", .setAlignment(.left), table, address, range: range),
                action("Center", "text.aligncenter", .setAlignment(.center), table, address, range: range),
                action("Right", "text.alignright", .setAlignment(.right), table, address, range: range)
            ]),
            UIMenu(options: .displayInline, children: [
                action("Delete Table", "trash", .deleteTable, table, address, range: nil, .destructive)
            ])
        ])
    }

    private func action(_ title: String,
                        _ symbol: String,
                        _ command: MarkdownTableCommand,
                        _ table: MarkdownTable,
                        _ address: MarkdownTableCellAddress,
                        range: ClosedRange<Int>? = nil,
                        _ attributes: UIMenuElement.Attributes = []) -> UIAction {
        UIAction(title: title,
                 image: UIImage(systemName: symbol),
                 attributes: attributes) { [weak self, weak target] _ in
            self?.bandSelection = nil
            target?.bandSelectionStateDidChange()
            target?.perform(command, table: table, address: address, selectedRange: range)
        }
    }

    private func copyAction(_ title: String,
                            _ symbol: String,
                            _ table: MarkdownTable,
                            handler: @escaping (MarkdownTableOverlayController, MarkdownTable) -> Void) -> UIAction {
        UIAction(title: title, image: UIImage(systemName: symbol)) { [weak target] _ in
            guard let target else { return }
            handler(target, table)
        }
    }

    private func configureHandle(_ handle: MarkdownTableHandleView, id: String) {
        handle.foregroundColor = .secondaryLabel
        handle.accessibilityHint = "Tap to select, drag to reorder, or tap again for table actions"
        handle.accessibilityIdentifier = id
    }

    private func configureSelectionGrip(_ button: MarkdownTableSelectionGripButton,
                                        id: String,
                                        action: Selector) {
        button.tintColor = UIColor(ListsTokens.accent)
        button.accessibilityIdentifier = id
        button.isHidden = true
        let pan = UIPanGestureRecognizer(target: self, action: action)
        pan.name = id
        pan.cancelsTouchesInView = true
        pan.delaysTouchesBegan = false
        pan.delegate = self
        button.addGestureRecognizer(pan)
    }

    private func handleHandleTap(axis: MarkdownTableReorderAxis) {
        guard let table,
              let geometry,
              let address = selectedAddress() else { return }
        let index = axis == .row ? address.row : address.column
        if let selection = bandSelection,
           selection.axis == axis,
           selection.range.contains(index) {
            let menuAddress: MarkdownTableCellAddress
            switch axis {
            case .row:
                menuAddress = MarkdownTableCellAddress(
                    row: selection.range.lowerBound,
                    column: address.column
                )
            case .column:
                menuAddress = MarkdownTableCellAddress(
                    row: address.row,
                    column: selection.range.lowerBound
                )
            }
            presentEditMenu(
                axis == .row
                    ? rowMenu(table: table, address: menuAddress, range: selection.range)
                    : columnMenu(table: table, address: menuAddress, range: selection.range),
                from: axis == .row ? rowHandle.frame : columnHandle.frame
            )
            return
        }

        editMenuInteraction.dismissMenu()
        bandSelection = BandSelection(axis: axis, range: index...index)
        activeAddress = address
        target?.bandSelectionStateDidChange()
        // A band is a structural selection, not a text selection. Give UIKit
        // one unambiguous selection owner by ending cell editing instead of
        // leaving a first responder whose caret is artificially hidden.
        cellFields.values.forEach { $0.resignFirstResponder() }
        UIView.animate(withDuration: 0.18,
                       delay: 0,
                       options: [.beginFromCurrentState, .curveEaseOut]) {
            self.updateHandles(table: table, geometry: geometry)
            self.drawGrid(geometry: geometry)
            self.layoutIfNeeded()
        }
    }

    private func presentEditMenu(_ menu: UIMenu, from targetRect: CGRect) {
        pendingEditMenu = menu
        pendingEditMenuTargetRect = targetRect
        isEditMenuPresented = true
        isEditMenuDismissing = false
        documentGesturesEnabledBeforeMenu = competingDocumentGestures.filter(\.isEnabled)
        let configuration = UIEditMenuConfiguration(
            identifier: nil,
            sourcePoint: CGPoint(x: targetRect.midX, y: targetRect.midY)
        )
        editMenuInteraction.presentEditMenu(with: configuration)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        pendingEditMenu
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        willDismissMenuFor configuration: UIEditMenuConfiguration,
        animator: any UIEditMenuInteractionAnimating
    ) {
        isEditMenuDismissing = true
        animator.addCompletion { [weak self] in
            self?.finishEditMenuDismissal()
        }
    }

    private func finishEditMenuDismissal() {
        pendingEditMenu = nil
        pendingEditMenuTargetRect = .zero
        isEditMenuPresented = false
        isEditMenuDismissing = false

        // UIEditMenuInteraction installs private text-selection gestures while
        // presented. When dismissal is triggered by entering a table cell,
        // those recognizers can remain disabled or terminal on the host text
        // view. Reset only the gestures that were enabled before presentation
        // so the next document tap can place a normal caret again.
        let gestures = documentGesturesEnabledBeforeMenu
        documentGesturesEnabledBeforeMenu = []
        for gesture in gestures where gesture.view != nil {
            gesture.isEnabled = false
            gesture.isEnabled = true
        }
        hostTextView?.isSelectable = true
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        pendingEditMenuTargetRect
    }

    @objc private func handleSelectionStartDrag(_ gesture: UIPanGestureRecognizer) {
        updateSelectionGrip(gesture, isStart: true)
    }

    @objc private func handleSelectionEndDrag(_ gesture: UIPanGestureRecognizer) {
        updateSelectionGrip(gesture, isStart: false)
    }

    private func updateSelectionGrip(_ gesture: UIPanGestureRecognizer, isStart: Bool) {
        guard let geometry,
              var selection = bandSelection else { return }
        switch gesture.state {
        case .began:
            selectionBeforeGrip = selection
            selectionGripAnchor = isStart ? selection.range.upperBound : selection.range.lowerBound
            return
        case .cancelled, .failed:
            if let selectionBeforeGrip {
                bandSelection = selectionBeforeGrip
            }
            selectionGripAnchor = nil
            selectionBeforeGrip = nil
            setNeedsLayout()
            return
        default:
            break
        }
        let location = gesture.location(in: self)
        let candidate: Int
        switch selection.axis {
        case .row:
            candidate = MarkdownTableSelectionGripCandidate.row(
                at: location.y,
                isStart: isStart,
                rowRects: geometry.rowRects
            )
        case .column:
            let width = geometry.gridRect.width / CGFloat(max(1, geometry.columnCount))
            candidate = MarkdownTableSelectionGripCandidate.column(
                at: location.x,
                isStart: isStart,
                gridMinX: geometry.gridRect.minX,
                columnWidth: width,
                columnCount: geometry.columnCount
            )
        }
        let anchor = selectionGripAnchor
            ?? (isStart ? selection.range.upperBound : selection.range.lowerBound)
        selection.range = MarkdownTableBandSelectionRange.resolved(
            anchor: anchor,
            candidate: candidate
        )
        if selection.range != bandSelection?.range {
            bandSelection = selection
            setNeedsLayout()
        }
        if gesture.state == .ended {
            selectionGripAnchor = nil
            selectionBeforeGrip = nil
        }
    }

    @objc private func handleInteraction(
        _ gesture: MarkdownTableHandleGestureRecognizer
    ) {
        guard let axis = gesture.claimedAxis else { return }
        updateHandleInteraction(gesture, axis: axis)
    }

    private func updateHandleInteraction(_ gesture: MarkdownTableHandleGestureRecognizer,
                                         axis: MarkdownTableReorderAxis) {
        let location = gesture.location(in: self)
        switch gesture.state {
        case .began:
            suspendDocumentSelectionForHandleTouch()
            handleInteractionStart = location
            handleInteractionAxis = axis
            handleInteractionBecameDrag = false
            handleInteractionRejected = false
        case .changed:
            guard handleInteractionAxis == axis,
                  let start = handleInteractionStart else { return }
            let translation = CGPoint(
                x: location.x - start.x,
                y: location.y - start.y
            )
            if !handleInteractionBecameDrag && !handleInteractionRejected {
                let distance = hypot(translation.x, translation.y)
                guard distance >= 6 else { return }
                if MarkdownTableDragDirection.accepts(translation, for: axis) {
                    handleInteractionBecameDrag = true
                    updateDrag(
                        state: .began,
                        location: start,
                        translation: .zero,
                        axis: axis
                    )
                } else {
                    handleInteractionRejected = true
                    return
                }
            }
            if handleInteractionBecameDrag {
                updateDrag(
                    state: .changed,
                    location: location,
                    translation: translation,
                    axis: axis
                )
            }
        case .ended:
            if handleInteractionBecameDrag {
                let start = handleInteractionStart ?? location
                updateDrag(
                    state: .ended,
                    location: location,
                    translation: CGPoint(
                        x: location.x - start.x,
                        y: location.y - start.y
                    ),
                    axis: axis
                )
            } else if !handleInteractionRejected {
                handleHandleTap(axis: axis)
            }
            resetHandleInteraction()
            restoreDocumentSelectionAfterHandleTouch()
        case .cancelled, .failed:
            if handleInteractionBecameDrag {
                updateDrag(
                    state: gesture.state,
                    location: location,
                    translation: .zero,
                    axis: axis
                )
            }
            resetHandleInteraction()
            restoreDocumentSelectionAfterHandleTouch()
        default:
            break
        }
    }

    private func resetHandleInteraction() {
        handleInteractionStart = nil
        handleInteractionAxis = nil
        handleInteractionBecameDrag = false
        handleInteractionRejected = false
    }

    private func suspendDocumentSelectionForHandleTouch() {
        suspendedDocumentGestures = competingDocumentGestures.filter(\.isEnabled)
        suspendedDocumentGestures.forEach { $0.isEnabled = false }
        if let hostTextView {
            hostTextViewWasSelectable = hostTextView.isSelectable
            hostTextView.isSelectable = false
        }
    }

    private func restoreDocumentSelectionAfterHandleTouch() {
        let gestures = suspendedDocumentGestures
        suspendedDocumentGestures = []
        let textView = hostTextView
        let wasSelectable = hostTextViewWasSelectable
        hostTextViewWasSelectable = nil
        DispatchQueue.main.async {
            gestures.forEach { $0.isEnabled = true }
            if let wasSelectable {
                textView?.isSelectable = wasSelectable
            }
        }
    }

    private func handleAxis(at point: CGPoint) -> MarkdownTableReorderAxis? {
        let candidates: [(MarkdownTableReorderAxis, MarkdownTableHandleView)] = [
            (.row, rowHandle),
            (.column, columnHandle)
        ]
        return candidates
            .filter { _, handle in
                !handle.isHidden
                    && handle.alpha > 0.01
                    && handle.frame.contains(point)
            }
            .min { lhs, rhs in
                let lhsDistance = hypot(
                    point.x - lhs.1.frame.midX,
                    point.y - lhs.1.frame.midY
                )
                let rhsDistance = hypot(
                    point.x - rhs.1.frame.midX,
                    point.y - rhs.1.frame.midY
                )
                return lhsDistance < rhsDistance
            }?
            .0
    }

    private func updateDrag(state: UIGestureRecognizer.State,
                            location: CGPoint,
                            translation: CGPoint,
                            axis: MarkdownTableReorderAxis) {
        guard let table,
              let geometry,
              let address = selectedAddress() else {
            clearReorderPreview()
            return
        }
        let selectedIndex = axis == .row ? address.row : address.column
        let selectionBeforeDrag = bandSelection
        let dragSelection = MarkdownTableDragSelectionPolicy.resolve(
            axis: axis,
            selectedIndex: selectedIndex,
            selectedAxis: selectionBeforeDrag?.axis,
            selectedRange: selectionBeforeDrag?.range
        )
        let preservesSelection = dragSelection.preservesSelection
        let source = dragSelection.source
        switch state {
        case .began:
            editMenuInteraction.dismissMenu()
            reorderPreview = ReorderPreview(
                axis: axis,
                source: source,
                selectionBeforeDrag: selectionBeforeDrag,
                preservesSelection: preservesSelection,
                destination: source.lowerBound
            )
            beginDragVisuals(axis: axis, selection: source, geometry: geometry)
            setNeedsLayout()
        case .changed:
            let destination = reorderDestination(
                at: location,
                axis: axis,
                source: source,
                geometry: geometry
            )
            if reorderPreview?.destination != destination {
                reorderPreview?.destination = destination
                if let preview = reorderPreview {
                    UIView.animate(withDuration: 0.16,
                                   delay: 0,
                                   options: [.beginFromCurrentState, .curveEaseOut]) {
                        self.settleNeighborSnapshots(preview, geometry: geometry)
                    }
                }
            }
            updateDragSnapshot(translation: translation, axis: axis)
        case .ended:
            let preview = reorderPreview
            guard let preview else {
                endDragVisuals(animated: true)
                return
            }
            settleDrag(
                preview,
                table: table,
                address: address,
                geometry: geometry
            )
        case .cancelled, .failed:
            bandSelection = reorderPreview?.selectionBeforeDrag
            target?.bandSelectionStateDidChange()
            endDragVisuals(animated: true)
        default:
            break
        }
    }

    private func reorderDestination(at location: CGPoint,
                                    axis: MarkdownTableReorderAxis,
                                    source: ClosedRange<Int>,
                                    geometry: MarkdownTableOverlayGeometry) -> Int {
        let count = source.count
        switch axis {
        case .row:
            let lastStart = max(0, geometry.rowRects.count - count)
            let candidates = Array(0...lastStart)
            return candidates.min { lhs, rhs in
                let lhsEnd = min(geometry.rowRects.count - 1, lhs + count - 1)
                let rhsEnd = min(geometry.rowRects.count - 1, rhs + count - 1)
                let lhsMid = (geometry.rowRects[lhs].minY + geometry.rowRects[lhsEnd].maxY) / 2
                let rhsMid = (geometry.rowRects[rhs].minY + geometry.rowRects[rhsEnd].maxY) / 2
                return abs(lhsMid - location.y) < abs(rhsMid - location.y)
            } ?? source.lowerBound
        case .column:
            let width = geometry.gridRect.width / CGFloat(max(1, geometry.columnCount))
            let lastStart = max(0, geometry.columnCount - count)
            let proposed = Int(round(
                (location.x - geometry.gridRect.minX - CGFloat(count) * width / 2) / max(1, width)
            ))
            return min(max(0, proposed), lastStart)
        }
    }

    private func beginDragVisuals(axis: MarkdownTableReorderAxis,
                                  selection: ClosedRange<Int>,
                                  geometry: MarkdownTableOverlayGeometry) {
        guard let rect = selectionRect(
            for: BandSelection(axis: axis, range: selection),
            geometry: geometry
        ) else { return }

        let activeHandle = handle(for: axis)
        let handleFrame = activeHandle.frame
        let handleSnapshot = activeHandle.snapshotView(afterScreenUpdates: true)

        rowHandle.isHidden = true
        columnHandle.isHidden = true
        selectionStartGrip.isHidden = true
        selectionEndGrip.isHidden = true
        [rowHandle, columnHandle, selectionStartGrip, selectionEndGrip].forEach {
            $0.alpha = 0
        }
        selectionLayer.isHidden = true
        bandSelectionLayer.isHidden = true
        rowSelectionCapLayer.isHidden = true
        columnSelectionCapLayer.isHidden = true
        layoutIfNeeded()

        guard let snapshot = resizableSnapshotView(
            from: rect,
            afterScreenUpdates: true,
            withCapInsets: .zero
        ) else {
            selectionLayer.isHidden = false
            bandSelectionLayer.isHidden = false
            rowSelectionCapLayer.isHidden = false
            columnSelectionCapLayer.isHidden = false
            if let table {
                updateHandles(table: table, geometry: geometry)
            }
            [rowHandle, columnHandle, selectionStartGrip, selectionEndGrip].forEach {
                $0.alpha = 1
            }
            return
        }
        let containerFrame = rect.union(handleFrame)
        let container = UIView(frame: containerFrame)
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false
        snapshot.frame = rect.offsetBy(dx: -containerFrame.minX, dy: -containerFrame.minY)
        if let handleSnapshot {
            handleSnapshot.frame = handleFrame.offsetBy(
                dx: -containerFrame.minX,
                dy: -containerFrame.minY
            )
            container.addSubview(handleSnapshot)
        }
        container.addSubview(snapshot)
        if let handleSnapshot {
            container.bringSubviewToFront(handleSnapshot)
        }

        let bandCount = axis == .row ? geometry.rowRects.count : geometry.columnCount
        var neighbors: [Int: UIView] = [:]
        for index in 0..<bandCount where !selection.contains(index) {
            guard let rect = bandRect(for: index, axis: axis, geometry: geometry),
                  let neighbor = resizableSnapshotView(
                    from: rect,
                    afterScreenUpdates: true,
                    withCapInsets: .zero
                  ) else { continue }
            neighbor.frame = rect
            neighbors[index] = neighbor
        }

        surfaceLayer.isHidden = true
        headerLayer.isHidden = true
        gridLayer.isHidden = true
        cellFields.values.forEach { $0.alpha = 0 }
        neighbors.keys.sorted().forEach { index in
            if let neighbor = neighbors[index] {
                addSubview(neighbor)
            }
        }
        addSubview(container)
        dragNeighborSnapshots = neighbors
        dragContainer = container
        dragSnapshot = snapshot
        dragHandleSnapshot = handleSnapshot
        dragStartFrame = rect

        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.22
        container.layer.shadowRadius = 7
        container.layer.shadowOffset = CGSize(width: 0, height: 3)
        snapshot.layer.cornerRadius = 6
        let lift = liftTransform(for: axis)
        UIView.animate(withDuration: 0.14,
                       delay: 0,
                       options: [.beginFromCurrentState, .curveEaseOut]) {
            container.transform = lift
        }
    }

    private func updateDragSnapshot(translation: CGPoint,
                                    axis: MarkdownTableReorderAxis) {
        let primary = axis == .row
            ? CGAffineTransform(translationX: -5, y: translation.y)
            : CGAffineTransform(translationX: translation.x, y: -5)
        dragContainer?.transform = primary
    }

    private func liftTransform(for axis: MarkdownTableReorderAxis) -> CGAffineTransform {
        axis == .row
            ? CGAffineTransform(translationX: -5, y: 0)
            : CGAffineTransform(translationX: 0, y: -5)
    }

    private func handle(for axis: MarkdownTableReorderAxis) -> UIView {
        axis == .row ? rowHandle : columnHandle
    }

    private func bandRect(for index: Int,
                          axis: MarkdownTableReorderAxis,
                          geometry: MarkdownTableOverlayGeometry) -> CGRect? {
        switch axis {
        case .row:
            return geometry.rowRects[safe: index]
        case .column:
            guard geometry.columnCount > 0, index < geometry.columnCount else { return nil }
            let width = geometry.gridRect.width / CGFloat(geometry.columnCount)
            return CGRect(x: geometry.gridRect.minX + CGFloat(index) * width,
                          y: geometry.gridRect.minY,
                          width: width,
                          height: geometry.gridRect.height)
        }
    }

    private func settleNeighborSnapshots(_ preview: ReorderPreview,
                                         geometry: MarkdownTableOverlayGeometry) {
        guard let sourceRect = selectionRect(
            for: BandSelection(axis: preview.axis, range: preview.source),
            geometry: geometry
        ) else { return }
        let blockDistance = preview.axis == .row ? sourceRect.height : sourceRect.width
        for (index, snapshot) in dragNeighborSnapshots {
            let offset = MarkdownTableNeighborSnap.offset(
                for: index,
                source: preview.source,
                destination: preview.destination,
                sourceExtent: blockDistance
            )
            snapshot.transform = preview.axis == .row
                ? CGAffineTransform(translationX: 0, y: offset)
                : CGAffineTransform(translationX: offset, y: 0)
        }
    }

    private func settleDrag(_ preview: ReorderPreview,
                            table: MarkdownTable,
                            address: MarkdownTableCellAddress,
                            geometry: MarkdownTableOverlayGeometry) {
        let destinationRange = preview.destination...(preview.destination + preview.source.count - 1)
        let destinationRect = selectionRect(
            for: BandSelection(axis: preview.axis, range: destinationRange),
            geometry: geometry
        )
        let translation: CGAffineTransform
        if let destinationRect {
            translation = CGAffineTransform(
                translationX: destinationRect.minX - dragStartFrame.minX,
                y: destinationRect.minY - dragStartFrame.minY
            )
        } else {
            translation = .identity
        }

        UIView.animate(withDuration: 0.18,
                       delay: 0,
                       options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.dragContainer?.transform = translation
            self.settleNeighborSnapshots(preview, geometry: geometry)
        } completion: { _ in
            let changed = preview.destination != preview.source.lowerBound
            self.bandSelection = preview.preservesSelection
                ? BandSelection(axis: preview.axis, range: destinationRange)
                : nil
            self.target?.bandSelectionStateDidChange()
            if changed {
                self.target?.reorder(
                    preview.axis,
                    range: preview.source,
                    table: table,
                    address: address,
                    destinationIndex: preview.destination,
                    selectedRangeAfterReorder: preview.preservesSelection
                        ? destinationRange
                        : nil
                )
            }
            self.finishDragVisuals()
        }
    }

    private func endDragVisuals(animated: Bool) {
        let changes = {
            self.dragContainer?.transform = .identity
            self.rowHandle.transform = .identity
            self.columnHandle.transform = .identity
            self.dragNeighborSnapshots.values.forEach { $0.transform = .identity }
        }
        let completion: (Bool) -> Void = { _ in self.finishDragVisuals() }
        if animated {
            UIView.animate(withDuration: 0.16,
                           delay: 0,
                           options: [.beginFromCurrentState, .curveEaseOut],
                           animations: changes,
                           completion: completion)
        } else {
            changes()
            completion(true)
        }
    }

    private func finishDragVisuals() {
        dragContainer?.removeFromSuperview()
        dragContainer = nil
        dragSnapshot = nil
        dragHandleSnapshot = nil
        dragNeighborSnapshots.values.forEach { $0.removeFromSuperview() }
        dragNeighborSnapshots.removeAll()
        rowHandle.transform = .identity
        columnHandle.transform = .identity
        [rowHandle, columnHandle, selectionStartGrip, selectionEndGrip].forEach {
            $0.alpha = 1
        }
        surfaceLayer.isHidden = false
        headerLayer.isHidden = false
        selectionLayer.isHidden = false
        gridLayer.isHidden = false
        bandSelectionLayer.isHidden = false
        rowSelectionCapLayer.isHidden = false
        columnSelectionCapLayer.isHidden = false
        for field in cellFields.values {
            field.alpha = 1
            field.transform = .identity
        }
        reorderPreview = nil
        if let table, let geometry {
            updateHandles(table: table, geometry: geometry)
            drawGrid(geometry: geometry)
        }
        setNeedsLayout()
    }

    private func clearReorderPreview() {
        guard reorderPreview != nil else { return }
        endDragVisuals(animated: false)
    }

    private func alignment(for alignment: MarkdownTableAlignment) -> NSTextAlignment {
        switch alignment {
        case .none, .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Array where Element == String {
    func padded(to count: Int) -> [String] {
        self + Array(repeating: "", count: Swift.max(0, count - self.count))
    }
}

private extension Array where Element == MarkdownTableAlignment {
    func padded(to count: Int, fill: MarkdownTableAlignment) -> [MarkdownTableAlignment] {
        self + Array(repeating: fill, count: Swift.max(0, count - self.count))
    }
}
