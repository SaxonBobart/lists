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
            return wrapInline(marker: "**", source: source, selection: selection)
        case .italic:
            return wrapInline(marker: "*", source: source, selection: selection)
        case .strikethrough:
            return wrapInline(marker: "~~", source: source, selection: selection)
        case .highlight:
            return wrapInline(marker: "==", source: source, selection: selection)
        case .code:
            return wrapInline(marker: "`", source: source, selection: selection)
        case .mathInline:
            return wrapInline(marker: "$", source: source, selection: selection)

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
            return wrapBlock(opener: "```\n", closer: "\n```", source: source, selection: selection)
        case .mathDisplay:
            return wrapBlock(opener: "$$\n", closer: "\n$$", source: source, selection: selection)
        case .mermaid:
            return insertMermaid(source: source, selection: selection)
        case .table:
            return insertTable(source: source, selection: selection)
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

private func wrapInline(marker: String,
                        source: String,
                        selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    let markerLen = (marker as NSString).length

    if selection.length == 0 {
        // Insert empty `markermarker` and place caret inside.
        let insert = marker + marker
        let newSource = ns.replacingCharacters(in: selection, with: insert)
        return (newSource,
                NSRange(location: selection.location + markerLen, length: 0))
    }

    // Toggle off if the selection is exactly wrapped by the marker.
    let leftStart = selection.location - markerLen
    let rightStart = selection.location + selection.length
    if leftStart >= 0, rightStart + markerLen <= ns.length {
        let pre = ns.substring(with: NSRange(location: leftStart, length: markerLen))
        let post = ns.substring(with: NSRange(location: rightStart, length: markerLen))
        if pre == marker && post == marker {
            // Disambiguate single-char markers (italic `*` vs bold `**`,
            // inline code `\`` vs fence `\`\`\``) — strip only when the
            // adjacent char outside the marker pair is NOT the same.
            if markerLen == 1 {
                let leftIsDoubled =
                    (leftStart - 1 >= 0
                     && ns.substring(with: NSRange(location: leftStart - 1, length: 1)) == marker)
                let rightIsDoubled =
                    (rightStart + markerLen + 0 < ns.length
                     && ns.substring(with: NSRange(location: rightStart + markerLen, length: 1)) == marker)
                if leftIsDoubled || rightIsDoubled {
                    return wrapAdding(marker: marker, source: source, selection: selection)
                }
            }
            let removeRange = NSRange(location: leftStart,
                                      length: markerLen + selection.length + markerLen)
            let inner = ns.substring(with: selection)
            let newSource = ns.replacingCharacters(in: removeRange, with: inner)
            return (newSource,
                    NSRange(location: leftStart, length: selection.length))
        }
    }
    return wrapAdding(marker: marker, source: source, selection: selection)
}

private func wrapAdding(marker: String,
                        source: String,
                        selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    let markerLen = (marker as NSString).length
    let inner = ns.substring(with: selection)
    let wrapped = marker + inner + marker
    let newSource = ns.replacingCharacters(in: selection, with: wrapped)
    return (newSource,
            NSRange(location: selection.location + markerLen, length: selection.length))
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
    let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
    let raw = ns.substring(with: lineRange)
    let lineContent = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw

    // Compute the existing prefix length to strip (could be a heading,
    // a list marker, or none).
    let existingLen = detectLinePrefixLength(in: lineContent)
    let lineStart = lineRange.location
    let stripRange = NSRange(location: lineStart, length: existingLen)

    let newPrefix: String
    let isToggleOff: Bool
    if let existingKind = detectLineMarkerKind(in: lineContent),
       existingKind == target {
        // Toggle off: same kind → strip prefix completely.
        newPrefix = ""
        isToggleOff = true
    } else {
        newPrefix = renderPrefix(target)
        isToggleOff = false
    }

    let newSource = ns.replacingCharacters(in: stripRange, with: newPrefix)
    let newPrefixLen = (newPrefix as NSString).length
    let delta = newPrefixLen - existingLen
    let originalCaret = selection.location
    let newCaret: Int
    if originalCaret < lineStart + existingLen {
        // Caret was inside the prefix being replaced — land at the new
        // content start.
        newCaret = lineStart + newPrefixLen
    } else {
        newCaret = max(lineStart + newPrefixLen, originalCaret + delta)
    }
    _ = isToggleOff
    return (newSource, NSRange(location: newCaret, length: max(0, selection.length)))
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
        // `[](url)` with caret inside `[]`
        let insert = "[](url)"
        let newSource = ns.replacingCharacters(in: selection, with: insert)
        return (newSource,
                NSRange(location: selection.location + 1, length: 0))
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
    let insert = "![](path)"
    let newSource = ns.replacingCharacters(in: selection, with: insert)
    return (newSource,
            NSRange(location: selection.location + 2, length: 0))
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

private func insertMermaid(source: String,
                           selection: NSRange) -> (source: String, selection: NSRange) {
    return wrapBlock(opener: "```mermaid\n",
                     closer: "\n```",
                     source: source,
                     selection: selection)
}

private func insertTable(source: String,
                         selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    let leading = needsLeadingNewline(in: source, at: selection.location) ? "\n" : ""
    let template = """
\(leading)|  |  |
| --- | --- |
|  |  |
"""
    let newSource = ns.replacingCharacters(in: selection, with: template)
    // Caret lands inside the first header cell (after `| `).
    let cellStart = selection.location + (leading as NSString).length + 2
    return (newSource, NSRange(location: cellStart, length: 0))
}

private func insertWikilink(source: String,
                            selection: NSRange) -> (source: String, selection: NSRange) {
    let ns = source as NSString
    if selection.length == 0 {
        let insert = "[[]]"
        let newSource = ns.replacingCharacters(in: selection, with: insert)
        return (newSource,
                NSRange(location: selection.location + 2, length: 0))
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
    let ref = "[^1]"
    let newSource = ns.replacingCharacters(in: selection, with: ref)
    let caret = selection.location + (ref as NSString).length
    // Append definition at doc end if not already present.
    let updated = newSource as NSString
    let appended: String
    if !newSource.contains("\n[^1]:") {
        let needsLeading = updated.length > 0 && updated.substring(with: NSRange(location: updated.length - 1, length: 1)) != "\n"
            ? "\n\n"
            : "\n"
        appended = newSource + "\(needsLeading)[^1]: "
    } else {
        appended = newSource
    }
    return (appended, NSRange(location: caret, length: 0))
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
