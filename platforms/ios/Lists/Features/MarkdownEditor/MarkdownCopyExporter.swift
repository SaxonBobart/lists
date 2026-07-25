import MarkdownUI
import UIKit
import UniformTypeIdentifiers

enum MarkdownCopyFormat: CaseIterable, Hashable {
    case markdown
    case richText
    case plainText

    var title: String {
        switch self {
        case .markdown:
            "Copy as Markdown"
        case .richText:
            "Copy as Rich Text"
        case .plainText:
            "Copy as Plain Text"
        }
    }

    var systemImage: String {
        switch self {
        case .markdown:
            "chevron.left.forwardslash.chevron.right"
        case .richText:
            "textformat"
        case .plainText:
            "text.alignleft"
        }
    }
}

struct MarkdownCopyPayload {
    let plainText: String
    let markdownData: Data?
    let htmlData: Data?

    static var markdownTypeIdentifier: String {
        if #available(iOS 27.0, *) {
            return UTType.markdown.identifier
        }
        return UTType(filenameExtension: "md")?.identifier
            ?? "net.daringfireball.markdown"
    }

    var pasteboardItem: [String: Any] {
        var item: [String: Any] = [
            UTType.utf8PlainText.identifier: plainText
        ]
        if let markdownData {
            item[Self.markdownTypeIdentifier] = markdownData
        }
        if let htmlData {
            item[UTType.html.identifier] = htmlData
        }
        return item
    }
}

enum MarkdownCopyExporter {
    private static let richHighlightDestination = "lists-copy-highlight:"
    private static let richHighlightLinkRegex = try! NSRegularExpression(
        pattern: #"<a href="lists-copy-highlight:">([\s\S]*?)</a>"#
    )

    static func selectedSource(in source: String, range: NSRange) -> String? {
        let ns = source as NSString
        guard range.location != NSNotFound,
              range.length > 0,
              range.location >= 0,
              NSMaxRange(range) <= ns.length else {
            return nil
        }
        return ns.substring(with: range)
    }

    static func payload(for source: String, format: MarkdownCopyFormat) -> MarkdownCopyPayload {
        switch format {
        case .markdown:
            return MarkdownCopyPayload(
                plainText: source,
                markdownData: source.data(using: .utf8),
                htmlData: nil
            )
        case .richText:
            let content = MarkdownContent(
                renderingSource(for: source, preservesRichFormatting: true)
            )
            return MarkdownCopyPayload(
                plainText: plainText(from: source),
                markdownData: nil,
                htmlData: richHTML(from: content).data(using: .utf8)
            )
        case .plainText:
            return MarkdownCopyPayload(
                plainText: plainText(from: source),
                markdownData: nil,
                htmlData: nil
            )
        }
    }

    private static func plainText(from source: String) -> String {
        MarkdownContent(
            renderingSource(for: source, preservesRichFormatting: false)
        ).renderPlainText()
    }

    private static func renderingSource(
        for source: String,
        preservesRichFormatting: Bool
    ) -> String {
        var rendered = replacingWikilinks(in: source)
        let highlightSpans = MarkdownSyntax.inlineSpans(in: rendered)
            .filter { $0.kind == .highlight }
            .sorted { $0.fullRange.location > $1.fullRange.location }
        let ns = rendered as NSString
        for span in highlightSpans {
            let content = ns.substring(with: span.contentRange)
            let replacement = preservesRichFormatting
                ? "[\(content)](\(richHighlightDestination))"
                : content
            rendered = (rendered as NSString).replacingCharacters(
                in: span.fullRange,
                with: replacement
            )
        }
        return rendered
    }

    private static func richHTML(from content: MarkdownContent) -> String {
        let html = content.renderHTML()
        return richHighlightLinkRegex.stringByReplacingMatches(
            in: html,
            range: NSRange(location: 0, length: (html as NSString).length),
            withTemplate: "<mark>$1</mark>"
        )
    }

    private static func replacingWikilinks(in source: String) -> String {
        var rendered = source
        let ranges = ExtensionParsers.wikilinkRanges(in: source)
            .sorted { $0.full.location > $1.full.location }
        let ns = source as NSString
        for range in ranges {
            let raw = ns.substring(with: range.inner)
            let label = raw.split(separator: "|", maxSplits: 1)
                .last
                .map(String.init) ?? raw
            rendered = (rendered as NSString).replacingCharacters(
                in: range.full,
                with: label
            )
        }
        return rendered
    }
}

@MainActor
enum MarkdownClipboard {
    static func copy(_ source: String, as format: MarkdownCopyFormat) {
        let payload = MarkdownCopyExporter.payload(for: source, format: format)
        UIPasteboard.general.setItems([payload.pasteboardItem])
    }
}
