import Foundation

/// Buttons exposed in the Apple Reminders-style keyboard accessory
/// toolbar. Each case maps 1:1 to a pure `apply(to:selection:)`
/// transform — the same transform tests drive directly.
///
/// Toolbar visual layout lives in `MarkdownReminderToolbar`; the
/// logic of each button lives here.
enum ToolbarAction: Hashable, Sendable {
    // Text formatting
    case bold
    case italic
    case strikethrough
    case highlight

    // Headings
    case heading(Int)        // 1...6
    case paragraph

    // Lists
    case bullet
    case numbered
    case task
    case blockquote

    // Indent
    case indent
    case outdent

    // Inline
    case link
    case code

    // Blocks
    case codeBlock
    case image
    case table
    case tableAddRow
    case tableAddColumn
    case tableDeleteRow
    case tableDeleteColumn
    case tableAlign
    case tableDelete
    case horizontalRule

    // Extensions (P7)
    case mathInline
    case mathDisplay
    case mermaid
    case wikilink
    case footnote
}

extension ToolbarAction {
    func apply(to source: String,
               selection: NSRange) -> (source: String, selection: NSRange) {
        switch self {
        case .bold:
            return toggleInline(action: self, marker: "**", source: source, selection: selection)
        case .italic:
            return toggleInline(action: self, marker: "*", source: source, selection: selection)
        case .strikethrough:
            return toggleInline(action: self, marker: "~~", source: source, selection: selection)
        case .highlight:
            return toggleInline(action: self, marker: "==", source: source, selection: selection)
        case .code:
            return toggleInline(action: self, marker: "`", source: source, selection: selection)
        case .mathInline:
            return insertInlineMath(source: source, selection: selection)

        case .heading(let level):
            return toggleLinePrefix(.heading(level: level), in: source, selection: selection)
        case .paragraph:
            return toggleLinePrefix(.paragraph, in: source, selection: selection)
        case .bullet:
            return toggleLinePrefix(.bullet, in: source, selection: selection)
        case .numbered:
            return toggleLinePrefix(.numbered, in: source, selection: selection)
        case .task:
            return toggleLinePrefix(.task, in: source, selection: selection)
        case .blockquote:
            return toggleLinePrefix(.blockquote, in: source, selection: selection)

        case .indent:
            return IndentHandler.indent(source: source, selection: selection)
        case .outdent:
            return IndentHandler.outdent(source: source, selection: selection)

        case .link:
            return insertLink(source: source, selection: selection)
        case .image:
            return insertImage(source: source, selection: selection)
        case .horizontalRule:
            return insertHorizontalRule(source: source, selection: selection)
        case .codeBlock:
            return insertCodeBlock(source: source, selection: selection)
        case .mathDisplay:
            return insertDisplayMath(source: source, selection: selection)
        case .mermaid:
            return insertMermaid(source: source, selection: selection)
        case .table:
            return insertTable(source: source, selection: selection)
        case .tableAddRow:
            return MarkdownTableCommand.addRowBelow.apply(to: source, selection: selection)
        case .tableAddColumn:
            return MarkdownTableCommand.addColumnAfter.apply(to: source, selection: selection)
        case .tableDeleteRow:
            return MarkdownTableCommand.deleteRow.apply(to: source, selection: selection)
        case .tableDeleteColumn:
            return MarkdownTableCommand.deleteColumn.apply(to: source, selection: selection)
        case .tableAlign:
            return MarkdownTableCommand.cycleAlignment.apply(to: source, selection: selection)
        case .tableDelete:
            return MarkdownTableCommand.deleteTable.apply(to: source, selection: selection)
        case .wikilink:
            return insertWikilink(source: source, selection: selection)
        case .footnote:
            return insertFootnote(source: source, selection: selection)
        }
    }

    /// Accessibility id used by the toolbar SwiftUI view and the L3
    /// UI tests. Keeps the mapping next to the enum.
    var accessibilityId: String {
        switch self {
        case .bold:            return "markdown.toolbar.bold"
        case .italic:          return "markdown.toolbar.italic"
        case .strikethrough:   return "markdown.toolbar.strike"
        case .highlight:       return "markdown.toolbar.highlight"
        case .heading(let n):  return "markdown.toolbar.heading.\(n)"
        case .paragraph:       return "markdown.toolbar.heading.0"
        case .bullet:          return "markdown.toolbar.bullet"
        case .numbered:        return "markdown.toolbar.numbered"
        case .task:            return "markdown.toolbar.task"
        case .blockquote:      return "markdown.toolbar.quote"
        case .indent:          return "markdown.indent"
        case .outdent:         return "markdown.outdent"
        case .link:            return "markdown.toolbar.link"
        case .code:            return "markdown.toolbar.code"
        case .codeBlock:       return "markdown.toolbar.codeBlock"
        case .image:           return "markdown.toolbar.image"
        case .table:           return "markdown.toolbar.table"
        case .tableAddRow:     return "markdown.toolbar.table.row.add"
        case .tableAddColumn:  return "markdown.toolbar.table.column.add"
        case .tableDeleteRow:  return "markdown.toolbar.table.row.delete"
        case .tableDeleteColumn: return "markdown.toolbar.table.column.delete"
        case .tableAlign:      return "markdown.toolbar.table.align"
        case .tableDelete:     return "markdown.toolbar.table.delete"
        case .horizontalRule:  return "markdown.toolbar.hr"
        case .mathInline:      return "markdown.toolbar.math"
        case .mathDisplay:     return "markdown.toolbar.math.display"
        case .mermaid:         return "markdown.toolbar.mermaid"
        case .wikilink:        return "markdown.toolbar.wikilink"
        case .footnote:        return "markdown.toolbar.footnote"
        }
    }
}

// MARK: Inline wrap helper

private func toggleInline(action: ToolbarAction,
                          marker: String,
                          source: String,
                          selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    let selection = MarkdownSyntax.clamped(selection, length: ns.length)
    let markerLen = (marker as NSString).length

    if let active = MarkdownSyntax.inlineSpan(for: action, in: source, selection: selection) {
        return removeInlineMarkers(active, source: source, selection: selection)
    }

    if selection.length == 0 {
        // Insert empty `markermarker` only when the caret is not already
        // inside this format. Caret toggles should remove the containing span.
        let insert = marker + marker
        let newSource = ns.replacingCharacters(in: selection, with: insert)
        return (newSource,
                NSRange(location: selection.location + markerLen, length: 0))
    }

    var target = selection
    if action != .code,
       let codeSpan = MarkdownSyntax.inlineSpans(in: source).first(where: {
           $0.kind == .code && range(selection, isContainedIn: $0.contentRange)
       }) {
        target = codeSpan.fullRange
    }

    return wrapAdding(marker: marker, source: source, selection: selection, target: target)
}

private func wrapAdding(marker: String,
                        source: String,
                        selection: NSRange,
                        target: NSRange? = nil) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    let markerLen = (marker as NSString).length
    let target = target ?? selection
    let inner = ns.substring(with: target)
    let wrapped = marker + inner + marker
    let newSource = ns.replacingCharacters(in: target, with: wrapped)
    let newSelectionLocation = selection.location >= target.location
        ? selection.location + markerLen
        : selection.location
    return (newSource,
            NSRange(location: newSelectionLocation, length: selection.length))
}

private func removeInlineMarkers(_ span: MarkdownSyntax.InlineSpan,
                                 source: String,
                                 selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    let withoutClose = ns.replacingCharacters(in: span.closeRange, with: "") as NSString
    let newSource = withoutClose.replacingCharacters(in: span.openRange, with: "")
    let newSelection = selectionAfterRemoving(open: span.openRange,
                                              close: span.closeRange,
                                              content: span.contentRange,
                                              full: span.fullRange,
                                              selection: selection)
    return (newSource, newSelection)
}

private func selectionAfterRemoving(open: NSRange,
                                    close: NSRange,
                                    content: NSRange,
                                    full: NSRange,
                                    selection: NSRange) -> NSRange {
    if selection.location == full.location, selection.length == full.length {
        return NSRange(location: open.location, length: content.length)
    }

    let start = adjustedPosition(selection.location, removing: [open, close])
    let end = adjustedPosition(NSMaxRange(selection), removing: [open, close])
    return NSRange(location: start, length: max(0, end - start))
}

private func adjustedPosition(_ position: Int, removing ranges: [NSRange]) -> Int {
    var adjusted = position
    for range in ranges.sorted(by: { $0.location < $1.location }) {
        if position <= range.location {
            continue
        } else if position <= NSMaxRange(range) {
            adjusted -= position - range.location
        } else {
            adjusted -= range.length
        }
    }
    return max(0, adjusted)
}

private func range(_ range: NSRange, isContainedIn container: NSRange) -> Bool {
    range.location >= container.location && NSMaxRange(range) <= NSMaxRange(container)
}

// MARK: Line-prefix toggle helper

private enum LineMarkerKind: Hashable {
    case heading(level: Int)
    case paragraph
    case bullet
    case numbered
    case task
    case blockquote
}

private func toggleLinePrefix(_ target: LineMarkerKind,
                              in source: String,
                              selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    let selection = MarkdownSyntax.clamped(selection, length: ns.length)
    let lineRanges = MarkdownSyntax.lineRanges(in: ns, selection: selection)
    guard !lineRanges.isEmpty else { return (source, selection) }

    let lineKinds = lineRanges.map { range -> LineMarkerKind? in
        let raw = ns.substring(with: range)
        let lineContent = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
        return detectLineMarkerKind(in: lineContent)
    }
    let removingTarget = target != .paragraph && lineKinds.allSatisfy { $0 == target }
    var result = ns
    var newStart = selection.location
    var newEnd = NSMaxRange(selection)

    for lineRange in lineRanges.reversed() {
        let raw = ns.substring(with: lineRange)
        let lineContent = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
        let existingLen = detectLinePrefixLength(in: lineContent)
        let lineStart = lineRange.location
        let stripRange = NSRange(location: lineStart, length: existingLen)
        let newPrefix = removingTarget ? "" : renderPrefix(target)
        result = result.replacingCharacters(in: stripRange, with: newPrefix) as NSString

        let newPrefixLen = (newPrefix as NSString).length
        newStart = adjustedPosition(newStart,
                                    replacing: stripRange,
                                    replacementLength: newPrefixLen)
        newEnd = adjustedPosition(newEnd,
                                  replacing: stripRange,
                                  replacementLength: newPrefixLen)
    }

    return (result as String,
            NSRange(location: newStart, length: max(0, newEnd - newStart)))
}

private func adjustedPosition(_ position: Int,
                              replacing range: NSRange,
                              replacementLength: Int) -> Int {
    if position <= range.location {
        return position
    }
    if position <= NSMaxRange(range) {
        return range.location + replacementLength
    }
    return position + replacementLength - range.length
}

private func detectLinePrefixLength(in line: String) -> Int {
    // Heading `# `…`###### `
    let chars = Array(line)
    var hashes = 0
    while hashes < chars.count, chars[hashes] == "#" { hashes += 1 }
    if hashes >= 1, hashes <= 6,
       hashes < chars.count, chars[hashes] == " " {
        return hashes + 1
    }
    if let marker = ListMarker.detect(in: line) {
        // For prefix-toggle purposes we strip the entire marker
        // including the trailing space. Leading indent is preserved
        // by NOT being part of the strip (we strip from line start +
        // indent ... line start + contentStart).
        // To keep the algorithm simple here we strip the WHOLE prefix
        // including indent — toolbar toggle resets indent too.
        return marker.contentStart
    }
    return 0
}

private func detectLineMarkerKind(in line: String) -> LineMarkerKind? {
    let chars = Array(line)
    var hashes = 0
    while hashes < chars.count, chars[hashes] == "#" { hashes += 1 }
    if hashes >= 1, hashes <= 6,
       hashes < chars.count, chars[hashes] == " " {
        return .heading(level: hashes)
    }
    if let marker = ListMarker.detect(in: line) {
        switch marker.kind {
        case .bullet:      return .bullet
        case .task:        return .task
        case .numbered:    return .numbered
        case .blockquote:  return .blockquote
        }
    }
    return nil
}

private func renderPrefix(_ kind: LineMarkerKind) -> String {
    switch kind {
    case .heading(let level):  return String(repeating: "#", count: level) + " "
    case .paragraph:           return ""
    case .bullet:              return "- "
    case .numbered:            return "1. "
    case .task:                return "- [ ] "
    case .blockquote:          return "> "
    }
}

// MARK: Other inserts

private func insertLink(source: String,
                        selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    if selection.length == 0 {
        let insert = "[link text](url)"
        let newSource = ns.replacingCharacters(in: selection, with: insert)
        return (newSource,
                NSRange(location: selection.location + 1, length: 9))
    }
    let text = ns.substring(with: selection)
    let wrapped = "[\(text)](url)"
    let newSource = ns.replacingCharacters(in: selection, with: wrapped)
    // Place caret on the `url` placeholder (select it).
    let urlLocation = selection.location + 1 + (text as NSString).length + 2
    return (newSource, NSRange(location: urlLocation, length: 3))
}

private func insertImage(source: String,
                         selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    let alt = selection.length > 0 ? ns.substring(with: selection) : "alt text"
    let insert = "![\(alt)](path)"
    let newSource = ns.replacingCharacters(in: selection, with: insert)
    let pathLocation = selection.location + 4 + (alt as NSString).length
    return (newSource,
            NSRange(location: pathLocation, length: 4))
}

private func insertHorizontalRule(source: String,
                                  selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    let prefix = needsLeadingNewline(in: source, at: selection.location) ? "\n" : ""
    // Always emit a trailing newline so the caret lands on a fresh
    // empty line ready for typing.
    let insert = prefix + "---\n"
    let newSource = ns.replacingCharacters(in: selection, with: insert)
    let newCaret = selection.location + (insert as NSString).length
    return (newSource, NSRange(location: newCaret, length: 0))
}

private func wrapBlock(opener: String,
                       closer: String,
                       source: String,
                       selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    let inner = selection.length > 0 ? ns.substring(with: selection) : ""
    let leading = needsLeadingNewline(in: source, at: selection.location) ? "\n" : ""
    let trailing = needsTrailingNewline(in: source, at: selection.location + selection.length) ? "\n" : ""
    let insert = leading + opener + inner + closer + trailing
    let newSource = ns.replacingCharacters(in: selection, with: insert)
    // Place caret inside the block, after the opener fence + its
    // trailing newline.
    let openerOffset = (leading as NSString).length + (opener as NSString).length
    let newCaret = selection.location + openerOffset + (inner as NSString).length
    return (newSource, NSRange(location: newCaret, length: 0))
}

private func insertCodeBlock(source: String,
                             selection: NSRange) -> (source: String, selection: NSRange) {
    let placeholder = selection.length > 0 ? nil : "code"
    return insertBlock(opener: "```\n",
                       fallbackBody: placeholder,
                       closer: "\n```",
                       source: source,
                       selection: selection)
}

private func insertInlineMath(source: String,
                              selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    if selection.length == 0 {
        let insert = "$x$"
        let newSource = ns.replacingCharacters(in: selection, with: insert)
        return (newSource, NSRange(location: selection.location + 1, length: 1))
    }
    return toggleInline(action: .mathInline, marker: "$", source: source, selection: selection)
}

private func insertDisplayMath(source: String,
                               selection: NSRange) -> (source: String, selection: NSRange) {
    return insertBlock(opener: "$$\n",
                       fallbackBody: "x = y",
                       closer: "\n$$",
                       source: source,
                       selection: selection)
}

private func insertMermaid(source: String,
                           selection: NSRange) -> (source: String, selection: NSRange) {
    return insertBlock(opener: "```mermaid\n",
                       fallbackBody: "graph TD\n    A[Start] --> B[Next]",
                       closer: "\n```",
                       source: source,
                       selection: selection)
}

private func insertBlock(opener: String,
                         fallbackBody: String?,
                         closer: String,
                         source: String,
                         selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    let body = selection.length > 0 ? ns.substring(with: selection) : (fallbackBody ?? "")
    let leading = needsLeadingNewline(in: source, at: selection.location) ? "\n" : ""
    let trailing = needsTrailingNewline(in: source, at: selection.location + selection.length) ? "\n" : ""
    let insert = leading + opener + body + closer + trailing
    let newSource = ns.replacingCharacters(in: selection, with: insert)
    let bodyLocation = selection.location + (leading as NSString).length + (opener as NSString).length
    return (newSource, NSRange(location: bodyLocation, length: (body as NSString).length))
}

private func insertTable(source: String,
                         selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    let leading = needsLeadingNewline(in: source, at: selection.location) ? "\n" : ""
    let trailing = needsTrailingNewline(in: source, at: selection.location + selection.length) ? "\n" : ""
    let firstHeader = selection.length > 0 ? ns.substring(with: selection) : "Column 1"
    let rendered = MarkdownTableParser.render(
        header: [firstHeader, "Column 2"],
        alignments: [.none, .none],
        bodyRows: [["Cell A", "Cell B"]]
    )
    let template = leading + rendered.source + trailing
    let newSource = ns.replacingCharacters(in: selection, with: template)
    let firstCellRange = rendered.cellRanges.first?.first ?? NSRange(location: 2, length: (firstHeader as NSString).length)
    return (
        newSource,
        NSRange(location: selection.location + (leading as NSString).length + firstCellRange.location,
                length: firstCellRange.length)
    )
}

private func insertWikilink(source: String,
                            selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    if selection.length == 0 {
        let insert = "[[Page]]"
        let newSource = ns.replacingCharacters(in: selection, with: insert)
        return (newSource,
                NSRange(location: selection.location + 2, length: 4))
    }
    let text = ns.substring(with: selection)
    let wrapped = "[[\(text)]]"
    let newSource = ns.replacingCharacters(in: selection, with: wrapped)
    return (newSource,
            NSRange(location: selection.location + 2, length: (text as NSString).length))
}

private func insertFootnote(source: String,
                            selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    let id = nextFootnoteId(in: source)
    let ref = "[^\(id)]"
    let selectedText = selection.length > 0 ? ns.substring(with: selection) : ""
    let replacement = selectedText + ref
    let newSource = ns.replacingCharacters(in: selection, with: replacement)
    let caret = selection.location + (replacement as NSString).length
    let updated = newSource as NSString
    let appended: String
    if !newSource.contains("\n[^\(id)]:") {
        let needsLeading = updated.length > 0
            && updated.substring(with: NSRange(location: updated.length - 1, length: 1)) != "\n"
            ? "\n\n"
            : "\n"
        appended = newSource + "\(needsLeading)[^\(id)]: "
    } else {
        appended = newSource
    }
    return (appended, NSRange(location: caret, length: 0))
}

private func nextFootnoteId(in source: String) -> Int {
    var candidate = 1
    while source.contains("[^\(candidate)]") || source.contains("[^\(candidate)]:") {
        candidate += 1
    }
    return candidate
}

private func needsLeadingNewline(in source: String, at location: Int) -> Bool {
    let ns = source as NSString
    guard location > 0 else { return false }
    let prev = ns.substring(with: NSRange(location: location - 1, length: 1))
    return prev != "\n"
}

private func needsTrailingNewline(in source: String, at location: Int) -> Bool {
    let ns = source as NSString
    guard location < ns.length else { return false }
    let next = ns.substring(with: NSRange(location: location, length: 1))
    return next != "\n"
}
