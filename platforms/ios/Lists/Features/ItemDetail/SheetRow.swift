import SwiftUI

/// Single row inside an item-detail sheet's section card. Icon badge on the
/// left, label, value on the right. Subtle tint when value is empty/none.
struct SheetRow: View {
    let icon: String
    let hue: Color
    let label: String
    let value: String
    var subtle: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, hue: hue)
            Text(label)
                .font(ListsTypography.callout)
                .foregroundStyle(ListsTokens.Foreground.primary)
            Spacer()
            Text(value)
                .font(ListsTypography.callout)
                .foregroundStyle(subtle
                                 ? ListsTokens.Foreground.tertiary
                                 : ListsTokens.Foreground.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, ListsSpacing.s4)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}
