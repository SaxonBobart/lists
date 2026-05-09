import SwiftUI

/// Small rounded-square icon badge used in sidebar rows. White SF Symbol on a
/// hued background. See `IconBadge` in design `primitives.jsx`.
struct IconBadge: View {
    let systemName: String
    let hue: Color
    var size: CGFloat = 28
    var glyphSize: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(hue)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: glyphSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}
