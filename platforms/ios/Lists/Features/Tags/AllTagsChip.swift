import SwiftUI

struct AllTagsChip: View {
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "number")
                    .font(.caption.weight(.semibold))
                Text("All")
                    .font(.system(.callout, design: .monospaced))
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? ListsTokens.accent : Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tags.all")
    }
}
