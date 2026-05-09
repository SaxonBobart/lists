import SwiftUI

/// Full-width colored row for a smart list. White SF Symbol + label +
/// monospaced count on a tile-coloured background.
/// Layout per `screens-mobile.jsx#SmartRowFilled`; colors per system palette.
struct SmartListTile: View {
    let smartList: SmartList
    let count: Int
    var hideCount: Bool = false
    var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: smartList.iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text(smartList.displayName)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            if !hideCount {
                Text("\(count)")
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, ListsSpacing.s4)
        .padding(.vertical, 14)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ListsTokens.smartColor(smartList))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(isHovered ? 0.7 : 0), lineWidth: 2)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
