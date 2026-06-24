import SwiftUI

extension View {
    /// Presents the correct detail surface for any item type and preserves the
    /// shared in-place move flow when detail asks to move its item.
    func itemDetailCover(item: Binding<Item?>,
                         store: ItemStore,
                         onBeginMove: @escaping (Item) -> Void) -> some View {
        fullScreenCover(item: item) { presentedItem in
            ItemDetailRoute(
                item: presentedItem,
                store: store,
                presentedItem: item,
                onBeginMove: onBeginMove
            )
        }
    }
}

private struct ItemDetailRoute: View {
    let item: Item
    let store: ItemStore
    @Binding var presentedItem: Item?
    let onBeginMove: (Item) -> Void

    var body: some View {
        if item.type == .habit {
            HabitDetailView(item: item, store: store, onBeginMove: beginMove)
        } else {
            ItemDetailSheet(item: item, store: store, onBeginMove: beginMove)
        }
    }

    private func beginMove(_ moving: Item) {
        presentedItem = nil
        onBeginMove(moving)
    }
}
