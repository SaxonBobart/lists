import UIKit

enum MarkdownChecklistMetrics {
    static let symbolLeadingOffset: CGFloat = 0
    static let textGap: CGFloat = 8
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
    private struct QuoteVisualLine {
        let lineRange: NSRange
        let level: Int
        let callout: CalloutVisual?
    }

    private struct CalloutVisual {
        let kind: String
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
        drawQuoteBlockBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawCodeBlockBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawInlineCodeBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawHighlightBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawHorizontalRules(forGlyphRange: glyphsToShow, at: origin)
    }

    /// Overlay SF Symbol images on top of the default glyph render for
    /// any char marked with `.sfSymbolCheckbox`. The underlying ☐ / ☑
    /// glyph reserves layout space; we hide it via `.foregroundColor =
    /// .clear` in the styler and draw the tinted symbol image here.
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
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
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
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
        let rowRects = visibleRows.compactMap { row -> (MarkdownTableRow, CGRect)? in
            guard let rect = rowRect(for: row, in: container, at: origin) else { return nil }
            return (row, rect)
        }
        guard let first = rowRects.first?.1,
              let last = rowRects.last?.1,
              table.columnCount > 0 else { return }

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

    private func rowRect(for row: MarkdownTableRow,
                         in container: NSTextContainer,
                         at origin: CGPoint) -> CGRect? {
        let glyphs = glyphRange(forCharacterRange: row.lineRange, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var rect: CGRect?
        enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, _, stop in
            rect = lineRect.offsetBy(dx: origin.x, dy: origin.y)
            stop.pointee = true
        }
        guard var rect else { return nil }
        let font = (textStorage?.attribute(.font,
                                           at: row.lineRange.location,
                                           effectiveRange: nil) as? UIFont)
            ?? UIFont.preferredFont(forTextStyle: .body)
        let minimumHeight = MarkdownTableVisualMetrics.rowHeight(for: font)
        if rect.height < minimumHeight {
            rect.origin.y -= (minimumHeight - rect.height) / 2
            rect.size.height = minimumHeight
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

        drawCalloutBlocks(blocks: calloutBlocks, in: container, at: origin)
        drawQuoteRails(lines: lines, excluding: calloutBlocks, in: container, at: origin)
    }

    private func drawCalloutBlocks(blocks: [CalloutVisualBlock],
                                   in container: NSTextContainer,
                                   at origin: CGPoint) {
        for block in blocks {
            guard let callout = block.header.callout,
                  let rect = quoteBlockRect(for: block.lines, level: block.header.level, in: container, at: origin) else {
                continue
            }

            if block.header.level == 1 {
                let fill = UIBezierPath(roundedRect: rect, cornerRadius: 10)
                callout.tint.withAlphaComponent(0.12).setFill()
                fill.fill()

                callout.tint.withAlphaComponent(0.28).setStroke()
                fill.lineWidth = 0.5
                fill.stroke()
            }

            let railSourceRect: CGRect
            if block.header.level == 1 {
                railSourceRect = rect
            } else if let nestedRail = quoteRailRect(for: block.lines, level: block.header.level, in: container, at: origin) {
                railSourceRect = nestedRail
            } else {
                railSourceRect = rect
            }
            let rail = CGRect(
                x: railSourceRect.minX,
                y: railSourceRect.minY + 2,
                width: 3,
                height: max(0, railSourceRect.height - 4)
            )
            let railPath = UIBezierPath(roundedRect: rail, cornerRadius: 1.5)
            callout.tint.setFill()
            railPath.fill()

            drawCalloutIcon(callout, in: block.header.lineRange, rect: rect, container: container, at: origin)
        }
    }

    private func drawQuoteRails(lines: [QuoteVisualLine],
                                excluding calloutBlocks: [CalloutVisualBlock],
                                in container: NSTextContainer,
                                at origin: CGPoint) {
        let maxLevel = lines.map(\.level).max() ?? 0
        guard maxLevel > 0 else { return }
        let calloutLineLocations = Set(calloutBlocks.flatMap { block in
            block.lines.map { $0.lineRange.location }
        })

        for level in 1...maxLevel {
            var run: [QuoteVisualLine] = []
            func flush() {
                guard let rect = quoteRailRect(for: run, level: level, in: container, at: origin) else {
                    run.removeAll()
                    return
                }
                let color = run.first(where: { $0.level == level })?.callout?.tint ?? UIColor.separator
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 1.5)
                color.withAlphaComponent(color == UIColor.separator ? 0.65 : 0.85).setFill()
                path.fill()
                run.removeAll()
            }

            for line in lines {
                let isInsideCallout = calloutLineLocations.contains(line.lineRange.location)
                let isContiguous = run.last.map { NSMaxRange($0.lineRange) >= line.lineRange.location - 1 } ?? true
                if line.level >= level, !isInsideCallout, isContiguous {
                    run.append(line)
                } else {
                    flush()
                    if line.level >= level, !isInsideCallout {
                        run.append(line)
                    }
                }
            }
            flush()
        }
    }

    private func calloutVisualBlocks(from lines: [QuoteVisualLine]) -> [CalloutVisualBlock] {
        lines.enumerated().compactMap { index, line in
            guard line.callout != nil else { return nil }
            var blockLines = [line]
            var next = index + 1
            while next < lines.count {
                let candidate = lines[next]
                let isContiguous = NSMaxRange(lines[next - 1].lineRange) >= candidate.lineRange.location - 1
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
        guard let firstLine = lines.first,
              let lastLine = lines.last else { return nil }
        let blockRange = NSRange(
            location: firstLine.lineRange.location,
            length: NSMaxRange(lastLine.lineRange) - firstLine.lineRange.location
        )
        let glyphs = glyphRange(forCharacterRange: blockRange, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        let bounds = boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: origin.x, dy: origin.y)
        let left = origin.x + container.lineFragmentPadding + CGFloat(max(0, level - 1)) * 20 + 8
        let right = origin.x + container.size.width - container.lineFragmentPadding
        return CGRect(
            x: left,
            y: bounds.minY - 1,
            width: max(24, right - left),
            height: max(22, bounds.height + 2)
        )
    }

    private func quoteRailRect(for lines: [QuoteVisualLine],
                               level: Int,
                               in container: NSTextContainer,
                               at origin: CGPoint) -> CGRect? {
        let rects = lines.compactMap {
            fullLineFragmentRect(for: $0.lineRange, in: container, at: origin)
        }
        guard let first = rects.first, let last = rects.last else { return nil }
        let x = origin.x + container.lineFragmentPadding + CGFloat(level - 1) * 20
        return CGRect(x: x, y: first.minY + 2, width: 3, height: max(0, last.maxY - first.minY - 4))
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
        let size = CGSize(width: 16, height: 16)
        let drawRect = CGRect(
            x: rect.minX + 10,
            y: lineRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        image.withTintColor(callout.tint, renderingMode: .alwaysOriginal).draw(in: drawRect)
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
        return CalloutVisual(
            kind: kind,
            tint: calloutTint(for: kind),
            symbolName: calloutSymbol(for: kind),
            titleRange: match.range(at: 1)
        )
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
