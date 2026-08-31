import SwiftUI

/// Grid tile for the Sidebar's "Pinned Lists" section. A faint tinted
/// background (the list color at low opacity) with the SF Symbol, label, and
/// count rendered in the full-strength color as foreground — the Apple Fitness
/// "Summary" pill treatment. Used for auto-lists and the Tags tile.
struct SmartListTile: View {
    let icon: String
    let label: String
    let tint: Color
    let count: Int?           // nil = hide count
    var glyphSize: CGFloat = 16
    var isHovered: Bool = false

    /// Convenience init for built-in smart lists.
    init(smartList: SmartList, count: Int, hideCount: Bool = false, isHovered: Bool = false) {
        self.icon = smartList.iconName
        self.label = smartList.displayName
        self.tint = ListsTokens.smartColor(smartList)
        self.count = hideCount ? nil : count
        self.glyphSize = smartList == .alarms ? 14 : 16
        self.isHovered = isHovered
    }

    /// Direct init for non-smart-list tiles (Tags, etc.).
    init(icon: String, label: String, tint: Color, count: Int?, glyphSize: CGFloat = 16, isHovered: Bool = false) {
        self.icon = icon
        self.label = label
        self.tint = tint
        self.count = count
        self.glyphSize = glyphSize
        self.isHovered = isHovered
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if let count {
                Text("\(count)")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(tint.opacity(0.7))
                    .fixedSize()
            }
        }
        .padding(.horizontal, ListsSpacing.s3)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 60)
        .background(
            RoundedRectangle(cornerRadius: ListsRadius.xl, style: .continuous)
                .fill(tint.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ListsRadius.xl, style: .continuous)
                .strokeBorder(tint.opacity(isHovered ? 0.7 : 0), lineWidth: 2)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
