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
        case blockquote
    }

    var continuationPrefix: String {
        let pad = String(repeating: " ", count: indent)
        switch kind {
        case .bullet(let c):    return "\(pad)\(c) "
        case .task:             return "\(pad)- [ ] "
        case .numbered(let n):  return "\(pad)\(n + 1). "
        case .blockquote:       return "\(pad)> "
        }
    }

    func prefix(indentedBy indent: Int) -> String {
        let pad = String(repeating: " ", count: max(0, indent))
        switch kind {
        case .bullet(let c):        return "\(pad)\(c) "
        case .task(let checked):    return "\(pad)- [\(checked ? "x" : " ")] "
        case .numbered(let n):      return "\(pad)\(n). "
        case .blockquote:           return "\(pad)> "
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

        // Blockquote — `> ` (space required).
        if chars.count - i >= 2,
           chars[i] == ">", chars[i + 1] == " " {
            return ListMarker(indent: indent,
                              kind: .blockquote,
                              contentStart: i + 2)
        }

        return nil
    }
}
