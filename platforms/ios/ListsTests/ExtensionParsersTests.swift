import Foundation
import Testing
@testable import Lists

@Suite("ExtensionParsers")
struct ExtensionParsersTests {

    @Suite("Wikilinks")
    struct WikilinkTests {
        @Test func matchesSimpleWikilink() {
            let ranges = ExtensionParsers.wikilinkRanges(in: "see [[Page]] today")
            #expect(ranges.count == 1)
            #expect(ranges.first?.full.location == 4)
            #expect(ranges.first?.full.length == 8)
            #expect(ranges.first?.inner.location == 6)
            #expect(ranges.first?.inner.length == 4)
        }
        @Test func matchesWikilinkWithAlias() {
            let ranges = ExtensionParsers.wikilinkRanges(in: "see [[Page|Alias]] today")
            #expect(ranges.count == 1)
            #expect(ranges.first?.full.length == 14)  // "[[Page|Alias]]"
        }
        @Test func matchesMultipleWikilinks() {
            let ranges = ExtensionParsers.wikilinkRanges(in: "[[A]] and [[B]]")
            #expect(ranges.count == 2)
        }
        @Test func doesNotMatchSingleBracket() {
            let ranges = ExtensionParsers.wikilinkRanges(in: "see [link] there")
            #expect(ranges.isEmpty)
        }
        @Test func doesNotMatchAcrossLines() {
            let ranges = ExtensionParsers.wikilinkRanges(in: "[[a\nb]]")
            #expect(ranges.isEmpty)
        }
    }

    @Suite("Footnotes")
    struct FootnoteTests {
        @Test func matchesFootnoteRef() {
            let ranges = ExtensionParsers.footnoteRefRanges(in: "see[^1] there")
            #expect(ranges.count == 1)
            #expect(ranges.first?.full.length == 4)  // "[^1]"
        }
        @Test func doesNotMatchFootnoteDefAsRef() {
            // `[^1]:` is a definition, not a ref.
            let ranges = ExtensionParsers.footnoteRefRanges(in: "[^1]: text")
            #expect(ranges.isEmpty)
        }
        @Test func matchesFootnoteDef() {
            let ranges = ExtensionParsers.footnoteDefRanges(in: "[^note]: definition")
            #expect(ranges.count == 1)
            #expect(ranges.first?.full.length == 8)  // "[^note]:"
        }
        @Test func footnoteDefRequiresLineStart() {
            let ranges = ExtensionParsers.footnoteDefRanges(in: "text [^1]: not at start")
            #expect(ranges.isEmpty)
        }
        @Test func allowsAlphanumericIds() {
            let ranges = ExtensionParsers.footnoteRefRanges(in: "see[^abc-1_2] now")
            #expect(ranges.count == 1)
        }
    }

    @Suite("Math")
    struct MathTests {
        @Test func matchesInlineMath() {
            let ranges = ExtensionParsers.mathInlineRanges(in: "see $x+1$ here")
            #expect(ranges.count == 1)
            #expect(ranges.first?.full.length == 5)  // "$x+1$"
        }
        @Test func doesNotMatchDisplayMathAsInline() {
            let ranges = ExtensionParsers.mathInlineRanges(in: "see $$x+1$$ here")
            #expect(ranges.isEmpty)
        }
        @Test func matchesDisplayMath() {
            let ranges = ExtensionParsers.mathDisplayRanges(in: "$$\nx = 1\n$$")
            #expect(ranges.count == 1)
        }
        @Test func matchesInlineDisplayMath() {
            // `$$x$$` is a degenerate display block too.
            let ranges = ExtensionParsers.mathDisplayRanges(in: "see $$x$$ here")
            #expect(ranges.count == 1)
            #expect(ranges.first?.full.length == 5)  // "$$x$$"
        }
        @Test func inlineMathDoesNotCrossLines() {
            let ranges = ExtensionParsers.mathInlineRanges(in: "$x\ny$")
            #expect(ranges.isEmpty)
        }
    }

    @Suite("Mermaid")
    struct MermaidTests {
        @Test func matchesMermaidFence() {
            let ranges = ExtensionParsers.mermaidBlockRanges(in: "```mermaid\nflowchart LR\nA-->B\n```")
            #expect(ranges.count == 1)
        }
        @Test func doesNotMatchPlainCodeFence() {
            let ranges = ExtensionParsers.mermaidBlockRanges(in: "```\nplain code\n```")
            #expect(ranges.isEmpty)
        }
        @Test func doesNotMatchSwiftCodeFence() {
            let ranges = ExtensionParsers.mermaidBlockRanges(in: "```swift\ncode\n```")
            #expect(ranges.isEmpty)
        }
    }
}
