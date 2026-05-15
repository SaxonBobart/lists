import Testing
import UIKit
@testable import Lists

@Suite("MarkdownStyler")
struct MarkdownStylerTests {

    // MARK: Attribute application (live mode, base styling)

    @Test func headingAppliesLargerFont() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Hello")
        let attrs = storage.attributes(at: 2, effectiveRange: nil)
        let font = attrs[.font] as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        #expect((font?.pointSize ?? 0) > UIFont.preferredFont(forTextStyle: .body).pointSize)
    }

    @Test func boldContentGetsBoldTrait() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "say **hi** now")
        let attrs = storage.attributes(at: 6, effectiveRange: nil)
        let font = attrs[.font] as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }

    @Test func italicContentGetsItalicTrait() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "feels *odd* today")
        let attrs = storage.attributes(at: 7, effectiveRange: nil)
        let font = attrs[.font] as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
    }

    @Test func inlineCodeGetsMonoFontAndInlineCodeSpan() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "run `npm test` now")
        let attrs = storage.attributes(at: 6, effectiveRange: nil)
        let font = attrs[.font] as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true
                || font?.fontName.lowercased().contains("mono") == true)
        // The custom layout manager draws the rounded pill; the styler
        // marks the run with the .inlineCodeSpan attribute.
        #expect(attrs[.inlineCodeSpan] as? Bool == true)
    }

    @Test func linkLabelGetsUnderlineButKeepsDefaultColor() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "see [Apple](https://apple.com)")
        // index 5 is inside "Apple"
        let attrs = storage.attributes(at: 5, effectiveRange: nil)
        // Underline is the link affordance; color stays neutral (no blue tinting).
        #expect(attrs[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(attrs[.foregroundColor] as? UIColor == UIColor.label)
    }

    @Test func strikethroughContentGetsStrikethrough() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "~~old~~")
        let attrs = storage.attributes(at: 3, effectiveRange: nil)
        #expect(attrs[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test func highlightContentGetsYellowBackground() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "see ==this== now")
        let attrs = storage.attributes(at: 6, effectiveRange: nil)
        #expect(attrs[.backgroundColor] != nil)
    }

    // MARK: Cursor-aware hiding

    @Test func headingHashHidesWhenCursorOffLine() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Hello\nworld")
        storage.cursorRange = NSRange(location: 9, length: 0)   // inside "world"
        #expect(storage.glyphProperty(at: 0) == .null)
    }

    @Test func headingHashVisibleWhenCursorOnLine() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Hello\nworld")
        storage.cursorRange = NSRange(location: 3, length: 0)   // inside "# Hello"
        #expect(storage.glyphProperty(at: 0) == nil)
    }

    @Test func headingHashHiddenWhenCursorIsNowhere() {
        // "Start hidden" — until the user taps in, markers are hidden.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Hello")
        // cursorRange defaults to NSNotFound
        #expect(storage.glyphProperty(at: 0) == .null)
    }

    @Test func boldMarkersHideWhenCursorOnOtherLine() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "say **hi** now\nother line")
        storage.cursorRange = NSRange(location: 17, length: 0)   // "other line"
        // First `*` of `**` opener is at index 4
        #expect(storage.glyphProperty(at: 4) == .null)
        #expect(storage.glyphProperty(at: 5) == .null)
    }

    @Test func boldMarkersVisibleWhenCursorInsideSpan() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "say **hi** now\nother line")
        storage.cursorRange = NSRange(location: 6, length: 0)    // inside the bold span
        #expect(storage.glyphProperty(at: 4) == nil)
    }

    @Test func boldMarkersHideWhenCursorMovesPastSpanWithinSameLine() {
        // Per-span behaviour: cursor on "now" is still on the same line
        // as the bold span but OUTSIDE it. Markers must hide.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "say **hi** now")
        storage.cursorRange = NSRange(location: 12, length: 0)   // 'o' in "now"
        #expect(storage.glyphProperty(at: 4) == .null)
        #expect(storage.glyphProperty(at: 5) == .null)
        #expect(storage.glyphProperty(at: 8) == .null)
        #expect(storage.glyphProperty(at: 9) == .null)
    }

    // MARK: Glyph substitution

    @Test func bulletSubstitutesDashForStandardBulletWhenCursorOffLine() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "- coffee\nelse")
        storage.cursorRange = NSRange(location: 11, length: 0)   // "else"
        #expect(storage.glyphSubstitution(at: 0) == 0x2022)      // • (regular iOS bullet)
    }

    @Test func bulletSubstitutesEvenWhenCursorOnLine() {
        // The `•` appears the instant `- ` is typed; we don't wait for
        // the cursor to leave the line. Lighter visual flicker, matches
        // user expectation that the bullet "becomes a dot" right after
        // typing the trailing space.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "- coffee")
        storage.cursorRange = NSRange(location: 3, length: 0)
        #expect(storage.glyphSubstitution(at: 0) == 0x2022)
    }

    @Test func taskListCheckedSubstitutesCheckedBox() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "- [x] done\nelse")
        storage.cursorRange = NSRange(location: 12, length: 0)
        #expect(storage.glyphSubstitution(at: 2) == 0x2611)      // ☑
    }

    @Test func taskListUncheckedSubstitutesEmptyBox() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "- [ ] todo\nelse")
        storage.cursorRange = NSRange(location: 12, length: 0)
        #expect(storage.glyphSubstitution(at: 2) == 0x2610)      // ☐
    }

    @Test func completedTaskTextIsStrikethrough() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "- [x] done")
        // Content "done" starts at index 6
        let attrs = storage.attributes(at: 7, effectiveRange: nil)
        #expect(attrs[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }

    // MARK: Raw mode

    @Test func rawModeNeverHidesMarkers() {
        let storage = MarkdownStyler()
        storage.mode = .raw
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Hello\nworld")
        storage.cursorRange = NSRange(location: 9, length: 0)
        #expect(storage.glyphProperty(at: 0) == nil)
    }

    @Test func rawModeNeverSubstitutesGlyphs() {
        let storage = MarkdownStyler()
        storage.mode = .raw
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "- coffee\nelse")
        storage.cursorRange = NSRange(location: 11, length: 0)
        #expect(storage.glyphSubstitution(at: 0) == nil)
    }

    @Test func rawModeAppliesMonoFontEverywhere() {
        let storage = MarkdownStyler()
        storage.mode = .raw
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "plain text")
        let attrs = storage.attributes(at: 3, effectiveRange: nil)
        let font = attrs[.font] as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true
                || font?.fontName.lowercased().contains("mono") == true)
    }

    @Test func rawModeTintsHeadingHashes() {
        let storage = MarkdownStyler()
        storage.mode = .raw
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Title")
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        // Neutral system color, NOT blue.
        #expect(attrs[.foregroundColor] as? UIColor == UIColor.secondaryLabel)
    }

    // MARK: Source preservation

    @Test func editPreservesPlainTextSource() {
        let storage = MarkdownStyler()
        let source = "# Hello\n**bold** *italic* `code` ~~strike~~ ==hi==\n- bullet\n1. numbered\n> quote\n- [x] done"
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        #expect(storage.string == source)
    }

    @Test func incompleteSyntaxDoesNotStyle() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "say **He")
        let attrs = storage.attributes(at: 6, effectiveRange: nil)
        let font = attrs[.font] as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == false)
    }

    // MARK: GFM / Obsidian extensions

    @Test func boldItalicAppliesBothTraits() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "***hello***")
        // index 5 is inside "hello"
        let attrs = storage.attributes(at: 5, effectiveRange: nil)
        let font = attrs[.font] as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
    }

    @Test func boldItalicUnderscoreAppliesBothTraits() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "___hello___")
        let attrs = storage.attributes(at: 5, effectiveRange: nil)
        let font = attrs[.font] as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
    }

    @Test func nestedBlockquoteIndentsProportionalToLevel() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "> level 1\n>> level 2")

        // index 3 is inside "level 1"
        let lvl1 = storage.attributes(at: 3, effectiveRange: nil)
        let p1 = lvl1[.paragraphStyle] as? NSParagraphStyle

        // index 13 is inside "level 2" (after ">> ")
        let lvl2 = storage.attributes(at: 13, effectiveRange: nil)
        let p2 = lvl2[.paragraphStyle] as? NSParagraphStyle

        #expect(p1 != nil)
        #expect(p2 != nil)
        #expect((p2?.firstLineHeadIndent ?? 0) > (p1?.firstLineHeadIndent ?? 0))
    }

    @Test func nestedBlockquoteHidesAllMarkers() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "first line\n>> deep quote")
        storage.cursorRange = NSRange(location: 3, length: 0)    // "first line"
        // Indices 11, 12 are the two `>`s on line 2
        #expect(storage.glyphProperty(at: 11) == .null)
        #expect(storage.glyphProperty(at: 12) == .null)
    }

    @Test func taskListMatchesWithTabAfterBullet() {
        // iOS keyboards sometimes insert non-space whitespace; the regex
        // uses \s so all whitespace variants register the checkbox.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "-\t[ ]\ttodo")
        storage.cursorRange = NSRange(location: 50, length: 0)   // far away
        // The `[` lands at index 2 (after `-` + `\t`).
        #expect(storage.glyphSubstitution(at: 2) == 0x2610)      // ☐
    }

    // MARK: Nested lists (Round 3)

    @Test func nestedBulletSubstitutesMarker() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "- parent\n  - child")
        storage.cursorRange = NSRange(location: 50, length: 0)   // far away
        // "- parent\n" is 9 chars. "  - child" starts at index 9.
        // The `-` of the nested item lands at index 9 + 2 = 11.
        #expect(storage.glyphSubstitution(at: 11) == 0x2022)     // •
    }

    @Test func nestedTaskListSubstitutesCheckbox() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "- parent\n  - [ ] sub")
        storage.cursorRange = NSRange(location: 50, length: 0)
        // Nested line starts at index 9. The `[` lands at 9 + 4 = 13.
        #expect(storage.glyphSubstitution(at: 13) == 0x2610)     // ☐
    }

    @Test func leadingWhitespaceHidesWhenCursorOffLine() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "first\n  - nested")
        storage.cursorRange = NSRange(location: 2, length: 0)    // on "first"
        // Indices 6 and 7 are the leading WS of the nested line.
        #expect(storage.glyphProperty(at: 6) == .null)
        #expect(storage.glyphProperty(at: 7) == .null)
    }

    @Test func leadingWhitespaceHidesWhenCursorOnLine() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "first\n  - nested")
        storage.cursorRange = NSRange(location: 10, length: 0)   // on nested line
        // Live mode renders list indentation through paragraph style;
        // Raw mode is where source spaces are shown directly.
        #expect(storage.glyphProperty(at: 6) == .null)
        #expect(storage.glyphProperty(at: 7) == .null)
    }

    @Test func nestedLineGetsLargerFirstLineHeadIndentWhenCursorOff() {
        // When cursor is off the nested line, the leading WS is hidden
        // and the paragraphStyle absorbs the indent — firstLineHeadIndent
        // is larger than the top-level line's.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "- top\n  - nested")
        storage.cursorRange = NSRange(location: 50, length: 0)   // far away

        // Top-level marker at index 0
        let topAttrs = storage.attributes(at: 0, effectiveRange: nil)
        let topP = topAttrs[.paragraphStyle] as? NSParagraphStyle

        // Nested marker `-` is at index 8 ("- top\n" is 6 chars, "  " is
        // indices 6-7, marker at 8).
        let nestedAttrs = storage.attributes(at: 8, effectiveRange: nil)
        let nestedP = nestedAttrs[.paragraphStyle] as? NSParagraphStyle

        #expect((nestedP?.firstLineHeadIndent ?? 0) > (topP?.firstLineHeadIndent ?? 0))
    }

    @Test func nestedLineFirstLineHeadIndentStaysStableWhenCursorOnLine() {
        // Live mode always uses paragraph style for list indentation,
        // so toolbar/hardware indent remains visually stable whether
        // the cursor is on or off the nested line.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "- top\n  - nested")

        // Cursor off: get the (large) nested firstLineHeadIndent
        storage.cursorRange = NSRange(location: 0, length: 0)
        let offAttrs = storage.attributes(at: 8, effectiveRange: nil)
        let offP = offAttrs[.paragraphStyle] as? NSParagraphStyle
        let offIndent = offP?.firstLineHeadIndent ?? 0

        // Cursor on the nested line: indent should remain stable.
        storage.cursorRange = NSRange(location: 12, length: 0)
        let onAttrs = storage.attributes(at: 8, effectiveRange: nil)
        let onP = onAttrs[.paragraphStyle] as? NSParagraphStyle
        let onIndent = onP?.firstLineHeadIndent ?? 0

        #expect(onIndent == offIndent)
    }

    @Test func tabLeadingWhitespaceRendersAsFourSpaceIndent() {
        let spaces = MarkdownStyler()
        spaces.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "- top\n    - child")

        let tab = MarkdownStyler()
        tab.replaceCharacters(in: NSRange(location: 0, length: 0),
                              with: "- top\n\t- child")

        let spacesAttrs = spaces.attributes(at: 10, effectiveRange: nil)
        let tabAttrs = tab.attributes(at: 7, effectiveRange: nil)
        let spacesP = spacesAttrs[.paragraphStyle] as? NSParagraphStyle
        let tabP = tabAttrs[.paragraphStyle] as? NSParagraphStyle

        #expect(spacesP?.firstLineHeadIndent == tabP?.firstLineHeadIndent)
        #expect(spacesP?.headIndent == tabP?.headIndent)
    }

    // MARK: Round 4 — code fences, horizontal rules, autolinks

    @Test func codeFenceMarkersHiddenWhenCursorOutsideFence() {
        // Fence markers go transparent (not `.null`) when the cursor
        // leaves the fence — keeps the line fragment height intact so
        // the rounded panel renders correctly across all three lines.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "above\n```\nhello\n```\nbelow")
        storage.cursorRange = NSRange(location: 2, length: 0)
        let openerAttrs = storage.attributes(at: 6, effectiveRange: nil)
        let closerAttrs = storage.attributes(at: 16, effectiveRange: nil)
        #expect(openerAttrs[.foregroundColor] as? UIColor == UIColor.clear)
        #expect(closerAttrs[.foregroundColor] as? UIColor == UIColor.clear)
    }

    @Test func codeFenceMarkersVisibleWhenCursorInBody() {
        // Cursor inside the fence body keeps BOTH opener and closer
        // markers visible (dimmed) — context is the whole fence.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "above\n```\nhello\n```\nbelow")
        storage.cursorRange = NSRange(location: 12, length: 0)
        let openerAttrs = storage.attributes(at: 6, effectiveRange: nil)
        let closerAttrs = storage.attributes(at: 16, effectiveRange: nil)
        #expect(openerAttrs[.foregroundColor] as? UIColor == UIColor.tertiaryLabel)
        #expect(closerAttrs[.foregroundColor] as? UIColor == UIColor.tertiaryLabel)
    }

    @Test func codeFenceWithBlankLineStillDetectsCloser() {
        // Regression: prior code broke the fence scan on the empty
        // line in the middle of the body, so the closer line slipped
        // through. After the fix the closer chars are styled as fence
        // markers — transparent foreground when the cursor is outside
        // the fence (here, on "above").
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "above\n```\nhello\n\nworld\n```")
        storage.cursorRange = NSRange(location: 2, length: 0)        // on "above"
        // Layout: "above\n" 0-5, "```\n" 6-9, "hello\n" 10-15, "\n" 16,
        //         "world\n" 17-22, "```" 23-25. Closer chars at 23/24/25.
        let closerAttrs = storage.attributes(at: 23, effectiveRange: nil)
        #expect(closerAttrs[.foregroundColor] as? UIColor == UIColor.clear)
    }

    @Test func codeBlockBodyAttributeCoversOpenerAndCloserLines() {
        // The rounded panel must reach over the opener + closer marker
        // lines too — `.codeBlockBody` is set on the WHOLE fence range.
        // Layout: ```\nhello\n``` → 13 chars.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "```\nhello\n```")
        let opener = storage.attributes(at: 0, effectiveRange: nil)     // first `
        let body   = storage.attributes(at: 5, effectiveRange: nil)     // 'e' in "hello"
        let closer = storage.attributes(at: 10, effectiveRange: nil)    // first ` of closer
        #expect(opener[.codeBlockBody] as? Bool == true)
        #expect(body[.codeBlockBody]   as? Bool == true)
        #expect(closer[.codeBlockBody] as? Bool == true)
    }

    @Test func horizontalRuleAddsHorizontalRuleAttributeWhenCursorOff() {
        // Layout: "above\n" 0-5, "---\n" 6-9 (HR line), "below" 10-14.
        // Source `---` chars are transparent (`.clear`) — keeps the
        // line fragment height alive so the rule draws at the correct
        // y. (Earlier `.null` glyph collapsed the line on iOS 26.)
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "above\n---\nbelow")
        storage.cursorRange = NSRange(location: 1, length: 0)    // "above"
        let attrs = storage.attributes(at: 6, effectiveRange: nil)
        #expect(attrs[.horizontalRule] as? Bool == true)
        #expect(attrs[.foregroundColor] as? UIColor == UIColor.clear)
    }

    @Test func horizontalRuleSourceVisibleWhenCursorOnLine() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "above\n---\nbelow")
        storage.cursorRange = NSRange(location: 7, length: 0)    // on the "---" line
        let attrs = storage.attributes(at: 6, effectiveRange: nil)
        #expect(attrs[.horizontalRule] as? Bool != true)
        #expect(attrs[.foregroundColor] as? UIColor == UIColor.tertiaryLabel)
    }

    @Test func bareUrlGetsUnderline() {
        // "see " 0-3, "https://example.com" 4-22, " here" 23-27
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "see https://example.com here")
        let attrs = storage.attributes(at: 10, effectiveRange: nil)  // inside URL
        #expect(attrs[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }

    // MARK: Round 5 — looser checkbox, code-bg attributes

    @Test func taskRegexRequiresTrailingSpaceToRender() {
        // "- [ ]" alone (no trailing space) doesn't match yet — the
        // user is still typing and the chars stay raw.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "- [ ]")
        storage.cursorRange = NSRange(location: 100, length: 0)
        #expect(storage.glyphSubstitution(at: 2) == nil)
    }

    @Test func taskRegexRendersAfterTrailingSpace() {
        // The trailing space completes the marker; the checkbox glyph
        // appears immediately and stays visible while the cursor is
        // on the line so the user can keep typing the task content.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "- [ ] ")
        storage.cursorRange = NSRange(location: 6, length: 0)     // cursor on the line
        #expect(storage.glyphSubstitution(at: 2) == 0x2610)       // ☐
        #expect(storage.glyphProperty(at: 0) == .null)            // `-` hidden
    }

    @Test func taskBulletHideUsesZeroWidthFont() {
        // The leading `- ` is hidden AND given a 0.01pt font so iOS
        // 26's typesetter advances ~zero, keeping the cursor at column
        // 0 aligned with the ☐ at column 2.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "- [ ] todo")
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? UIFont
        #expect((font?.pointSize ?? 100) < 1)
    }

    @Test func taskInnerBracketHideUsesZeroWidthFont() {
        // Inner state char + closing `]` get the same tiny font so
        // the line content (after the trailing space) lays out where
        // the ☐ visually ends.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "- [ ] todo")
        let stateAttrs = storage.attributes(at: 3, effectiveRange: nil)   // space inside brackets
        let bracketCloseAttrs = storage.attributes(at: 4, effectiveRange: nil) // `]`
        let stateFont = stateAttrs[.font] as? UIFont
        let closeFont = bracketCloseAttrs[.font] as? UIFont
        #expect((stateFont?.pointSize ?? 100) < 1)
        #expect((closeFont?.pointSize ?? 100) < 1)
    }

    @Test func codeBlockBodyAttributeAppliedToFenceContent() {
        // Fence "```\nhello\n```". Content "hello\n" at indices 4-9.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "```\nhello\n```")
        let attrs = storage.attributes(at: 5, effectiveRange: nil)   // 'e' in "hello"
        #expect(attrs[.codeBlockBody] as? Bool == true)
    }

    @Test func inlineCodeSpanAttributeAppliedToContent() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "run `npm` here")
        // "run " 0-3, "`" 4, "npm" 5-7, "`" 8, " here" 9-13
        let attrs = storage.attributes(at: 6, effectiveRange: nil)   // 'p' in "npm"
        #expect(attrs[.inlineCodeSpan] as? Bool == true)
    }

    // MARK: Round 8 — content alignment + SF Symbols + fence polish

    @Test func bulletTrailingSpaceGetsKernPushingContentToIndentColumn() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "- List")
        // Trailing space char is at index 1 (between `-` and `L`).
        let attrs = storage.attributes(at: 1, effectiveRange: nil)
        let kern = attrs[.kern] as? CGFloat ?? 0
        #expect(kern > 0)
        let spaceWidth = (" " as NSString)
            .size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .body)]).width
        let target = 4 * spaceWidth
        let bullet = ("\u{2022}" as NSString)
            .size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .body)]).width
        let expected = target - bullet - spaceWidth
        #expect(abs(kern - expected) < 0.5)
    }

    @Test func taskTrailingSpaceGetsKernPushingContentToIndentColumn() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "- [ ] Checkbox")
        // Source: "- [ ] Checkbox". The trailing space is at index 5
        // (right after `]`, before `C`).
        let attrs = storage.attributes(at: 5, effectiveRange: nil)
        let kern = attrs[.kern] as? CGFloat ?? 0
        #expect(kern > 0)
    }

    @Test func numberedTrailingSpaceGetsPositiveKern() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "1. step")
        // Trailing space is at index 2 (after `1.`).
        let attrs = storage.attributes(at: 2, effectiveRange: nil)
        let kern = attrs[.kern] as? CGFloat ?? 0
        #expect(kern > 0)
    }

    @Test func wideNumberedMarkerGetsNoNegativeKern() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "100. wide")
        // Trailing space is at index 4 (after `100.`).
        let attrs = storage.attributes(at: 4, effectiveRange: nil)
        // The `100.` marker is wider than indentWidth, so kern should
        // be skipped (treated as 0 / not present) rather than negative.
        let kern = attrs[.kern] as? CGFloat ?? 0
        #expect(kern <= 0)
    }

    @Test func taskMarkerHasSfSymbolAttribute() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "- [ ] todo")
        // The marker character we tag is the `[` at index 2.
        let attrs = storage.attributes(at: 2, effectiveRange: nil)
        let symbol = attrs[.sfSymbolCheckbox] as? String
        #expect(symbol == "square")
    }

    @Test func checkedTaskMarkerUsesFilledSfSymbol() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "- [x] done")
        let attrs = storage.attributes(at: 2, effectiveRange: nil)
        let symbol = attrs[.sfSymbolCheckbox] as? String
        #expect(symbol == "checkmark.square.fill")
    }

    @Test func taskMarkerForegroundIsClearToHideAppleSymbolsGlyph() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "- [ ] todo")
        let attrs = storage.attributes(at: 2, effectiveRange: nil)
        let color = attrs[.foregroundColor] as? UIColor
        #expect(color == UIColor.clear)
    }

    @Test func fenceOpenerUsesMonoFont() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "```\nhello\n```")
        // First char of the opener `` ``` ``.
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? UIFont
        let isMono = (font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true)
            || (font?.fontName.lowercased().contains("mono") == true)
        #expect(isMono)
    }

    @Test func fenceLanguageTagStaysVisibleWhenCursorOff() {
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "before\n```swift\nlet x = 1\n```\n")
        // Cursor on the "before" line so opener/closer are "off-fence".
        storage.cursorRange = NSRange(location: 0, length: 0)
        // "before\n" = 7 chars; opener starts at 7 with `` ``` `` (3),
        // then `swift` (5). So index 10 is 's' of "swift".
        let langAttrs = storage.attributes(at: 10, effectiveRange: nil)
        let tickAttrs = storage.attributes(at: 7, effectiveRange: nil)
        let langColor = langAttrs[.foregroundColor] as? UIColor
        let tickColor = tickAttrs[.foregroundColor] as? UIColor
        // Backticks fade to clear; the language word stays visible.
        #expect(tickColor == UIColor.clear)
        #expect(langColor != UIColor.clear)
    }

    @Test func fenceOpenerAndCloserIndentToBodyColumn() {
        // Opener / closer ``` lines indent to one regular indent (four
        // body-font spaces) so the apostrophes line up with the body
        // AND with a sibling Tab-indented plain-text line. Body font
        // (not mono) so the column matches what `Tab` inserts as
        // four-space indent. The paragraph style only covers the
        // marker chars themselves, NOT the trailing newline — so the
        // line just past the closer keeps the default style and the
        // cursor there blinks at column 0, not inside the panel.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "```\nhello\n```")
        let spaceWidth = (" " as NSString).size(withAttributes: [
            .font: UIFont.preferredFont(forTextStyle: .body)
        ]).width
        let openerAttrs = storage.attributes(at: 0, effectiveRange: nil)   // first ` of opener
        let closerAttrs = storage.attributes(at: 10, effectiveRange: nil)  // first ` of closer
        let openerP = openerAttrs[.paragraphStyle] as? NSParagraphStyle
        let closerP = closerAttrs[.paragraphStyle] as? NSParagraphStyle
        #expect(abs((openerP?.firstLineHeadIndent ?? 0) - 4 * spaceWidth) < 0.5)
        #expect(abs((closerP?.firstLineHeadIndent ?? 0) - 4 * spaceWidth) < 0.5)
    }

    @Test func codeBodyHeadIndentIsFourBodySpaces() {
        // Code body indents to one regular indent (four body-font
        // spaces) so a fence block aligns with a sibling Tab-indented
        // plain-text line. Body font (not mono) because mono spaces
        // are wider, which would push the code past where Tab puts
        // plain content.
        let storage = MarkdownStyler()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0),
                                  with: "```\nhello\n```")
        // 'h' in "hello" — first body char.
        let attrs = storage.attributes(at: 4, effectiveRange: nil)
        let p = attrs[.paragraphStyle] as? NSParagraphStyle
        let spaceWidth = (" " as NSString).size(withAttributes: [
            .font: UIFont.preferredFont(forTextStyle: .body)
        ]).width
        #expect(abs((p?.firstLineHeadIndent ?? 0) - 4 * spaceWidth) < 0.5)
    }

    // MARK: Sibling task rows — uniform attribute application

    /// Reproduces the user-reported "sibling rows misalign" bug at the
    /// source level. After styling, EVERY task line's marker chars
    /// (`-`, ` `, `[`, ` `, `]`) must have the zero-width font. If any
    /// row's marker chars carry body font instead, that row renders
    /// ~one indent unit too far right.
    @Test func everyTaskRowsMarkerCharsAreZeroWidthFonted() {
        let storage = MarkdownStyler()
        let source = "- [ ] 1\n- [ ] 2\n- [ ] 3\n- [ ] 4\nA"
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        // Cursor on the last line ("A") so it can't be the "current line
        // is special" exemption that exists for some marker types.
        storage.cursorRange = NSRange(location: (source as NSString).length,
                                      length: 0)
        let lineStarts = [0, 8, 16, 24]  // 4 task lines, each 7+1 chars
        for (idx, start) in lineStarts.enumerated() {
            // Marker chars at line offsets 0..4 inclusive: `-`, ` `, `[`, ` `, `]`
            for offset in 0...4 {
                let charIdx = start + offset
                let attrs = storage.attributes(at: charIdx, effectiveRange: nil)
                let font = attrs[.font] as? UIFont
                #expect(
                    (font?.pointSize ?? 0) < 1.0,
                    "Row \(idx + 1) char \(offset) at index \(charIdx) has font size \(font?.pointSize ?? -1) (expected ~0.01pt)"
                )
            }
            // Trailing space at offset 5 keeps body font and gets kern.
            let trailingAttrs = storage.attributes(at: start + 5, effectiveRange: nil)
            let trailingFont = trailingAttrs[.font] as? UIFont
            let kern = trailingAttrs[.kern] as? CGFloat ?? 0
            #expect(
                (trailingFont?.pointSize ?? 0) > 10,
                "Row \(idx + 1) trailing space has unexpectedly small font \(trailingFont?.pointSize ?? -1)"
            )
            #expect(kern > 10, "Row \(idx + 1) trailing space kern \(kern) too small")
        }
    }

    /// Identical to the next test but uses the production
    /// `MarkdownLayoutManager` + delegate setup (instead of a bare
    /// NSLayoutManager). If the visible drift is caused by the
    /// delegate's glyph-property mutation (`.null` on hide chars) NOT
    /// being honored for advance-calculation post-edit, this test
    /// reproduces it where the bare-NSLayoutManager test does not.
    @Test func taskRowsRenderUniformlyThroughProductionLayoutManager() {
        let storage = MarkdownStyler()
        let layout = MarkdownLayoutManager()
        let delegate = MarkdownLayoutDelegate()
        delegate.styler = storage
        layout.delegate = delegate
        let container = NSTextContainer(size: CGSize(width: 400,
                                                      height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        storage.glyphInvalidatable = layout

        let keystrokes = ["- [ ] 1", "\n", "- [ ] 2", "\n", "- [ ] 3", "\n",
                          "- [ ] 4", "\n", "- [ ] A"]
        var caret = 0
        for stroke in keystrokes {
            storage.replaceCharacters(in: NSRange(location: caret, length: 0),
                                      with: stroke)
            caret += (stroke as NSString).length
            let chars = NSRange(location: 0, length: storage.length)
            let glyphs = layout.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
            layout.ensureLayout(forGlyphRange: glyphs)
        }
        storage.cursorRange = NSRange(location: storage.length, length: 0)
        let chars = NSRange(location: 0, length: storage.length)
        let glyphs = layout.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
        layout.ensureGlyphs(forCharacterRange: chars)
        layout.ensureLayout(forGlyphRange: glyphs)

        // Assert: all content at same x.
        var contentMinXs: [CGFloat] = []
        for contentChar in [6, 14, 22, 30, 38] {
            let glyphIndex = layout.glyphIndexForCharacter(at: contentChar)
            let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1),
                                           in: container)
            contentMinXs.append(rect.minX)
        }
        let reference = contentMinXs[0]
        for (idx, value) in contentMinXs.enumerated() {
            #expect(
                abs(value - reference) < 0.5,
                "Row \(idx + 1) content minX=\(value) ≠ row 1's \(reference). All=\(contentMinXs)"
            )
        }
    }

    /// Incremental-edit reproduction of the user-visible sibling drift.
    /// The "all-at-once" layout case below passes, suggesting the bug
    /// only manifests when the LM's caches accumulate state from
    /// per-keystroke edits. This test mimics the real-app typing flow:
    /// type "- [ ] 1", Enter, "2", Enter, "3", Enter, "4", Enter,
    /// "A" — each character through `replaceCharacters` so processEditing
    /// fires per-char like UITextView does, with `ensureLayout` between
    /// to let any cache divergence accumulate.
    @Test func taskRowsLineFragmentRectMinXSurvivesIncrementalEdits() {
        let storage = MarkdownStyler()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 400,
                                                      height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        // Simulate per-keystroke insertion (matches UITextView behavior).
        let keystrokes = ["- [ ] 1", "\n", "- [ ] 2", "\n", "- [ ] 3", "\n",
                          "- [ ] 4", "\n", "- [ ] A"]
        var caret = 0
        for stroke in keystrokes {
            storage.replaceCharacters(in: NSRange(location: caret, length: 0),
                                      with: stroke)
            caret += (stroke as NSString).length
            // Force layout after each keystroke to let any caching bug accumulate.
            let chars = NSRange(location: 0, length: storage.length)
            let glyphs = layout.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
            layout.ensureLayout(forGlyphRange: glyphs)
        }
        storage.cursorRange = NSRange(location: storage.length, length: 0)
        let chars = NSRange(location: 0, length: storage.length)
        let glyphs = layout.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
        layout.ensureLayout(forGlyphRange: glyphs)

        var minXs: [CGFloat] = []
        for lineStart in [0, 8, 16, 24, 32] {
            let glyphIndex = layout.glyphIndexForCharacter(at: lineStart)
            let rect = layout.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            minXs.append(rect.minX)
        }
        let reference = minXs[0]
        for (idx, value) in minXs.enumerated() {
            #expect(
                abs(value - reference) < 0.5,
                "After incremental edits, row \(idx + 1) minX=\(value) ≠ row 1's \(reference). All minXs=\(minXs)"
            )
        }
    }

    /// Layout-level reproduction of the user-visible sibling drift. We
    /// create the styler + a real NSLayoutManager + NSTextContainer
    /// and force layout, then query `lineFragmentRect.minX` for each
    /// task row's first glyph. All rows share source-level indent 0,
    /// so all minX values must be equal (and small — just textContainer
    /// inset + lineFragmentPadding). If TextKit is drifting subsequent
    /// paragraphs' first lines to `headIndent` instead of
    /// `firstLineHeadIndent`, this test exposes it directly.
    @Test func everyTaskRowsLineFragmentRectMinXIsUniform() {
        let storage = MarkdownStyler()
        let source = "- [ ] 1\n- [ ] 2\n- [ ] 3\n- [ ] 4\n- [ ] A"
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        // Cursor at end so all rows are off-cursor (matches the user's
        // visible-bug scenario).
        storage.cursorRange = NSRange(location: (source as NSString).length, length: 0)

        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        // Force complete glyph + layout generation.
        let fullChars = NSRange(location: 0, length: storage.length)
        let fullGlyphs = layout.glyphRange(forCharacterRange: fullChars, actualCharacterRange: nil)
        layout.ensureGlyphs(forCharacterRange: fullChars)
        layout.ensureLayout(forGlyphRange: fullGlyphs)

        // Each task line starts at chars 0, 8, 16, 24, 32. Read the
        // line fragment rect for the FIRST glyph of each line.
        var minXs: [CGFloat] = []
        for lineStart in [0, 8, 16, 24, 32] {
            let glyphIndex = layout.glyphIndexForCharacter(at: lineStart)
            let rect = layout.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            minXs.append(rect.minX)
        }
        let reference = minXs[0]
        for (idx, value) in minXs.enumerated() {
            #expect(
                abs(value - reference) < 0.5,
                "Row \(idx + 1) lineFragmentRect.minX=\(value) ≠ row 1's \(reference) — TextKit is drifting!"
            )
        }
    }

    /// All task rows at the same nesting depth must carry IDENTICAL
    /// paragraph-style `firstLineHeadIndent` values. If even one row's
    /// paragraph style is different, the SF-Symbol overlay (drawn at
    /// firstLineHeadIndent) and the content (positioned by the
    /// typesetter using the same value) will diverge across siblings.
    @Test func everyTaskRowsParagraphStyleFirstLineHeadIndentIsUniform() {
        let storage = MarkdownStyler()
        let source = "- [ ] 1\n- [ ] 2\n- [ ] 3\n- [ ] 4\nA"
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        storage.cursorRange = NSRange(location: (source as NSString).length,
                                      length: 0)
        let lineStarts = [0, 8, 16, 24]
        var firstLineIndents: [CGFloat] = []
        for start in lineStarts {
            // Read paragraph style at line-start (char 0 of each task).
            let attrs = storage.attributes(at: start, effectiveRange: nil)
            let p = attrs[.paragraphStyle] as? NSParagraphStyle
            firstLineIndents.append(p?.firstLineHeadIndent ?? -1)
        }
        // All four rows share the same source indent (none) — their
        // firstLineHeadIndent must match exactly.
        let reference = firstLineIndents[0]
        for (idx, value) in firstLineIndents.enumerated() {
            #expect(
                abs(value - reference) < 0.01,
                "Row \(idx + 1) firstLineHeadIndent \(value) ≠ row 1's \(reference)"
            )
        }
        // And for top-level tasks, all four should be ~0.
        #expect(abs(reference) < 0.5, "Top-level firstLineHeadIndent \(reference) should be ~0")
    }
}
