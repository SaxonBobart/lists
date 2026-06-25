import SwiftUI

/// Single user-list view. Items are grouped by section when sections exist,
/// otherwise flat. The body is a UIKit collection/list bridge so rows can
/// support inline editing, reorder, hierarchy, swipe actions, and drag targets.
///
/// Top-trailing toolbar exposes a `•••` overflow menu with:
/// - Sort By (Manual / Due Date / Title / Date Added / Priority)
/// - Show Completed toggle
/// - Edit List → ListEditSheet
/// - Delete List → confirm → softDeleteList + pop nav
///
/// FloatingAddButton at bottom-right: tap → inline item, drag → positioned
/// inline item, long-press → Quick Capture for this list.
struct ListDetailView: View {
    let store: ItemStore
    /// The list value the navigation was created with — used only as a
    /// stable seed for the `listId` lookup and as a fallback if the list
    /// later vanishes from the store. **Never read inside the view body**;
    /// always go through the computed `list` accessor so SwiftUI re-reads
    /// the current value out of the observable store on every render.
    private let initialList: ItemList
    /// Shared global UI prefs (owned by the Sidebar). Read here for the
    /// default item type; passed down to sub-lists so the
    /// choice is consistent at every depth.
    let autoListPrefs: AutoListPreferences
    let moveSession: ItemMoveSession
    let habitsPluginEnabled: Bool

    init(
        store: ItemStore,
        list: ItemList,
        autoListPrefs: AutoListPreferences,
        moveSession: ItemMoveSession = ItemMoveSession(),
        habitsPluginEnabled: Bool = true
    ) {
        self.store = store
        self.initialList = list
        self.autoListPrefs = autoListPrefs
        self.moveSession = moveSession
        self.habitsPluginEnabled = habitsPluginEnabled
    }

    /// Always read the freshest value out of the store. This keeps section
    /// renames, reorders, additions, and other mutations reflecting in
    /// real time — without this, the view would snapshot at navigation
    /// time and edits would only appear after leaving + re-entering.
    private var list: ItemList {
        store.lists.first(where: { $0.id == initialList.id }) ?? initialList
    }

    @State private var captureTarget: CaptureTarget?
    @State private var fabIsInteracting = false
    /// Bridge to the collection-view coordinator for FAB-drag inline create.
    @State private var cvBridge = ListDetailBridge()
    @State private var prefs = ListViewPreferences()
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var showingNewSubList = false
    @State private var showingEditSections = false
    @State private var pendingDeleteSectionId: UUID?
    @State private var pendingDeleteSectionName: String = ""
    @State private var pendingDeleteSectionCount: Int = 0
    /// Item presented from row taps or swipe actions. The parent owns the
    /// detail route so a move started from detail can dismiss and continue in
    /// the shared bottom shelf.
    @State private var detailItem: Item?
    /// Pending sub-list navigation. Set by tapping a sub-list row in the
    /// collection view; presented via `navigationDestination(item:)` so we
    /// can route the tap manually (no NavigationLink in the cell) and keep
    /// the chevron aligned with the Sub-Lists header.
    @State private var navigatingSubList: ItemList?
    /// Multi-select mode — shows a trailing selection circle and the
    /// system drag handles on every row, swaps the row tap from "open
    /// detail" to "toggle selection", and replaces the `•••` toolbar with
    /// a Done button.
    @State private var inSelectMode = false
    @State private var selection: Set<UUID> = []
    /// Id of the row being edited inline (title + notes in place). Set by
    /// tapping a row's text; cleared when inline editing ends.
    @State private var editingItemId: UUID?
    /// Section key whose header is being renamed inline. Set by "New Section"
    /// (so you name it in place); cleared when the rename finishes.
    @State private var editingSectionKey: String?
    /// IDs of just-completed items kept visible during the linger window so
    /// the row can fade out instead of vanishing instantly. Cleared when the
    /// linger Task wakes up after ~1.5s, or immediately if the item is
    /// un-completed.
    @State private var lingeringIds: Set<UUID> = []
    /// Row currently lifted by UIKit drag-and-drop. While set, List Detail shows
    /// a bottom shelf target; dropping there enters shared move mode.
    @State private var moveShelfDragCandidate: Item?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
                Color(.systemBackground).ignoresSafeArea()

                // Keep the collection view mounted even when the list is empty
                // and overlay the empty state, rather than swapping the two.
                // Swapping tore down the collection view — and with it the
                // navigation controller's content-scroll-view association — so
                // a large title that had collapsed (from scrolling a populated
                // list) before the list emptied stayed stuck collapsed, only
                // re-appearing after the next manual scroll.
                ListDetailCollectionView(
                    store: store,
                    listId: list.id,
                    prefs: prefs,
                    listColor: ListsTokens.listColor(list.color),
                    bridge: cvBridge,
                    inSelectMode: $inSelectMode,
                    selection: $selection,
                    editingItemId: $editingItemId,
                    editingSectionKey: $editingSectionKey,
                    lingeringIds: lingeringIds,
                    defaultNewItemType: effectiveDefaultNewItemType,
                    habitsPluginEnabled: habitsPluginEnabled,
                    moveSession: moveSession,
                    onToggleItem: { toggleAndLinger($0) },
                    onIncrementHabit: { incrementHabitAndLinger($0) },
                    onSelectToggle: { toggleSelection($0) },
                    onPromptDeleteSection: { promptDeleteSection($0, name: $1) },
                    onSoftDeleteSubList: { id in
                        Task { try? await store.softDeleteList(id) }
                    },
                    onSoftDeleteItem: { id in
                        Task { try? await store.softDelete(id) }
                    },
                    onPromoteOthers: { name in
                        Task { try? await store.promoteOthersToSection(in: list.id, name: name) }
                    },
                    onRenameSection: { uuid, name in
                        Task { try? await store.renameSection(uuid, in: list.id, to: name) }
                    },
                    onShowItemDetail: { detailItem = $0 },
                    onOpenSubList: { navigatingSubList = $0 },
                    onMoveShelfDragCandidateChanged: { moveShelfDragCandidate = $0 },
                    onBeginInlineEdit: { id in
                        guard let item = store.item(id) else { return }
                        guard item.type != .habit else {
                            detailItem = item
                            return
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            editingItemId = id
                        }
                    },
                    onBeginMove: { beginMove($0) },
                    onEndInlineEdit: { endedId in
                        if editingItemId == endedId { editingItemId = nil }
                    },
                    onEndEditSection: { editingSectionKey = nil }
                )
                // Full-bleed so rows scroll under the glass nav bar; the
                // controller's collection view is auto-tracked by the
                // navigation controller, driving large-title collapse.
                .ignoresSafeArea()
                .overlay {
                    if !moveSession.isActive && visibleItems.isEmpty && childLists.isEmpty {
                        emptyState
                    }
                }
                .navigationDestination(item: $navigatingSubList) { child in
                    ListDetailView(
                        store: store,
                        list: child,
                        autoListPrefs: autoListPrefs,
                        moveSession: moveSession,
                        habitsPluginEnabled: habitsPluginEnabled
                    )
                }

                ListDetailBottomChrome(
                    store: store,
                    listId: list.id,
                    listColor: ListsTokens.listColor(list.color),
                    defaultNewItemType: effectiveDefaultNewItemType,
                    cvBridge: cvBridge,
                    moveSession: moveSession,
                    inSelectMode: $inSelectMode,
                    selection: $selection,
                    editingItemId: $editingItemId,
                    fabIsInteracting: $fabIsInteracting,
                    moveShelfDragCandidate: moveShelfDragCandidate,
                    onBeginMove: beginMove,
                    onOpenQuickCapture: {
                        captureTarget = CaptureTarget(listId: list.id, section: nil)
                    }
                )
            }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarTitleColor(ListsTokens.listColor(list.color))
        .tint(ListsTokens.listColor(list.color))
        .toolbar {
            // The ⋯ menu (or Done in select mode) — stays put while editing and
            // shifts left to make room for the ✓.
            if !moveSession.isActive {
                ToolbarItem(placement: .topBarTrailing) {
                    if inSelectMode {
                        Button("Done") {
                            inSelectMode = false
                            selection.removeAll()
                        }
                        .accessibilityIdentifier("list.selectMode.done")
                    } else {
                        ListDetailToolbarMenu(
                            listId: list.id,
                            hasSections: list.sections.isEmpty == false,
                            prefs: prefs,
                            onNewSection: createSectionAndRename,
                            onEditSections: { showingEditSections = true },
                            onNewSublist: { showingNewSubList = true },
                            onSelectItems: { inSelectMode = true },
                            onEditList: { showingEdit = true },
                            onDeleteList: { showingDeleteConfirm = true }
                        )
                    }
                }
            }
            // Separate trailing button (its own glass circle) — the blue ✓ that
            // commits the inline edit. The spacer breaks iOS 26's shared-glass
            // grouping so the ✓ sits apart from the ⋯ pill, not inside it.
            if editingItemId != nil && !inSelectMode && !moveSession.isActive {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    inlineDoneTick
                }
            }
        }
        .sheet(item: $captureTarget) { target in
            QuickCaptureSheet(
                store: store,
                defaultListId: target.listId,
                defaultSection: target.section,
                defaultNewItemType: effectiveDefaultNewItemType,
                onOpenCreatedItem: { detailItem = $0 }
            )
        }
        .itemDetailCover(item: $detailItem, store: store, onBeginMove: beginMove)
        .sheet(isPresented: $showingEdit) {
            ListEditSheet(existing: list, store: store)
        }
        .sheet(isPresented: $showingNewSubList) {
            ListEditSheet(store: store, initialParentId: list.id)
        }
        .sheet(isPresented: $showingEditSections) {
            EditSectionsSheet(store: store, list: list)
        }
        .onChange(of: moveSession.movingItemId) { _, _ in
            guard moveSession.isActive else { return }
            clearTransientModesForMove()
        }
        .onDisappear {
            moveShelfDragCandidate = nil
        }
        .task(id: list.id) {
            try? await store.migrateLegacySectionsIfNeeded(listId: list.id)
        }
        .alert("Delete this list?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await store.softDeleteList(list.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteListMessage)
        }
        .alert(
            "Delete \"\(pendingDeleteSectionName)\"?",
            isPresented: Binding(
                get: { pendingDeleteSectionId != nil },
                set: { if !$0 { pendingDeleteSectionId = nil } }
            )
        ) {
            Button("Delete", role: .destructive) { confirmDeleteSection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if pendingDeleteSectionCount > 0 {
                let noun = pendingDeleteSectionCount == 1 ? "item" : "items"
                Text("This section and its \(pendingDeleteSectionCount) \(noun) will move to Recently Deleted.")
            } else {
                Text("This section will be removed.")
            }
        }
    }

    // MARK: - Toolbar

    /// Solid blue ✓ shown while editing inline. Uses the prominent button style
    /// so iOS fills the whole toolbar circle blue (rather than a glass ring
    /// around a smaller filled circle).
    private var inlineDoneTick: some View {
        Button {
            editingItemId = nil
        } label: {
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .accessibilityLabel("Done editing")
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(ListsTokens.accent)
        .accessibilityIdentifier("inline.editor.done")
    }

    // MARK: - Empty state inputs

    /// Direct child lists of the current list, non-deleted, sorted by
    /// position. Empty when this is a leaf list.
    private var childLists: [ItemList] {
        store.lists
            .filter { $0.parentId == list.id && $0.deletedAt == nil }
            .sorted { $0.position < $1.position }
    }

    private func promptDeleteSection(_ id: UUID, name: String) {
        let sidStr = id.uuidString
        let count = store.items.filter {
            $0.listId == list.id && $0.section == sidStr && $0.deletedAt == nil
        }.count
        pendingDeleteSectionId = id
        pendingDeleteSectionName = name
        pendingDeleteSectionCount = count
    }

    private func confirmDeleteSection() {
        guard let sid = pendingDeleteSectionId else { return }
        let listId = list.id
        Task { try? await store.deleteSection(sid, in: listId, cascadingItems: true) }
        pendingDeleteSectionId = nil
    }

    private var deleteListMessage: String {
        if store.descendantIds(of: list.id).isEmpty {
            return "\"\(list.name)\" and its items will move to Recently Deleted."
        }
        return "\"\(list.name)\", its sub-lists, and its items will move to Recently Deleted."
    }

    private func createSectionAndRename() {
        Task {
            if let section = try? await store.addSection(in: list.id, name: "New Section") {
                editingSectionKey = section.id.uuidString
            }
        }
    }

    private var emptyState: some View {
        ListDetailEmptyStateView(
            icon: list.icon,
            color: ListsTokens.listColor(list.color)
        )
    }

    // MARK: - Data

    /// Top-level items in this list — filtered by "show completed" and
    /// reordered by the active sort mode. Just-completed items in
    /// `lingeringIds` stay visible for the fade window.
    private var visibleItems: [Item] {
        let showCompleted = prefs.showCompleted(for: list.id)
        let showPastEvents = prefs.showPastEvents(for: list.id)
        let now = Date.now
        let calendar = Calendar.current
        let filtered = store.items.filter { item in
            item.listId == list.id
                && item.deletedAt == nil
                && item.parentId == nil
                && item.isAvailable(habitsEnabled: habitsPluginEnabled)
                && (showCompleted || !item.isComplete(at: now) || lingeringIds.contains(item.id))
                && (showPastEvents || !item.isRolledOffPastEvent(now: now, calendar: calendar))
        }
        return applySort(filtered)
    }

    private var effectiveDefaultNewItemType: Item.ItemType {
        BuiltInModulePreferences.effectiveItemType(
            autoListPrefs.defaultNewItemType,
            habitsEnabled: habitsPluginEnabled
        )
    }

    private func toggleAndLinger(_ item: Item) {
        ItemCompletionLinger.toggle(
            item,
            store: store,
            showCompleted: prefs.showCompleted(for: list.id),
            lingeringIds: &lingeringIds,
            startLinger: startLinger
        )
    }

    private func incrementHabitAndLinger(_ item: Item) {
        ItemCompletionLinger.incrementHabit(
            item,
            store: store,
            showCompleted: prefs.showCompleted(for: list.id),
            startLinger: startLinger
        )
    }

    private func toggleSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func beginMove(_ item: Item) {
        clearTransientModesForMove()
        moveSession.begin(item: item)
    }

    private func clearTransientModesForMove() {
        editingItemId = nil
        editingSectionKey = nil
        moveShelfDragCandidate = nil
        inSelectMode = false
        selection.removeAll()
    }

    private func startLinger(for id: UUID) {
        lingeringIds.insert(id)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.4)) {
                _ = lingeringIds.remove(id)
            }
        }
    }

    private func applySort(_ items: [Item]) -> [Item] {
        items.sortedBy(prefs.sort(for: list.id), direction: prefs.sortDirection(for: list.id))
    }

}
