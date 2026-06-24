import SwiftUI

struct MoveShelfView: View {
    let session: ItemMoveSession
    let store: ItemStore

    var body: some View {
        Group {
            if let item = session.movingItem(in: store) {
                let title = shelfTitle(for: item)
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.headline)
                        .foregroundStyle(ListsTokens.accent)
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Moving")
                            .font(ListsTypography.caption1)
                            .foregroundStyle(ListsTokens.Foreground.secondary)
                        Text(title)
                            .font(ListsTypography.body.weight(.semibold))
                            .foregroundStyle(ListsTokens.Foreground.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Moving")
                    .accessibilityValue(title)

                    Button("Cancel", systemImage: "xmark") {
                        session.cancel()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Cancel move")
                    .accessibilityIdentifier("move.shelf.cancel")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityIdentifier("move.shelf")
                .accessibilityHint("Pick None or another item in a user list. Open another list to move across lists.")
            }
        }
        .onAppear { session.cancelIfMovingItemUnavailable(in: store) }
        .onChange(of: movingItemAvailabilityToken) { _, _ in
            session.cancelIfMovingItemUnavailable(in: store)
        }
    }

    private func shelfTitle(for item: Item) -> String {
        item.title.isEmpty ? "Untitled" : item.title
    }

    private var movingItemAvailabilityToken: String {
        guard let movingItemId = session.movingItemId else { return "none" }
        guard let item = store.item(movingItemId) else { return "missing:\(movingItemId)" }
        return item.deletedAt == nil ? "active:\(movingItemId)" : "deleted:\(movingItemId)"
    }
}
