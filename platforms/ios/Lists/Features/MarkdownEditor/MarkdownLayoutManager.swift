import UIKit

enum MarkdownChecklistMetrics {
    static let symbolLeadingOffset: CGFloat = 0
    static let textGap: CGFloat = 8
}

enum MarkdownQuoteCardMetrics {
    static let cornerRadius: CGFloat = 10
    static let railWidth: CGFloat = 3
    static let liveVerticalInset: CGFloat = 3
    static let liveMinimumHeight: CGFloat = 26
    static let contentLeadingPadding: CGFloat = 25
    static let contentTrailingPadding: CGFloat = 11
    static let contentVerticalPadding: CGFloat = 10

    static func railRect(in cardRect: CGRect) -> CGRect {
        CGRect(
            x: cardRect.minX,
            y: cardRect.minY,
            width: railWidth,
            height: cardRect.height
        )
    }
}

/// `NSLayoutManager` subclass that paints extras the standard
/// text-rendering path can't:
/// - **Horizontal rule**: 0.5pt full-width separator across line
///   fragments carrying `.horizontalRule`.
/// - **Inline tables**: rounded row backgrounds, cell borders, and
///   header tint behind pipe-table rows while the source pipes stay hidden.
/// - **Code block body**: prominent rounded `.secondarySystemFill`
///   panel behind any contiguous run of chars with `.codeBlockBody`.
/// - **Inline decorations**: tight rounded backgrounds behind inline code,
///   inline math, and highlights. They share one line-safe rect routine so
///   nested and wrapped spans do not bleed into hidden Markdown markers.
final class MarkdownLayoutManager: NSLayoutManager {
    private let localImageCache = NSCache<NSString, UIImage>()
    private struct QuoteVisualLine {
        let lineRange: NSRange
        let level: Int
        let callout: CalloutVisual?
    }

    private struct CalloutVisual {
        let kind: String
        let displayTitle: String
        let tint: UIColor
        let symbolName: String
        let titleRange: NSRange
    }

    private struct CalloutVisualBlock {
        let header: QuoteVisualLine
        let lines: [QuoteVisualLine]
    }

    private struct InlineDecorationStyle {
        let color: UIColor
        let horizontalPadding: CGFloat
        let verticalInset: CGFloat
        let cornerRadius: CGFloat

        static var code: InlineDecorationStyle {
            InlineDecorationStyle(
                color: .tertiarySystemFill,
                horizontalPadding: 2,
                verticalInset: 1.5,
                cornerRadius: 4
            )
        }

        static func highlight(_ color: UIColor) -> InlineDecorationStyle {
            InlineDecorationStyle(
                color: color,
                horizontalPadding: 1,
                verticalInset: 2,
                cornerRadius: 5
            )
        }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard drawsMarkdownDecorations else { return }
        drawQuoteBlockBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawCodeBlockBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawInlineCodeBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawHighlightBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawLocalImages(forGlyphRange: glyphsToShow, at: origin)
        drawHorizontalRules(forGlyphRange: glyphsToShow, at: origin)
    }

    /// Overlay SF Symbol images on top of the default glyph render for
    /// any char marked with `.sfSymbolCheckbox`. The underlying ☐ / ☑
    /// glyph reserves layout space; we hide it via `.foregroundColor =
    /// .clear` in the styler and draw the tinted symbol image here.
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard drawsMarkdownDecorations else { return }
        guard let storage = textStorage else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.sfSymbolCheckbox, in: charRange, options: []) { value, range, _ in
            guard let symbolName = value as? String else { return }
            let bodyFont = UIFont.preferredFont(forTextStyle: .body)
            let config = UIImage.SymbolConfiguration(font: bodyFont)
            guard let image = UIImage(systemName: symbolName, withConfiguration: config) else { return }
            // Read firstLineHeadIndent from the paragraph style attribute
            // directly rather than relying on lineFragmentRect.minX, which
            // can return stale x positions on adjacent list rows when the
            // cursor crosses between them (a Text Kit layout caching
            // quirk). The paragraph style attribute is canonical — set by
            // MarkdownStyler.applyListIndent and re-applied on every edit.
            let paraStyle = storage.attribute(.paragraphStyle,
                                              at: range.location,
                                              effectiveRange: nil) as? NSParagraphStyle
            let firstLineIndent = paraStyle?.firstLineHeadIndent ?? 0
            let lfPadding = textContainers.first?.lineFragmentPadding ?? 0
            // Y still comes from the line fragment — vertical layout is
            // stable; only horizontal positioning suffers from staleness.
            let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let lineFragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let isChecked = symbolName.contains("fill")
            let tint: UIColor = isChecked ? .tintColor : .label
            let size = image.size
            let x = lfPadding + firstLineIndent + origin.x
            let y = lineFragment.midY + origin.y
            let drawRect = CGRect(
                x: x + MarkdownChecklistMetrics.symbolLeadingOffset,
                y: y - size.height / 2,
                width: size.width,
                height: size.height
            )
            image.withTintColor(tint, renderingMode: .alwaysOriginal).draw(in: drawRect)
        }
    }

    var drawsMarkdownDecorations: Bool {
        guard let styler = textStorage as? MarkdownStyler else { return true }
        return styler.mode == .live
    }

    private func drawTableBackgrounds(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let storage = textStorage,
              let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        for table in MarkdownTableParser.tables(in: storage.string)
            where NSIntersectionRange(table.fullRange, charRange).length > 0 {
            drawTable(table, in: container, at: origin)
        }
    }

    private func drawTable(_ table: MarkdownTable,
                           in container: NSTextContainer,
                           at origin: CGPoint) {
        let visibleRows = [table.header] + table.bodyRows
        guard let headerLineRect = tableLineRect(
            for: table.header.lineRange,
            in: container,
            at: origin
        ), table.columnCount > 0 else { return }
        let font = (textStorage?.attribute(
            .font,
            at: table.header.lineRange.location,
            effectiveRange: nil
        ) as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
        let editorWidth = max(
            1,
            (container.size.width - 2 * container.lineFragmentPadding)
                / CGFloat(max(1, table.columnCount))
                - 2 * MarkdownTableVisualMetrics.horizontalCellPadding
        )
        let heights = MarkdownTableVisualMetrics.rowHeights(
            for: table,
            font: font,
            editorWidth: editorWidth
        )
        let blockHeight = heights.reduce(0, +)
        var nextY = headerLineRect.maxY - blockHeight
        let rowRects = zip(visibleRows, heights).map { row, height in
            defer { nextY += height }
            return (
                row,
                CGRect(
                    x: headerLineRect.minX,
                    y: nextY,
                    width: headerLineRect.width,
                    height: height
                )
            )
        }
        guard let first = rowRects.first?.1,
              let last = rowRects.last?.1 else { return }

        let pad = container.lineFragmentPadding
        let tableX = origin.x + pad
        let tableWidth = max(0, container.size.width - 2 * pad)
        let tableRect = CGRect(x: tableX,
                               y: first.minY,
                               width: tableWidth,
                               height: last.maxY - first.minY)
        guard tableRect.width > 20, tableRect.height > 12 else { return }

        let border = UIColor.separator.withAlphaComponent(0.75)
        border.setStroke()

        for row in rowRects {
            strokeLine(from: CGPoint(x: tableRect.minX, y: row.1.minY),
                       to: CGPoint(x: tableRect.maxX, y: row.1.minY),
                       color: border)
        }
        strokeLine(from: CGPoint(x: tableRect.minX, y: tableRect.maxY),
                   to: CGPoint(x: tableRect.maxX, y: tableRect.maxY),
                   color: border)

        let cellWidth = tableRect.width / CGFloat(table.columnCount)
        for column in 0...table.columnCount {
            let x = tableRect.minX + CGFloat(column) * cellWidth
            strokeLine(from: CGPoint(x: x, y: tableRect.minY),
                       to: CGPoint(x: x, y: tableRect.maxY),
                       color: border)
        }

    }

    private func tableLineRect(for range: NSRange,
                               in container: NSTextContainer,
                               at origin: CGPoint) -> CGRect? {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var rect: CGRect?
        enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, _, stop in
            rect = lineRect.offsetBy(dx: origin.x, dy: origin.y)
            stop.pointee = true
        }
        return rect
    }

    private func strokeLine(from start: CGPoint, to end: CGPoint, color: UIColor) {
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        color.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private func drawQuoteBlockBackgrounds(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let storage = textStorage,
              let container = textContainers.first else { return }
        let lines = quoteVisualLines(in: storage.string)
        let calloutBlocks = calloutVisualBlocks(from: lines)
        let maxLevel = lines.map(\.level).max() ?? 0
        guard maxLevel > 0 else { return }

        // Paint parents before children regardless of whether either block is
        // a plain quote or a callout. Nested cards then layer inside their
        // containing card instead of being covered by it.
        for level in 1...maxLevel {
            drawPlainQuoteBlocks(
                lines: lines,
                excluding: calloutBlocks,
                level: level,
                in: container,
                at: origin
            )
            drawCalloutBlocks(
                blocks: calloutBlocks.filter { $0.header.level == level },
                in: container,
                at: origin
            )
        }
    }

    private func drawCalloutBlocks(blocks: [CalloutVisualBlock],
                                   in container: NSTextContainer,
                                   at origin: CGPoint) {
        for block in blocks {
            guard let callout = block.header.callout,
                  let rect = quoteBlockRect(for: block.lines, level: block.header.level, in: container, at: origin) else {
                continue
            }

            // Paint every depth. Blocks are ordered parent-first, so each
            // nested tint layers inside its parent's background like a
            // recursively nested callout rather than degrading to bare rails.
            drawQuoteCard(in: rect, tint: callout.tint)

            drawCalloutIcon(callout, in: block.header.lineRange, rect: rect, container: container, at: origin)
        }
    }

    private func drawPlainQuoteBlocks(lines: [QuoteVisualLine],
                                      excluding calloutBlocks: [CalloutVisualBlock],
                                      level: Int,
                                      in container: NSTextContainer,
                                      at origin: CGPoint) {
        for run in plainQuoteRuns(
            lines: lines,
            excluding: calloutBlocks,
            level: level
        ) {
            guard let cardRect = quoteBlockRect(
                for: run,
                level: level,
                in: container,
                at: origin
            ) else { continue }

            drawQuoteCard(in: cardRect, tint: .secondaryLabel)
        }
    }

    private func drawQuoteCard(in rect: CGRect, tint: UIColor) {
        let card = UIBezierPath(
            roundedRect: rect,
            cornerRadius: MarkdownQuoteCardMetrics.cornerRadius
        )
        calloutBackgroundColor(for: tint).setFill()
        card.fill()

        if let context = UIGraphicsGetCurrentContext() {
            context.saveGState()
            card.addClip()
            context.setFillColor(tint.cgColor)
            context.fill(MarkdownQuoteCardMetrics.railRect(in: rect))
            context.restoreGState()
        }

        // Draw the perimeter last so the background and integrated rail read
        // as one continuous squircle rather than overlapping decorations.
        tint.withAlphaComponent(0.28).setStroke()
        card.lineWidth = 0.5
        card.stroke()
    }

    private func plainQuoteRuns(lines: [QuoteVisualLine],
                                excluding calloutBlocks: [CalloutVisualBlock],
                                level: Int) -> [[QuoteVisualLine]] {
        // A callout suppresses a plain quote card only at its own depth. Its
        // deeper descendants may still be genuine nested blockquotes, while
        // a plain parent at a shallower depth must contain a nested callout.
        let calloutLineLocations = Set(calloutBlocks
            .filter { $0.header.level == level }
            .flatMap { block in
                block.lines.map { $0.lineRange.location }
            })

        var result: [[QuoteVisualLine]] = []
        var run: [QuoteVisualLine] = []
        func flush() {
            if !run.isEmpty { result.append(run) }
            run.removeAll()
        }
        for line in lines {
            let isInsideSameLevelCallout = calloutLineLocations.contains(line.lineRange.location)
            let isContiguous = run.last.map {
                NSMaxRange($0.lineRange) == line.lineRange.location
            } ?? true
            if line.level >= level, !isInsideSameLevelCallout, isContiguous {
                run.append(line)
            } else {
                flush()
                if line.level >= level, !isInsideSameLevelCallout {
                    run.append(line)
                }
            }
        }
        flush()
        return result
    }

    private func calloutVisualBlocks(from lines: [QuoteVisualLine]) -> [CalloutVisualBlock] {
        lines.enumerated().compactMap { index, line in
            guard line.callout != nil else { return nil }
            var blockLines = [line]
            var next = index + 1
            while next < lines.count {
                let candidate = lines[next]
                let isContiguous = NSMaxRange(lines[next - 1].lineRange) == candidate.lineRange.location
                guard isContiguous,
                      candidate.level >= line.level else {
                    break
                }

                // A callout header at this block's own level starts a sibling
                // block. Deeper callout headers remain part of the parent so
                // the parent's background and rail contain the complete
                // nested subtree until the source dedents again.
                if candidate.level == line.level, candidate.callout != nil {
                    break
                }
                blockLines.append(candidate)
                next += 1
            }
            return CalloutVisualBlock(header: line, lines: blockLines)
        }
    }

    private func quoteBlockRect(for lines: [QuoteVisualLine],
                                level: Int,
                                in container: NSTextContainer,
                                at origin: CGPoint) -> CGRect? {
        let renderedLines = lines.compactMap {
            fullLineUsedRect(for: $0.lineRange, in: container, at: origin)
        }
        guard let first = renderedLines.first else { return nil }
        let bounds = renderedLines.dropFirst().reduce(first) { $0.union($1) }
        let nestedDepth = CGFloat(max(0, level - 1))
        let left = origin.x + container.lineFragmentPadding + nestedDepth * 20 + 8
        let right = origin.x + container.size.width - container.lineFragmentPadding - nestedDepth * 10
        let height = max(
            MarkdownQuoteCardMetrics.liveMinimumHeight,
            bounds.height + MarkdownQuoteCardMetrics.liveVerticalInset * 2
        )
        return CGRect(
            x: left,
            y: bounds.midY - height / 2,
            width: max(24, right - left),
            height: height
        )
    }

    /// Produces the same subtle tint as drawing the accent at 12% over the
    /// system background, but returns an opaque color. Nested cards therefore
    /// retain their own hue instead of blending through the parent tint.
    private func calloutBackgroundColor(for tint: UIColor) -> UIColor {
        UIColor { traits in
            let base = UIColor.systemBackground.resolvedColor(with: traits)
            let accent = tint.resolvedColor(with: traits)
            var br: CGFloat = 0
            var bg: CGFloat = 0
            var bb: CGFloat = 0
            var ba: CGFloat = 0
            var ar: CGFloat = 0
            var ag: CGFloat = 0
            var ab: CGFloat = 0
            var aa: CGFloat = 0
            guard base.getRed(&br, green: &bg, blue: &bb, alpha: &ba),
                  accent.getRed(&ar, green: &ag, blue: &ab, alpha: &aa) else {
                return accent.withAlphaComponent(0.12)
            }
            let fraction: CGFloat = 0.12
            return UIColor(
                red: br + (ar - br) * fraction,
                green: bg + (ag - bg) * fraction,
                blue: bb + (ab - bb) * fraction,
                alpha: 1
            )
        }
    }

    /// Returns the union of every rendered fragment belonging to a Markdown
    /// source line. A source line can wrap into several Text Kit fragments;
    /// using only its first fragment clips quote and nested-callout rails.
    func fullLineFragmentRect(for range: NSRange,
                              in container: NSTextContainer,
                              at origin: CGPoint = .zero) -> CGRect? {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var result: CGRect?
        enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, _, _ in
            let positioned = lineRect.offsetBy(dx: origin.x, dy: origin.y)
            result = result.map { $0.union(positioned) } ?? positioned
        }
        return result
    }

    /// Glyph-used bounds exclude the paragraph-after spacing Text Kit only
    /// materializes when a following paragraph exists. Quote cards add their
    /// own vertical inset to these stable bounds, so EOF cannot change height.
    private func fullLineUsedRect(for range: NSRange,
                                  in container: NSTextContainer,
                                  at origin: CGPoint = .zero) -> CGRect? {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var result: CGRect?
        enumerateLineFragments(forGlyphRange: glyphs) { _, usedRect, _, _, _ in
            let positioned = usedRect.offsetBy(dx: origin.x, dy: origin.y)
            result = result.map { $0.union(positioned) } ?? positioned
        }
        return result
    }

    /// Testable source-range contract for callout containment. Layout drawing
    /// uses the same parsed blocks immediately above.
    func calloutBlockRanges(in source: String) -> [NSRange] {
        calloutVisualBlocks(from: quoteVisualLines(in: source)).compactMap { block in
            guard let first = block.lines.first, let last = block.lines.last else { return nil }
            return NSRange(
                location: first.lineRange.location,
                length: NSMaxRange(last.lineRange) - first.lineRange.location
            )
        }
    }

    /// Testable source-range contract for neutral quote-card containment.
    /// Returns cards in paint order: outer depth first, then nested depth.
    func plainQuoteBlockRanges(in source: String) -> [NSRange] {
        let lines = quoteVisualLines(in: source)
        let callouts = calloutVisualBlocks(from: lines)
        let maxLevel = lines.map(\.level).max() ?? 0
        guard maxLevel > 0 else { return [] }
        return (1...maxLevel).flatMap { level in
            plainQuoteRuns(lines: lines, excluding: callouts, level: level).compactMap { run in
                guard let first = run.first, let last = run.last else { return nil }
                return NSRange(
                    location: first.lineRange.location,
                    length: NSMaxRange(last.lineRange) - first.lineRange.location
                )
            }
        }
    }

    private func lineRect(for range: NSRange,
                          in container: NSTextContainer,
                          at origin: CGPoint) -> CGRect? {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var result: CGRect?
        enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, _, stop in
            result = lineRect.offsetBy(dx: origin.x, dy: origin.y)
            stop.pointee = true
        }
        return result
    }

    private func drawCalloutIcon(_ callout: CalloutVisual,
                                 in lineRange: NSRange,
                                 rect: CGRect,
                                 container: NSTextContainer,
                                 at origin: CGPoint) {
        if let styler = textStorage as? MarkdownStyler,
           styler.isCursor(onLine: lineRange) {
            return
        }
        let lineRect = titleRect(for: callout, headerLineRange: lineRange, in: container, at: origin)
            ?? lineRect(for: lineRange, in: container, at: origin)
        guard let lineRect else { return }
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        guard let image = UIImage(systemName: callout.symbolName, withConfiguration: config) else { return }
        let slot = CGSize(width: 16, height: 16)
        let scale = min(slot.width / image.size.width, slot.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = CGRect(
            x: rect.minX + 10 + (slot.width - size.width) / 2,
            y: lineRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        image.withTintColor(callout.tint, renderingMode: .alwaysOriginal).draw(in: drawRect)

        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitBold)
            ?? baseFont.fontDescriptor
        let titleFont = UIFont(descriptor: descriptor, size: 0)
        let title = callout.displayTitle as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: callout.tint
        ]
        let titleSize = title.size(withAttributes: attributes)
        title.draw(
            at: CGPoint(
                x: rect.minX + 36,
                y: lineRect.midY - titleSize.height / 2
            ),
            withAttributes: attributes
        )
    }

    private func titleRect(for callout: CalloutVisual,
                           headerLineRange: NSRange,
                           in container: NSTextContainer,
                           at origin: CGPoint) -> CGRect? {
        let range = NSRange(
            location: headerLineRange.location + callout.titleRange.location,
            length: callout.titleRange.length
        )
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        return boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: origin.x, dy: origin.y)
    }

    private func quoteVisualLines(in source: String) -> [QuoteVisualLine] {
        let ns = source as NSString
        var result: [QuoteVisualLine] = []
        var location = 0
        while location < ns.length {
            let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
            let line = ns.substring(with: paragraph)
                .trimmingCharacters(in: .newlines)
            if let prefix = Self.quotePrefix(in: line) {
                let callout = Self.calloutVisual(in: line, contentStart: prefix.range.length)
                result.append(QuoteVisualLine(lineRange: paragraph, level: prefix.level, callout: callout))
            }
            location = NSMaxRange(paragraph)
        }
        return result
    }

    private static func quotePrefix(in line: String) -> (range: NSRange, level: Int)? {
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
        return (NSRange(location: 0, length: index), level)
    }

    private static func calloutVisual(in line: String, contentStart: Int) -> CalloutVisual? {
        let ns = line as NSString
        guard contentStart < ns.length else { return nil }
        let pattern = #"\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][+-]?(?:\s|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: line, range: NSRange(location: contentStart, length: ns.length - contentStart)),
              match.numberOfRanges >= 2 else {
            return nil
        }
        let kind = ns.substring(with: match.range(at: 1)).uppercased()
        let remainderStart = NSMaxRange(match.range(at: 0))
        let customTitle: String
        if remainderStart < ns.length {
            customTitle = ns.substring(from: remainderStart)
                .trimmingCharacters(in: .whitespaces)
        } else {
            customTitle = ""
        }
        return CalloutVisual(
            kind: kind,
            displayTitle: customTitle.isEmpty ? kind.capitalized : customTitle,
            tint: calloutTint(for: kind),
            symbolName: calloutSymbol(for: kind),
            titleRange: match.range(at: 1)
        )
    }

    func calloutDisplayTitles(in source: String) -> [String] {
        quoteVisualLines(in: source).compactMap { $0.callout?.displayTitle }
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

    private static func calloutSymbol(for kind: String) -> String {
        switch kind {
        case "TIP": return "lightbulb"
        case "IMPORTANT": return "exclamationmark.bubble"
        case "WARNING": return "exclamationmark.triangle"
        case "CAUTION": return "hand.raised"
        default: return "info.circle"
        }
    }

    private func drawHorizontalRules(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let storage = textStorage,
              let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.horizontalRule, in: charRange, options: []) { value, range, _ in
            guard value as? Bool == true else { return }
            let lineGlyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: lineGlyphs) { rect, _, _, _, _ in
                let y = rect.midY + origin.y
                let path = UIBezierPath()
                path.move(to: CGPoint(x: origin.x, y: y))
                path.addLine(to: CGPoint(x: origin.x + container.size.width, y: y))
                UIColor.separator.setStroke()
                path.lineWidth = 0.5
                path.stroke()
            }
        }
    }

    private func drawCodeBlockBackgrounds(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let storage = textStorage,
              let container = textContainers.first else { return }
        // Enumerate the FULL document — we need each fence's entire
        // range to compute the bounding rect correctly even when only
        // part of the fence is in `glyphsToShow`. The graphics context
        // clips off-screen portions of the path naturally.
        let fullRange = NSRange(location: 0, length: storage.length)
        let stringView = storage.string as NSString
        storage.enumerateAttribute(.codeBlockBody, in: fullRange, options: []) { value, range, _ in
            guard value as? Bool == true else { return }
            // Trim a trailing `\n` from the range — `boundingRect` on a
            // range ending in a newline pulls in the virtual next-line
            // fragment, which makes the panel extend a whole line below
            // the closer.
            var trimmed = range
            if trimmed.length > 0,
               stringView.character(at: NSMaxRange(trimmed) - 1) == 0x0A {
                trimmed.length -= 1
            }
            guard trimmed.length > 0 else { return }
            let glyphs = glyphRange(forCharacterRange: trimmed, actualCharacterRange: nil)
            let bounding = boundingRect(forGlyphRange: glyphs, in: container)
            // Panel matches the visible text column on each side —
            // inset by `lineFragmentPadding` so the rounded edges sit
            // flush with where text actually starts (the textContainer
            // reserves ~5pt of padding for layout, otherwise the panel
            // would extend past the heading/body text on both sides).
            let pad = container.lineFragmentPadding
            let rect = CGRect(
                x: origin.x + pad,
                y: bounding.minY + origin.y,
                width: max(0, container.size.width - 2 * pad),
                height: bounding.height
            )
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
            UIColor.secondarySystemFill.setFill()
            path.fill()
        }
    }

    private func drawInlineCodeBackgrounds(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let storage = textStorage,
              let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.inlineCodeSpan, in: charRange, options: []) { value, range, _ in
            guard value as? Bool == true else { return }
            drawInlineDecoration(range: range,
                                 style: .code,
                                 in: container,
                                 at: origin)
        }
    }

    private func drawHighlightBackgrounds(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let storage = textStorage,
              let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.highlightSpan, in: charRange, options: []) { value, range, _ in
            guard value != nil else { return }
            let color = (value as? UIColor) ?? ListsTokens.Markdown.highlightBackground
            drawInlineDecoration(range: range,
                                 style: .highlight(color),
                                 in: container,
                                 at: origin)
        }
    }

    private func drawLocalImages(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let storage = textStorage,
              let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.markdownLocalImage, in: charRange, options: []) { value, range, _ in
            guard let relativePath = value as? String,
                  MarkdownAttachmentIndex.isSafeRelativePath(relativePath) else { return }
            let url = StorageRoot.defaultListsDirectory().appendingPathComponent(relativePath)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate?.timeIntervalSinceReferenceDate) ?? 0
            let cacheKey = "\(url.path)#\(modified)" as NSString
            let image: UIImage
            if let cached = self.localImageCache.object(forKey: cacheKey) {
                image = cached
            } else if let loaded = UIImage(contentsOfFile: url.path) {
                image = loaded
                self.localImageCache.setObject(loaded, forKey: cacheKey)
            } else {
                return
            }
            let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            var lineRect: CGRect?
            self.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, stop in
                lineRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                stop.pointee = true
            }
            guard let lineRect else { return }
            let available = CGRect(
                x: origin.x + container.lineFragmentPadding,
                y: lineRect.minY + 4,
                width: max(1, container.size.width - container.lineFragmentPadding * 2),
                height: max(1, lineRect.height - 8)
            )
            let scale = min(available.width / image.size.width, available.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let rect = CGRect(
                x: available.minX,
                y: available.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
            let clip = UIBezierPath(roundedRect: rect, cornerRadius: 12)
            UIColor.secondarySystemBackground.setFill()
            clip.fill()
            UIGraphicsGetCurrentContext()?.saveGState()
            clip.addClip()
            image.draw(in: rect)
            UIGraphicsGetCurrentContext()?.restoreGState()
            UIColor.separator.withAlphaComponent(0.55).setStroke()
            clip.lineWidth = 0.5
            clip.stroke()
        }
    }

    private func drawInlineDecoration(range: NSRange,
                                      style: InlineDecorationStyle,
                                      in container: NSTextContainer,
                                      at origin: CGPoint) {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }

        enumerateLineFragments(forGlyphRange: glyphs) { _, usedRect, _, lineGlyphRange, _ in
            let lineStart = max(glyphs.location, lineGlyphRange.location)
            let lineEnd = min(NSMaxRange(glyphs), NSMaxRange(lineGlyphRange))
            guard lineEnd > lineStart else { return }

            let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
            let glyphBounds = self.boundingRect(forGlyphRange: lineRange, in: container)
            guard glyphBounds.width > 0, glyphBounds.height > 0 else { return }

            let used = usedRect.offsetBy(dx: origin.x, dy: origin.y)
            let maxLeft = used.minX
            let maxRight = used.maxX
            let left = max(maxLeft, glyphBounds.minX + origin.x - style.horizontalPadding)
            let right = min(maxRight, glyphBounds.maxX + origin.x + style.horizontalPadding)
            guard right > left else { return }

            let rect = CGRect(
                x: left,
                y: used.minY + style.verticalInset,
                width: right - left,
                height: max(0, used.height - style.verticalInset * 2)
            )

            let path = UIBezierPath(roundedRect: rect, cornerRadius: style.cornerRadius)
            style.color.setFill()
            path.fill()
        }
    }
}
