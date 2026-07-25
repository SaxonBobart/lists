import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Lists

@Suite("Markdown Copy As export")
struct MarkdownCopyExporterTests {
    @Test("Selection uses the editor's UTF-16 range and preserves source exactly")
    func selectedMarkdownSource() throws {
        let source = "Before 😀 **selected** after"
        let ns = source as NSString
        let range = ns.range(of: "**selected**")

        let selected = try #require(
            MarkdownCopyExporter.selectedSource(in: source, range: range)
        )

        #expect(selected == "**selected**")
    }

    @Test("Collapsed and invalid editor selections do not export")
    func invalidSelections() {
        let source = "Text"

        #expect(MarkdownCopyExporter.selectedSource(
            in: source,
            range: NSRange(location: 2, length: 0)
        ) == nil)
        #expect(MarkdownCopyExporter.selectedSource(
            in: source,
            range: NSRange(location: 3, length: 4)
        ) == nil)
        #expect(MarkdownCopyExporter.selectedSource(
            in: source,
            range: NSRange(location: NSNotFound, length: 0)
        ) == nil)
    }

    @Test("Markdown copy advertises Markdown and preserves the source")
    func markdownPayload() throws {
        let source = "# Heading\n\n**Bold** and [link](https://example.com)"
        let payload = MarkdownCopyExporter.payload(for: source, format: .markdown)
        let item = payload.pasteboardItem

        #expect(payload.plainText == source)
        #expect(item[UTType.utf8PlainText.identifier] as? String == source)
        #expect(item[UTType.html.identifier] == nil)
        let markdown = try #require(
            item[MarkdownCopyPayload.markdownTypeIdentifier] as? Data
        )
        #expect(String(data: markdown, encoding: .utf8) == source)
    }

    @Test("Plain text removes portable Markdown formatting")
    func plainTextPayload() {
        let source = "**Bold**, ==marked==, and [[Project|Roadmap]]"
        let payload = MarkdownCopyExporter.payload(for: source, format: .plainText)

        #expect(payload.plainText == "Bold, marked, and Roadmap")
        #expect(payload.markdownData == nil)
        #expect(payload.htmlData == nil)
    }

    @Test("Rich text provides semantic HTML and a plain fallback")
    func richTextPayload() throws {
        let source = """
        # Heading

        **Bold**, ==marked==, and [link](https://example.com)

        | Name | Value |
        | --- | ---: |
        | One | 1 |
        """
        let payload = MarkdownCopyExporter.payload(for: source, format: .richText)
        let htmlData = try #require(payload.htmlData)
        let html = try #require(String(data: htmlData, encoding: .utf8))
        let item = payload.pasteboardItem

        #expect(html.contains("<h1>Heading</h1>"))
        #expect(html.contains("<strong>Bold</strong>"))
        #expect(html.contains("<mark>marked</mark>"))
        #expect(html.contains(#"<a href="https://example.com">link</a>"#))
        #expect(html.contains("<table>"))
        #expect(payload.plainText.contains("Heading"))
        #expect(payload.plainText.contains("One"))
        #expect(item[UTType.html.identifier] as? Data == htmlData)
        #expect(item[MarkdownCopyPayload.markdownTypeIdentifier] == nil)
    }
}
