import Foundation

/// Paste handling for the markdown editor.
///
/// The pure entry point (`apply`) takes a String payload — pasteboard
/// resolution (URL, image, rich text) happens UI-side in the
/// coordinator and is resolved to a markdown String before reaching
/// here.
///
/// Source-verbatim invariants enforced by `normalize`:
/// - **No smart-typography mutation.** `"` stays `"`, `--` stays `--`,
///   `...` stays `...`. The editor turns smart-quotes / smart-dashes /
///   ellipsis / smart-insert-delete OFF on its `UITextView`; this
///   helper makes the same guarantee for the paste path.
/// - **CRLF → LF.** Pasting from Windows-source text doesn't leave
///   stray `\r` chars in the source.
/// - **Bare CR → LF.** Pasting from classic-Mac-source text normalises.
/// - **Tab → 4 spaces.** Matches the editor's indent unit.
/// - **Leading BOM stripped.**
///
/// Auto-continuation suppression: pastes never trigger list-marker
/// auto-continuation. The `EditorIntent.paste` dispatch path bypasses
/// `ListContinuation` entirely; we don't call it from here.
enum PasteHandler {
    static func apply(_ pasted: String,
                      to source: String,
                      selection: NSRange) -> (source: String, selection: NSRange) {
        let normalized = normalize(pasted)
        let ns = source as NSString
        let newSource = ns.replacingCharacters(in: selection, with: normalized)
        let normalizedLen = (normalized as NSString).length
        let newCaret = selection.location + normalizedLen
        return (newSource, NSRange(location: newCaret, length: 0))
    }

    /// Source-verbatim normalisation. Public for the coordinator's
    /// pasteboard resolution path so URL/image conversions can also
    /// pass their generated markdown through it.
    static func normalize(_ pasted: String) -> String {
        var s = pasted
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")
        s = s.replacingOccurrences(of: "\t", with: "    ")
        return s
    }
}
