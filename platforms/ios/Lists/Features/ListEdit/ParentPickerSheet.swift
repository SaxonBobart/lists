import SwiftUI

/// Picker for choosing a parent list when nesting / moving lists. A thin shim
/// over the unified `MoveToPicker` (list mode) so the list "Move to" and the
/// item "Move to" are literally the same view — just without items.
///
/// Used by:
/// 1. **Create / edit list** — `ListEditSheet`'s Parent row (`movingListId` is
///    nil for a brand-new list).
/// 2. **Move existing list** — `SidebarView`'s "Move to…" swipe / context menu.
struct ParentPickerSheet: View {
    let store: ItemStore
    let movingListId: String?
    let initialSelection: String?
    let onPick: (String?) -> Void

    init(
        store: ItemStore,
        movingListId: String? = nil,
        initialSelection: String? = nil,
        onPick: @escaping (String?) -> Void
    ) {
        self.store = store
        self.movingListId = movingListId
        self.initialSelection = initialSelection
        self.onPick = onPick
    }

    var body: some View {
        MoveToPicker(
            store: store,
            movingListId: movingListId,
            initialSelection: initialSelection,
            onPick: onPick
        )
    }
}
