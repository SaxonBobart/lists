import UIKit

/// `NSLayoutManager` subclass that paints extras the standard
/// text-rendering path can't:
/// - **Horizontal rule**: 0.5pt full-width separator across line
///   fragments carrying `.horizontalRule`.
/// - **Code block body**: prominent rounded `.secondarySystemFill`
///   panel behind any contiguous run of chars with `.codeBlockBody`.
/// - **Inline code span**: smaller rounded `.tertiarySystemFill` pill
///   behind chars with `.inlineCodeSpan`. Uses
///   `enumerateEnclosingRects` so wrapped spans get a pill per line
///   fragment.
final class MarkdownLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        drawCodeBlockBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawInlineCodeBackgrounds(forGlyphRange: glyphsToShow, at: origin)
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
            // Use `location(forGlyphAt:)` + the line fragment rect rather
            // than `boundingRect(forGlyphRange:in:)`. On iOS 26 the latter
            // returns a position that drifts to the end of the line for a
            // substituted, 0.01pt-sized glyph sitting at the start of a
            // paragraph with a non-zero `firstLineHeadIndent` — so the
            // checkbox appears to the right of the content on nested task
            // rows. `location` reliably reports the glyph's actual x within
            // its line fragment, which is what we want.
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let lineFragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let glyphLocation = location(forGlyphAt: glyphs.location)
            let isChecked = symbolName.contains("fill")
            let tint: UIColor = isChecked ? .tintColor : .label
            let size = image.size
            // Shift the symbol 6pt left of its cell origin so it sits
            // visibly inset from the content (which lands at the indent
            // column). The user is fine with this drifting past the
            // textContainer's left inset — keeps the marker compact.
            let x = lineFragment.minX + glyphLocation.x + origin.x
            let y = lineFragment.midY + origin.y
            let drawRect = CGRect(
                x: x - 6,
                y: y - size.height / 2,
                width: size.width,
                height: size.height
            )
            image.withTintColor(tint, renderingMode: .alwaysOriginal).draw(in: drawRect)
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
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateEnclosingRects(forGlyphRange: glyphs,
                                    withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                    in: container) { rect, _ in
                let r = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -3, dy: -1)
                let path = UIBezierPath(roundedRect: r, cornerRadius: 4)
                UIColor.tertiarySystemFill.setFill()
                path.fill()
            }
        }
    }
}
