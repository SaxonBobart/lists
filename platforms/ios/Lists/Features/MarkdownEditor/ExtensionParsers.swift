import Foundation

/// Shared detection helpers for the previously-deferred markdown
/// constructs:
///   * Wikilinks  `[[Page]]` / `[[Page|alias]]`
///   * Footnotes  `[^id]` / `[^id]: text`
///   * Math       `$x$` (inline) / `$$x$$` (display)
///   * Mermaid    ```` ```mermaid \n ... \n ``` ````
///
/// `MarkdownStyler` calls these to surface attributes; the renderer
/// (MarkdownUI extension layer) calls them for tap targets and
/// rendered display. Centralising the regex / range-finding here
/// keeps the editor and renderer in lock-step.
///
/// P7 implements; this file is a placeholder so the build wires up.
enum ExtensionParsers {
    struct Range {
        let full: NSRange
        let inner: NSRange
    }

    static func wikilinkRanges(in source: String) -> [Range] { [] }
    static func footnoteRefRanges(in source: String) -> [Range] { [] }
    static func footnoteDefRanges(in source: String) -> [Range] { [] }
    static func mathInlineRanges(in source: String) -> [Range] { [] }
    static func mathDisplayRanges(in source: String) -> [Range] { [] }
    static func mermaidBlockRanges(in source: String) -> [Range] { [] }
}
