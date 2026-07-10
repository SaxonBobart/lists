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
    static let handleGutterWidth: CGFloat = 28
    static let handleGlyphSize: CGFloat = 28
    static let topHandleHeight: CGFloat = 32

    static func rowHeight(for font: UIFont) -> CGFloat {
        max(44, ceil(font.lineHeight + 22))
    }

    static func caretHeight(for font: UIFont, rowHeight: CGFloat) -> CGFloat {
        min(max(18, ceil(font.lineHeight)), max(18, rowHeight - 10))
    }
}

struct MarkdownTableCellAddress: Hashable, Sendable {
    /// Visible table row: `0` is the header row, `1...` are body rows.
    let row: Int
    let column: Int
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
    case cycleAlignment
    case setAlignment(MarkdownTableAlignment)
    case deleteTable

    func apply(to source: String, selection: NSRange) -> (source: String, selection: NSRange) {
        guard let table = MarkdownTableParser.table(containing: selection, in: source) else {
            return (source, selection)
        }

        let column = MarkdownTableParser.cell(containing: selection, in: table)?.column ?? 0
        let selectedRow = MarkdownTableParser.row(containing: selection, in: table)
        let bodyRowIndex: Int? = {
            if case .body(let index) = selectedRow?.role { return index }
            return nil
        }()

        var header = table.header.cells.map(\.text)
        var alignments = table.alignments
        var body = table.bodyRows.map { $0.cells.map(\.text) }
        let columnCount = max(1, table.columnCount)
        header = header.padded(to: columnCount)
        alignments = alignments.padded(to: columnCount, fill: .none)
        body = body.isEmpty ? [Array(repeating: "", count: columnCount)] : body.map { $0.padded(to: columnCount) }

        let targetRow: Int
        let targetColumn: Int

        switch self {
        case .addRowAbove:
            let insertIndex = bodyRowIndex ?? 0
            body.insert(Array(repeating: "", count: columnCount), at: min(max(0, insertIndex), body.count))
            targetRow = min(max(0, insertIndex), body.count - 1) + 1
            targetColumn = min(column, columnCount - 1)
        case .addRowBelow:
            let insertIndex = (bodyRowIndex ?? -1) + 1
            body.insert(Array(repeating: "", count: columnCount), at: min(max(0, insertIndex), body.count))
            targetRow = min(max(0, insertIndex), body.count - 1) + 1
            targetColumn = min(column, columnCount - 1)
        case .addColumnBefore:
            let insertColumn = min(max(0, column), columnCount)
            header.insert("", at: insertColumn)
            alignments.insert(.none, at: insertColumn)
            for index in body.indices {
                body[index].insert("", at: insertColumn)
            }
            targetRow = (bodyRowIndex ?? -1) + 1
            targetColumn = insertColumn
        case .addColumnAfter:
            let insertColumn = min(column + 1, columnCount)
            header.insert("", at: insertColumn)
            alignments.insert(.none, at: insertColumn)
            for index in body.indices {
                body[index].insert("", at: insertColumn)
            }
            targetRow = (bodyRowIndex ?? -1) + 1
            targetColumn = insertColumn
        case .deleteRow:
            if let bodyRowIndex, body.count > 1 {
                body.remove(at: bodyRowIndex)
                targetRow = min(bodyRowIndex, body.count - 1) + 1
            } else {
                body = [Array(repeating: "", count: columnCount)]
                targetRow = 1
            }
            targetColumn = min(column, max(0, columnCount - 1))
        case .deleteColumn:
            if columnCount <= 1 {
                return delete(table: table, from: source)
            }
            header.remove(at: min(column, header.count - 1))
            alignments.remove(at: min(column, alignments.count - 1))
            for index in body.indices where column < body[index].count {
                body[index].remove(at: column)
            }
            targetRow = (bodyRowIndex ?? -1) + 1
            targetColumn = min(column, max(0, columnCount - 2))
        case .cycleAlignment:
            alignments[column] = alignments[column].next
            targetRow = (bodyRowIndex ?? -1) + 1
            targetColumn = column
        case .setAlignment(let alignment):
            alignments[column] = alignment
            targetRow = (bodyRowIndex ?? -1) + 1
            targetColumn = column
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

    override var canBecomeFirstResponder: Bool {
        true
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
final class MarkdownTableOverlayController: NSObject, UITextViewDelegate {
    private weak var textView: MarkdownInternalTextView?
    private weak var coordinator: EditorCoordinator?
    private var tableViews: [Int: MarkdownTableOverlayView] = [:]
    private var isApplyingCellEdit = false

    init(textView: MarkdownInternalTextView, coordinator: EditorCoordinator) {
        self.textView = textView
        self.coordinator = coordinator
        super.init()
    }

    func isAttached(to textView: MarkdownInternalTextView) -> Bool {
        self.textView === textView
    }

    func detach() {
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

        let tables = MarkdownTableParser.tables(in: storage.string)
        var activeKeys = Set<Int>()
        for (index, table) in tables.enumerated() {
            let existingOverlay = tableViews[index]
            let reservesHandleGutter = existingOverlay?.hasFocusedCell == true
            guard let geometry = geometry(for: table,
                                          in: textView,
                                          reservesHandleGutter: reservesHandleGutter) else { continue }
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
    }

    private func geometry(for table: MarkdownTable,
                          in textView: MarkdownInternalTextView,
                          reservesHandleGutter: Bool) -> MarkdownTableOverlayGeometry? {
        let layout = textView.layoutManager
        let container = textView.textContainer
        layout.ensureLayout(for: container)

        let visibleRows = [table.header] + table.bodyRows
        let rowData = visibleRows.compactMap { row -> (rect: CGRect, height: CGFloat)? in
            let glyphs = layout.glyphRange(forCharacterRange: row.lineRange,
                                           actualCharacterRange: nil)
            guard glyphs.length > 0 else { return nil }
            var rect: CGRect?
            layout.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, _, stop in
                rect = lineRect.offsetBy(dx: textView.textContainerInset.left,
                                         dy: textView.textContainerInset.top)
                stop.pointee = true
            }
            guard var rect else { return nil }
            let font = textView.textStorage.attribute(.font,
                                                      at: row.lineRange.location,
                                                      effectiveRange: nil) as? UIFont
                ?? UIFont.preferredFont(forTextStyle: .body)
            let rowHeight = rowHeight(for: row, table: table, font: font)
            if rect.height < rowHeight {
                rect.origin.y -= (rowHeight - rect.height) / 2
                rect.size.height = rowHeight
            }
            return (rect, rowHeight)
        }

        guard table.columnCount > 0,
              rowData.count == visibleRows.count,
              let first = rowData.first?.rect,
              let last = rowData.last?.rect else { return nil }

        let pad = container.lineFragmentPadding
        let outerX = textView.textContainerInset.left + pad
        let outerWidth = max(0, container.size.width - 2 * pad)
        let handleGutter = reservesHandleGutter ? MarkdownTableVisualMetrics.handleGutterWidth : 0
        let x = outerX + handleGutter
        let width = max(0, outerWidth - handleGutter)
        guard width > 40 else { return nil }

        let gridScreenRect = CGRect(x: x,
                                    y: first.minY,
                                    width: width,
                                    height: last.maxY - first.minY)
        let frameX = max(0, outerX)
        let frameY = max(0, gridScreenRect.minY - MarkdownTableVisualMetrics.topHandleHeight)
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

    private func rowHeight(for row: MarkdownTableRow, table: MarkdownTable, font: UIFont) -> CGFloat {
        let visibleCells: [String]
        switch row.role {
        case .header:
            visibleCells = table.header.cells.map(\.text)
        case .body(let index):
            visibleCells = table.bodyRows[safe: index]?.cells.map(\.text) ?? []
        case .divider:
            visibleCells = []
        }
        let lineCounts = visibleCells.map { max(1, $0.components(separatedBy: "\n").count) }
        let lines = max(1, lineCounts.max() ?? 1)
        let base = MarkdownTableVisualMetrics.rowHeight(for: font)
        return max(base, ceil(font.lineHeight * CGFloat(lines) + 24))
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        guard let field = textView as? MarkdownTableCellTextView,
              let payload = field.tablePayload else { return }
        select(payload.table, address: payload.address)
        reveal(field)
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
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
        isApplyingCellEdit = true
        let result = MarkdownTableCellEdit.apply(to: storage.string,
                                                 table: table,
                                                 address: payload.address,
                                                 text: field.text ?? "")
        coordinator?.applyExternalTableEdit(result, keepFirstResponder: field)
        isApplyingCellEdit = false
        refresh()
    }

    func perform(_ command: MarkdownTableCommand,
                 table: MarkdownTable,
                 address: MarkdownTableCellAddress) {
        guard let textView,
              let storage = textView.textStorage as? MarkdownStyler else { return }
        let result = command.apply(to: storage.string,
                                   selection: selection(for: address, in: table))
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

    func select(_ table: MarkdownTable, address: MarkdownTableCellAddress) {
        coordinator?.selectTableCell(address, in: table)
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

@MainActor
private final class MarkdownTableOverlayView: UIView {
    private var table: MarkdownTable?
    private var geometry: MarkdownTableOverlayGeometry?
    private weak var target: MarkdownTableOverlayController?
    private var cellFields: [MarkdownTableCellAddress: MarkdownTableCellTextView] = [:]
    private let gridLayer = CAShapeLayer()
    private let rowHandle = UIButton(type: .system)
    private let columnHandle = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false
        layer.addSublayer(gridLayer)
        configureHandle(rowHandle, id: "markdown.table.row.menu")
        configureHandle(columnHandle, id: "markdown.table.column.menu")
        rowHandle.transform = CGAffineTransform(rotationAngle: .pi / 2)
        addSubview(rowHandle)
        addSubview(columnHandle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(table: MarkdownTable,
                   geometry: MarkdownTableOverlayGeometry,
                   textView: MarkdownInternalTextView,
                   target: MarkdownTableOverlayController) {
        self.table = table
        self.geometry = geometry
        self.target = target
        rebuildCells(table: table, geometry: geometry, textView: textView, target: target)
        updateHandles(table: table, geometry: geometry)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let table, let geometry else { return }
        drawGrid(geometry: geometry)
        layoutCells(geometry: geometry)
        updateHandles(table: table, geometry: geometry)
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
                let field = cellFields[address] ?? makeField(textView: textView, target: target)
                field.tablePayload = MarkdownTableFieldPayload(table: table, address: address)
                if !field.isFirstResponder {
                    field.text = row.cells.first(where: { $0.column == column })?.text ?? ""
                }
                field.font = UIFont.preferredFont(forTextStyle: .body)
                field.textColor = .label
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

    private func makeField(textView: MarkdownInternalTextView,
                           target: MarkdownTableOverlayController) -> MarkdownTableCellTextView {
        let field = MarkdownTableCellTextView(frame: .zero)
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
        let inset = UIEdgeInsets(top: 9, left: 12, bottom: 9, right: 12)
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
            return
        }
        rowHandle.isHidden = false
        columnHandle.isHidden = false
        let rowRect = geometry.rowRects[safe: address.row] ?? geometry.rowRects.first ?? bounds
        let cellWidth = geometry.gridRect.width / CGFloat(max(1, geometry.columnCount))
        columnHandle.frame = CGRect(
            x: geometry.gridRect.minX + CGFloat(address.column) * cellWidth + cellWidth / 2 - MarkdownTableVisualMetrics.handleGlyphSize / 2,
            y: 0,
            width: MarkdownTableVisualMetrics.handleGlyphSize,
            height: geometry.gridRect.minY
        )
        rowHandle.frame = CGRect(
            x: max(0, geometry.gridRect.minX - MarkdownTableVisualMetrics.handleGutterWidth),
            y: rowRect.midY - MarkdownTableVisualMetrics.handleGlyphSize / 2,
            width: MarkdownTableVisualMetrics.handleGutterWidth,
            height: MarkdownTableVisualMetrics.handleGlyphSize
        )
        columnHandle.menu = columnMenu(table: table, address: address)
        rowHandle.menu = rowMenu(table: table, address: address)
        bringSubviewToFront(rowHandle)
        bringSubviewToFront(columnHandle)
    }

    private func selectedAddress() -> MarkdownTableCellAddress? {
        cellFields.first(where: { $0.value.isFirstResponder })?.key
    }

    var hasFocusedCell: Bool {
        selectedAddress() != nil
    }

    func represents(_ table: MarkdownTable) -> Bool {
        self.table?.fullRange.location == table.fullRange.location
    }

    func focusCell(_ address: MarkdownTableCellAddress) -> MarkdownTableCellTextView? {
        let field = cellFields[address]
        field?.becomeFirstResponder()
        return field
    }

    private func drawGrid(geometry: MarkdownTableOverlayGeometry) {
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
    }

    private func rowMenu(table: MarkdownTable, address: MarkdownTableCellAddress) -> UIMenu {
        UIMenu(children: [
            action("Add Row Above", "arrow.up.to.line", .addRowAbove, table, address),
            action("Add Row Below", "arrow.down.to.line", .addRowBelow, table, address),
            action("Delete Row", "minus", .deleteRow, table, address, .destructive)
        ])
    }

    private func columnMenu(table: MarkdownTable, address: MarkdownTableCellAddress) -> UIMenu {
        UIMenu(children: [
            UIMenu(options: .displayInline, children: [
                action("Add Column Before", "arrow.left.to.line", .addColumnBefore, table, address),
                action("Add Column After", "arrow.right.to.line", .addColumnAfter, table, address),
                action("Delete Column", "minus", .deleteColumn, table, address, .destructive)
            ]),
            UIMenu(title: "Alignment", image: UIImage(systemName: "text.alignleft"), children: [
                action("Default", "text.alignleft", .setAlignment(.none), table, address),
                action("Left", "text.alignleft", .setAlignment(.left), table, address),
                action("Center", "text.aligncenter", .setAlignment(.center), table, address),
                action("Right", "text.alignright", .setAlignment(.right), table, address)
            ]),
            UIMenu(options: .displayInline, children: [
                action("Delete Table", "trash", .deleteTable, table, address, .destructive)
            ])
        ])
    }

    private func action(_ title: String,
                        _ symbol: String,
                        _ command: MarkdownTableCommand,
                        _ table: MarkdownTable,
                        _ address: MarkdownTableCellAddress,
                        _ attributes: UIMenuElement.Attributes = []) -> UIAction {
        UIAction(title: title,
                 image: UIImage(systemName: symbol),
                 attributes: attributes) { [weak target] _ in
            target?.perform(command, table: table, address: address)
        }
    }

    private func configureHandle(_ button: UIButton, id: String) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "ellipsis")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        config.baseForegroundColor = UIColor.secondaryLabel
        config.contentInsets = .zero
        button.configuration = config
        button.tintColor = .secondaryLabel
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = id
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
