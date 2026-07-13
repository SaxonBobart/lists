import Foundation

/// A Markdown prose link with both its visible and source-level ranges.
///
/// Live Markdown presents only `labelRange` while the caret is outside the
/// link. Entering `markdownRange` reveals the complete source so the label or
/// destination can be edited like ordinary Markdown.
struct MarkdownInlineLink: Equatable, Sendable {
    let label: String
    let destination: String
    let labelRange: NSRange
    let destinationRange: NSRange
    let markdownRange: NSRange

    var url: URL? { URL(string: destination) }
    var isActionableProseLink: Bool {
        if DocumentMarkdownIndex.isPotentialInternalDestination(destination) { return true }
        guard let url, url.scheme != nil else { return false }
        return MarkdownAttachmentIndex.isSafeRelativePath(destination) == false
    }

    private static let regex = try! NSRegularExpression(
        pattern: #"(?<!!)(\[)([^\]\n]+)(\])(\()([^)\n]+)(\))"#
    )
    private static let bareURLRegex = try! NSRegularExpression(
        pattern: #"(?<![\(\[\w])https?://[^\s<>\)]+"#
    )
    private static let fencedCodeRegex = try! NSRegularExpression(
        pattern: #"(?ms)^```[^\n]*\n.*?^```[ \t]*(?:\n|$)"#
    )

    static func links(in source: String) -> [MarkdownInlineLink] {
        let ns = source as NSString
        let range = NSRange(location: 0, length: ns.length)
        let protectedRanges = MarkdownSyntax.inlineSpans(in: source)
            .filter { $0.kind == .code }
            .map(\.fullRange)
            + fencedCodeRegex.matches(in: source, range: range).map(\.range)
        var results: [MarkdownInlineLink] = regex.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges >= 7 else { return nil }
            guard protectedRanges.contains(where: {
                NSIntersectionRange($0, match.range).length > 0
            }) == false else { return nil }
            let labelRange = match.range(at: 2)
            let destinationRange = match.range(at: 5)
            return MarkdownInlineLink(
                label: ns.substring(with: labelRange),
                destination: ns.substring(with: destinationRange),
                labelRange: labelRange,
                destinationRange: destinationRange,
                markdownRange: match.range(at: 0)
            )
        }
        let occupied = results.map(\.markdownRange)
        for match in bareURLRegex.matches(in: source, range: range) {
            guard protectedRanges.contains(where: {
                NSIntersectionRange($0, match.range).length > 0
            }) == false,
            occupied.contains(where: {
                NSIntersectionRange($0, match.range).length > 0
            }) == false else { continue }
            let value = ns.substring(with: match.range)
            results.append(MarkdownInlineLink(
                label: value,
                destination: value,
                labelRange: match.range,
                destinationRange: match.range,
                markdownRange: match.range
            ))
        }
        return results.sorted { $0.markdownRange.location < $1.markdownRange.location }
    }

    static func link(containing characterIndex: Int,
                     in source: String) -> MarkdownInlineLink? {
        links(in: source).first {
            $0.isActionableProseLink && NSLocationInRange(characterIndex, $0.labelRange)
        }
    }

}
