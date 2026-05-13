import Foundation

/// Smart Backspace and forward-Delete.
///
/// Backspace semantics (rebuild scope):
/// - At start of content of a list item — remove the entire row
///   (marker + content + trailing newline). The previous line stays.
/// - At start of content of a nested list item — outdent first; a
///   subsequent Backspace then joins with the prior content.
/// - At start of plain text below a list — join with the previous
///   line.
/// - Across a selection that spans multiple items — replace the
///   selection in one go; do not run marker logic per line.
///
/// Forward-Delete (Fn+Delete / Cmd+D) covers symmetric cases.
///
/// Public API: pure transforms returning `(source, selection)`. P3
/// fills in the matrix.
enum BackspaceHandler {
    static func applyBackspace(to source: String,
                               selection: NSRange) -> (source: String, selection: NSRange) {
        return (source, selection)
    }

    static func applyForwardDelete(to source: String,
                                   selection: NSRange) -> (source: String, selection: NSRange) {
        return (source, selection)
    }
}
