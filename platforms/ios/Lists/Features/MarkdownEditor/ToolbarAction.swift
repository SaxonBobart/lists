import Foundation

/// Buttons exposed in the Apple Reminders-style keyboard accessory
/// toolbar. Each case maps 1:1 to a pure `apply(to:selection:)`
/// transform — the same transform that test cases drive directly.
///
/// Toolbar layout & visual fidelity live in `MarkdownReminderToolbar`;
/// the logic of each button lives here.
///
/// P4 fills in the bodies. For now this is the shape only.
enum ToolbarAction: Hashable, Sendable {
    // Text formatting
    case bold
    case italic
    case strikethrough
    case highlight

    // Headings
    case heading(Int)        // 1...6; 0 means paragraph
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
        // Stub: passthrough. P4 fills in each case.
        return (source, selection)
    }

    /// Accessibility id used by the toolbar SwiftUI view + L3 UI
    /// tests. Keeping the mapping next to the enum keeps the two
    /// from drifting.
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
