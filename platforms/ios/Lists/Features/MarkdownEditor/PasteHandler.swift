import Foundation

/// Paste handling. Resolves a pasteboard payload to the source
/// + selection diff that should land in the editor.
///
/// Coverage (P5):
/// - Plain text — verbatim insert, line-ending normalisation,
///   smart-typography NOT applied (markdown source preservation).
/// - URL — wrap selection as `[text](url)` if selection non-empty;
///   else autolink `<url>`.
/// - Image — save to `Documents/Lists/Attachments/<uuid>.<ext>`;
///   insert `![](Attachments/<uuid>.<ext>)`.
/// - Rich text (NSAttributedString) — convert via attribute walker
///   to markdown source.
/// - Inside fenced code body — plain insert; never re-style.
///
/// Public API: `apply(_:to:selection:)`. Pure transform on plain
/// strings — the live-app version that touches `UIPasteboard` is
/// wired up by the coordinator and just resolves to a `String` then
/// calls into here.
enum PasteHandler {
    static func apply(_ pasted: String,
                      to source: String,
                      selection: NSRange) -> (source: String, selection: NSRange) {
        // Stub: passthrough — coordinator currently lets UIKit
        // handle paste via default behaviour (which is verbatim insert
        // already, since smart-typography is off on the text view).
        _ = pasted
        return (source, selection)
    }
}
