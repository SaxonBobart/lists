import UIKit

/// Hooks `NSLayoutManager.shouldGenerateGlyphs` to (1) hide markdown
/// markers when the cursor is off their line by marking their glyphs
/// as `.null` (zero-advance, no draw), and (2) swap `-` for `•`
/// (bullets) and `[` for ☐ / ☑ (task checkboxes) on the fly. Source
/// string is untouched — this is purely a layout-time substitution.
final class MarkdownLayoutDelegate: NSObject, NSLayoutManagerDelegate {
    weak var styler: MarkdownStyler?

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<CGRect>,
                       baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer,
                       forGlyphRange glyphRange: NSRange) -> Bool {
        let characters = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        var height = lineFragmentRect.pointee.height
        for index in characters.location..<NSMaxRange(characters) {
            if let mediaHeight = styler?.mediaHeight(at: index) { height = max(height, mediaHeight) }
            if let rendered = styler?.renderedImage(at: index) {
                height = max(height, rendered.image.size.height + 4)
            }
        }
        guard height > lineFragmentRect.pointee.height else { return false }
        let extra = height - lineFragmentRect.pointee.height
        lineFragmentRect.pointee.size.height = height
        lineFragmentUsedRect.pointee.size.height = height
        baselineOffset.pointee += extra / 2
        return true
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction, forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        styler?.renderedImage(at: charIndex) != nil || styler?.mediaHeight(at: charIndex) != nil ? .whitespace : action
    }

    func layoutManager(_ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer, proposedLineFragment proposedRect: CGRect, glyphPosition: CGPoint, characterIndex charIndex: Int) -> CGRect {
        if let height = styler?.mediaHeight(at: charIndex) {
            return CGRect(x: 0, y: 0, width: max(1, textContainer.size.width - 2 * textContainer.lineFragmentPadding), height: height)
        }
        guard let image = styler?.renderedImage(at: charIndex)?.image else { return .zero }
        let inline = styler?.renderedImage(at: charIndex)?.kind == "inline"
        let width = inline ? min(image.size.width + 4, textContainer.size.width)
            : max(1, textContainer.size.width - 2 * textContainer.lineFragmentPadding)
        return CGRect(x: 0, y: 0, width: width, height: image.size.height + 4)
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes charIndexes: UnsafePointer<Int>,
                       font aFont: UIFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard let styler else { return 0 }

        let count = glyphRange.length
        let newGlyphs = UnsafeMutablePointer<CGGlyph>.allocate(capacity: count)
        let newProps  = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>.allocate(capacity: count)
        defer {
            newGlyphs.deallocate()
            newProps.deallocate()
        }

        var didModify = false
        let ctFont = unsafeBitCast(aFont, to: CTFont.self)

        for i in 0..<count {
            var glyph = glyphs[i]
            var prop  = props[i]
            let charIdx = charIndexes[i]

            if let hideProp = styler.glyphProperty(at: charIdx) {
                prop = hideProp
                didModify = true
            }

            if let subChar = styler.glyphSubstitution(at: charIdx) {
                var c = subChar
                var subGlyph: CGGlyph = 0
                if CTFontGetGlyphsForCharacters(ctFont, &c, &subGlyph, 1), subGlyph != 0 {
                    glyph = subGlyph
                    didModify = true
                }
            }

            newGlyphs[i] = glyph
            newProps[i]  = prop
        }

        if !didModify { return 0 }

        layoutManager.setGlyphs(newGlyphs,
                                properties: newProps,
                                characterIndexes: charIndexes,
                                font: aFont,
                                forGlyphRange: glyphRange)
        return count
    }
}
