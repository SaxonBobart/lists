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
            Text(icon)
                .font(.system(size: size * 1.15))
        }
    }

    static func isSFSymbol(_ name: String) -> Bool {
        UIImage(systemName: name) != nil
    }
}
