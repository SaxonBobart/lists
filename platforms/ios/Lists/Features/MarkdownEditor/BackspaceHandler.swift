import Foundation

/// Smart Backspace and forward-Delete.
///
/// Backspace semantics:
/// - **At content start of a list item, line is nested (>=4 leading
///   spaces)** — outdent the line (remove 4 leading spaces).
/// - **At content start of a list item, line is the first line of
///   the document** — strip the marker only (line becomes plain).
/// - **At content start of a list item, line has a previous line** —
///   strip the marker AND the preceding newline (lines join). This
///   is the case Saxon hits most: "delete an item in the middle of
///   the list with backspace".
/// - **Anywhere else** — default UIKit behaviour (delete one char
///   back, or replace selection).
///
/// Forward-Delete (Fn+Delete / Cmd+D) is the symmetric case. P3
/// fills in the matrix once Backspace settles; for now it's the
/// default char delete.
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

        if marker.indent >= 4 {
            // Outdent: remove 4 leading spaces from the line.
            let removeRange = NSRange(location: lineRange.location, length: 4)
            let newSource = ns.replacingCharacters(in: removeRange, with: "")
            return (newSource, NSRange(location: caret - 4, length: 0))
        }

        if lineRange.location > 0 {
            // Strip marker + preceding newline → join with prev line.
            let deleteStart = lineRange.location - 1
            let deleteLength = 1 + marker.contentStart
            let removeRange = NSRange(location: deleteStart, length: deleteLength)
            let newSource = ns.replacingCharacters(in: removeRange, with: "")
            return (newSource, NSRange(location: deleteStart, length: 0))
        }

        // First line of document, no nesting — strip marker only.
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
