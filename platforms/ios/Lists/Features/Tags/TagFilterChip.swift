import SwiftUI

struct TagFilterChip: View {
    let text: String
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void
    let allowsEditing: Bool
    let onRename: () -> Void
    let onDelete: () -> Void

    @ViewBuilder
    var body: some View {
        if allowsEditing {
            chipButton
                .contextMenu {
                    Button {
                        onRename()
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
        } else {
            chipButton
        }
    }

    private var chipButton: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text("#\(text)")
                    .font(.system(.callout, design: .monospaced))
                Text("\(count)")
                    .font(.system(.caption, design: .monospaced).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
            }
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    if isSelected {
                        Capsule().fill(ListsTokens.accent)
                    } else {
                        Capsule()
                            .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tags.row.\(text)")
    }
}
