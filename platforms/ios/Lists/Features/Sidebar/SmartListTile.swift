import SwiftUI

/// Full-width colored tile for the Sidebar's "Pinned Lists" section. White
/// SF Symbol + label + monospaced count on a tile-coloured background. Used
/// for auto-lists AND the Tags row (per Saxon's restructure).
struct SmartListTile: View {
    let icon: String
    let label: String
    let tint: Color
    let count: Int?           // nil = hide count
    var isHovered: Bool = false

    /// Convenience init for built-in smart lists.
    init(smartList: SmartList, count: Int, hideCount: Bool = false, isHovered: Bool = false) {
        self.icon = smartList.iconName
        self.label = smartList.displayName
        self.tint = ListsTokens.smartColor(smartList)
        self.count = hideCount ? nil : count
        self.isHovered = isHovered
    }

    /// Direct init for non-smart-list tiles (Tags, etc.).
    init(icon: String, label: String, tint: Color, count: Int?, isHovered: Bool = false) {
        self.icon = icon
        self.label = label
        self.tint = tint
        self.count = count
        self.isHovered = isHovered
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, ListsSpacing.s4)
        .padding(.vertical, 14)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(isHovered ? 0.7 : 0), lineWidth: 2)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
