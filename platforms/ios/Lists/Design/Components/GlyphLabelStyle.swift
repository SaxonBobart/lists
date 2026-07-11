import SwiftUI

/// Shared row-icon styling: secondary icon, small image scale, 24pt leading
/// column. Use for compact form labels that pair an SF Symbol with text.
struct GlyphLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .imageScale(.small)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            configuration.title
        }
    }
}
