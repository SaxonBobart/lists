import SwiftUI

/// Picker for choosing a parent list when nesting / moving lists. Item moving
/// uses the in-place move shelf; this picker is retained only for list
/// hierarchy choices.
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
        ListParentPicker(
            store: store,
            movingListId: movingListId,
            initialSelection: initialSelection,
            onPick: onPick
        )
    }
}
