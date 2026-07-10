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

enum MarkdownSyntax {
    enum InlineKind: Hashable, Sendable {
        case bold
        case italic
        case strikethrough
        case code
        case highlight
        case mathInline

        var toolbarAction: ToolbarAction {
            switch self {
            case .bold: return .bold
            case .italic: return .italic
            case .strikethrough: return .strikethrough
            case .code: return .code
            case .highlight: return .highlight
            case .mathInline: return .mathInline
            }
        }
    }

    struct InlineSpan: Hashable, Sendable {
        let kind: InlineKind
        let fullRange: NSRange
        let contentRange: NSRange
        let openRange: NSRange
        let closeRange: NSRange
    }

    struct TableCell: Hashable, Sendable {
        let column: Int
        let segmentRange: NSRange
        let contentRange: NSRange
    }

    enum LineKind: Equatable, Sendable {
        case paragraph
        case heading(Int)
        case bullet
        case numbered
        case task
        case quote
    }

    static func clamped(_ range: NSRange, length: Int) -> NSRange {
        guard range.location != NSNotFound else { return NSRange(location: 0, length: 0) }
        let location = min(max(0, range.location), length)
        let maxLength = max(0, length - location)
        return NSRange(location: location, length: min(max(0, range.length), maxLength))
    }

    static func lineRanges(in source: NSString, selection: NSRange) -> [NSRange] {
        guard source.length > 0 else { return [] }
        let selection = clamped(selection, length: source.length)
        if selection.length == 0 {
            let probe = min(selection.location, max(0, source.length - 1))
            return [source.lineRange(for: NSRange(location: probe, length: 0))]
        }

        let lastTouched = min(source.length - 1, max(selection.location, NSMaxRange(selection) - 1))
        var cursor = selection.location
        var ranges: [NSRange] = []
        while cursor <= lastTouched {
            let line = source.lineRange(for: NSRange(location: min(cursor, source.length - 1), length: 0))
            ranges.append(line)
            let next = NSMaxRange(line)
            guard next > cursor else { break }
            cursor = next
        }
        return ranges
    }

    static func lineContent(in source: NSString, range: NSRange) -> String {
        var line = source.substring(with: range)
        while line.last == "\n" || line.last == "\r" {
            line.removeLast()
        }
        return line
    }

    static func lineKind(in line: String) -> LineKind {
        if let heading = headingLevel(in: line) {
            return .heading(heading)
        }
        if let marker = ListMarker.detect(in: line) {
            switch marker.kind {
            case .bullet:
                return .bullet
            case .numbered:
                return .numbered
            case .task:
                return .task
            case .blockquote:
                return .quote
            }
        }
        return .paragraph
    }

    static func headingLevel(in line: String) -> Int? {
        let chars = Array(line)
        var hashes = 0
        while hashes < chars.count, hashes < 6, chars[hashes] == "#" {
            hashes += 1
        }
        guard hashes > 0,
              hashes < chars.count,
              chars[hashes] == " " else {
            return nil
        }
        return hashes
    }

    static func inlineSpans(in source: String) -> [InlineSpan] {
        let ns = source as NSString
        guard ns.length > 0 else { return [] }

        var spans: [InlineSpan] = []

        let codeSpans = pairedSpans(kind: .code,
                                    marker: "`",
                                    in: ns,
                                    excludedFullRanges: [],
                                    disallowAdjacentSameMarker: false)
        spans.append(contentsOf: codeSpans)
        let codeRanges = codeSpans.map(\.fullRange)

        var boldItalicRanges: [NSRange] = []
        for marker in ["***", "___"] {
            let triples = tripleEmphasisSpans(marker: marker,
                                              in: ns,
                                              excludedFullRanges: codeRanges)
            boldItalicRanges.append(contentsOf: triples.map(\.fullRange))
            spans.append(contentsOf: triples)
        }

        let protectedForEmphasis = codeRanges + boldItalicRanges
        spans.append(contentsOf: pairedSpans(kind: .bold,
                                             marker: "**",
                                             in: ns,
                                             excludedFullRanges: protectedForEmphasis,
                                             disallowAdjacentSameMarker: true))
        spans.append(contentsOf: pairedSpans(kind: .bold,
                                             marker: "__",
                                             in: ns,
                                             excludedFullRanges: protectedForEmphasis,
                                             disallowAdjacentSameMarker: true))
        spans.append(contentsOf: pairedSpans(kind: .italic,
                                             marker: "*",
                                             in: ns,
                                             excludedFullRanges: protectedForEmphasis,
                                             disallowAdjacentSameMarker: true))
        spans.append(contentsOf: pairedSpans(kind: .italic,
                                             marker: "_",
                                             in: ns,
                                             excludedFullRanges: protectedForEmphasis,
                                             disallowAdjacentSameMarker: true))
        spans.append(contentsOf: pairedSpans(kind: .strikethrough,
                                             marker: "~~",
                                             in: ns,
                                             excludedFullRanges: codeRanges,
                                             disallowAdjacentSameMarker: true))
        spans.append(contentsOf: pairedSpans(kind: .highlight,
                                             marker: "==",
                                             in: ns,
                                             excludedFullRanges: codeRanges,
                                             disallowAdjacentSameMarker: true))
        spans.append(contentsOf: pairedSpans(kind: .mathInline,
                                             marker: "$",
                                             in: ns,
                                             excludedFullRanges: codeRanges,
                                             disallowAdjacentSameMarker: true))

        return spans.sorted {
            if $0.fullRange.location == $1.fullRange.location {
                return $0.fullRange.length > $1.fullRange.length
            }
            return $0.fullRange.location < $1.fullRange.location
        }
    }

    static func inlineSpan(for action: ToolbarAction,
                           in source: String,
                           selection: NSRange) -> InlineSpan? {
        guard let kind = inlineKind(for: action) else { return nil }
        let ns = source as NSString
        let selection = clamped(selection, length: ns.length)
        return inlineSpans(in: source)
            .filter { $0.kind == kind }
            .filter { spanContains($0, selection: selection) }
            .sorted {
                if $0.fullRange.length == $1.fullRange.length {
                    return $0.fullRange.location > $1.fullRange.location
                }
                return $0.fullRange.length < $1.fullRange.length
            }
            .first
    }

    static func inlineKind(for action: ToolbarAction) -> InlineKind? {
        switch action {
        case .bold: return .bold
        case .italic: return .italic
        case .strikethrough: return .strikethrough
        case .code: return .code
        case .highlight: return .highlight
        case .mathInline: return .mathInline
        default: return nil
        }
    }

    static func selection(_ selection: NSRange, isActiveIn spans: [InlineSpan]) -> Bool {
        guard !spans.isEmpty else { return false }
        if selection.length == 0 {
            return spans.contains {
                selection.location >= $0.contentRange.location
                    && selection.location <= NSMaxRange($0.contentRange)
            }
        }
        return range(selection, isCoveredBy: spans.map(\.contentRange))
            || range(selection, isCoveredBy: spans.map(\.fullRange))
    }

    static func tableBlockRanges(in source: String) -> [ExtensionParsers.Range] {
        MarkdownTableParser.tables(in: source).map {
            ExtensionParsers.Range(full: $0.fullRange, inner: $0.fullRange)
        }
    }

    static func isTableRow(_ line: String) -> Bool {
        MarkdownTableParser.isTableRow(line)
    }

    static func isTableDivider(_ line: String) -> Bool {
        MarkdownTableParser.isDividerRow(line)
    }

    static func tableCells(in line: String) -> [String] {
        MarkdownTableParser.cellTexts(in: line)
    }

    static func tableCells(in line: String, lineRange: NSRange) -> [TableCell] {
        MarkdownTableParser.cells(in: line, lineRange: lineRange).map {
            TableCell(column: $0.column,
                      segmentRange: $0.segmentRange,
                      contentRange: $0.contentRange)
        }
    }

    private static func spanContains(_ span: InlineSpan, selection: NSRange) -> Bool {
        if selection.length == 0 {
            return selection.location >= span.contentRange.location
                && selection.location <= NSMaxRange(span.contentRange)
        }
        return range(selection, isCoveredBy: [span.contentRange])
            || range(selection, isCoveredBy: [span.fullRange])
    }

    private static func pairedSpans(kind: InlineKind,
                                    marker: String,
                                    in ns: NSString,
                                    excludedFullRanges: [NSRange],
                                    disallowAdjacentSameMarker: Bool) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        let markerLength = (marker as NSString).length
        for lineRange in lineRanges(in: ns, selection: NSRange(location: 0, length: ns.length)) {
            let line = lineContent(in: ns, range: lineRange) as NSString
            var searchLocation = 0
            while searchLocation < line.length {
                let remaining = NSRange(location: searchLocation, length: line.length - searchLocation)
                let open = line.range(of: marker, options: [], range: remaining)
                guard open.location != NSNotFound else { break }

                let absoluteOpen = NSRange(location: lineRange.location + open.location,
                                           length: open.length)
                if isRangeStart(absoluteOpen, insideAny: excludedFullRanges)
                    || (disallowAdjacentSameMarker && hasAdjacentSameMarker(marker, around: open, in: line)) {
                    searchLocation = NSMaxRange(open)
                    continue
                }

                let contentStart = NSMaxRange(open)
                var closeSearchLocation = contentStart
                var close: NSRange?
                while closeSearchLocation < line.length {
                    let closeSearch = NSRange(location: closeSearchLocation,
                                              length: line.length - closeSearchLocation)
                    let candidate = line.range(of: marker, options: [], range: closeSearch)
                    guard candidate.location != NSNotFound else { break }
                    let absoluteClose = NSRange(location: lineRange.location + candidate.location,
                                                length: candidate.length)
                    if !isRangeStart(absoluteClose, insideAny: excludedFullRanges)
                        && !(disallowAdjacentSameMarker && hasAdjacentSameMarker(marker, around: candidate, in: line))
                        && candidate.location > contentStart {
                        close = candidate
                        break
                    }
                    closeSearchLocation = NSMaxRange(candidate)
                }

                guard let close else { break }
                let content = NSRange(location: lineRange.location + contentStart,
                                      length: close.location - contentStart)
                spans.append(InlineSpan(
                    kind: kind,
                    fullRange: NSRange(location: absoluteOpen.location,
                                       length: NSMaxRange(close) + lineRange.location - absoluteOpen.location),
                    contentRange: content,
                    openRange: absoluteOpen,
                    closeRange: NSRange(location: lineRange.location + close.location,
                                        length: markerLength)
                ))
                searchLocation = NSMaxRange(close)
            }
        }
        return spans
    }

    private static func tripleEmphasisSpans(marker: String,
                                            in ns: NSString,
                                            excludedFullRanges: [NSRange]) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        let markerLength = (marker as NSString).length
        for lineRange in lineRanges(in: ns, selection: NSRange(location: 0, length: ns.length)) {
            let line = lineContent(in: ns, range: lineRange) as NSString
            var searchLocation = 0
            while searchLocation < line.length {
                let remaining = NSRange(location: searchLocation, length: line.length - searchLocation)
                let open = line.range(of: marker, options: [], range: remaining)
                guard open.location != NSNotFound else { break }
                let absoluteOpen = NSRange(location: lineRange.location + open.location,
                                           length: markerLength)
                if isRangeStart(absoluteOpen, insideAny: excludedFullRanges) {
                    searchLocation = NSMaxRange(open)
                    continue
                }

                let contentStart = NSMaxRange(open)
                let closeSearch = NSRange(location: contentStart, length: line.length - contentStart)
                let close = line.range(of: marker, options: [], range: closeSearch)
                guard close.location != NSNotFound, close.location > contentStart else { break }

                let absoluteClose = NSRange(location: lineRange.location + close.location,
                                            length: markerLength)
                if isRangeStart(absoluteClose, insideAny: excludedFullRanges) {
                    searchLocation = NSMaxRange(close)
                    continue
                }

                let content = NSRange(location: lineRange.location + contentStart,
                                      length: close.location - contentStart)
                let full = NSRange(location: absoluteOpen.location,
                                   length: NSMaxRange(absoluteClose) - absoluteOpen.location)

                spans.append(InlineSpan(
                    kind: .bold,
                    fullRange: full,
                    contentRange: content,
                    openRange: NSRange(location: absoluteOpen.location, length: 2),
                    closeRange: NSRange(location: absoluteClose.location + 1, length: 2)
                ))
                spans.append(InlineSpan(
                    kind: .italic,
                    fullRange: full,
                    contentRange: content,
                    openRange: NSRange(location: absoluteOpen.location + 2, length: 1),
                    closeRange: NSRange(location: absoluteClose.location, length: 1)
                ))

                searchLocation = NSMaxRange(close)
            }
        }
        return spans
    }

    private static func hasAdjacentSameMarker(_ marker: String, around range: NSRange, in line: NSString) -> Bool {
        let markerLength = (marker as NSString).length
        guard markerLength == 1 else {
            let before = range.location > 0
                && line.substring(with: NSRange(location: range.location - 1, length: 1)) == String(marker.first!)
            let after = NSMaxRange(range) < line.length
                && line.substring(with: NSRange(location: NSMaxRange(range), length: 1)) == String(marker.first!)
            return before || after
        }
        let before = range.location > 0
            && line.substring(with: NSRange(location: range.location - 1, length: 1)) == marker
        let after = NSMaxRange(range) < line.length
            && line.substring(with: NSRange(location: NSMaxRange(range), length: 1)) == marker
        return before || after
    }

    private static func isRangeStart(_ range: NSRange, insideAny ranges: [NSRange]) -> Bool {
        ranges.contains { NSLocationInRange(range.location, $0) }
    }

    private static func range(_ range: NSRange, isCoveredBy coveredRanges: [NSRange]) -> Bool {
        var cursor = range.location
        let end = NSMaxRange(range)
        for covered in coveredRanges.sorted(by: { $0.location < $1.location }) {
            guard cursor < end else { return true }
            if NSMaxRange(covered) <= cursor { continue }
            if covered.location > cursor { return false }
            cursor = max(cursor, NSMaxRange(covered))
        }
        return cursor >= end
    }
}
