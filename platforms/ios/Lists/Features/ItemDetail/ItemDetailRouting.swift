import SwiftUI

extension View {
    /// Presents the correct detail surface for any item type and preserves the
    /// shared in-place move flow when detail asks to move its item.
    func itemDetailCover(item: Binding<Item?>,
                         store: ItemStore,
                         onBeginMove: @escaping (Item) -> Void,
                         onBeginDocumentLink: ((DocumentLinkSource) -> Void)? = nil) -> some View {
        fullScreenCover(item: item) { presentedItem in
            ItemDetailRoute(
                item: presentedItem,
                store: store,
                presentedItem: item,
                onBeginMove: onBeginMove,
                onBeginDocumentLink: onBeginDocumentLink
            )
        }
    }
}

private struct ItemDetailRoute: View {
    let item: Item
    let store: ItemStore
    @Binding var presentedItem: Item?
    let onBeginMove: (Item) -> Void
    let onBeginDocumentLink: ((DocumentLinkSource) -> Void)?

    var body: some View {
        if item.type == .habit {
            HabitDetailView(item: item, store: store, onBeginMove: beginMove)
        } else if item.type == .canvas {
            CanvasItemView(item: item, store: store)
        } else {
            ItemDetailSheet(
                item: item,
                store: store,
                onBeginMove: beginMove,
                onBeginDocumentLink: beginDocumentLink
            )
        }
    }

    private func beginMove(_ moving: Item) {
        presentedItem = nil
        onBeginMove(moving)
    }

    private func beginDocumentLink(_ source: DocumentLinkSource) {
        presentedItem = nil
        onBeginDocumentLink?(source)
    }
}
