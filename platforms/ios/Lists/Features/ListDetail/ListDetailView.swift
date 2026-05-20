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

    init(store: ItemStore, list: ItemList) {
        self.store = store
        self.initialList = list
    }

    /// Always read the freshest value out of the store. This keeps section
    /// renames, reorders, additions, and other mutations reflecting in
    /// real time — without this, the view would snapshot at navigation
    /// time and edits would only appear after leaving + re-entering.
    private var list: ItemList {
        store.lists.first(where: { $0.id == initialList.id }) ?? initialList
    }

    @State private var captureTarget: CaptureTarget?
    @State private var dropFrames: [DropTargetFrame] = []
    @State private var hoveredId: String?
    @State private var fabIsInteracting = false
    @State private var prefs = ListViewPreferences()
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var showingNewSubList = false
    @State private var showingNewSectionAlert = false
    @State private var newSectionName: String = ""
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

            if visibleItems.isEmpty && childLists.isEmpty {
                emptyState
            } else {
                ListDetailCollectionView(
                    store: store,
                    listId: list.id,
                    prefs: prefs,
                    listColor: ListsTokens.listColor(list.color),
                    inSelectMode: $inSelectMode,
                    selection: $selection,
                    lingeringIds: lingeringIds,
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
                    onShowItemDetail: { detailItem = $0 }
                )
                .ignoresSafeArea(edges: .bottom)
            }

            FloatingAddButton(
                tint: ListsTokens.listColor(list.color),
                action: {
                    captureTarget = CaptureTarget(listId: list.id, section: nil)
                },
                onDragChanged: { location in
                    let hit = dropFrames.first { $0.rect.contains(location) }
                    if hoveredId != hit?.id {
                        hoveredId = hit?.id
                    }
                },
                onDragEnded: { location in
                    if let hit = dropFrames.first(where: { $0.rect.contains(location) }),
                       let section = parseSection(hit.id) {
                        captureTarget = CaptureTarget(listId: list.id, section: section)
                    } else {
                        captureTarget = CaptureTarget(listId: list.id, section: nil)
                    }
                    hoveredId = nil
                },
                isInteracting: $fabIsInteracting
            )
            .padding(.trailing, 16)
            .padding(.bottom, 0)
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarTitleColor(ListsTokens.listColor(list.color))
        .tint(ListsTokens.listColor(list.color))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if inSelectMode {
                    Button("Done") {
                        inSelectMode = false
                        selection.removeAll()
                    }
                } else {
                    Menu {
                        Menu {
                            Button {
                                newSectionName = ""
                                showingNewSectionAlert = true
                            } label: {
                                Label("New Section", systemImage: "plus")
                            }
                            Button {
                                showingEditSections = true
                            } label: {
                                Label("Edit Sections", systemImage: "pencil")
                            }
                            .disabled(list.sections.isEmpty)
                        } label: {
                            Label("Manage Sections", systemImage: "list.bullet.below.rectangle")
                        }
                        sortMenuSection
                        Toggle(isOn: showCompletedBinding) {
                            Label("Show Completed", systemImage: "checkmark.circle")
                        }
                        Divider()
                        Button {
                            showingNewSubList = true
                        } label: {
                            Label("New Sub-List", systemImage: "folder.badge.plus")
                        }
                        Button {
                            inSelectMode = true
                        } label: {
                            Label("Select Reminders", systemImage: "checkmark.circle")
                        }
                        Button {
                            showingEdit = true
                        } label: {
                            Label("Edit List", systemImage: "info.circle")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete List", systemImage: "trash")
                        }
                        .tint(.red)
                    } label: {
                        Image(systemName: "ellipsis")
                            .accessibilityLabel("List Options")
                    }
                }
            }
        }
        .sheet(item: $captureTarget) { target in
            QuickCaptureSheet(store: store, defaultListId: target.listId, defaultSection: target.section)
        }
        .sheet(item: $detailItem) { item in
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
        .alert("New Section", isPresented: $showingNewSectionAlert) {
            TextField("Name", text: $newSectionName)
            Button("Add") {
                let name = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task { _ = try? await store.addSection(in: list.id, name: name) }
            }
            Button("Cancel", role: .cancel) {}
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
        let filtered = store.items.filter { item in
            item.listId == list.id
                && item.deletedAt == nil
                && item.parentId == nil
                && (showCompleted || !item.isComplete || lingeringIds.contains(item.id))
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
        let key = HabitCycle.key(for: item.frequency ?? .daily, on: .now)
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
