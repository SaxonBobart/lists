import UIKit

/// Hooks `NSLayoutManager.shouldGenerateGlyphs` to (1) hide markdown
/// markers when the cursor is off their line by marking their glyphs
/// as `.null` (zero-advance, no draw), and (2) swap `-` for `•`
/// (bullets) and `[` for ☐ / ☑ (task checkboxes) on the fly. Source
/// string is untouched — this is purely a layout-time substitution.
final class MarkdownLayoutDelegate: NSObject, NSLayoutManagerDelegate {
    weak var styler: MarkdownStyler?

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
