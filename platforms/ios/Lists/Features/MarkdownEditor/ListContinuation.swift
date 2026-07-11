import Foundation

/// Smart Return: when the caret is at the end of a list / task /
/// numbered / blockquote item, the next line auto-continues with the
/// same marker (and the same leading indent). When the caret is on
/// an *empty* nested list item, Return outdents one level; top-level
/// empty items exit the list.
///
/// Pure transform. Selection-non-empty falls through to a plain
/// `\n` insert; selection-aware continuation isn't part of the
/// smart path.
enum ListContinuation {
    private static let indentWidth = 4

    static func apply(to source: String,
                      selection: NSRange) -> (source: String, selection: NSRange) {
        guard selection.length == 0 else {
            return defaultNewline(source: source, selection: selection)
        }
        let ns = source as NSString
        let caret = selection.location
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        let rawLine = ns.substring(with: lineRange)
        let lineContent = rawLine.hasSuffix("\n") ? String(rawLine.dropLast()) : rawLine
        let lineEnd = lineRange.location + (lineContent as NSString).length

        if MarkdownSyntax.isTableRow(lineContent),
           !MarkdownSyntax.isTableDivider(lineContent) {
            return insertTableRow(source: source,
                                  selection: selection,
                                  lineRange: lineRange,
                                  lineContent: lineContent)
        }

        guard let marker = ListMarker.detect(in: lineContent) else {
            return defaultNewline(source: source, selection: selection)
        }

        // Content of the line after the marker; leading spaces stripped.
        let contentStart = marker.contentStart
        let contentNs = lineContent as NSString
        let afterMarker: String = {
            guard contentStart < contentNs.length else { return "" }
            return contentNs.substring(from: contentStart)
        }()
        let trimmedContent = afterMarker.drop(while: { $0 == " " })

        // Empty marker — caret at or past content-start, no actual
        // content. Nested items step out one indent level; top-level
        // items exit the list into an empty paragraph.
        if trimmedContent.isEmpty && caret >= lineRange.location + contentStart {
            if case .blockquote(let depth) = marker.kind {
                let removeRange = NSRange(location: lineRange.location,
                                          length: lineEnd - lineRange.location)
                if depth > 1 {
                    let pad = String(repeating: " ", count: marker.indent)
                    let prefix = pad + String(repeating: "> ", count: depth - 1)
                    let newSource = ns.replacingCharacters(in: removeRange, with: prefix)
                    return (newSource, NSRange(
                        location: lineRange.location + (prefix as NSString).length,
                        length: 0
                    ))
                }
                let newSource = ns.replacingCharacters(in: removeRange, with: "")
                return (newSource, NSRange(location: lineRange.location, length: 0))
            }
            if marker.indent > 0 {
                let outdentAmount = min(Self.indentWidth, marker.indent)
                let outdentedPrefix = marker.prefix(indentedBy: marker.indent - outdentAmount)
                let removeRange = NSRange(location: lineRange.location,
                                           length: lineEnd - lineRange.location)
                let newSource = ns.replacingCharacters(in: removeRange,
                                                       with: outdentedPrefix)
                let newCaret = lineRange.location + (outdentedPrefix as NSString).length
                return (newSource, NSRange(location: newCaret, length: 0))
            }

            let removeRange = NSRange(location: lineRange.location,
                                       length: lineEnd - lineRange.location)
            let newSource = ns.replacingCharacters(in: removeRange, with: "")
            return (newSource, NSRange(location: lineRange.location, length: 0))
        }

        // Non-empty content — insert `\n` + continuation prefix at caret.
        let insert = "\n\(marker.continuationPrefix)"
        let newSource = ns.replacingCharacters(in: NSRange(location: caret, length: 0),
                                               with: insert)
        let newCaret = caret + (insert as NSString).length
        return (newSource, NSRange(location: newCaret, length: 0))
    }

    private static func defaultNewline(source: String,
                                       selection: NSRange) -> (source: String, selection: NSRange) {
        let ns = source as NSString
        let newSource = ns.replacingCharacters(in: selection, with: "\n")
        return (newSource, NSRange(location: selection.location + 1, length: 0))
    }

    private static func insertTableRow(source: String,
                                       selection: NSRange,
                                       lineRange: NSRange,
                                       lineContent: String) -> (source: String, selection: NSRange) {
        let ns = source as NSString
        let cells = MarkdownSyntax.tableCells(in: lineContent, lineRange: lineRange)
        let columnCount = max(1, cells.count)
        let currentColumn = cells.first {
            selection.location >= $0.segmentRange.location
                && selection.location <= NSMaxRange($0.segmentRange)
        }?.column ?? 0

        if let nextRow = nextEditableTableRow(after: lineRange, in: ns) {
            let nextCells = MarkdownSyntax.tableCells(
                in: MarkdownSyntax.lineContent(in: ns, range: nextRow),
                lineRange: nextRow
            )
            if !nextCells.isEmpty {
                let target = nextCells[min(currentColumn, nextCells.count - 1)].contentRange
                return (source, NSRange(location: target.location, length: target.length))
            }
        }

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
        guard let nextLine = nextLineRange(after: currentLineRange, in: ns) else {
            return currentLineRange
        }
        let nextContent = MarkdownSyntax.lineContent(in: ns, range: nextLine)
        if MarkdownSyntax.isTableDivider(nextContent) {
            return nextLine
        }
        return currentLineRange
    }

    private static func nextLineRange(after lineRange: NSRange, in ns: NSString) -> NSRange? {
        let start = NSMaxRange(lineRange)
        guard start < ns.length else { return nil }
        return ns.lineRange(for: NSRange(location: start, length: 0))
    }
}

/// Recognised line-starting markers. Used by `ListContinuation` and
/// (later) `IndentHandler` / `BackspaceHandler` so all three modules
/// agree on what a "list item" looks like.
struct ListMarker {
    let indent: Int
    let kind: Kind
    let contentStart: Int   // index in the line where content begins

    enum Kind: Hashable {
        case bullet(Character)        // `-`, `*`, `+`
        case task(checked: Bool)
        case numbered(Int)
        case blockquote(depth: Int)
    }

    var continuationPrefix: String {
        let pad = String(repeating: " ", count: indent)
        switch kind {
        case .bullet(let c):    return "\(pad)\(c) "
        case .task:             return "\(pad)- [ ] "
        case .numbered(let n):  return "\(pad)\(n + 1). "
        case .blockquote(let depth):
            return pad + String(repeating: "> ", count: max(1, depth))
        }
    }

    func prefix(indentedBy indent: Int) -> String {
        let pad = String(repeating: " ", count: max(0, indent))
        switch kind {
        case .bullet(let c):        return "\(pad)\(c) "
        case .task(let checked):    return "\(pad)- [\(checked ? "x" : " ")] "
        case .numbered(let n):      return "\(pad)\(n). "
        case .blockquote(let depth):
            return pad + String(repeating: "> ", count: max(1, depth))
        }
    }

    static func detect(in line: String) -> ListMarker? {
        let chars = Array(line)
        var i = 0
        while i < chars.count, chars[i] == " " { i += 1 }
        let indent = i
        guard i < chars.count else { return nil }

        // Task marker — accept `- [ ]` / `- [x]` / `- [X]` with optional
        // trailing space. Lists wants the bare `- [ ]` + Return to
        // exit (no trailing space typed yet).
        if chars.count - i >= 5,
           chars[i] == "-", chars[i + 1] == " ",
           chars[i + 2] == "[",
           (chars[i + 3] == " " || chars[i + 3] == "x" || chars[i + 3] == "X"),
           chars[i + 4] == "]" {
            let checked = (chars[i + 3] == "x" || chars[i + 3] == "X")
            let contentStart: Int = {
                if i + 5 < chars.count, chars[i + 5] == " " { return i + 6 }
                return i + 5
            }()
            return ListMarker(indent: indent,
                              kind: .task(checked: checked),
                              contentStart: contentStart)
        }

        // Bullet — `-`, `*`, `+` followed by a space.
        if chars.count - i >= 2,
           (chars[i] == "-" || chars[i] == "*" || chars[i] == "+"),
           chars[i + 1] == " " {
            return ListMarker(indent: indent,
                              kind: .bullet(chars[i]),
                              contentStart: i + 2)
        }

        // Numbered — digits + `. ` (space required for GFM).
        if chars[i].isNumber {
            var j = i
            while j < chars.count, chars[j].isNumber { j += 1 }
            if j + 1 < chars.count, chars[j] == ".", chars[j + 1] == " ",
               let n = Int(String(chars[i..<j])) {
                return ListMarker(indent: indent,
                                  kind: .numbered(n),
                                  contentStart: j + 2)
            }
        }

        // Blockquote/callout — preserve the complete depth for both compact
        // (`>>> `) and spaced (`> > > `) forms. The first marker does not
        // require a space so `>[!NOTE]` receives the same smart behavior.
        if chars[i] == ">" {
            var j = i
            var depth = 0
            while j < chars.count, chars[j] == ">" {
                depth += 1
                j += 1
                if j < chars.count, chars[j] == " " {
                    j += 1
                }
            }
            return ListMarker(indent: indent,
                              kind: .blockquote(depth: depth),
                              contentStart: j)
        }

        return nil
    }
}
