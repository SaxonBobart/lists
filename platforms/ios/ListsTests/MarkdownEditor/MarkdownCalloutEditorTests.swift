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
        #expect(inactive.firstLineHeadIndent == 20)
        let inactivePrefixFont = try #require(styler.attribute(
            .font,
            at: 0,
            effectiveRange: nil
        ) as? UIFont)
        #expect(inactivePrefixFont.pointSize > 1)
        let inactiveTitleFont = try #require(styler.attribute(
            .font,
            at: 4,
            effectiveRange: nil
        ) as? UIFont)
        #expect(inactiveTitleFont.pointSize > 1)

        styler.cursorRange = NSRange(location: 4, length: 0)

        let active = try #require(styler.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle)
        #expect(active.firstLineHeadIndent == 20)
        #expect(active.headIndent == inactive.headIndent)
        #expect(styler.isCursor(onLine: NSRange(location: 0, length: 10)))
        let activePrefixFont = try #require(styler.attribute(
            .font,
            at: 0,
            effectiveRange: nil
        ) as? UIFont)
        #expect(activePrefixFont.pointSize > 1)
        let activeTitleFont = try #require(styler.attribute(
            .font,
            at: 4,
            effectiveRange: nil
        ) as? UIFont)
        #expect(activeTitleFont.pointSize > 1)

        let openingSyntaxColor = try #require(styler.attribute(
            .foregroundColor,
            at: 2,
            effectiveRange: nil
        ) as? UIColor)
        #expect(openingSyntaxColor != UIColor.clear)
    }

    @Test("Callout display title is normalized or replaced by custom text")
    func calloutDisplayTitles() {
        let source = """
        > [!NOTE]
        > [!note]
        > [!Note]
        >[!nOtE] Project Notes
        """
        #expect(MarkdownLayoutManager().calloutDisplayTitles(in: source) == [
            "Note", "Note", "Note", "Project Notes"
        ])
    }

    @Test("Focused nested quote wraps at its content column")
    func focusedNestedQuoteWrapping() throws {
        let styler = MarkdownStyler()
        styler.replaceCharacters(
            in: NSRange(location: 0, length: 0),
            with: "> > A nested quote that wraps"
        )
        let inactive = try #require(styler.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle)
        let inactivePrefixFont = try #require(styler.attribute(
            .font,
            at: 0,
            effectiveRange: nil
        ) as? UIFont)
        #expect(inactive.headIndent == inactive.firstLineHeadIndent)
        #expect(inactivePrefixFont.pointSize < 1)

        styler.cursorRange = NSRange(location: 8, length: 0)

        let paragraph = try #require(styler.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle)
        #expect(paragraph.firstLineHeadIndent == 40)
        #expect(paragraph.headIndent > paragraph.firstLineHeadIndent)
        let activePrefixFont = try #require(styler.attribute(
            .font,
            at: 0,
            effectiveRange: nil
        ) as? UIFont)
        #expect(activePrefixFont.pointSize > 1)
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

    @Test("Blank and plain lines remain outside neighboring callouts")
    func ordinaryLinesSeparateCallouts() throws {
        let source = """
        > [!NOTE]
        > First body.

        Ordinary body text between callouts.

        > [!TIP]
        > Second body.
        """
        let ranges = MarkdownLayoutManager().calloutBlockRanges(in: source)
        #expect(ranges.count == 2)

        let ordinary = try #require((source as NSString)
            .range(of: "Ordinary body text between callouts.").optional)
        #expect(ranges.allSatisfy { NSIntersectionRange($0, ordinary).length == 0 })
        #expect(NSMaxRange(ranges[0]) < ordinary.location)
        #expect(NSMaxRange(ordinary) < ranges[1].location)
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

    @Test("Inactive callout header stays on one rendered line")
    func inactiveHeaderHasNoPhantomFragment() throws {
        let styler = MarkdownStyler()
        let layout = MarkdownLayoutManager()
        let delegate = MarkdownLayoutDelegate()
        let container = NSTextContainer(
            size: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        )
        delegate.styler = styler
        layout.delegate = delegate
        styler.glyphInvalidatable = layout
        styler.addLayoutManager(layout)
        layout.addTextContainer(container)
        styler.replaceCharacters(
            in: NSRange(location: 0, length: 0),
            with: "> [!NOTE]\n> Highlights information that is useful while skimming."
        )
        styler.cursorRange = NSRange(location: styler.length - 1, length: 0)
        layout.ensureLayout(for: container)

        let header = (styler.string as NSString).paragraphRange(
            for: NSRange(location: 0, length: 0)
        )
        let bounds = try #require(layout.fullLineFragmentRect(for: header, in: container))
        #expect(bounds.height < UIFont.preferredFont(forTextStyle: .body).lineHeight * 1.7)
    }
}

private extension NSRange {
    var optional: NSRange? {
        location == NSNotFound ? nil : self
    }
}
