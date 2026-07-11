import Foundation

/// Smart Backspace and forward-Delete.
///
/// Backspace semantics:
/// - **At content start of a nested list item** — outdent the line by
///   one editor indent level.
/// - **At content start of a top-level list item** — strip the marker
///   only, keeping the item on its own line as plain text.
/// - **Anywhere else** — default UIKit behaviour (delete one char
///   back, or replace selection).
///
/// Forward-Delete (Fn+Delete / Cmd+D) currently keeps UIKit's default
/// character-delete behavior.
enum BackspaceHandler {
    static func applyBackspace(to source: String,
                               selection: NSRange) -> (source: String, selection: NSRange) {
        guard selection.length == 0 else {
            return defaultBackspace(source: source, selection: selection)
        }
        let ns = source as NSString
        let caret = selection.location
        guard caret > 0 else { return (source, selection) }

        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        let raw = ns.substring(with: lineRange)
        let lineContent = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw

        guard let marker = ListMarker.detect(in: lineContent) else {
            return defaultBackspace(source: source, selection: selection)
        }

        let contentStartGlobal = lineRange.location + marker.contentStart
        guard caret == contentStartGlobal else {
            return defaultBackspace(source: source, selection: selection)
        }

        if case .blockquote(let depth) = marker.kind {
            let pad = String(repeating: " ", count: marker.indent)
            let replacement = depth > 1
                ? pad + String(repeating: "> ", count: depth - 1)
                : ""
            let removeRange = NSRange(location: lineRange.location,
                                      length: marker.contentStart)
            let newSource = ns.replacingCharacters(in: removeRange, with: replacement)
            return (newSource, NSRange(
                location: lineRange.location + (replacement as NSString).length,
                length: 0
            ))
        }

        if marker.indent > 0 {
            // Outdent: remove one indent level, or all available
            // leading spaces for partially-indented pasted Markdown.
            let outdentAmount = min(4, marker.indent)
            let removeRange = NSRange(location: lineRange.location, length: outdentAmount)
            let newSource = ns.replacingCharacters(in: removeRange, with: "")
            return (newSource, NSRange(location: caret - outdentAmount, length: 0))
        }

        // Top-level list item — strip marker only. Joining here turns
        // cursor navigation into content edits, e.g. `parentchild`.
        let removeRange = NSRange(location: lineRange.location, length: marker.contentStart)
        let newSource = ns.replacingCharacters(in: removeRange, with: "")
        return (newSource, NSRange(location: lineRange.location, length: 0))
    }

    static func applyForwardDelete(to source: String,
                                   selection: NSRange) -> (source: String, selection: NSRange) {
        return defaultForwardDelete(source: source, selection: selection)
    }

    // MARK: Defaults that mimic UIKit's built-in behaviour

    private static func defaultBackspace(source: String,
                                         selection: NSRange) -> (source: String, selection: NSRange) {
        let ns = source as NSString
        if selection.length > 0 {
            let newSource = ns.replacingCharacters(in: selection, with: "")
            return (newSource, NSRange(location: selection.location, length: 0))
        }
        guard selection.location > 0 else { return (source, selection) }
        let removeRange = NSRange(location: selection.location - 1, length: 1)
        let newSource = ns.replacingCharacters(in: removeRange, with: "")
        return (newSource, NSRange(location: selection.location - 1, length: 0))
    }

    private static func defaultForwardDelete(source: String,
                                             selection: NSRange) -> (source: String, selection: NSRange) {
        let ns = source as NSString
        if selection.length > 0 {
            let newSource = ns.replacingCharacters(in: selection, with: "")
            return (newSource, NSRange(location: selection.location, length: 0))
        }
        guard selection.location < ns.length else { return (source, selection) }
        let removeRange = NSRange(location: selection.location, length: 1)
        let newSource = ns.replacingCharacters(in: removeRange, with: "")
        return (newSource, selection)
    }
}
