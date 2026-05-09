import SwiftUI

/// Sidebar row for a list / sub-list / system entry. Icon badge on the left,
/// label, optional count on the right. Mirrors design `SidebarRow`.
struct SidebarRow: View {
    let icon: String
    let hue: Color
    let label: String
    var count: Int? = nil
    var indent: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, hue: hue)
            Text(label)
                .font(ListsTypography.callout)
                .foregroundStyle(ListsTokens.Foreground.primary)
                .lineLimit(1)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(ListsTypography.mono)
                    .foregroundStyle(ListsTokens.Foreground.tertiary)
            }
        }
        .padding(.horizontal, 12 + CGFloat(indent) * 20)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
