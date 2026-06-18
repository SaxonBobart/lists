import SwiftUI
import UIKit

/// Renders a list's `icon` string — either an SF Symbol (e.g. `list.bullet`)
/// or a single emoji character. We detect by asking UIKit whether the name
/// resolves to a system symbol image; if not, we treat the string as an
/// emoji and render it as text.
struct ListIconGlyph: View {
    let icon: String
    var size: CGFloat = 17
    var weight: Font.Weight = .semibold
    var color: Color = .white

    var body: some View {
        if ListIconGlyph.isSFSymbol(icon) {
            Image(systemName: icon)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
        } else {
            // Emoji ignore small point sizes — they lay out at ~1.3–1.4× their
            // font metrics — so in the small badges they'd fill the circle
            // rim-to-rim and read as cramped / "squishy". Cap each emoji to the
            // intended glyph box so it sits with the same breathing room as an
            // SF Symbol at the same `size`.
            Text(icon)
                .font(.system(size: size))
                .lineLimit(1)
                .minimumScaleFactor(0.1)
                .frame(width: size, height: size)
        }
    }

    static func isSFSymbol(_ name: String) -> Bool {
        UIImage(systemName: name) != nil
    }
}
