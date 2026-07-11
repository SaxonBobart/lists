import Testing
import UIKit
@testable import Lists

@MainActor
@Suite("Markdown callout editing")
struct MarkdownCalloutEditorTests {
    @Test("Integrated rails share the complete card edge at every depth")
    func integratedRailGeometry() {
        let cards = [
            CGRect(x: 8, y: 12, width: 300, height: 72),
            CGRect(x: 28, y: 96, width: 260, height: 116),
            CGRect(x: 48, y: 224, width: 220, height: 54)
        ]

        for card in cards {
            let rail = MarkdownQuoteCardMetrics.railRect(in: card)
            #expect(rail.minX == card.minX)
            #expect(rail.minY == card.minY)
            #expect(rail.height == card.height)
            #expect(rail.width == 3)
            #expect(rail.maxX == card.minX + MarkdownQuoteCardMetrics.railWidth)
        }
    }

    @Test("A blank line after a callout does not focus its header")
    func nextBlankLineDoesNotFocusCalloutHeader() {
        let styler = MarkdownStyler()
        let source = "> [!NOTE]\n"
        styler.replaceCharacters(
            in: NSRange(location: 0, length: 0),
            with: source
        )
        let header = (source as NSString).paragraphRange(
            for: NSRange(location: 0, length: 0)
        )

        styler.cursorRange = NSRange(location: styler.length, length: 0)

        #expect(styler.isCursor(onLine: header) == false)

        styler.replaceCharacters(
            in: NSRange(location: styler.length - 1, length: 1),
            with: ""
        )
        styler.cursorRange = NSRange(location: styler.length, length: 0)

        #expect(styler.isCursor(onLine: NSRange(location: 0, length: styler.length)))
    }

    @Test("The first quote allows navigation and insertion before its marker")
    func firstQuoteAllowsLeadingParagraph() {
        let source = "> Callout"
        let snapped = CursorSnapping.snapped(
            1,
            in: source,
            movingForward: false,
            sameLineMovement: true
        )
        #expect(snapped == 0)

        let entered = ListContinuation.apply(
            to: source,
            selection: NSRange(location: snapped, length: 0)
        )
        #expect(entered.source == "\n> Callout")
        #expect(entered.selection == NSRange(location: 1, length: 0))
    }

    @Test("Empty paragraphs never inherit quote typing indentation")
    func emptyParagraphUsesDefaultTypingStyle() {
        let source = "> First quote.\n\n> Second quote.\n"
        let ns = source as NSString
        let blankBetween = ns.range(of: "\n\n").location + 1

        #expect(MarkdownTypingStyle.isEmptyParagraph(in: ns, at: blankBetween))
        #expect(MarkdownTypingStyle.isEmptyParagraph(in: ns, at: ns.length))
        #expect(MarkdownTypingStyle.isEmptyParagraph(in: ns, at: 3) == false)
    }

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

    @Test("Plain quotes and callout bodies use primary text")
    func quoteBodyTextUsesPrimaryColor() throws {
        let source = """
        > [!NOTE]
        > Callout body.

        > Plain quote body.
        """
        let styler = MarkdownStyler()
        styler.replaceCharacters(
            in: NSRange(location: 0, length: 0),
            with: source
        )
        let ns = source as NSString
        for text in ["Callout body.", "Plain quote body."] {
            let range = try #require(ns.range(of: text).optional)
            let color = try #require(styler.attribute(
                .foregroundColor,
                at: range.location,
                effectiveRange: nil
            ) as? UIColor)
            #expect(color == UIColor.label)
        }
        #expect(MarkdownBodyView.usesSemanticHighlightRenderer("> Plain quote body."))
    }

    @Test("Return preserves nested callout depth")
    func returnPreservesQuoteDepth() {
        let body = "> > > A third-level body"
        let continued = ListContinuation.apply(
            to: body,
            selection: NSRange(location: (body as NSString).length, length: 0)
        )
        #expect(continued.source == body + "\n> > > ")
        #expect(continued.selection.location == (continued.source as NSString).length)

        let header = "> > [!NOTE] Project Notes"
        let headerContinuation = ListContinuation.apply(
            to: header,
            selection: NSRange(location: (header as NSString).length, length: 0)
        )
        #expect(headerContinuation.source == header + "\n> > ")
    }

    @Test("Empty quote Return and Backspace outdent one depth")
    func emptyQuoteOutdents() {
        let empty = "> > > "
        let returned = ListContinuation.apply(
            to: empty,
            selection: NSRange(location: (empty as NSString).length, length: 0)
        )
        #expect(returned.source == "> > ")
        #expect(returned.selection == NSRange(location: 4, length: 0))

        let backspaced = BackspaceHandler.applyBackspace(
            to: empty,
            selection: NSRange(location: (empty as NSString).length, length: 0)
        )
        #expect(backspaced.source == "> > ")
        #expect(backspaced.selection == NSRange(location: 4, length: 0))

        let exited = ListContinuation.apply(
            to: "> ",
            selection: NSRange(location: 2, length: 0)
        )
        #expect(exited.source.isEmpty)
    }

    @Test("Tab and outdent change quote depth instead of adding spaces")
    func quoteIndentControls() {
        let source = "> > Nested body"
        let caret = NSRange(location: (source as NSString).length, length: 0)
        let indented = IndentHandler.indent(source: source, selection: caret)
        #expect(indented.source == "> > > Nested body")
        #expect(indented.selection.location == caret.location + 2)

        let outdented = IndentHandler.outdent(
            source: indented.source,
            selection: indented.selection
        )
        #expect(outdented.source == source)
        #expect(outdented.selection == caret)
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
        #expect(inactive.tailIndent == -22)
        #expect(inactivePrefixFont.pointSize < 1)

        styler.cursorRange = NSRange(location: 8, length: 0)

        let paragraph = try #require(styler.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle)
        #expect(paragraph.firstLineHeadIndent == 40)
        #expect(paragraph.headIndent > paragraph.firstLineHeadIndent)
        #expect(paragraph.tailIndent == -22)
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

    @Test("Plain quote cards contain nested blocks without duplicating callouts")
    func plainQuoteCardContainment() throws {
        let quoteParent = """
        > Plain parent.
        > > [!NOTE]
        > > Nested callout.
        > Back in parent.
        """
        let layout = MarkdownLayoutManager()
        let parentCards = layout.plainQuoteBlockRanges(in: quoteParent)
        let parent = try #require(parentCards.first)
        #expect(parentCards.count == 1)
        #expect(parent.location == 0)
        #expect(NSMaxRange(parent) == (quoteParent as NSString).length)

        let calloutParent = """
        > [!NOTE]
        > Callout parent.
        > > Nested plain quote.
        > Back in callout.
        """
        let nestedCards = layout.plainQuoteBlockRanges(in: calloutParent)
        let nested = try #require(nestedCards.first)
        #expect(nestedCards.count == 1)
        #expect((calloutParent as NSString)
            .substring(with: nested)
            .trimmingCharacters(in: .newlines) == "> > Nested plain quote.")
    }

    @Test("One blank line separates quote and callout cards")
    func blankLineSeparatesQuoteCards() {
        let layout = MarkdownLayoutManager()
        let quotes = """
        > First quote.

        > Second quote.
        """
        #expect(layout.plainQuoteBlockRanges(in: quotes).count == 2)

        let callouts = """
        > [!NOTE]
        > First body.

        > [!TIP]
        > Second body.
        """
        #expect(layout.calloutBlockRanges(in: callouts).count == 2)
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
