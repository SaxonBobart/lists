import SwiftUI

/// Small icon badge — circle (Apple Reminders style) or rounded square.
/// White SF Symbol on a hued background.
struct IconBadge: View {
    let systemName: String
    let hue: Color
    var size: CGFloat = 28
    var glyphSize: CGFloat = 14
    var shape: Shape = .roundedSquare
    var glyphColor: Color = .white

    enum Shape {
        case roundedSquare
        case circle
    }

    var body: some View {
        Group {
            switch shape {
            case .roundedSquare:
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hue)
            case .circle:
                Circle().fill(hue)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            ListIconGlyph(
                icon: systemName,
                size: glyphSize,
                weight: .semibold,
                color: glyphColor
            )
        }
    }
}
