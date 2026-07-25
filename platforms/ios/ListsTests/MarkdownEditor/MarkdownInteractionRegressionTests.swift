import Testing
import UIKit
@testable import Lists

@Suite("Markdown live interaction regressions")
struct MarkdownInteractionRegressionTests {
    struct Fixture: CustomTestStringConvertible, Sendable {
        let name: String
        let source: String
        let marker: String
        let content: String

        var testDescription: String { name }
    }

    private static let inlineFixtures = [
        Fixture(name: "bold", source: "Before **bold** after", marker: "**", content: "bold"),
        Fixture(name: "inline code", source: "Before `code` after", marker: "`", content: "code"),
        Fixture(name: "inline math", source: "Before $x + y$ after", marker: "$", content: "x + y"),
        Fixture(name: "link", source: "Before [Lists](https://example.com) after", marker: "[", content: "Lists"),
        Fixture(name: "wikilink", source: "Before [[Roadmap]] after", marker: "[[", content: "Roadmap"),
        Fixture(name: "footnote", source: "Before reference[^source] after", marker: "[^", content: "source")
    ]

    @Test("Inline syntax hides outside and reveals inside its own span", arguments: inlineFixtures)
    @MainActor
    func inlineSyntaxTracksCaretContext(_ fixture: Fixture) throws {
        let harness = makeHarness(source: fixture.source)
        let markerRange = try #require((fixture.source as NSString).range(of: fixture.marker).optional)
        let contentRange = try #require((fixture.source as NSString).range(of: fixture.content).optional)

        #expect(harness.styler.glyphProperty(at: markerRange.location) == .null)
        harness.styler.cursorRange = NSRange(location: contentRange.location, length: 0)
        #expect(harness.styler.glyphProperty(at: markerRange.location) == nil)

        harness.styler.cursorRange = NSRange(location: 0, length: 0)
        #expect(harness.styler.glyphProperty(at: markerRange.location) == .null)
        #expect(harness.styler.string == fixture.source)
    }

    @Test("Footnote definitions use the same caret-aware marker contract")
    @MainActor
    func footnoteDefinitionTracksCaretContext() throws {
        let source = "[^source]: Durable reference"
        let harness = makeHarness(source: source)
        let content = try #require((source as NSString).range(of: "source").optional)

        #expect(harness.styler.glyphProperty(at: 0) == .null)
        #expect(harness.styler.glyphProperty(at: NSMaxRange(content)) == .null)
        harness.styler.cursorRange = NSRange(location: content.location, length: 0)
        #expect(harness.styler.glyphProperty(at: 0) == nil)
        #expect(harness.styler.glyphProperty(at: NSMaxRange(content)) == nil)
    }

    @Test("Display math delimiters reveal from anywhere inside the block")
    @MainActor
    func displayMathUsesWholeBlockContext() throws {
        let source = "$$\nx + y\n$$"
        let harness = makeHarness(source: source)
        let body = try #require((source as NSString).range(of: "x + y").optional)

        #expect(harness.styler.glyphProperty(at: 0) == .null)
        #expect(harness.styler.glyphProperty(at: (source as NSString).length - 1) == .null)
        harness.styler.cursorRange = NSRange(location: body.location, length: 0)
        #expect(harness.styler.glyphProperty(at: 0) == nil)
        #expect(harness.styler.glyphProperty(at: (source as NSString).length - 1) == nil)
    }

    @Test("Supported block geometry keeps its line height across focus", arguments: [
        Fixture(name: "heading", source: "## Heading", marker: "##", content: "Heading"),
        Fixture(name: "bullet", source: "- Bullet", marker: "-", content: "Bullet"),
        Fixture(name: "quote", source: "> Quoted text", marker: ">", content: "Quoted text"),
        Fixture(name: "callout", source: "> [!NOTE] Heads up", marker: "[!", content: "Heads up"),
        Fixture(name: "fenced code", source: "```swift\nlet value = 1\n```", marker: "```", content: "let value = 1"),
        Fixture(name: "display math", source: "$$\nx + y\n$$", marker: "$$", content: "x + y")
    ])
    @MainActor
    func blockLineHeightIsStable(_ fixture: Fixture) throws {
        let harness = makeHarness(source: fixture.source)
        let content = try #require((fixture.source as NSString).range(of: fixture.content).optional)
        let inactiveHeight = lineHeight(containing: content.location, in: harness)

        harness.styler.cursorRange = NSRange(location: content.location, length: 0)
        let activeHeight = lineHeight(containing: content.location, in: harness)

        #expect(abs(activeHeight - inactiveHeight) < 0.5)
        #expect(harness.styler.string == fixture.source)
    }

    @Test("Table object editing keeps source hidden and row geometry fixed")
    @MainActor
    func tableGeometryDoesNotDependOnCaret() throws {
        let source = "| Name | Status |\n| --- | --- |\n| Lists | Ready |"
        let harness = makeHarness(source: source)
        let cell = try #require((source as NSString).range(of: "Lists").optional)
        let inactiveHeight = lineHeight(containing: cell.location, in: harness)

        #expect(color(at: cell.location, in: harness.styler) == .clear)
        harness.styler.cursorRange = NSRange(location: cell.location, length: 0)
        #expect(color(at: cell.location, in: harness.styler) == .clear)
        #expect(abs(lineHeight(containing: cell.location, in: harness) - inactiveHeight) < 0.5)
        #expect(harness.styler.string == source)
    }

    @Test("Raw mode never hides extension syntax")
    @MainActor
    func rawModeShowsEveryMarker() {
        let source = "[[Roadmap]] [^source] $x$"
        let harness = makeHarness(source: source)
        harness.styler.mode = .raw

        for location in 0..<(source as NSString).length {
            #expect(harness.styler.glyphProperty(at: location) == nil)
        }
        #expect(harness.layout.drawsMarkdownDecorations == false)
    }

    @Test("Raw mode disables every custom layout decoration")
    @MainActor
    func rawModeDisablesLayoutDecorations() {
        let source = "> Quote\n\n> [!NOTE]\n> Callout\n\n- [x] Task\n\n```swift\ncode\n```"
        let harness = makeHarness(source: source)
        #expect(harness.layout.drawsMarkdownDecorations)

        harness.styler.mode = .raw

        #expect(!harness.layout.drawsMarkdownDecorations)
        #expect(harness.styler.string == source)
    }

    private struct Harness {
        let styler: MarkdownStyler
        let layout: MarkdownLayoutManager
        let container: NSTextContainer
    }

    private func makeHarness(source: String) -> Harness {
        let styler = MarkdownStyler()
        let layout = MarkdownLayoutManager()
        let delegate = MarkdownLayoutDelegate()
        let container = NSTextContainer(
            size: CGSize(width: 360, height: CGFloat.greatestFiniteMagnitude)
        )
        delegate.styler = styler
        layout.delegate = delegate
        layout.addTextContainer(container)
        styler.addLayoutManager(layout)
        styler.glyphInvalidatable = layout
        styler.mode = .live
        styler.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        return Harness(styler: styler, layout: layout, container: container)
    }

    private func lineHeight(containing location: Int, in harness: Harness) -> CGFloat {
        harness.layout.ensureLayout(for: harness.container)
        let characterRange = (harness.styler.string as NSString).lineRange(
            for: NSRange(location: location, length: 0)
        )
        let glyphRange = harness.layout.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        return harness.layout.boundingRect(forGlyphRange: glyphRange, in: harness.container).height
    }

    private func color(at location: Int, in styler: MarkdownStyler) -> UIColor? {
        styler.attribute(.foregroundColor, at: location, effectiveRange: nil) as? UIColor
    }
}

private extension NSRange {
    var optional: NSRange? {
        location == NSNotFound ? nil : self
    }
}
