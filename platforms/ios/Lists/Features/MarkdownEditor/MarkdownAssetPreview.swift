import Foundation

enum MarkdownAssetPreviewStyle: String, Equatable, Sendable {
    case compact
    case large
}

/// A Canvas or image reference whose presentation can change without changing
/// the referenced resource. Compact references remain ordinary inline Markdown
/// links; large references occupy their own line and render as a preview.
struct MarkdownAssetPreviewReference: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case canvas
        case image
    }

    let kind: Kind
    let style: MarkdownAssetPreviewStyle
    let label: String
    let destination: String
    let markdownRange: NSRange
}

enum MarkdownAssetPreview {
    private static let imageEmbedRegex = try! NSRegularExpression(
        pattern: #"^!\[([^\]\n]*)\]\((Attachments/[^)\n]+)\)$"#
    )
    private static let canvasEmbedRegex = try! NSRegularExpression(
        pattern: #"^!\[\[([^\]\n]+\.canvas)(?:\|([^\]\n]+))?\]\]$"#,
        options: [.caseInsensitive]
    )

    static func reference(in source: String, selection rawSelection: NSRange) -> MarkdownAssetPreviewReference? {
        let ns = source as NSString
        let selection = MarkdownSyntax.clamped(rawSelection, length: ns.length)

        if let block = blockReference(in: ns, selection: selection) {
            return block
        }

        return MarkdownInlineLink.links(in: source).first { link in
            guard compactKind(for: link.destination) != nil else { return false }
            return selectionTouches(selection, range: link.markdownRange)
        }.flatMap { link in
            guard let kind = compactKind(for: link.destination) else { return nil }
            return MarkdownAssetPreviewReference(
                kind: kind,
                style: .compact,
                label: link.label,
                destination: link.destination,
                markdownRange: link.markdownRange
            )
        }
    }

    static func setting(
        _ style: MarkdownAssetPreviewStyle,
        in source: String,
        selection: NSRange
    ) -> (source: String, selection: NSRange) {
        guard let reference = reference(in: source, selection: selection),
              reference.style != style else {
            return (source, selection)
        }

        switch style {
        case .compact:
            return makeCompact(reference, in: source)
        case .large:
            return makeLarge(reference, in: source)
        }
    }

    private static func blockReference(
        in source: NSString,
        selection: NSRange
    ) -> MarkdownAssetPreviewReference? {
        guard source.length > 0 else { return nil }
        let probe = min(selection.location, source.length - 1)
        let lineRange = source.lineRange(for: NSRange(location: probe, length: 0))
        let hasNewline = lineRange.length > 0
            && source.character(at: NSMaxRange(lineRange) - 1) == 0x0A
        let contentRange = NSRange(
            location: lineRange.location,
            length: lineRange.length - (hasNewline ? 1 : 0)
        )
        let line = source.substring(with: contentRange)
        let full = NSRange(location: 0, length: (line as NSString).length)

        if let match = canvasEmbedRegex.firstMatch(in: line, range: full) {
            let destination = (line as NSString).substring(with: match.range(at: 1))
            let aliasRange = match.range(at: 2)
            let label = aliasRange.location == NSNotFound
                ? canvasLabel(for: destination)
                : (line as NSString).substring(with: aliasRange)
            return MarkdownAssetPreviewReference(
                kind: .canvas,
                style: .large,
                label: label,
                destination: destination,
                markdownRange: contentRange
            )
        }

        if let match = imageEmbedRegex.firstMatch(in: line, range: full) {
            return MarkdownAssetPreviewReference(
                kind: .image,
                style: .large,
                label: (line as NSString).substring(with: match.range(at: 1)),
                destination: (line as NSString).substring(with: match.range(at: 2)),
                markdownRange: contentRange
            )
        }
        return nil
    }

    private static func compactKind(for destination: String) -> MarkdownAssetPreviewReference.Kind? {
        let path = destination
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? destination
        let decoded = path.removingPercentEncoding ?? path
        let scheme = URL(string: destination)?.scheme?.lowercased()
        if (scheme == nil || scheme == "lists"),
           (decoded as NSString).pathExtension.caseInsensitiveCompare("canvas") == .orderedSame {
            return .canvas
        }
        if MarkdownAttachmentIndex.isSafeRelativePath(destination) {
            return .image
        }
        return nil
    }

    private static func selectionTouches(_ selection: NSRange, range: NSRange) -> Bool {
        if selection.length > 0 {
            return NSIntersectionRange(selection, range).length > 0
        }
        return selection.location >= range.location && selection.location <= NSMaxRange(range)
    }

    private static func makeCompact(
        _ reference: MarkdownAssetPreviewReference,
        in source: String
    ) -> (source: String, selection: NSRange) {
        let replacement = DocumentMarkdownLinkBuilder.markdownLink(
            label: reference.label,
            destination: reference.destination
        )
        let updated = (source as NSString).replacingCharacters(
            in: reference.markdownRange,
            with: replacement
        )
        return (
            updated,
            NSRange(
                location: reference.markdownRange.location + (replacement as NSString).length,
                length: 0
            )
        )
    }

    private static func makeLarge(
        _ reference: MarkdownAssetPreviewReference,
        in source: String
    ) -> (source: String, selection: NSRange) {
        let ns = source as NSString
        let lineRange = ns.lineRange(for: reference.markdownRange)
        let hasNewline = lineRange.length > 0
            && ns.character(at: NSMaxRange(lineRange) - 1) == 0x0A
        let contentRange = NSRange(
            location: lineRange.location,
            length: lineRange.length - (hasNewline ? 1 : 0)
        )
        let beforeRange = NSRange(
            location: contentRange.location,
            length: reference.markdownRange.location - contentRange.location
        )
        let afterStart = NSMaxRange(reference.markdownRange)
        let afterRange = NSRange(
            location: afterStart,
            length: NSMaxRange(contentRange) - afterStart
        )
        let before = ns.substring(with: beforeRange)
            .trimmingCharacters(in: .whitespaces)
        let after = ns.substring(with: afterRange)
            .trimmingCharacters(in: .whitespaces)
        let largeSyntax: String
        switch reference.kind {
        case .canvas:
            largeSyntax = "![[\(reference.destination)]]"
        case .image:
            let label = DocumentMarkdownLinkBuilder.escapedLabel(reference.label)
            largeSyntax = "![\(label)](\(reference.destination))"
        }

        var components: [String] = []
        if before.isEmpty == false { components.append(before) }
        let largeIndex = components.reduce(0) { $0 + ($1 as NSString).length + 1 }
        components.append(largeSyntax)
        if after.isEmpty == false { components.append(after) }
        let replacement = components.joined(separator: "\n")
        let updated = ns.replacingCharacters(in: contentRange, with: replacement)
        return (
            updated,
            NSRange(
                location: contentRange.location + largeIndex + (largeSyntax as NSString).length,
                length: 0
            )
        )
    }

    private static func canvasLabel(for destination: String) -> String {
        let decoded = destination.removingPercentEncoding ?? destination
        let fileName = (decoded as NSString).lastPathComponent
        let title = (fileName as NSString).deletingPathExtension
        return title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Canvas"
    }
}
