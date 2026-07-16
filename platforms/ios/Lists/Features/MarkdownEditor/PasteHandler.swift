import Foundation

/// Paste handling for the markdown editor.
///
/// Pasteboard resolution (URL, image, rich text) happens UI-side in the
/// coordinator. Text and URL payloads then come through this pure transform so
/// selection replacement, table recognition, and caret placement stay covered
/// without depending on the process-wide pasteboard.
///
/// Source-verbatim invariants enforced by `normalize`:
/// - **No smart-typography mutation.** `"` stays `"`, `--` stays `--`,
///   `...` stays `...`. The editor turns smart-quotes / smart-dashes /
///   ellipsis / smart-insert-delete OFF on its `UITextView`; this
///   helper makes the same guarantee for the paste path.
/// - **CRLF → LF.** Pasting from Windows-source text doesn't leave
///   stray `\r` chars in the source.
/// - **Bare CR → LF.** Pasting from classic-Mac-source text normalises.
/// - **Tab → 4 spaces** for ordinary text. Rectangular tab-separated data is
///   promoted to a portable GFM table before this fallback is applied.
/// - **Leading BOM stripped.**
///
/// Auto-continuation suppression: pastes never trigger list-marker
/// auto-continuation. The `EditorIntent.paste` dispatch path bypasses
/// `ListContinuation` entirely; we don't call it from here.
enum PasteHandler {
    enum Payload: Equatable {
        case text(String)
        case url(URL)
    }

    static func apply(_ pasted: String,
                      to source: String,
                      selection: NSRange) -> (source: String, selection: NSRange) {
        apply(.text(pasted), to: source, selection: selection)
    }

    static func apply(_ payload: Payload,
                      to source: String,
                      selection proposedSelection: NSRange) -> (source: String, selection: NSRange) {
        let ns = source as NSString
        let selection = MarkdownSyntax.clamped(proposedSelection, length: ns.length)

        switch payload {
        case .url(let url):
            let destination = safeLinkDestination(url.absoluteString)
            let replacement: String
            if selection.length > 0 {
                let label = markdownLinkLabel(ns.substring(with: selection))
                replacement = "[\(label)](\(destination))"
            } else {
                // A bare URL remains bare. Lists already recognizes ordinary
                // prose URLs, and paste should not rewrite source needlessly.
                replacement = url.absoluteString
            }
            return replacing(selection, in: ns, with: replacement)

        case .text(let pasted):
            let lineNormalized = normalizeLineEndings(pasted)
            if let table = tableSource(from: lineNormalized) {
                return replacingWithBlock(table, selection: selection, in: ns)
            }
            return replacing(selection, in: ns, with: normalize(lineNormalized))
        }
    }

    /// Source-verbatim normalisation. Public for the coordinator's
    /// pasteboard resolution path so URL/image conversions can also
    /// pass their generated markdown through it.
    static func normalize(_ pasted: String) -> String {
        var s = normalizeLineEndings(pasted)
        s = s.replacingOccurrences(of: "\t", with: "    ")
        return s
    }

    /// Converts a rectangular TSV payload into a GFM table. The first pasted
    /// row becomes the header, matching spreadsheet copy semantics. Ragged or
    /// malformed quoted data returns nil and follows the ordinary text path.
    static func tableSource(from pasted: String) -> String? {
        guard pasted.contains("\t"), let rows = parseTSV(pasted) else { return nil }
        guard let first = rows.first,
              first.count >= 2,
              rows.allSatisfy({ $0.count == first.count }),
              rows.joined().contains(where: { !$0.isEmpty }) else {
            return nil
        }
        return MarkdownTableParser.render(
            header: first,
            alignments: Array(repeating: .none, count: first.count),
            bodyRows: Array(rows.dropFirst())
        ).source
    }

    private static func normalizeLineEndings(_ pasted: String) -> String {
        var result = pasted
        if result.hasPrefix("\u{FEFF}") { result.removeFirst() }
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")
        return result
    }

    private static func replacing(_ selection: NSRange,
                                  in source: NSString,
                                  with replacement: String) -> (source: String, selection: NSRange) {
        let updated = source.replacingCharacters(in: selection, with: replacement)
        return (
            updated,
            NSRange(
                location: selection.location + (replacement as NSString).length,
                length: 0
            )
        )
    }

    private static func replacingWithBlock(_ block: String,
                                           selection: NSRange,
                                           in source: NSString) -> (source: String, selection: NSRange) {
        let selectionEnd = NSMaxRange(selection)
        let needsLeadingNewline = selection.location > 0
            && source.substring(with: NSRange(location: selection.location - 1, length: 1)) != "\n"
        let needsTrailingNewline = selectionEnd < source.length
            && source.substring(with: NSRange(location: selectionEnd, length: 1)) != "\n"
        let replacement = (needsLeadingNewline ? "\n" : "")
            + block
            + (needsTrailingNewline ? "\n" : "")
        return replacing(selection, in: source, with: replacement)
    }

    private static func markdownLinkLabel(_ selected: String) -> String {
        selected
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "[", with: "&#91;")
            .replacingOccurrences(of: "]", with: "&#93;")
    }

    private static func safeLinkDestination(_ destination: String) -> String {
        destination
            .replacingOccurrences(of: "\\", with: "%5C")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
    }

    private static func parseTSV(_ source: String) -> [[String]]? {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var closedQuote = false
        var endedWithRowBreak = false
        var index = source.startIndex

        func appendField() {
            row.append(field)
            field = ""
            closedQuote = false
        }

        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)

            if inQuotes {
                if character == "\"" {
                    if next < source.endIndex, source[next] == "\"" {
                        field.append("\"")
                        index = source.index(after: next)
                        endedWithRowBreak = false
                        continue
                    }
                    inQuotes = false
                    closedQuote = true
                } else {
                    field.append(character)
                }
                endedWithRowBreak = false
                index = next
                continue
            }

            switch character {
            case "\"" where field.isEmpty && !closedQuote:
                inQuotes = true
                endedWithRowBreak = false
            case "\t":
                appendField()
                endedWithRowBreak = false
            case "\n":
                appendField()
                rows.append(row)
                row = []
                endedWithRowBreak = true
            default:
                guard !closedQuote else { return nil }
                field.append(character)
                endedWithRowBreak = false
            }
            index = next
        }

        guard !inQuotes else { return nil }
        if !endedWithRowBreak {
            appendField()
            rows.append(row)
        }
        return rows
    }
}
