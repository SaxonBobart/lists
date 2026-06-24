import SwiftUI

struct ListDetailBottomChrome: View {
    let store: ItemStore
    let listId: String
    let listColor: Color
    let defaultNewItemType: Item.ItemType
    let cvBridge: ListDetailBridge
    let moveSession: ItemMoveSession
    @Binding var inSelectMode: Bool
    @Binding var selection: Set<UUID>
    @Binding var editingItemId: UUID?
    @Binding var fabIsInteracting: Bool
    let moveShelfDragCandidate: Item?
    let onBeginMove: (Item) -> Void
    let onOpenQuickCapture: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if inSelectMode && !moveSession.isActive {
                SelectionToolbar(
                    store: store,
                    listId: listId,
                    selection: $selection,
                    inSelectMode: $inSelectMode
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            } else if editingItemId == nil && !moveSession.isActive && moveShelfDragCandidate == nil {
                FloatingAddButton(
                    tint: listColor,
                    action: createInlineItem,
                    onDragChanged: { location in
                        cvBridge.updateInlineDragCue(globalPoint: location)
                    },
                    onDragEnded: { location in
                        createInlineItem(at: location)
                    },
                    onLongPress: onOpenQuickCapture,
                    isInteracting: $fabIsInteracting
                )
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }

            if let moveShelfDragCandidate, !moveSession.isActive {
                MoveShelfDropTargetView(
                    item: moveShelfDragCandidate,
                    store: store,
                    onBeginMove: onBeginMove
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func createInlineItem() {
        editingItemId = store.addInlineItem(
            type: defaultNewItemType,
            listId: listId,
            section: nil
        )
    }

    private func createInlineItem(at location: CGPoint) {
        if let id = cvBridge.createInlineItemAtDrag(globalPoint: location) {
            editingItemId = id
        } else {
            createInlineItem()
        }
    }
}
