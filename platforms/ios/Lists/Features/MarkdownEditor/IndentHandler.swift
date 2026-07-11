import Foundation

/// Tab / Shift-Tab indent and outdent.
///
/// Both always operate on the current line (not the caret position
/// within the line). Tab inserts 4 spaces at line start; Shift-Tab
/// removes up to 4 leading spaces.
///
/// Multi-line selections indent every line touched by the selection
/// and the selection extends to cover the new boundaries.
///
/// Pure transform. `(source, selection) -> (source, selection)`.
enum IndentHandler {

    private static let indentWidth = 4
    private static let indentString = "    "

    static func indent(source: String,
                       selection: NSRange) -> (source: String, selection: NSRange) {
        if let tableMove = moveToNextTableCell(source: source, selection: selection) {
            return tableMove
        }
        let lines = linesTouched(by: selection, in: source)
        let ns = source as NSString
        let edits = lines.map { start -> LineEdit in
            let line = lineContent(in: ns, startingAt: start)
            if let marker = ListMarker.detect(in: line),
               case .blockquote = marker.kind {
                return LineEdit(location: start, length: 0, replacement: "> ")
            }
            return LineEdit(location: start, length: 0, replacement: indentString)
        }
        return apply(edits: edits, source: source, selection: selection)
    }

    static func outdent(source: String,
                        selection: NSRange) -> (source: String, selection: NSRange) {
        let lines = linesTouched(by: selection, in: source)
        let ns = source as NSString
        let edits = lines.compactMap { start -> LineEdit? in
            let line = lineContent(in: ns, startingAt: start)
            if let marker = ListMarker.detect(in: line),
               case .blockquote = marker.kind {
                let markerStart = start + marker.indent
                var length = 1
                if markerStart + 1 < ns.length,
                   ns.character(at: markerStart + 1) == 0x20 {
                    length += 1
                }
                return LineEdit(location: markerStart, length: length, replacement: "")
            }

            var spaces = 0
            while start + spaces < ns.length,
                  spaces < indentWidth,
                  ns.character(at: start + spaces) == 0x20 {
                spaces += 1
            }
            guard spaces > 0 else { return nil }
            return LineEdit(location: start, length: spaces, replacement: "")
        }
        return apply(edits: edits, source: source, selection: selection)
    }

    // MARK: Implementation

    /// Returns the line start indices for every line touched by the
    /// selection. Single-caret returns one index; multi-line
    /// selection returns each line's start.
    private static func linesTouched(by selection: NSRange,
                                     in source: String) -> [Int] {
        let ns = source as NSString
        var lineStarts: [Int] = []
        let firstLine = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        lineStarts.append(firstLine.location)
        let end = max(selection.location, selection.location + selection.length - 1)
        var cursor = firstLine.location + firstLine.length
        while cursor <= end, cursor < ns.length {
            let lr = ns.lineRange(for: NSRange(location: cursor, length: 0))
            lineStarts.append(lr.location)
            cursor = lr.location + lr.length
        }
        return lineStarts
    }

    private struct LineEdit {
        let location: Int
        let length: Int
        let replacement: String
    }

    private static func lineContent(in source: NSString, startingAt start: Int) -> String {
        let range = source.lineRange(for: NSRange(location: start, length: 0))
        let raw = source.substring(with: range)
        return raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
    }

    private static func apply(edits: [LineEdit],
                              source: String,
                              selection: NSRange) -> (source: String, selection: NSRange) {
        guard !edits.isEmpty else { return (source, selection) }
        var result = source as NSString
        for edit in edits.sorted(by: { $0.location > $1.location }) {
            result = result.replacingCharacters(
                in: NSRange(location: edit.location, length: edit.length),
                with: edit.replacement
            ) as NSString
        }

        func adjusted(_ original: Int) -> Int {
            var position = original
            for edit in edits.sorted(by: { $0.location < $1.location }) {
                let replacementLength = (edit.replacement as NSString).length
                if edit.length == 0 {
                    if original >= edit.location {
                        position += replacementLength
                    }
                } else if original >= edit.location + edit.length {
                    position += replacementLength - edit.length
                } else if original > edit.location {
                    position = edit.location + replacementLength
                }
            }
            return position
        }

        let start = adjusted(selection.location)
        let end = adjusted(NSMaxRange(selection))
        return (result as String, NSRange(location: start, length: max(0, end - start)))
    }

    private static func moveToNextTableCell(source: String,
                                            selection: NSRange) -> (source: String, selection: NSRange)? {
        guard selection.length == 0 else { return nil }
        let ns = source as NSString
        guard ns.length > 0, selection.location <= ns.length else { return nil }
        let lineRange = ns.lineRange(for: NSRange(location: min(selection.location, max(0, ns.length - 1)), length: 0))
        let rawLine = ns.substring(with: lineRange)
        let lineContent = rawLine.hasSuffix("\n") ? String(rawLine.dropLast()) : rawLine
        guard MarkdownSyntax.isTableRow(lineContent),
              !MarkdownSyntax.isTableDivider(lineContent) else {
            return nil
        }

        let cells = MarkdownSyntax.tableCells(in: lineContent, lineRange: lineRange)
        guard !cells.isEmpty else { return nil }
        let currentIndex = cells.firstIndex {
            selection.location >= $0.segmentRange.location
                && selection.location <= NSMaxRange($0.segmentRange)
        } ?? 0
        if currentIndex + 1 < cells.count {
            let next = cells[currentIndex + 1].contentRange
            return (source, NSRange(location: next.location, length: next.length))
        }

        if let nextRow = nextEditableTableRow(after: lineRange, in: ns) {
            let nextCells = MarkdownSyntax.tableCells(
                in: MarkdownSyntax.lineContent(in: ns, range: nextRow),
                lineRange: nextRow
            )
            if let firstCell = nextCells.first {
                return (source, NSRange(location: firstCell.contentRange.location,
                                        length: firstCell.contentRange.length))
            }
        }

        let columnCount = max(1, cells.count)
        let row = "| " + Array(repeating: "", count: columnCount).joined(separator: " | ") + " |"
        let target = tableRowInsertionTarget(in: ns, currentLineRange: lineRange)
        let targetContentLength = (MarkdownSyntax.lineContent(in: ns, range: target) as NSString).length
        let lineHasTrailingNewline = target.length > targetContentLength
        let insert = lineHasTrailingNewline ? row + "\n" : "\n" + row
        let insertAt = NSMaxRange(target)
        let newSource = ns.replacingCharacters(in: NSRange(location: insertAt, length: 0),
                                               with: insert)
        let firstCellOffset = lineHasTrailingNewline ? 2 : 3
        return (newSource, NSRange(location: insertAt + firstCellOffset, length: 0))
    }

    private static func nextEditableTableRow(after lineRange: NSRange,
                                             in ns: NSString) -> NSRange? {
        var cursor = NSMaxRange(lineRange)
        while cursor < ns.length {
            let nextLine = ns.lineRange(for: NSRange(location: cursor, length: 0))
            let lineContent = MarkdownSyntax.lineContent(in: ns, range: nextLine)
            guard MarkdownSyntax.isTableRow(lineContent) else { return nil }
            if !MarkdownSyntax.isTableDivider(lineContent) {
                return nextLine
            }
            cursor = NSMaxRange(nextLine)
        }
        return nil
    }

    private static func tableRowInsertionTarget(in ns: NSString,
                                                currentLineRange: NSRange) -> NSRange {
        guard NSMaxRange(currentLineRange) < ns.length else {
            return currentLineRange
        }
        let nextLine = ns.lineRange(for: NSRange(location: NSMaxRange(currentLineRange), length: 0))
        let nextContent = MarkdownSyntax.lineContent(in: ns, range: nextLine)
        if MarkdownSyntax.isTableDivider(nextContent) {
            return nextLine
        }
        return currentLineRange
    }
}
