import Foundation

/// Smart Return: when the caret is at the end of a list / task /
/// numbered / blockquote item, the next line auto-continues with the
/// same marker (and the same leading indent). When the caret is on
/// an *empty* list item, Return exits the list.
///
/// Public API: `apply(to:selection:)` is the dispatch entry. It is
/// a pure transform — no `UITextView`, no shared state.
///
/// P3 fills in the matrix. For now this is a no-op passthrough so the
/// coordinator can wire to it without changing UITextView's default
/// Return behaviour.
enum ListContinuation {
    static func apply(to source: String,
                      selection: NSRange) -> (source: String, selection: NSRange) {
        // Stub: passthrough. Tests in MarkdownEditorBehaviorTests will be red.
        return (source, selection)
    }
}
