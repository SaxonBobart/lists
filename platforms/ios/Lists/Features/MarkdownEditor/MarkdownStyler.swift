import UIKit

/// Editor display mode.
/// - `live`: Bear-style. Markers hide instantly when the cursor leaves
///   their **context** (a single line for block markers; the marker
///   span itself for inline ones). On-context markers show dimmed.
/// - `raw`: Code-editor view. Everything monospaced, syntax markers
///   tinted in a neutral system color. Nothing is ever hidden.
public enum MarkdownEditorMode: String, CaseIterable, Hashable {
    case live
    case raw
}

/// `NSTextStorage` subclass that applies live markdown formatting and
/// publishes per-character glyph metadata for the layout manager
/// delegate to hide / substitute glyphs.
///
/// Plain-text storage — what the user types is what the binding hands
/// back. Visibility is purely a display concern.
///
/// Target flavor: CommonMark + GFM plus small editor extensions where they
/// preserve well as text (`==highlight==`; legacy `<mark data-color="...">`
/// remains readable).
/// Tags are metadata, not Markdown syntax; a literal `#word` in a document
/// remains user text.
final class MarkdownStyler: NSTextStorage {

    private let backing = NSMutableAttributedString()

    // MARK: External state

    public var mode: MarkdownEditorMode = .live {
        didSet {
            guard oldValue != mode else { return }
            beginEditing()
            edited(.editedAttributes,
                   range: NSRange(location: 0, length: backing.length),
                   changeInLength: 0)
            endEditing()
        }
    }

    /// Cursor position. `NSNotFound` location means "no cursor" — all
    /// markers stay hidden (initial open, focus lost).
    public var cursorRange: NSRange = NSRange(location: NSNotFound, length: 0) {
        didSet { invalidateForCursorChange(oldValue: oldValue, newValue: cursorRange) }
    }

    /// Weak; for invalidation via the framework's edit-notification path
    /// which is more reliable than direct `invalidateGlyphs` calls.
    public weak var glyphInvalidatable: NSLayoutManager?

    // MARK: Tokenization caches (rebuilt every processEditing)

    private var hideIndices: Set<Int> = []
    private var substitutionMap: [Int: unichar] = [:]

    /// Per-character context range. For block markers (heading, list,
    /// task, blockquote, fence), this is the full line. For inline
    /// markers (bold, italic, code, strike, highlight, link), this is
    /// the marker span itself (open through close, inclusive). The
    /// cursor must intersect this range for the marker to stay visible.
    private var contextRangeByCharIndex: [Int: NSRange] = [:]

    /// Line ranges for every fence opener and closer in the document.
    /// Whole-fence cursor awareness means these lines need glyph
    /// re-generation on every cursor move, not just when the cursor
    /// passes through them. Cached during `applyLiveStyling` and
    /// unioned into the `invalidateForCursorChange` range set.
    private var fenceMarkerLineRanges: [NSRange] = []

    // MARK: NSTextStorage required overrides

    override var string: String { backing.string }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range,
               changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    func invalidateLayoutDependentStyling() {
        guard backing.length > 0 else { return }
        beginEditing()
        edited([.editedAttributes, .editedCharacters],
               range: NSRange(location: 0, length: backing.length),
               changeInLength: 0)
        endEditing()
    }

    // MARK: Highlight hook

    override func processEditing() {
        clearTokens()
        let full = NSRange(location: 0, length: backing.length)
        applyBaseAttributes(in: full)
        switch mode {
        case .live: applyLiveStyling(in: full)
        case .raw:  applyRawStyling(in: full)
        }
        // Critical: `applyBaseAttributes` and `applyLiveStyling` mutate
        // `backing` (the underlying NSMutableAttributedString) directly,
        // bypassing this NSTextStorage subclass's edit-notification path.
        // Result: the framework only auto-invalidates the originally
        // edited range, so sibling list rows whose attributes WE just
        // re-touched keep their stale GLYPH cache (the most visible
        // symptom: a row's leading marker glyphs stuck at body-font
        // width even though we just gave them the zero-width font, which
        // shoves the row visibly farther right). `.editedAttributes`
        // alone only invalidates layout; `.editedCharacters` (even with
        // changeInLength: 0) is what tells the layout manager to
        // invalidate GLYPHS too. Combining both expands the edited
        // range to full-doc and forces glyph + layout regen as part of
        // this edit cycle, before any draw. Safe inside processEditing
        // — that's the documented place to call `edited`.
        if full.length > 0 {
            edited([.editedAttributes, .editedCharacters],
                   range: full,
                   changeInLength: 0)
        }
        super.processEditing()
    }

    private func clearTokens() {
        hideIndices.removeAll(keepingCapacity: true)
        substitutionMap.removeAll(keepingCapacity: true)
        contextRangeByCharIndex.removeAll(keepingCapacity: true)
        fenceMarkerLineRanges.removeAll(keepingCapacity: true)
    }

    private func applyBaseAttributes(in range: NSRange) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.label,
            .paragraphStyle: defaultParagraphStyle
        ]
        backing.setAttributes(attrs, range: range)
    }

    // MARK: Glyph metadata (queried by the layout manager delegate)

    public func glyphProperty(at charIndex: Int) -> NSLayoutManager.GlyphProperty? {
        if mode == .raw { return nil }
        guard hideIndices.contains(charIndex) else { return nil }
        if cursorOnContextContaining(charIndex) { return nil }
        return .null
    }

    public func glyphSubstitution(at charIndex: Int) -> unichar? {
        if mode == .raw { return nil }
        guard let sub = substitutionMap[charIndex] else { return nil }
        if cursorOnContextContaining(charIndex) { return nil }
        return sub
    }

    private func cursorOnContextContaining(_ charIndex: Int) -> Bool {
        guard cursorRange.location != NSNotFound else { return false }
        guard let context = contextRangeByCharIndex[charIndex] else { return false }
        let loc = cursorRange.location
        return loc >= context.location && loc <= NSMaxRange(context)
    }

    // MARK: Cursor change → re-trigger styling

    /// Fires on EVERY cursor move (not just line crossings) — necessary
    /// for per-span inline marker awareness. Goes through the framework
    /// edit-notification path so glyph regen + display refresh follow
    /// reliably; lighter-weight `invalidateGlyphs` alone has proven
    /// flaky for direction-dependent moves on iOS 26.
    private func invalidateForCursorChange(oldValue: NSRange, newValue: NSRange) {
        let oldLine = lineRangeOfPosition(oldValue.location)
        let newLine = lineRangeOfPosition(newValue.location)
        var ranges: Set<NSRange> = []
        if let r = oldLine { ranges.insert(r) }
        if let r = newLine { ranges.insert(r) }
        // Whole-fence cursor context: opener / closer markers reside on
        // lines DIFFERENT from where the cursor lives, so they would
        // never be invalidated by old/new alone. Re-edit them on every
        // cursor move so the layout manager regenerates their glyphs.
        for r in fenceMarkerLineRanges { ranges.insert(r) }
        if ranges.isEmpty { return }

        beginEditing()
        for r in ranges {
            edited(.editedAttributes, range: r, changeInLength: 0)
        }
        endEditing()
        // endEditing → processEditing now expands the edited range to
        // the full document (see `processEditing` above), so the
        // framework invalidates glyphs + layout doc-wide as part of
        // this edit cycle. No follow-up invalidate needed.
    }

    private func lineRangeOfPosition(_ position: Int) -> NSRange? {
        guard position != NSNotFound, backing.length > 0 else { return nil }
        let clamped = min(position, backing.length)
        return (backing.string as NSString).paragraphRange(for: NSRange(location: clamped, length: 0))
    }

    // MARK: Live styling

    private func applyLiveStyling(in range: NSRange) {
        let source = backing.string as NSString
        let (fenceContent, fenceFull) = fenceRanges(in: source, within: range)
        for r in fenceContent { styleAsCode(range: r) }
        let mathDisplayRanges = ExtensionParsers.mathDisplayRanges(in: backing.string)
        for math in mathDisplayRanges {
            if math.inner.length > 0 {
                styleAsCode(range: math.inner)
            }
            if math.full.length > 0 {
                backing.addAttribute(.codeBlockBody, value: true, range: math.full)
            }
        }

        // Whole-fence panel — opener line + body + closer line all get
        // `.codeBlockBody = true` so `MarkdownLayoutManager` paints ONE
        // continuous rounded background spanning the entire block (the
        // way Bear / Apple Notes does it). Includes the newline chars
        // between lines so the attribute run is unbroken.
        for r in fenceFull { backing.addAttribute(.codeBlockBody, value: true, range: r) }

        // Cache opener + closer line ranges for cursor-change invalidation.
        for fence in fenceFull where fence.length > 0 {
            let opener = source.lineRange(for: NSRange(location: fence.location, length: 0))
            fenceMarkerLineRanges.append(opener)
            let lastIdx = max(NSMaxRange(fence) - 1, fence.location)
            let closer = source.lineRange(for: NSRange(location: lastIdx, length: 0))
            if closer.location != opener.location {
                fenceMarkerLineRanges.append(closer)
            }
        }

        source.enumerateSubstrings(in: range, options: .byLines) { line, _, lineRange, _ in
            if fenceContent.contains(where: { NSLocationInRange(lineRange.location, $0) }) { return }
            if mathDisplayRanges.contains(where: { NSLocationInRange(lineRange.location, $0.inner) }) { return }
            self.styleLineLive(line: line ?? "", lineRange: lineRange, fenceFullRanges: fenceFull)
        }
    }

    private func styleLineLive(line: String, lineRange: NSRange, fenceFullRanges: [NSRange]) {
        let lineNS = line as NSString
        let lineLen = lineNS.length
        let fullLine = NSRange(location: lineRange.location, length: lineLen)

        // Fence open / close lines — same iOS 26 collapse trap as HR:
        // `.null` glyphs would zero out the line height and crush the
        // rounded panel onto adjacent text. So source chars stay laid
        // out and we toggle between `.tertiaryLabel` (cursor anywhere
        // inside the fence — markers dimmed and visible) and `.clear`
        // (cursor outside — markers invisible, panel still spans the
        // line). Fence context is the WHOLE fence range. The opener may
        // carry a GFM-style language hint (` ```swift `); we keep that
        // word visible at .tertiaryLabel so the user can see what
        // language they tagged even after the cursor moves away.
        if line.hasPrefix("```") {
            let ctx = fenceFullRanges.first(where: { NSLocationInRange(fullLine.location, $0) }) ?? fullLine
            let onFence = isCursorLineWithin(ctx)
            backing.addAttribute(.font, value: monoBodyFont, range: fullLine)
            // Indent the opener / closer ``` to the same column as the
            // body — visually the apostrophes line up with the code on
            // every fence line, AND with a sibling indented-text line.
            // Body-font space width (NOT mono) so the column matches
            // what a Tab insert (`    `) puts plain text at. The
            // paragraph style applies only to the marker chars (not
            // the trailing newline, which is outside `fullLine`), so a
            // fresh cursor on the line just past the closer blinks at
            // column 0, not inside the panel. See also: the cursor at
            // EOF when the doc ends with the closer's `\n` would
            // otherwise inherit the closer's indent — that's handled in
            // `MarkdownTextView` by overriding `typingAttributes`.
            let p = NSMutableParagraphStyle()
            p.firstLineHeadIndent = indentWidth
            p.headIndent = indentWidth
            p.lineHeightMultiple = 1.2
            backing.addAttribute(.paragraphStyle, value: p, range: fullLine)

            if let m = Self.fenceMarkerRegex.firstMatch(in: line, range: NSRange(location: 0, length: lineLen)),
               m.numberOfRanges >= 3 {
                let tickRange = m.range(at: 1)
                let langRange = m.range(at: 2)
                let absTick = NSRange(location: lineRange.location + tickRange.location, length: tickRange.length)
                backing.addAttribute(.foregroundColor,
                                     value: onFence ? UIColor.tertiaryLabel : UIColor.clear,
                                     range: absTick)
                if langRange.length > 0 {
                    let absLang = NSRange(location: lineRange.location + langRange.location, length: langRange.length)
                    backing.addAttribute(.foregroundColor,
                                         value: UIColor.tertiaryLabel,
                                         range: absLang)
                }
            } else {
                backing.addAttribute(.foregroundColor,
                                     value: onFence ? UIColor.tertiaryLabel : UIColor.clear,
                                     range: fullLine)
            }
            return
        }

        // Horizontal rule — `^---+`, `^***+`, or `^___+` on a line
        // alone. Cursor on the line: show source dimmed (no rule). Off:
        // make markers transparent (`.clear`) and tag the paragraph
        // with `.horizontalRule` so `MarkdownLayoutManager` strokes a
        // 0.5pt separator across the line. NB: deliberately NOT using
        // `.null` glyph property — on iOS 26, an all-null line
        // collapses to zero height and the rule renders on top of the
        // preceding heading. Transparent glyphs keep the line fragment
        // alive with its natural height.
        if let m = Self.horizontalRuleRegex.firstMatch(in: line, range: NSRange(location: 0, length: lineLen)),
           m.numberOfRanges >= 2 {
            let markerRange = m.range(at: 1)
            let absMarker = NSRange(location: lineRange.location + markerRange.location,
                                    length: markerRange.length)
            let onLine = isCursorOnRange(fullLine)
            if onLine {
                backing.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: absMarker)
            } else {
                backing.addAttribute(.foregroundColor, value: UIColor.clear, range: absMarker)
                backing.addAttribute(.horizontalRule, value: true, range: fullLine)
            }
            let p = NSMutableParagraphStyle()
            p.paragraphSpacingBefore = 8
            p.paragraphSpacing = 8
            p.minimumLineHeight = bodyFont.lineHeight
            p.lineHeightMultiple = 1.2
            backing.addAttribute(.paragraphStyle, value: p, range: fullLine)
            return
        }

        if MarkdownSyntax.isTableRow(line) {
            applyTableLive(line: line,
                           lineRange: lineRange,
                           fullLine: fullLine)
            return
        }

        // Heading
        if let m = Self.headingRegex.firstMatch(in: line, range: NSRange(location: 0, length: lineLen)) {
            let hashRange = m.range(at: 1)
            let level = min(hashRange.length, 6)
            backing.addAttribute(.font, value: headingFont(level: level), range: fullLine)
            backing.addAttribute(.foregroundColor, value: UIColor.label, range: fullLine)
            let hideLen = min(hashRange.length + 1, lineLen)
            let hideRange = NSRange(location: lineRange.location, length: hideLen)
            if isCursorOnRange(fullLine) {
                backing.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: hideRange)
            } else {
                registerHideZeroWidth(hideRange, contextRange: nil)
                backing.addAttribute(.foregroundColor, value: UIColor.clear, range: hideRange)
            }
            return
        }

        // Quoted task list — `> - [ ] do` or `>     - [x] do`.
        if let m = Self.quotedTaskRegex.firstMatch(in: line, range: NSRange(location: 0, length: lineLen)),
           m.numberOfRanges >= 6 {
            let quoteRange = m.range(at: 1)
            let wsRange = m.range(at: 2)
            let bulletRange = m.range(at: 3)
            let bracketRange = m.range(at: 4)
            let stateRange = m.range(at: 5)
            let quoteIndent = applyQuotePrefix(quoteRange,
                                               line: lineNS,
                                               lineRange: lineRange,
                                               lineLength: lineLen,
                                               fullLine: fullLine)
            let isChecked = lineNS.substring(with: stateRange).lowercased() == "x"

            registerLeadingWhitespace(wsRange, lineRange: lineRange, fullLine: fullLine)

            let bulletHide = NSRange(location: lineRange.location + bulletRange.location,
                                     length: bulletRange.length + 1)
            registerHideZeroWidth(bulletHide, contextRange: nil)
            backing.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: bulletHide)

            let bracketStart = lineRange.location + bracketRange.location
            substitutionMap[bracketStart] = isChecked ? 0x2611 : 0x2610
            backing.addAttribute(.font, value: zeroWidthFont,
                                 range: NSRange(location: bracketStart, length: 1))

            let innerStart = bracketRange.location + 1
            let innerLen = max(0, NSMaxRange(bracketRange) - innerStart)
            if innerLen > 0 {
                let innerHide = NSRange(location: lineRange.location + innerStart, length: innerLen)
                registerHideZeroWidth(innerHide, contextRange: nil)
            }

            let markerCharRange = NSRange(location: bracketStart, length: 1)
            backing.addAttribute(.sfSymbolCheckbox,
                                 value: isChecked ? "checkmark.square.fill" : "square",
                                 range: markerCharRange)
            backing.addAttribute(.foregroundColor, value: UIColor.clear, range: markerCharRange)

            let trailingSpaceAbs = NSRange(
                location: lineRange.location + NSMaxRange(bracketRange),
                length: 1
            )
            applyQuotedListIndent(lineRange: lineRange,
                                  length: lineLen,
                                  quoteIndent: quoteIndent,
                                  leadingWhitespace: lineNS.substring(with: wsRange),
                                  fullLine: fullLine,
                                  markerAdvance: -MarkdownChecklistMetrics.textGap,
                                  trailingSpaceAbsRange: trailingSpaceAbs)
            applyInlineLive(line: line, lineRange: lineRange)
            return
        }

        // Quoted numbered list — `> 1. do` or `>     1. do`.
        if let m = Self.quotedNumberedListRegex.firstMatch(in: line, range: NSRange(location: 0, length: lineLen)),
           m.numberOfRanges >= 4 {
            let quoteRange = m.range(at: 1)
            let wsRange = m.range(at: 2)
            let markerRange = m.range(at: 3)
            let quoteIndent = applyQuotePrefix(quoteRange,
                                               line: lineNS,
                                               lineRange: lineRange,
                                               lineLength: lineLen,
                                               fullLine: fullLine)
            registerLeadingWhitespace(wsRange, lineRange: lineRange, fullLine: fullLine)
            let abs = NSRange(location: lineRange.location + markerRange.location,
                              length: markerRange.length)
            backing.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: abs)
            let markerText = lineNS.substring(with: markerRange)
            let markerAdvance = (markerText as NSString).size(withAttributes: [.font: bodyFont]).width
            let trailingSpaceAbs = NSRange(
                location: lineRange.location + NSMaxRange(markerRange),
                length: 1
            )
            applyQuotedListIndent(lineRange: lineRange,
                                  length: lineLen,
                                  quoteIndent: quoteIndent,
                                  leadingWhitespace: lineNS.substring(with: wsRange),
                                  fullLine: fullLine,
                                  markerAdvance: markerAdvance,
                                  trailingSpaceAbsRange: trailingSpaceAbs)
            applyInlineLive(line: line, lineRange: lineRange)
            return
        }

        // Quoted bulleted list — `> - do` or `>     - do`.
        if let m = Self.quotedBulletRegex.firstMatch(in: line, range: NSRange(location: 0, length: lineLen)),
           m.numberOfRanges >= 4 {
            let quoteRange = m.range(at: 1)
            let wsRange = m.range(at: 2)
            let markerRange = m.range(at: 3)
            let quoteIndent = applyQuotePrefix(quoteRange,
                                               line: lineNS,
                                               lineRange: lineRange,
                                               lineLength: lineLen,
                                               fullLine: fullLine)
            registerLeadingWhitespace(wsRange, lineRange: lineRange, fullLine: fullLine)
            let absMarker = NSRange(location: lineRange.location + markerRange.location,
                                    length: markerRange.length)
            substitutionMap[absMarker.location] = 0x2022
            backing.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: absMarker)
            let trailingSpaceAbs = NSRange(
                location: lineRange.location + NSMaxRange(markerRange),
                length: 1
            )
            applyQuotedListIndent(lineRange: lineRange,
                                  length: lineLen,
                                  quoteIndent: quoteIndent,
                                  leadingWhitespace: lineNS.substring(with: wsRange),
                                  fullLine: fullLine,
                                  markerAdvance: bulletGlyphAdvance,
                                  trailingSpaceAbsRange: trailingSpaceAbs)
            applyInlineLive(line: line, lineRange: lineRange)
            return
        }

        // Task list — `- [ ] do` or `- [x] do`. Group 1 is leading WS so
        // nested task lists (`  - [ ] sub`) are recognised. Use \s in
        // regex so iOS keyboard whitespace variations (NBSP, tab) match.
        if let m = Self.taskRegex.firstMatch(in: line, range: NSRange(location: 0, length: lineLen)),
           m.numberOfRanges >= 5 {
            let wsRange = m.range(at: 1)
            let bulletRange = m.range(at: 2)
            let bracketRange = m.range(at: 3)
            let stateRange = m.range(at: 4)
            let isChecked = lineNS.substring(with: stateRange).lowercased() == "x"

            registerLeadingWhitespace(wsRange, lineRange: lineRange, fullLine: fullLine)

            // Task markers render UNCONDITIONALLY (no
            // `contextRangeByCharIndex` entries) — checkbox glyph is
            // visible even while editing the line. AND the hides use
            // a 0.01pt font so the chars contribute essentially zero
            // advance, keeping the cursor at column 0 aligned with the
            // substituted ☐ at column 2.

            // Hide leading `- <space>` (bullet + space, after leading WS).
            let bulletHide = NSRange(location: lineRange.location + bulletRange.location,
                                     length: bulletRange.length + 1)
            registerHideZeroWidth(bulletHide, contextRange: nil)
            backing.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: bulletHide)

            // Substitute `[` → ☐ / ☑ in the layout's substitution map so
            // downstream paths (raw-mode toggles, tests) still see the
            // marker char. The font is collapsed to ~zero (0.01pt) so
            // the substituted Apple Symbols glyph itself contributes no
            // advance; the SF Symbol image overlay (below) renders the
            // visible checkbox via `MarkdownLayoutManager.drawGlyphs`.
            let bracketStart = lineRange.location + bracketRange.location
            substitutionMap[bracketStart] = isChecked ? 0x2611 : 0x2610
            backing.addAttribute(.font, value: zeroWidthFont,
                                 range: NSRange(location: bracketStart, length: 1))
            // Hide the rest of `[ ]` (state char + closing bracket).
            let innerStart = bracketRange.location + 1
            let innerLen = max(0, NSMaxRange(bracketRange) - innerStart)
            if innerLen > 0 {
                let innerHide = NSRange(location: lineRange.location + innerStart, length: innerLen)
                registerHideZeroWidth(innerHide, contextRange: nil)
            }

            // SF Symbols overlay — mark the `[` char with the SF Symbol
            // name so `MarkdownLayoutManager.drawGlyphs` paints the
            // checkbox image on top. The cell beneath is a 0.01pt-font
            // Apple Symbols glyph (set above) — invisible due to size
            // and `.foregroundColor = .clear` here. The image draws at
            // the line's left edge with its natural body-font size.
            let markerCharRange = NSRange(location: bracketStart, length: 1)
            backing.addAttribute(.sfSymbolCheckbox,
                                 value: isChecked ? "checkmark.square.fill" : "square",
                                 range: markerCharRange)
            backing.addAttribute(.foregroundColor, value: UIColor.clear, range: markerCharRange)

            // Indent + content-column kern. Trailing space is the char
            // immediately after the `]`. `markerAdvance` is 0 because
            // the `[` cell is collapsed to a 0.01pt font; the visible
            // checkbox is painted by the SF Symbol overlay in
            // `MarkdownLayoutManager.drawGlyphs` and doesn't influence
            // the typesetter's advance.
            let trailingSpaceAbs = NSRange(
                location: lineRange.location + NSMaxRange(bracketRange),
                length: 1
            )
            let leadingWS = lineNS.substring(with: wsRange)
            applyListIndent(lineRange: lineRange, length: lineLen,
                            leadingWhitespace: leadingWS, fullLine: fullLine,
                            markerAdvance: -MarkdownChecklistMetrics.textGap,
                            trailingSpaceAbsRange: trailingSpaceAbs)
            applyInlineLive(line: line, lineRange: lineRange)
            return
        }

        // Numbered list — group 1 leading WS, group 2 marker
        if let m = Self.numberedListRegex.firstMatch(in: line, range: NSRange(location: 0, length: lineLen)),
           m.numberOfRanges >= 3 {
            let wsRange = m.range(at: 1)
            let markerRange = m.range(at: 2)
            registerLeadingWhitespace(wsRange, lineRange: lineRange, fullLine: fullLine)
            let abs = NSRange(location: lineRange.location + markerRange.location,
                              length: markerRange.length)
            backing.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: abs)
            // Marker width varies (`1.` vs `100.`) — measure for kern.
            let markerText = lineNS.substring(with: markerRange)
            let markerAdvance = (markerText as NSString).size(withAttributes: [.font: bodyFont]).width
            let trailingSpaceAbs = NSRange(
                location: lineRange.location + NSMaxRange(markerRange),
                length: 1
            )
            let leadingWS = lineNS.substring(with: wsRange)
            applyListIndent(lineRange: lineRange, length: lineLen,
                            leadingWhitespace: leadingWS, fullLine: fullLine,
                            markerAdvance: markerAdvance,
                            trailingSpaceAbsRange: trailingSpaceAbs)
            applyInlineLive(line: line, lineRange: lineRange)
            return
        }

        // Bulleted list — group 1 leading WS, group 2 marker; substitute
        // `-` / `*` / `+` with `•` (standard bullet). Substitution is
        // unconditional (no cursor-context) so the dot appears the
        // instant the user types the space after `-`, instead of
        // waiting for the cursor to leave the line.
        if let m = Self.bulletRegex.firstMatch(in: line, range: NSRange(location: 0, length: lineLen)),
           m.numberOfRanges >= 3 {
            let wsRange = m.range(at: 1)
            let markerRange = m.range(at: 2)
            registerLeadingWhitespace(wsRange, lineRange: lineRange, fullLine: fullLine)
            let absMarker = NSRange(location: lineRange.location + markerRange.location,
                                    length: markerRange.length)
            substitutionMap[absMarker.location] = 0x2022  // •
            backing.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: absMarker)
            let trailingSpaceAbs = NSRange(
                location: lineRange.location + NSMaxRange(markerRange),
                length: 1
            )
            let leadingWS = lineNS.substring(with: wsRange)
            applyListIndent(lineRange: lineRange, length: lineLen,
                            leadingWhitespace: leadingWS, fullLine: fullLine,
                            markerAdvance: bulletGlyphAdvance,
                            trailingSpaceAbsRange: trailingSpaceAbs)
            applyInlineLive(line: line, lineRange: lineRange)
            return
        }

        // Blockquote/callout — support both `>>>` and Obsidian/GitHub-style
        // nested `> >` prefixes while keeping the source hidden in live mode.
        if let quote = Self.quotePrefix(in: line) {
            let level = quote.level
            let isActiveLine = isCursorOnRange(fullLine)
            let prefixRange = NSRange(location: lineRange.location + quote.range.location,
                                      length: quote.range.length)
            // Quote/callout layout must never depend on focus. Keep the real
            // source glyphs at full advance and only toggle their color. The
            // invisible syntax then reserves exactly the same geometry that
            // becomes editable when the cursor enters the line.
            backing.addAttribute(
                .foregroundColor,
                value: isActiveLine ? UIColor.tertiaryLabel : UIColor.clear,
                range: prefixRange
            )
            let calloutKind = Self.calloutKind(in: line, contentStart: NSMaxRange(quote.range))
            if calloutKind == nil, !isActiveLine {
                // Body/quote rows have no replacement overlay. Collapse only
                // their invisible quote prefix so content sits at the natural
                // inset for its nesting depth instead of paying for every `>`.
                backing.addAttribute(.font, value: zeroWidthFont, range: prefixRange)
            }
            let quoteTint = calloutKind.map(Self.calloutTint(for:)) ?? UIColor.separator
            backing.addAttribute(.quoteBlockTint, value: quoteTint, range: fullLine)

            let contentLoc = NSMaxRange(prefixRange)
            let contentLen = max(0, NSMaxRange(fullLine) - contentLoc)
            backing.addAttribute(.foregroundColor, value: UIColor.secondaryLabel,
                                 range: NSRange(location: contentLoc, length: contentLen))
            if let calloutKind {
                for marker in Self.calloutSyntaxRanges(in: line, contentStart: NSMaxRange(quote.range)) {
                    let absMarker = NSRange(location: lineRange.location + marker.location,
                                            length: marker.length)
                    backing.addAttribute(
                        .foregroundColor,
                        value: isActiveLine ? UIColor.tertiaryLabel : UIColor.clear,
                        range: absMarker
                    )
                }
                if contentLen > 0 {
                    backing.addAttribute(.foregroundColor,
                                         value: Self.calloutTint(for: calloutKind),
                                         range: NSRange(location: contentLoc, length: contentLen))
                    applyTraitPreservingFont(.traitBold,
                                             in: NSRange(location: contentLoc, length: contentLen))
                }
            }

            let p = NSMutableParagraphStyle()
            let baseIndent = CGFloat(20 * level)
            let quotePrefix = lineNS.substring(with: quote.range)
            let quotePrefixAdvance = quotePrefix.size(withAttributes: [.font: bodyFont]).width
            p.firstLineHeadIndent = baseIndent
            p.headIndent = baseIndent + ((calloutKind != nil || isActiveLine) ? quotePrefixAdvance : 0)
            // Keep text inside the rounded card at every depth. Active raw
            // prefixes consume leading width, so the trailing inset must be
            // explicit rather than relying on the full text-container edge.
            let nestedDepth = CGFloat(max(0, level - 1))
            p.tailIndent = -(12 + nestedDepth * 10)
            if calloutKind != nil {
                p.paragraphSpacingBefore = level > 1 ? 8 : 3
                p.paragraphSpacing = 4
            } else {
                p.paragraphSpacingBefore = 4
                p.paragraphSpacing = 4
            }
            p.lineHeightMultiple = 1.2
            backing.addAttribute(.paragraphStyle, value: p, range: fullLine)

            applyInlineLive(line: line, lineRange: lineRange)
            // Inline passes may touch syntax colors. Restore the focus-only
            // visibility without changing any font or paragraph metrics.
            backing.addAttribute(
                .foregroundColor,
                value: isActiveLine ? UIColor.tertiaryLabel : UIColor.clear,
                range: prefixRange
            )
            if calloutKind != nil {
                for marker in Self.calloutSyntaxRanges(in: line, contentStart: NSMaxRange(quote.range)) {
                    let absMarker = NSRange(location: lineRange.location + marker.location,
                                            length: marker.length)
                    backing.addAttribute(
                        .foregroundColor,
                        value: isActiveLine ? UIColor.tertiaryLabel : UIColor.clear,
                        range: absMarker
                    )
                }
                if !isActiveLine {
                    // The layout manager draws one normalized/custom title at
                    // the stable header position. Keep source glyph advances
                    // intact so focus cannot change line count or card height.
                    backing.addAttribute(.foregroundColor, value: UIColor.clear, range: fullLine)
                }
            } else if !isActiveLine {
                backing.addAttribute(.font, value: zeroWidthFont, range: prefixRange)
            }
            return
        }

        applyInlineLive(line: line, lineRange: lineRange)
    }

    /// Aligns every list / task / numbered row's *content* to the same
    /// x-coordinate (`(nestLevel + 1) * indentWidth`), regardless of how
    /// wide the marker glyph is. Approach:
    ///
    /// - First-line indent reserves the nested-level offset. Leading
    ///   whitespace is always zero-width in Live mode; Raw mode is the
    ///   place where the source spaces are shown directly.
    /// - `.kern` is added to the trailing space char so the total
    ///   advance `markerAdvance + spaceWidth + kern` equals `indentWidth`
    ///   (one indent level relative to the line's first-line indent).
    ///   Content lands flush at the indent column.
    /// - Wraps align with the content column via `headIndent`.
    ///
    /// `markerAdvance` is measured per marker type (• / ☐ / `1.` / `10.`).
    /// `trailingSpaceAbsRange` is the absolute range of the single space
    /// that separates the marker from the content. If the marker is too
    /// wide for the indent column (e.g. `100. foo`), kern is clamped
    /// at 0 — content sits at its natural position past the marker.
    private func applyListIndent(lineRange: NSRange,
                                 length: Int,
                                 leadingWhitespace: String,
                                 fullLine: NSRange,
                                 markerAdvance: CGFloat,
                                 trailingSpaceAbsRange: NSRange) {
        // Continuous (not quantized) WS-based indent. Live mode always
        // collapses the raw leading spaces and uses paragraph style for
        // their visual offset, so toolbar/hardware indent has an
        // immediate visible effect.
        let wsIndent = indentWidth(forLeadingWhitespace: leadingWhitespace)
        let firstLineIndent = wsIndent
        // Critical: `headIndent` must equal `firstLineHeadIndent` for
        // task / list rows. On iOS 26 (TextKit 1), NSLayoutManager
        // treats non-first paragraphs' first lines as if they were
        // wrapped lines — using `headIndent` for x-positioning instead
        // of `firstLineHeadIndent`. With them mismatched (e.g. fLHI=0,
        // hI=indentWidth), the second-and-later task rows visibly drift
        // right by one indent unit while the first row renders
        // correctly. Setting them equal eliminates the drift. Content
        // alignment is preserved by the trailing-space kern (computed
        // below), so wrapped lines still indent at the same column as
        // first-line content without needing a separate hI value.
        let p = NSMutableParagraphStyle()
        p.firstLineHeadIndent = firstLineIndent
        p.headIndent = firstLineIndent
        p.paragraphSpacing = 2
        p.lineHeightMultiple = 1.2
        backing.addAttribute(.paragraphStyle, value: p,
                             range: NSRange(location: lineRange.location, length: length))

        // Compute the kern on the trailing space so the content char
        // that follows lands at the indent column.
        let kern = indentWidth - markerAdvance - spaceWidth
        if kern > 0, trailingSpaceAbsRange.length > 0 {
            backing.addAttribute(.kern, value: kern, range: trailingSpaceAbsRange)
        }
    }

    private func applyQuotePrefix(_ quoteRange: NSRange,
                                  line: NSString,
                                  lineRange: NSRange,
                                  lineLength: Int,
                                  fullLine: NSRange) -> CGFloat {
        let absQuote = NSRange(location: lineRange.location + quoteRange.location,
                               length: quoteRange.length)
        registerHide(absQuote, contextRange: fullLine)
        backing.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: absQuote)

        let contentStart = lineRange.location + NSMaxRange(quoteRange)
        let contentLen = max(0, lineRange.location + lineLength - contentStart)
        if contentLen > 0 {
            backing.addAttribute(.foregroundColor,
                                 value: UIColor.secondaryLabel,
                                 range: NSRange(location: contentStart, length: contentLen))
        }
        backing.addAttribute(.quoteBlockTint, value: UIColor.separator, range: fullLine)

        let quotePrefix = line.substring(with: quoteRange)
        let level = quotePrefix.reduce(0) { count, character in
            character == ">" ? count + 1 : count
        }
        return CGFloat(16 * max(level, 1))
    }

    private struct QuotePrefix {
        let range: NSRange
        let level: Int
    }

    private static func quotePrefix(in line: String) -> QuotePrefix? {
        let ns = line as NSString
        var index = 0
        var level = 0
        while index < ns.length {
            while index < ns.length, ns.character(at: index) == 0x20 {
                index += 1
            }
            guard index < ns.length, ns.character(at: index) == 0x3E else { break }
            level += 1
            index += 1
            if index < ns.length, ns.character(at: index) == 0x20 {
                index += 1
            }
        }
        guard level > 0 else { return nil }
        return QuotePrefix(range: NSRange(location: 0, length: index), level: level)
    }

    private static func calloutKind(in line: String, contentStart: Int) -> String? {
        guard let match = calloutMatch(in: line, contentStart: contentStart),
              match.numberOfRanges >= 2 else {
            return nil
        }
        return (line as NSString).substring(with: match.range(at: 1)).uppercased()
    }

    private static func calloutSyntaxRanges(in line: String, contentStart: Int) -> [NSRange] {
        guard let match = calloutMatch(in: line, contentStart: contentStart) else {
            return []
        }
        let typeRange = match.range(at: 1)
        guard typeRange.location != NSNotFound else { return [] }
        var ranges = [
            NSRange(location: match.range(at: 0).location, length: 2),
            NSRange(location: NSMaxRange(typeRange), length: 1)
        ]
        let afterBracket = NSMaxRange(typeRange) + 1
        let ns = line as NSString
        if afterBracket < ns.length {
            let character = ns.character(at: afterBracket)
            if character == 0x2B || character == 0x2D {
                ranges.append(NSRange(location: afterBracket, length: 1))
            }
        }
        return ranges
    }

    private static func calloutMatch(in line: String, contentStart: Int) -> NSTextCheckingResult? {
        let ns = line as NSString
        guard contentStart < ns.length else { return nil }
        let range = NSRange(location: contentStart, length: ns.length - contentStart)
        return calloutRegex.firstMatch(in: line, range: range)
    }

    private static func calloutTint(for kind: String) -> UIColor {
        switch kind {
        case "TIP": return .systemGreen
        case "IMPORTANT": return .systemPurple
        case "WARNING": return .systemOrange
        case "CAUTION": return .systemRed
        default: return .systemBlue
        }
    }

    private func applyQuotedListIndent(lineRange: NSRange,
                                       length: Int,
                                       quoteIndent: CGFloat,
                                       leadingWhitespace: String,
                                       fullLine: NSRange,
                                       markerAdvance: CGFloat,
                                       trailingSpaceAbsRange: NSRange) {
        let wsIndent = indentWidth(forLeadingWhitespace: leadingWhitespace)
        let firstLineIndent = quoteIndent + wsIndent

        // Same iOS 26 headIndent quirk as `applyListIndent`: TextKit 1
        // uses `headIndent` (not `firstLineHeadIndent`) to position
        // non-first paragraphs' first lines. Set them equal to prevent
        // sibling rows from drifting right.
        let p = NSMutableParagraphStyle()
        p.firstLineHeadIndent = firstLineIndent
        p.headIndent = firstLineIndent
        p.paragraphSpacing = 2
        p.lineHeightMultiple = 1.2
        backing.addAttribute(.paragraphStyle, value: p,
                             range: NSRange(location: lineRange.location, length: length))

        let kern = indentWidth - markerAdvance - spaceWidth
        if kern > 0, trailingSpaceAbsRange.length > 0 {
            backing.addAttribute(.kern, value: kern, range: trailingSpaceAbsRange)
        }
    }

    private func applyTableLive(line: String, lineRange: NSRange, fullLine: NSRange) {
        let isDivider = MarkdownSyntax.isTableDivider(line)
        if isDivider {
            backing.addAttribute(.foregroundColor, value: UIColor.clear, range: fullLine)
            backing.addAttribute(.font, value: zeroWidthFont, range: fullLine)
            let p = NSMutableParagraphStyle()
            p.minimumLineHeight = 0.01
            p.maximumLineHeight = 0.01
            p.paragraphSpacing = 0
            backing.addAttribute(.paragraphStyle, value: p, range: fullLine)
            return
        }

        let isHeader = nextLineIsTableDivider(after: lineRange)
        let table = MarkdownTableParser.table(containing: NSRange(location: lineRange.location, length: 0),
                                              in: backing.string)
        let cells = MarkdownTableParser.cells(in: line, lineRange: lineRange)
        let columnCount = max(1, table?.columnCount ?? cells.count)
        backing.addAttribute(.markdownTableRow,
                             value: isHeader ? MarkdownTableRowRole.header.rawValue : MarkdownTableRowRole.body.rawValue,
                             range: fullLine)
        backing.addAttribute(.font, value: bodyFont, range: fullLine)
        backing.addAttribute(.foregroundColor, value: UIColor.clear, range: fullLine)

        let p = NSMutableParagraphStyle()
        let rowHeight = MarkdownTableVisualMetrics.rowHeight(for: bodyFont)
        p.minimumLineHeight = rowHeight
        p.maximumLineHeight = rowHeight
        p.lineHeightMultiple = 1.0
        p.paragraphSpacing = 0
        backing.addAttribute(.paragraphStyle, value: p, range: fullLine)

        backing.addAttribute(.foregroundColor, value: UIColor.clear, range: fullLine)
        hideEscapedTablePipeBackslashes(in: line, lineRange: lineRange, fullLine: fullLine)
        applyTableColumnKerns(line: line,
                              lineRange: lineRange,
                              cells: cells,
                              columnCount: columnCount)
        backing.addAttribute(.foregroundColor, value: UIColor.clear, range: fullLine)
    }

    private func nextLineIsTableDivider(after lineRange: NSRange) -> Bool {
        let ns = backing.string as NSString
        let nextStart = NSMaxRange(lineRange)
        guard nextStart < ns.length else { return false }
        let nextRange = ns.lineRange(for: NSRange(location: nextStart, length: 0))
        return MarkdownSyntax.isTableDivider(MarkdownSyntax.lineContent(in: ns, range: nextRange))
    }

    private func applyTableColumnKerns(line: String,
                                       lineRange: NSRange,
                                       cells: [MarkdownTableCell],
                                       columnCount: Int) {
        guard let container = glyphInvalidatable?.textContainers.first,
              container.size.width > 1,
              columnCount > 0,
              !cells.isEmpty else { return }

        let lineNS = line as NSString
        let horizontalPadding = max(0, container.lineFragmentPadding)
        let tableWidth = max(0, container.size.width - 2 * horizontalPadding)
        let columnWidth = tableWidth / CGFloat(columnCount)
        let cellPadding: CGFloat = 12
        var accumulatedKern: CGFloat = 0

        for cell in cells {
            let localContentStart = max(0, cell.contentRange.location - lineRange.location)
            guard localContentStart <= lineNS.length else { continue }
            let prefix = lineNS.substring(with: NSRange(location: 0, length: localContentStart))
            let prefixWidth = (prefix as NSString).size(withAttributes: [.font: bodyFont]).width
            let currentX = prefixWidth + accumulatedKern
            let targetX = horizontalPadding + CGFloat(cell.column) * columnWidth + cellPadding
            let delta = max(0, targetX - currentX)
            let pipeLocation = max(lineRange.location, cell.segmentRange.location - 1)
            backing.addAttribute(.kern,
                                 value: delta,
                                 range: NSRange(location: pipeLocation, length: 1))
            accumulatedKern += delta
        }
    }

    private func unescapedPipeRanges(for cells: [MarkdownTableCell]) -> [NSRange] {
        guard !cells.isEmpty else { return [] }
        var ranges = cells.map {
            NSRange(location: max(0, $0.segmentRange.location - 1), length: 1)
        }
        if let last = cells.last {
            ranges.append(NSRange(location: NSMaxRange(last.segmentRange), length: 1))
        }
        return ranges
    }

    private func hideEscapedTablePipeBackslashes(in line: String,
                                                 lineRange: NSRange,
                                                 fullLine: NSRange) {
        let ns = line as NSString
        guard ns.length >= 2 else { return }
        var index = 0
        while index < ns.length - 1 {
            if ns.character(at: index) == 0x5C, ns.character(at: index + 1) == 0x7C {
                registerHideZeroWidth(NSRange(location: lineRange.location + index, length: 1),
                                      contextRange: fullLine)
                index += 2
            } else {
                index += 1
            }
        }
    }

    /// Register the leading whitespace of a list line for unconditional
    /// zero-width hiding in Live mode. The matching paragraph style in
    /// `applyListIndent` provides the visual offset; Raw mode bypasses
    /// glyph hiding and shows the source spaces directly.
    private func registerLeadingWhitespace(_ wsRange: NSRange,
                                           lineRange: NSRange,
                                           fullLine: NSRange) {
        guard wsRange.length > 0 else { return }
        let absWS = NSRange(location: lineRange.location + wsRange.location,
                            length: wsRange.length)
        _ = fullLine
        registerHideZeroWidth(absWS, contextRange: nil)
    }

    private func indentWidth(forLeadingWhitespace whitespace: String) -> CGFloat {
        var columns = 0
        for scalar in whitespace.unicodeScalars {
            if scalar.value == 0x09 {
                let tabSize = 4
                columns += tabSize - (columns % tabSize)
            } else {
                columns += 1
            }
        }
        return CGFloat(columns) * spaceWidth
    }

    private func isCursorOnRange(_ range: NSRange) -> Bool {
        guard cursorRange.location != NSNotFound else { return false }
        let loc = cursorRange.location
        return loc >= range.location && loc <= NSMaxRange(range)
    }

    func isCursor(onLine range: NSRange) -> Bool {
        guard cursorRange.location != NSNotFound else { return false }
        return cursorRange.location >= range.location
            && cursorRange.location <= NSMaxRange(range)
    }

    /// Stricter, line-based "is cursor in this range" check used for
    /// multi-line block constructs (fence). `isCursorOnRange` treats
    /// `loc == NSMaxRange(range)` as inside, which is correct for an
    /// inline span but wrong for a fence — the cursor sitting on the
    /// virtual empty line just past the closer's trailing newline
    /// should count as outside the fence.
    private func isCursorLineWithin(_ range: NSRange) -> Bool {
        guard cursorRange.location != NSNotFound else { return false }
        guard let line = lineRangeOfPosition(cursorRange.location) else { return false }
        return NSLocationInRange(line.location, range)
    }

    private func applyInlineLive(line: String, lineRange: NSRange) {
        let lineNS = line as NSString
        let lineFull = NSRange(location: 0, length: lineNS.length)
        let fullLine = NSRange(location: lineRange.location, length: lineNS.length)

        let spans = MarkdownSyntax.inlineSpans(in: backing.string).filter {
            NSIntersectionRange($0.fullRange, fullLine).length > 0
        }
        for span in spans.sorted(by: inlineStylingPrecedence) {
            applyInlineSpan(span)
        }
        let codeProtected = spans.filter { $0.kind == .code }.map(\.fullRange)
        let isInsideCode: (NSRange) -> Bool = { r in
            codeProtected.contains { NSLocationInRange(r.location, $0) }
        }

        for m in Self.htmlMarkRegex.matches(in: line, range: lineFull) where m.numberOfRanges >= 5 {
            let open = m.range(at: 1)
            let colorId = m.range(at: 2)
            let content = m.range(at: 3)
            let close = m.range(at: 4)
            let absOpen = NSRange(location: lineRange.location + open.location, length: open.length)
            let absColorId = NSRange(location: lineRange.location + colorId.location, length: colorId.length)
            let absContent = NSRange(location: lineRange.location + content.location, length: content.length)
            let absClose = NSRange(location: lineRange.location + close.location, length: close.length)
            if isInsideCode(absOpen) { continue }
            let span = NSRange(location: absOpen.location,
                               length: absOpen.length + absContent.length + absClose.length)
            let color = lineNS.substring(with: colorId)
            backing.addAttribute(.highlightSpan,
                                 value: Self.highlightBackground(for: color),
                                 range: absContent)
            registerHide(absOpen, contextRange: span)
            registerHide(absClose, contextRange: span)
            backing.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: absOpen)
            backing.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: absColorId)
            backing.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: absClose)
        }

        // 7. Link `[label](url)` — label keeps default foreground + underline
        var linkSpans: [NSRange] = []
        for m in Self.linkRegex.matches(in: line, range: lineFull) where m.numberOfRanges >= 7 {
            let openBracket = m.range(at: 1)
            let label = m.range(at: 2)
            let closeBracket = m.range(at: 3)
            let openParen = m.range(at: 4)
            let url = m.range(at: 5)
            let closeParen = m.range(at: 6)
            let absLabel = NSRange(location: lineRange.location + label.location, length: label.length)
            if isInsideCode(absLabel) { continue }
            let span = NSRange(location: lineRange.location + openBracket.location,
                               length: openBracket.length + label.length + closeBracket.length
                                   + openParen.length + url.length + closeParen.length)
            linkSpans.append(span)
            backing.addAttribute(.underlineStyle,
                                 value: NSUnderlineStyle.single.rawValue,
                                 range: absLabel)
            for r in [openBracket, closeBracket, openParen, url, closeParen] {
                let abs = NSRange(location: lineRange.location + r.location, length: r.length)
                registerHide(abs, contextRange: span)
                backing.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: abs)
            }
        }

        // 8. Bare-URL autolinks (`https?://...`) — GFM-style. Skip if
        // inside inline code or already inside a `[label](url)` span.
        for m in Self.urlRegex.matches(in: line, range: lineFull) {
            let url = m.range(at: 0)
            let absUrl = NSRange(location: lineRange.location + url.location, length: url.length)
            if isInsideCode(absUrl) { continue }
            if linkSpans.contains(where: { NSLocationInRange(absUrl.location, $0) }) { continue }
            backing.addAttribute(.underlineStyle,
                                 value: NSUnderlineStyle.single.rawValue,
                                 range: absUrl)
        }
    }

    private func inlineStylingPrecedence(_ lhs: MarkdownSyntax.InlineSpan,
                                         _ rhs: MarkdownSyntax.InlineSpan) -> Bool {
        func rank(_ kind: MarkdownSyntax.InlineKind) -> Int {
            switch kind {
            case .code, .mathInline: return 0
            case .bold, .italic: return 1
            case .strikethrough: return 2
            case .highlight: return 3
            }
        }
        let lhsRank = rank(lhs.kind)
        let rhsRank = rank(rhs.kind)
        if lhsRank == rhsRank {
            return lhs.fullRange.length > rhs.fullRange.length
        }
        return lhsRank < rhsRank
    }

    private func applyInlineSpan(_ span: MarkdownSyntax.InlineSpan) {
        switch span.kind {
        case .code, .mathInline:
            backing.addAttribute(.font, value: monoBodyFont, range: span.contentRange)
            backing.addAttribute(.inlineCodeSpan, value: true, range: span.contentRange)
            if span.kind == .mathInline {
                backing.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: span.contentRange)
            }
        case .bold:
            applyTraitPreservingFont(.traitBold, in: span.contentRange)
        case .italic:
            applyTraitPreservingFont(.traitItalic, in: span.contentRange)
        case .strikethrough:
            backing.addAttribute(.strikethroughStyle,
                                 value: NSUnderlineStyle.single.rawValue,
                                 range: span.contentRange)
            backing.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: span.contentRange)
        case .highlight:
            backing.addAttribute(.highlightSpan, value: true, range: span.contentRange)
            backing.addAttribute(.foregroundColor,
                                 value: ListsTokens.Markdown.highlightForegroundUIColor,
                                 range: span.contentRange)
        }

        registerHide(span.openRange, contextRange: span.fullRange)
        registerHide(span.closeRange, contextRange: span.fullRange)
        backing.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: span.openRange)
        backing.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: span.closeRange)
    }

    // MARK: Raw styling

    private func applyRawStyling(in range: NSRange) {
        backing.addAttribute(.font, value: monoBodyFont, range: range)
        backing.addAttribute(.foregroundColor, value: UIColor.label, range: range)

        let source = backing.string as NSString
        source.enumerateSubstrings(in: range, options: .byLines) { line, _, lineRange, _ in
            self.tintRawLine(line: line ?? "", lineRange: lineRange)
        }
    }

    private func tintRawLine(line: String, lineRange: NSRange) {
        let lineFull = NSRange(location: 0, length: (line as NSString).length)
        let syntaxColor = UIColor.secondaryLabel

        if line.hasPrefix("```") {
            backing.addAttribute(.foregroundColor, value: syntaxColor,
                                 range: NSRange(location: lineRange.location, length: lineFull.length))
        }
        for (regex, group) in [
            (Self.headingRegex, 1),
            (Self.horizontalRuleRegex, 1),
            (Self.bulletRegex, 1),
            (Self.numberedListRegex, 1),
            (Self.blockquoteRegex, 1)
        ] {
            if let m = regex.firstMatch(in: line, range: lineFull), m.numberOfRanges > group {
                let r = m.range(at: group)
                backing.addAttribute(.foregroundColor, value: syntaxColor,
                                     range: NSRange(location: lineRange.location + r.location, length: r.length))
            }
        }

        for pattern in [Self.boldItalicRegex, Self.boldItalicUnderscoreRegex,
                        Self.boldRegex, Self.boldUnderscoreRegex,
                        Self.italicRegex, Self.italicUnderscoreRegex,
                        Self.inlineCodeRegex, Self.strikeRegex, Self.highlightRegex] {
            for m in pattern.matches(in: line, range: lineFull) where m.numberOfRanges >= 4 {
                let open = m.range(at: 1)
                let close = m.range(at: 3)
                backing.addAttribute(.foregroundColor, value: syntaxColor,
                                     range: NSRange(location: lineRange.location + open.location, length: open.length))
                backing.addAttribute(.foregroundColor, value: syntaxColor,
                                     range: NSRange(location: lineRange.location + close.location, length: close.length))
            }
        }
        for m in Self.htmlMarkRegex.matches(in: line, range: lineFull) where m.numberOfRanges >= 5 {
            for i in [1, 4] {
                let r = m.range(at: i)
                backing.addAttribute(.foregroundColor, value: syntaxColor,
                                     range: NSRange(location: lineRange.location + r.location, length: r.length))
            }
        }

        for m in Self.linkRegex.matches(in: line, range: lineFull) where m.numberOfRanges >= 7 {
            for i in [1, 3, 4, 5, 6] {
                let r = m.range(at: i)
                backing.addAttribute(.foregroundColor, value: syntaxColor,
                                     range: NSRange(location: lineRange.location + r.location, length: r.length))
            }
        }

        if let m = Self.taskRegex.firstMatch(in: line, range: lineFull),
           m.numberOfRanges >= 3 {
            let bracket = m.range(at: 2)
            backing.addAttribute(.foregroundColor, value: syntaxColor,
                                 range: NSRange(location: lineRange.location + bracket.location, length: bracket.length))
        }
    }

    // MARK: Helpers

    private func styleAsCode(range: NSRange) {
        backing.addAttribute(.font, value: monoBodyFont, range: range)
        // Visual indent for body code — the raw source is NOT indented
        // (no leading spaces stored), this is purely a display offset.
        // Match the body-font 4-space indent (one regular indent, the
        // same column Tab inserts) so a code block aligns with a
        // sibling "indented text" line rather than landing further right
        // due to mono spaces being wider than body spaces.
        let p = NSMutableParagraphStyle()
        p.firstLineHeadIndent = indentWidth
        p.headIndent = indentWidth
        p.lineHeightMultiple = 1.2
        backing.addAttribute(.paragraphStyle, value: p, range: range)
        // `.codeBlockBody = true` is applied at the fence-full level in
        // `applyLiveStyling` so the rounded panel reaches over the
        // opener + closer marker lines too.
    }

    private func applyTraitPreservingFont(_ trait: UIFontDescriptor.SymbolicTraits, in range: NSRange) {
        backing.enumerateAttribute(.font, in: range, options: []) { value, sub, _ in
            let base = (value as? UIFont) ?? self.bodyFont
            var traits = base.fontDescriptor.symbolicTraits
            traits.insert(trait)
            if let d = base.fontDescriptor.withSymbolicTraits(traits) {
                let combined = UIFont(descriptor: d, size: 0)
                self.backing.addAttribute(.font, value: combined, range: sub)
            }
        }
    }

    private static func highlightBackground(for colorId: String) -> UIColor {
        switch colorId {
        case "orange": return UIColor.systemOrange.withAlphaComponent(0.28)
        case "red": return UIColor.systemRed.withAlphaComponent(0.24)
        case "green": return UIColor.systemGreen.withAlphaComponent(0.26)
        case "blue": return UIColor.systemBlue.withAlphaComponent(0.22)
        case "purple": return UIColor.systemPurple.withAlphaComponent(0.24)
        default: return ListsTokens.Markdown.highlightBackground
        }
    }

    private func registerHide(_ range: NSRange, contextRange: NSRange) {
        for i in range.location..<NSMaxRange(range) {
            hideIndices.insert(i)
            contextRangeByCharIndex[i] = contextRange
        }
    }

    /// Hides a range AND collapses each char's advance to ~zero by
    /// attaching a 0.01pt font. `.null` alone doesn't stop the
    /// typesetter from advancing in iOS 26 — chars keep their natural
    /// width unless the font itself shrinks. Pass `contextRange: nil`
    /// for an unconditional hide (no cursor-context check).
    private func registerHideZeroWidth(_ range: NSRange, contextRange: NSRange?) {
        for i in range.location..<NSMaxRange(range) {
            hideIndices.insert(i)
            if let context = contextRange {
                contextRangeByCharIndex[i] = context
            }
        }
        backing.addAttribute(.font, value: zeroWidthFont, range: range)
    }

    private lazy var zeroWidthFont: UIFont = {
        UIFont(descriptor: bodyFont.fontDescriptor, size: 0.01)
    }()

    /// Pair `^```` lines across the document and return:
    /// - `content`: the body of each fence (between opener and closer
    ///   newlines), styled as code.
    /// - `full`: the whole-fence range (opener line start through closer
    ///   line end, or EOF for an unclosed fence). Used as the hide
    ///   context for opener/closer markers so they stay visible while
    ///   the cursor is anywhere inside the fence.
    /// Empty lines do NOT terminate the scan; only true EOF does.
    private func fenceRanges(in source: NSString, within range: NSRange)
        -> (content: [NSRange], full: [NSRange]) {
        var content: [NSRange] = []
        var full: [NSRange] = []
        var index = range.location
        let end = NSMaxRange(range)
        var openFenceEnd: Int? = nil
        var openFenceStart: Int? = nil

        while index < end {
            var lineEnd = 0
            var contentsEnd = 0
            source.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd,
                                for: NSRange(location: index, length: 0))
            if lineEnd <= index { break }   // true EOF only
            let lineContentLen = max(0, contentsEnd - index)
            let line = lineContentLen > 0
                ? source.substring(with: NSRange(location: index, length: lineContentLen))
                : ""
            if line.hasPrefix("```") {
                if let openEnd = openFenceEnd, let openStart = openFenceStart {
                    content.append(NSRange(location: openEnd, length: index - openEnd))
                    full.append(NSRange(location: openStart, length: lineEnd - openStart))
                    openFenceEnd = nil
                    openFenceStart = nil
                } else {
                    openFenceEnd = lineEnd
                    openFenceStart = index
                }
            }
            index = lineEnd
        }
        if let openEnd = openFenceEnd, let openStart = openFenceStart, openEnd < end {
            content.append(NSRange(location: openEnd, length: end - openEnd))
            full.append(NSRange(location: openStart, length: end - openStart))
        }
        return (content, full)
    }

    // MARK: Fonts + paragraph style

    private var bodyFont: UIFont { UIFont.preferredFont(forTextStyle: .body) }

    private var monoBodyFont: UIFont {
        if let d = UIFont.preferredFont(forTextStyle: .body).fontDescriptor.withDesign(.monospaced) {
            return UIFont(descriptor: d, size: 0)
        }
        return UIFont.preferredFont(forTextStyle: .body)
    }

    /// Width of a single space character at body font, measured once per
    /// styler. Drives the state-aware indent math in `applyListIndent`.
    private lazy var spaceWidth: CGFloat = {
        (" " as NSString).size(withAttributes: [.font: bodyFont]).width
    }()

    /// Width of a single space character at mono body font. Drives the
    /// "4 mono spaces" indent of fence body + opener/closer lines.
    private lazy var monoSpaceWidth: CGFloat = {
        (" " as NSString).size(withAttributes: [.font: monoBodyFont]).width
    }()

    /// One indent level = 4 body-font spaces. Used to align list content
    /// at the same x-coordinate as a regular indented line.
    private lazy var indentWidth: CGFloat = { 4 * spaceWidth }()

    /// Measured advance of the substituted bullet glyph (`•`) at body
    /// font. Used to compute the kern padding on the trailing space so
    /// list content lands exactly at the indent column.
    private lazy var bulletGlyphAdvance: CGFloat = {
        ("\u{2022}" as NSString).size(withAttributes: [.font: bodyFont]).width
    }()

    fileprivate func headingFont(level: Int) -> UIFont {
        let style: UIFont.TextStyle
        switch level {
        case 1: style = .title1
        case 2: style = .title2
        case 3: style = .title3
        case 4: style = .headline
        case 5: style = .subheadline
        case 6: style = .footnote
        default: style = .body
        }
        let d = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        if let bold = d.withSymbolicTraits(.traitBold) {
            return UIFont(descriptor: bold, size: 0)
        }
        return UIFont(descriptor: d, size: 0)
    }

    private var defaultParagraphStyle: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.2
        return p
    }

    // MARK: Compiled regexes

    static let headingRegex             = try! NSRegularExpression(pattern: #"^(#{1,6}) +.*$"#)
    static let horizontalRuleRegex      = try! NSRegularExpression(pattern: #"^(-{3,}|\*{3,}|_{3,})\s*$"#)
    static let bulletRegex              = try! NSRegularExpression(pattern: #"^(\s*)([-*+])\s"#)
    static let numberedListRegex        = try! NSRegularExpression(pattern: #"^(\s*)(\d+\.)\s"#)
    static let blockquoteRegex          = try! NSRegularExpression(pattern: #"^(>+)\s"#)
    static let calloutRegex             = try! NSRegularExpression(pattern: #"\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][+-]?(?:\s|$)"#, options: [.caseInsensitive])
    static let taskRegex                = try! NSRegularExpression(pattern: #"^(\s*)([-*+])\s(\[([ xX])\])\s"#)
    static let quotedTaskRegex          = try! NSRegularExpression(pattern: #"^(>+\s)(\s*)([-*+])\s(\[([ xX])\])\s"#)
    static let quotedNumberedListRegex  = try! NSRegularExpression(pattern: #"^(>+\s)(\s*)(\d+\.)\s"#)
    static let quotedBulletRegex        = try! NSRegularExpression(pattern: #"^(>+\s)(\s*)([-*+])\s"#)
    /// Fence marker line — captures the three backticks (group 1) and an
    /// optional GFM-style language hint (group 2, possibly empty). Used
    /// to keep the language word visible while the cursor is off-fence.
    static let fenceMarkerRegex         = try! NSRegularExpression(pattern: #"^(```)(\S*)\s*$"#)

    static let boldItalicRegex          = try! NSRegularExpression(pattern: #"(\*\*\*)([^*\n]+?)(\*\*\*)"#)
    static let boldItalicUnderscoreRegex = try! NSRegularExpression(pattern: #"(___)([^_\n]+?)(___)"#)
    static let boldRegex                = try! NSRegularExpression(pattern: #"(\*\*)([^*\n]+?)(\*\*)"#)
    static let boldUnderscoreRegex      = try! NSRegularExpression(pattern: #"(__)([^_\n]+?)(__)"#)
    static let italicRegex              = try! NSRegularExpression(pattern: #"(?<![\*\w])(\*)([^*\n]+?)(\*)(?!\*)"#)
    static let italicUnderscoreRegex    = try! NSRegularExpression(pattern: #"(?<![_\w])(_)([^_\n]+?)(_)(?!_)"#)
    static let inlineCodeRegex          = try! NSRegularExpression(pattern: "(`)([^`\\n]+?)(`)")
    static let strikeRegex              = try! NSRegularExpression(pattern: #"(~~)([^~\n]+?)(~~)"#)
    static let highlightRegex           = try! NSRegularExpression(pattern: #"(==)([^=\n]+?)(==)"#)
    static let htmlMarkRegex            = try! NSRegularExpression(pattern: #"(<mark data-color="(yellow|orange|red|green|blue|purple)">)([^<\n]+?)(</mark>)"#)
    static let linkRegex                = try! NSRegularExpression(pattern: #"(\[)([^\]\n]+)(\])(\()([^)\n]+)(\))"#)
    static let urlRegex                 = try! NSRegularExpression(pattern: #"(?<![\(\[\w])https?://[^\s<>)]+"#)
}

/// Marks attributes the custom layout manager (`MarkdownLayoutManager`)
/// uses to paint extras the standard text-rendering path can't:
/// - `horizontalRule`: stroke a 0.5pt separator across the line fragment.
/// - `codeBlockBody`: fill a padded, rounded background behind a fence body.
/// - `inlineCodeSpan`: fill a smaller rounded pill behind inline code.
/// - `highlightSpan`: fill a padded, rounded background behind highlighted text.
extension NSAttributedString.Key {
    static let horizontalRule  = NSAttributedString.Key("io.github.saxonbobart.lists.markdown.horizontalRule")
    static let codeBlockBody   = NSAttributedString.Key("io.github.saxonbobart.lists.markdown.codeBlockBody")
    static let inlineCodeSpan  = NSAttributedString.Key("io.github.saxonbobart.lists.markdown.inlineCodeSpan")
    static let highlightSpan   = NSAttributedString.Key("io.github.saxonbobart.lists.markdown.highlightSpan")
    static let quoteBlockTint  = NSAttributedString.Key("io.github.saxonbobart.lists.markdown.quoteBlockTint")
    static let markdownTableRow = NSAttributedString.Key("io.github.saxonbobart.lists.markdown.tableRow")
    /// Value: `"square"` / `"checkmark.square.fill"`. `MarkdownLayoutManager`
    /// overlays a tinted SF Symbol image at the char's glyph position so
    /// the checkbox matches Apple's standard symbol set instead of the
    /// Apple Symbols `☐`/`☑` glyph (which renders at a smaller weight).
    static let sfSymbolCheckbox = NSAttributedString.Key("io.github.saxonbobart.lists.markdown.sfSymbolCheckbox")
}

enum MarkdownTableRowRole: String {
    case header
    case body
}
