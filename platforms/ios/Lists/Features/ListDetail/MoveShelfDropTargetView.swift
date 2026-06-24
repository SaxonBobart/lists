import SwiftUI

struct MoveShelfDropTargetView: View {
    let item: Item
    let store: ItemStore
    let onBeginMove: (Item) -> Void

    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.headline)
                .foregroundStyle(ListsTokens.accent)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Move")
                    .font(ListsTypography.caption1)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(ListsTypography.body.weight(.semibold))
                    .foregroundStyle(ListsTokens.Foreground.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    ListsTokens.accent.opacity(isTargeted ? 0.65 : 0),
                    lineWidth: 2
                )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .onDrop(of: [ItemMoveDragPayload.typeIdentifier], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first(where: {
                $0.hasItemConformingToTypeIdentifier(ItemMoveDragPayload.typeIdentifier)
            }) else {
                return false
            }
            provider.loadDataRepresentation(forTypeIdentifier: ItemMoveDragPayload.typeIdentifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    guard let moving = ItemMoveDragPayload.movingItem(from: data, store: store) else {
                        return
                    }
                    onBeginMove(moving)
                }
            }
            return true
        }
        .accessibilityIdentifier("move.shelf.dropTarget")
        .accessibilityLabel("Move \(item.title.isEmpty ? "Untitled" : item.title)")
        .accessibilityHint("Drop here to hold this item while opening another list.")
    }
}
