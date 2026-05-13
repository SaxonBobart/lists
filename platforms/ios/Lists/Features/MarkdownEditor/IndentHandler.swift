import Foundation

/// Tab / Shift-Tab indent and outdent for plain, list, blockquote,
/// and nested combos. Indent inserts 4 spaces at the start of the
/// current line's leading whitespace zone; outdent removes 4 leading
/// spaces if present. List items shift their marker prefix along
/// with the indent.
///
/// Public API: `indent(source:selection:)`, `outdent(source:selection:)`.
/// Both are pure transforms; P3 fills in the full matrix.
enum IndentHandler {
    static func indent(source: String,
                       selection: NSRange) -> (source: String, selection: NSRange) {
        return (source, selection)
    }

    static func outdent(source: String,
                        selection: NSRange) -> (source: String, selection: NSRange) {
        return (source, selection)
    }
}
