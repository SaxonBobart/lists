import Foundation

/// Shared detection helpers for extended markdown constructs:
///   * Wikilinks  `[[Page]]` / `[[Page|alias]]`
///   * Footnotes  `[^id]` (ref) and `[^id]: text` (def, line-start)
///   * Math       `$x$` (inline) / `$$x$$` (display)
///   * Mermaid    ```` ```mermaid \n ... \n ``` ````
///
/// `MarkdownStyler` calls these to surface attributes (live editor
/// display); the renderer (MarkdownUI extension layer) calls them
/// for tap targets and rendered display. Centralising the regex /
/// range-finding here keeps the editor and renderer in lock-step.
enum ExtensionParsers {
    /// A detected construct in the source, exposing both the full
    /// delimited range and the inner content range.
    struct Range: Hashable, Sendable {
        let full: NSRange
        let inner: NSRange
    }

    // MARK: Wikilinks

    static func wikilinkRanges(in source: String) -> [Range] {
        matches(for: wikilinkRegex, in: source)
    }

    private static let wikilinkRegex: NSRegularExpression = {
        // [[Page]] or [[Page|alias]]
        try! NSRegularExpression(pattern: #"\[\[([^\[\]\n]+)\]\]"#)
    }()

    // MARK: Footnotes

    static func footnoteRefRanges(in source: String) -> [Range] {
        matches(for: footnoteRefRegex, in: source)
    }

    static func footnoteDefRanges(in source: String) -> [Range] {
        matches(for: footnoteDefRegex, in: source)
    }

    private static let footnoteRefRegex: NSRegularExpression = {
        // `[^id]` NOT followed by `:` (that's a def).
        try! NSRegularExpression(pattern: #"\[\^([A-Za-z0-9_-]+)\](?!:)"#)
    }()

    private static let footnoteDefRegex: NSRegularExpression = {
        // `[^id]:` at line start.
        try! NSRegularExpression(pattern: #"^\[\^([A-Za-z0-9_-]+)\]:"#,
                                 options: [.anchorsMatchLines])
    }()

    // MARK: Math

    static func mathInlineRanges(in source: String) -> [Range] {
        matches(for: mathInlineRegex, in: source)
    }

    static func mathDisplayRanges(in source: String) -> [Range] {
        matches(for: mathDisplayRegex, in: source)
    }

    private static let mathInlineRegex: NSRegularExpression = {
        // `$expr$` — single dollar pair, not part of `$$display$$`.
        // Negative look-around to avoid catching $$...$$ as inline.
        try! NSRegularExpression(pattern: #"(?<!\$)\$([^\$\n]+?)\$(?!\$)"#)
    }()

    private static let mathDisplayRegex: NSRegularExpression = {
        // `$$...$$` — can span multiple lines.
        try! NSRegularExpression(pattern: #"\$\$([\s\S]+?)\$\$"#)
    }()

    // MARK: Mermaid

    static func mermaidBlockRanges(in source: String) -> [Range] {
        matches(for: mermaidBlockRegex, in: source)
    }

    private static let mermaidBlockRegex: NSRegularExpression = {
        // Code fence with `mermaid` language.
        try! NSRegularExpression(pattern: #"^```mermaid\s*\n([\s\S]+?)\n```"#,
                                 options: [.anchorsMatchLines])
    }()

    // MARK: Helpers

    private static func matches(for regex: NSRegularExpression,
                                in source: String) -> [Range] {
        let ns = source as NSString
        let range = NSRange(location: 0, length: ns.length)
        var out: [Range] = []
        regex.enumerateMatches(in: source, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            out.append(Range(full: match.range, inner: match.range(at: 1)))
        }
        return out
    }
}
