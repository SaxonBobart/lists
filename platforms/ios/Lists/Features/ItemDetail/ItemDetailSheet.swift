import SwiftUI

/// Full-screen detail router for existing items.
///
/// Tasks, notes, and events open as a document page (`ItemDocumentView`) with
/// breadcrumb navigation registered at the stack root. Habits use their
/// dedicated first-party surface (`HabitDetailView`).
struct ItemDetailSheet: View {
    let originalItem: Item
    let store: ItemStore
    let onBeginMove: ((Item) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()

    init(item: Item, store: ItemStore, onBeginMove: ((Item) -> Void)? = nil) {
        self.originalItem = item
        self.store = store
        self.onBeginMove = onBeginMove
    }

    var body: some View {
        if originalItem.type == .habit {
            HabitDetailView(item: originalItem, store: store, onBeginMove: moveHandler)
        } else {
            documentStack
        }
    }

    private var documentStack: some View {
        NavigationStack(path: $path) {
            ItemDocumentView(
                item: originalItem,
                store: store,
                path: $path,
                onBeginMove: moveHandler
            )
            // Single registration at the stack root so breadcrumb jumps work
            // from any depth. A per-page destination would collide by type.
            .navigationDestination(for: BreadcrumbDestination.self) { destination in
                if let item = store.items.first(where: { $0.id == destination.id && $0.deletedAt == nil }) {
                    ItemDocumentView(
                        item: item,
                        store: store,
                        path: $path,
                        onBeginMove: moveHandler
                    )
                }
            }
        }
    }

    private var moveHandler: ((Item) -> Void)? {
        onBeginMove.map { begin in
            { item in
                dismiss()
                begin(item)
            }
        }
    }
}
