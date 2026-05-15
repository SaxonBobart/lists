import SwiftUI

/// Sidebar row for a list / sub-list / system entry. Icon badge on the left,
/// label, optional count.
struct SidebarRow: View {
    let icon: String
    let hue: Color
    let label: String
    var count: Int? = nil
    var indent: Int = 0
    var iconShape: IconBadge.Shape = .roundedSquare
    var iconGlyphColor: Color = .white

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, hue: hue, shape: iconShape, glyphColor: iconGlyphColor)
            Text(label)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(ListsTypography.mono)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, CGFloat(indent) * 20)
        .contentShape(Rectangle())
    }
}
