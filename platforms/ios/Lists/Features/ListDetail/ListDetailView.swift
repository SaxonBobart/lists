import SwiftUI

/// Single user-list view (vertical layout). Items grouped by section if any
/// are set; otherwise flat. Uses SwiftUI `List` with `.insetGrouped` for
/// native iOS chrome.
///
/// Top-trailing toolbar exposes a `•••` overflow menu with:
/// - Sort By (Manual / Due Date / Title / Date Added / Priority)
/// - Show Completed toggle
/// - Edit List → ListEditSheet
/// - Delete List → confirm → softDeleteList + pop nav
///
/// FloatingAddButton at bottom-right: tap → QuickCaptureSheet for this list;
/// drag onto a section header → QuickCaptureSheet pre-targeted to that section.
struct ListDetailView: View {
    let store: ItemStore
    /// The list value the navigation was created with — used only as a
    /// stable seed for the `listId` lookup and as a fallback if the list
    /// later vanishes from the store. **Never read inside the view body**;
    /// always go through the computed `list` accessor so SwiftUI re-reads
    /// the current value out of the observable store on every render.
    private let initialList: ItemList
    /// Shared global UI prefs (owned by the Sidebar). Read here for the
    /// "New Item from +" default type; threaded down to sub-lists so the
    /// choice is consistent at every depth.
    let autoListPrefs: AutoListPreferences

    init(store: ItemStore, list: ItemList, autoListPrefs: AutoListPreferences) {
        self.store = store
        self.initialList = list
        self.autoListPrefs = autoListPrefs
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
    @State private var renamingSectionId: String?
    @State private var renameBuffer: String = ""
    @FocusState private var renameFocus: String?
    @State private var pendingDeleteSectionId: UUID?
    @State private var pendingDeleteSectionName: String = ""
    @State private var pendingDeleteSectionCount: Int = 0
    /// Item presented via the Details swipe action. Tap-to-open still uses
    /// `ItemRow`'s own internal state, so both paths land here.
    @State private var detailItem: Item?
    /// Pending sub-list navigation. Set by tapping a sub-list row in the
    /// collection view; presented via `navigationDestination(item:)` so we
    /// can route the tap manually (no NavigationLink in the cell) and keep
    /// the chevron aligned with the Sub-Lists header.
    @State private var navigatingSubList: ItemList?
    /// Whether the "Sub-Lists" section is currently expanded. Persisted
    /// per-list via [[ListViewPreferences]] so the choice survives navigation
    /// and relaunches.
    private var subListsExpanded: Bool {
        prefs.subListsExpanded(for: list.id)
    }
    /// "Select Reminders" mode — shows a trailing selection circle and the
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
    @Environment(\.dismiss) private var dismiss

    private static let sectionPrefix = "section:"

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
                    defaultNewItemType: autoListPrefs.defaultNewItemType,
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
                    onBeginInlineEdit: { id in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            editingItemId = id
                        }
                    },
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
                    if visibleItems.isEmpty && childLists.isEmpty {
                        emptyState
                    }
                }
                .navigationDestination(item: $navigatingSubList) { child in
                    ListDetailView(store: store, list: child, autoListPrefs: autoListPrefs)
                }

                if inSelectMode {
                    SelectionToolbar(
                        store: store,
                        listId: list.id,
                        selection: $selection,
                        inSelectMode: $inSelectMode
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                } else if editingItemId == nil {
                    // Hidden while editing inline — the keyboard toolbar + blue ✓
                    // own that mode, and a floating + over the keyboard reads as clutter.
                    FloatingAddButton(
                        tint: ListsTokens.listColor(list.color),
                        action: {
                            // Tap → instant inline item in "Others" (type per Settings),
                            // focused for typing.
                            editingItemId = store.addInlineItem(
                                type: autoListPrefs.defaultNewItemType,
                                listId: list.id,
                                section: nil
                            )
                        },
                        onDragChanged: { location in
                            // Live drop cue — same gap + placement rendering as
                            // dragging an existing item.
                            cvBridge.updateInlineDragCue(globalPoint: location)
                        },
                        onDragEnded: { location in
                            // Drag → position + indent via the move-items drop logic.
                            if let id = cvBridge.createInlineItemAtDrag(globalPoint: location) {
                                editingItemId = id
                            } else {
                                editingItemId = store.addInlineItem(
                                    type: autoListPrefs.defaultNewItemType,
                                    listId: list.id,
                                    section: nil
                                )
                            }
                        },
                        onLongPress: {
                            // Long-press → full capture sheet for this list's "Others".
                            captureTarget = CaptureTarget(listId: list.id, section: nil)
                        },
                        isInteracting: $fabIsInteracting
                    )
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                }
            }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarTitleColor(ListsTokens.listColor(list.color))
        .tint(ListsTokens.listColor(list.color))
        .toolbar {
            // The ⋯ menu (or Done in select mode) — stays put while editing and
            // shifts left to make room for the ✓.
            ToolbarItem(placement: .topBarTrailing) {
                if inSelectMode {
                    Button("Done") {
                        inSelectMode = false
                        selection.removeAll()
                    }
                    .accessibilityIdentifier("list.selectMode.done")
                } else {
                    overflowMenu
                }
            }
            // Separate trailing button (its own glass circle) — the blue ✓ that
            // commits the inline edit. The spacer breaks iOS 26's shared-glass
            // grouping so the ✓ sits apart from the ⋯ pill, not inside it.
            if editingItemId != nil && !inSelectMode {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    inlineDoneTick
                }
            }
        }
        .sheet(item: $captureTarget) { target in
            QuickCaptureSheet(store: store, defaultListId: target.listId, defaultSection: target.section)
        }
        .fullScreenCover(item: $detailItem) { item in
            if item.type == .habit {
                HabitDetailView(item: item, store: store)
            } else {
                ItemDetailSheet(item: item, store: store)
            }
        }
        .sheet(isPresented: $showingEdit) {
            ListEditSheet(existing: list, store: store)
        }
        .sheet(isPresented: $showingNewSubList) {
            ListEditSheet(store: store, initialParentId: list.id)
        }
        .sheet(isPresented: $showingEditSections) {
            EditSectionsSheet(store: store, list: list)
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
            Text("\"\(list.name)\" and its items will move to Recently Deleted.")
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

    // MARK: - Toolbar menu

    /// The `•••` overflow menu — stays put while editing inline (just shifts
    /// left to make room for the ✓), so list options remain reachable.
    private var overflowMenu: some View {
        Menu {
            Menu {
                Button {
                    // Create the section with a placeholder name and drop
                    // straight into renaming its header inline — no alert.
                    Task {
                        if let section = try? await store.addSection(in: list.id, name: "New Section") {
                            editingSectionKey = section.id.uuidString
                        }
                    }
                } label: {
                    Label("New Section", systemImage: "plus")
                }
                .accessibilityIdentifier("list.menu.newSection")
                Button {
                    showingEditSections = true
                } label: {
                    Label("Edit Sections", systemImage: "pencil")
                }
                .disabled(list.sections.isEmpty)
                .accessibilityIdentifier("list.menu.editSections")
            } label: {
                Label("Manage Sections", systemImage: "list.bullet.below.rectangle")
            }
            sortMenuSection
            Button {
                showCompletedBinding.wrappedValue.toggle()
            } label: {
                Label(
                    showCompletedBinding.wrappedValue ? "Hide Completed Items" : "Show Completed Items",
                    systemImage: showCompletedBinding.wrappedValue ? "eye.slash" : "eye"
                )
            }
            .accessibilityIdentifier("list.menu.showCompleted")
            Button {
                showPastEventsBinding.wrappedValue.toggle()
            } label: {
                Label(
                    showPastEventsBinding.wrappedValue ? "Hide Past Events" : "Show Past Events",
                    systemImage: showPastEventsBinding.wrappedValue ? "calendar.badge.minus" : "calendar.badge.clock"
                )
            }
            .accessibilityIdentifier("list.menu.showPastEvents")
            Divider()
            Button {
                showingNewSubList = true
            } label: {
                Label("New Sublist", systemImage: "folder.badge.plus")
            }
            .accessibilityIdentifier("list.menu.newSublist")
            Button {
                inSelectMode = true
            } label: {
                Label("Select Reminders", systemImage: "checkmark.circle")
            }
            .accessibilityIdentifier("list.menu.selectMode")
            Button {
                showingEdit = true
            } label: {
                Label("Edit List", systemImage: "info.circle")
            }
            .accessibilityIdentifier("list.menu.edit")
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete List", systemImage: "trash")
            }
            .tint(.red)
            .accessibilityIdentifier("list.menu.delete")
        } label: {
            Image(systemName: "ellipsis")
                .accessibilityLabel("List Options")
                .accessibilityIdentifier("list.menu")
        }
    }

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

    @ViewBuilder
    private var sortMenuSection: some View {
        let currentMode = prefs.sort(for: list.id)
        Menu {
            Picker(selection: sortBinding) {
                ForEach(ListViewPreferences.SortMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            } label: { EmptyView() }
            .pickerStyle(.inline)

            if currentMode != .manual {
                Picker(selection: sortDirectionBinding) {
                    ForEach(ListViewPreferences.SortDirection.allCases, id: \.self) { dir in
                        Text(currentMode.directionLabel(dir)).tag(dir)
                    }
                } label: { EmptyView() }
                .pickerStyle(.inline)
            }
        } label: {
            Label {
                Text("Sort By")
                Text(currentMode.label)
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("list.menu.sort")
        }
    }

    private var sortBinding: Binding<ListViewPreferences.SortMode> {
        Binding(
            get: { prefs.sort(for: list.id) },
            set: { prefs.setSort($0, for: list.id) }
        )
    }

    private var sortDirectionBinding: Binding<ListViewPreferences.SortDirection> {
        Binding(
            get: { prefs.sortDirection(for: list.id) },
            set: { prefs.setSortDirection($0, for: list.id) }
        )
    }

    private var showCompletedBinding: Binding<Bool> {
        Binding(
            get: { prefs.showCompleted(for: list.id) },
            set: { prefs.setShowCompleted($0, for: list.id) }
        )
    }

    private var showPastEventsBinding: Binding<Bool> {
        Binding(
            get: { prefs.showPastEvents(for: list.id) },
            set: { prefs.setShowPastEvents($0, for: list.id) }
        )
    }

    // MARK: - Sub-Lists section (child lists shown above items)

    /// Direct child lists of the current list, non-deleted, sorted by
    /// position. Empty when this is a leaf list.
    private var childLists: [ItemList] {
        store.lists
            .filter { $0.parentId == list.id && $0.deletedAt == nil }
            .sorted { $0.position < $1.position }
    }

    // MARK: - Legacy SwiftUI rendering (removed)
    //
    // The full list body now lives in `ListDetailCollectionView` (UIKit).
    // The helpers below — `subListsSection`, `sectionView`, `sectionHeader`,
    // `previousMeta`, `flatten`, `childrenOf`, `handleMove`,
    // `regroupRespectingParents` — were the SwiftUI List–based renderer.
    // They've been deleted. The remaining file is the SwiftUI shell
    // (toolbar, sheets, alerts) that wraps the collection view.


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

    private func commitSectionRename(key: String) {
        let trimmed = renameBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            renamingSectionId = nil
            renameBuffer = ""
        }
        guard !trimmed.isEmpty else { return }
        let listId = list.id
        if key == Self.uncategorized {
            Task { try? await store.promoteOthersToSection(in: listId, name: trimmed) }
            return
        }
        guard let uuid = UUID(uuidString: key) else { return }
        Task {
            try? await store.renameSection(uuid, in: listId, to: trimmed)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            VStack(spacing: 10) {
                ListIconGlyph(
                    icon: list.icon,
                    size: 38,
                    weight: .regular,
                    color: ListsTokens.listColor(list.color)
                )
                Text("No items yet")
            }
        } description: {
            Text("Tap or drag the + button to add one.")
        }
    }

    // MARK: - Data

    private static let uncategorized = "__uncategorized__"

    /// Top-level items in this list — filtered by "show completed" and
    /// reordered by the active sort mode. Just-completed items in
    /// `lingeringIds` stay visible for the fade window.
    private var visibleItems: [Item] {
        let showCompleted = prefs.showCompleted(for: list.id)
        let showPastEvents = prefs.showPastEvents(for: list.id)
        let filtered = store.items.filter { item in
            item.listId == list.id
                && item.deletedAt == nil
                && item.parentId == nil
                && (showCompleted || !item.isComplete || lingeringIds.contains(item.id))
                && (showPastEvents || !item.isRolledOffPastEvent())
        }
        return applySort(filtered)
    }

    /// Section keys to render, in order. Each key is either a `ListSection.id`
    /// (UUID string) or the `uncategorized` sentinel. When the list has named
    /// sections, the sentinel sits at the BOTTOM and renders as "Others"; when
    /// the list has no named sections, the sentinel renders headerless as a
    /// single flat group.
    private var sections: [String] {
        let visible = visibleItems
        let hasUncategorized = visible.contains { $0.section == nil }
        let named = list.sections
            .sorted { $0.position < $1.position }
            .map { $0.id.uuidString }
        if named.isEmpty {
            return hasUncategorized ? [Self.uncategorized] : []
        }
        return named + (hasUncategorized ? [Self.uncategorized] : [])
    }

    private func items(in section: String) -> [Item] {
        if section == Self.uncategorized {
            return visibleItems.filter { $0.section == nil }
        }
        return visibleItems.filter { $0.section == section }
    }

    private func sectionName(for key: String) -> String? {
        if key == Self.uncategorized {
            return list.sections.isEmpty ? nil : "Others"
        }
        return list.sections.first { $0.id.uuidString == key }?.name
    }

    /// Tap-handler for the checkbox. Calls the store toggle, and — when
    /// "Show Completed" is off and the tap *completes* the item — keeps the
    /// row visible for 1.5s so it can fade out instead of vanishing.
    private func toggleAndLinger(_ item: Item) {
        let willComplete = !item.done
        Task { try? await store.toggleDone(item.id) }
        let showCompleted = prefs.showCompleted(for: list.id)
        guard willComplete, !showCompleted else {
            lingeringIds.remove(item.id)
            return
        }
        startLinger(for: item.id)
    }

    /// Tap-handler for a habit's ring. Increments the current cycle, and —
    /// when this +1 takes the count to the goal — keeps the row visible for
    /// the linger window so the ring → checkmark transition is visible
    /// before the row fades.
    private func incrementHabitAndLinger(_ item: Item) {
        let key = HabitCycle.key(for: (item.frequency ?? .daily).normalizedForHabit, on: .now)  // MODEL-HABIT-1
        let current = item.completionLog[key] ?? 0
        let willComplete = current + 1 >= item.goalPerCycle
        Task { try? await store.incrementHabit(item.id) }
        let showCompleted = prefs.showCompleted(for: list.id)
        guard willComplete, !showCompleted else { return }
        startLinger(for: item.id)
    }

    private func toggleSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
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

    private func isOverdue(_ item: Item) -> Bool {
        guard let due = item.due else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    private func parseSection(_ id: String) -> String? {
        guard id.hasPrefix(Self.sectionPrefix) else { return nil }
        let s = String(id.dropFirst(Self.sectionPrefix.count))
        return s == Self.uncategorized ? nil : s
    }
}
