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
}
