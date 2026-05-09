import SwiftUI

/// Sidebar row for a list / sub-list / system entry. Icon badge on the
/// left, label, optional count.
struct SidebarRow: View {
    let icon: String
    let hue: Color
    let label: String
    var count: Int? = nil
    var indent: Int = 0
    var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, hue: hue)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.leading, CGFloat(indent) * 20)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? hue.opacity(0.18) : .clear)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
