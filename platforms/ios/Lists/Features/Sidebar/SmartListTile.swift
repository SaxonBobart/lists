import SwiftUI

/// Full-width colored row for a smart list (Today / Scheduled / Flagged /
/// Urgent / Completed / All). White SF Symbol + label + monospaced count, all
/// on a tile-coloured background. Mirrors design `SmartRowFilled`.
struct SmartListTile: View {
    let smartList: SmartList
    let count: Int
    var hideCount: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: smartList.iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text(smartList.displayName)
                .font(ListsTypography.headline)
                .foregroundStyle(.white)
            Spacer()
            if !hideCount {
                Text("\(count)")
                    .font(ListsTypography.title3.monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, ListsSpacing.s4)
        .padding(.vertical, 14)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tileColor)
        )
    }

    private var tileColor: Color {
        switch smartList {
        case .today:     return ListsTokens.Hue.amber
        case .scheduled: return ListsTokens.Hue.orange
        case .flagged:   return ListsTokens.Hue.pink
        case .urgent:    return ListsTokens.Semantic.danger
        case .completed: return ListsTokens.Hue.grey
        case .all:       return ListsTokens.accent
        }
    }
}
