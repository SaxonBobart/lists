import Testing
import UIKit
@testable import Lists

@MainActor
@Suite("Markdown callout editing")
struct MarkdownCalloutEditorTests {
    @Test("Focused callout syntax replaces the decorative icon gutter")
    func focusedCalloutHeader() throws {
        let styler = MarkdownStyler()
        styler.replaceCharacters(
            in: NSRange(location: 0, length: 0),
            with: "> [!NOTE]\n> Body"
        )

        let inactive = try #require(styler.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle)
        #expect(inactive.firstLineHeadIndent == 46)

        styler.cursorRange = NSRange(location: 4, length: 0)

        let active = try #require(styler.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle)
        #expect(active.firstLineHeadIndent == 20)
        #expect(active.headIndent > active.firstLineHeadIndent)
        #expect(styler.isCursor(onLine: NSRange(location: 0, length: 10)))

        let openingSyntaxColor = try #require(styler.attribute(
            .foregroundColor,
            at: 2,
            effectiveRange: nil
        ) as? UIColor)
        #expect(openingSyntaxColor != UIColor.clear)
    }

    @Test("Focused nested quote wraps at its content column")
    func focusedNestedQuoteWrapping() throws {
        let styler = MarkdownStyler()
        styler.replaceCharacters(
            in: NSRange(location: 0, length: 0),
            with: "> > A nested quote that wraps"
        )
        styler.cursorRange = NSRange(location: 8, length: 0)

        let paragraph = try #require(styler.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle)
        #expect(paragraph.firstLineHeadIndent == 40)
        #expect(paragraph.headIndent > paragraph.firstLineHeadIndent)
    }

    @Test("Parent callout contains its complete nested subtree")
    func parentContainsNestedCallouts() throws {
        let source = """
        > [!TIP] Nested callouts
        > Parent callout body text.
        > > [!NOTE]
        > > A nested note should sit inside the parent with its own rail.
        > > > [!IMPORTANT]
        > > > A third level should still remain readable.
        > Back to the parent callout.
        """
        let layout = MarkdownLayoutManager()
        let blocks = layout.calloutBlockRanges(in: source)

        #expect(blocks.count == 3)
        let parent = try #require(blocks.first)
        #expect(parent.location == 0)
        #expect(NSMaxRange(parent) == (source as NSString).length)

        guard blocks.indices.contains(1) else {
            Issue.record("Expected a nested NOTE callout block")
            return
        }
        let nestedNote = blocks[1]
        let backToParent = try #require((source as NSString).range(of: "> Back to").optional)
        #expect(NSMaxRange(nestedNote) <= backToParent.location)
    }

    @Test("Quote rail geometry includes every wrapped fragment")
    func quoteRailIncludesWrappedFragments() throws {
        let storage = NSTextStorage(string: String(repeating: "Wrapped quote text ", count: 8))
        let layout = MarkdownLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: 180, height: CGFloat.greatestFiniteMagnitude)
        )
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)

        let bounds = try #require(layout.fullLineFragmentRect(
            for: NSRange(location: 0, length: storage.length),
            in: container
        ))
        #expect(bounds.height > UIFont.preferredFont(forTextStyle: .body).lineHeight * 2)
    }
}

private extension NSRange {
    var optional: NSRange? {
        location == NSNotFound ? nil : self
    }
}
