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
    let list: ItemList

    @State private var captureTarget: CaptureTarget?
    @State private var dropFrames: [DropTargetFrame] = []
    @State private var hoveredId: String?
    @State private var fabIsInteracting = false
    @State private var prefs = ListViewPreferences()
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
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

            if visibleItems.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(sections, id: \.self) { section in
                        sectionView(section)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(fabIsInteracting)
                .onPreferenceChange(DropTargetFrameKey.self) { dropFrames = $0 }
                .animation(.easeInOut(duration: 0.4), value: lingeringIds)
                .environment(\.editMode, .constant(inSelectMode ? .active : .inactive))
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
                        sortMenuSection
                        Toggle(isOn: showCompletedBinding) {
                            Label("Show Completed", systemImage: "checkmark.circle")
                        }
                        Divider()
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
        .sheet(isPresented: $showingEdit) {
            ListEditSheet(existing: list, store: store)
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
    }

    // MARK: - Toolbar menu

    @ViewBuilder
    private var sortMenuSection: some View {
        Picker(selection: sortBinding) {
            ForEach(ListViewPreferences.SortMode.allCases, id: \.self) { mode in
                Label(mode.label, systemImage: mode.systemImage).tag(mode)
            }
        } label: {
            Label("Sort By", systemImage: "arrow.up.arrow.down")
        }
        .pickerStyle(.menu)
    }

    private var sortBinding: Binding<ListViewPreferences.SortMode> {
        Binding(
            get: { prefs.sort(for: list.id) },
            set: { prefs.setSort($0, for: list.id) }
        )
    }

    private var showCompletedBinding: Binding<Bool> {
        Binding(
            get: { prefs.showCompleted(for: list.id) },
            set: { prefs.setShowCompleted($0, for: list.id) }
        )
    }

    // MARK: - Section view

    @ViewBuilder
    private func sectionView(_ name: String) -> some View {
        let entries = items(in: name)
        if !entries.isEmpty {
            let rows = flatten(entries)
            Section {
                ForEach(rows, id: \.item.id) { row in
                    let prev = previousMeta(for: row.item.id, in: rows)
                    ItemRow(
                        item: row.item,
                        isOverdue: isOverdue(row.item),
                        store: store,
                        onToggle: { toggleAndLinger(row.item) },
                        onIncrementHabit: { incrementHabitAndLinger(row.item) },
                        indent: row.indent,
                        previousSiblingId: prev?.id,
                        previousSiblingParentId: prev?.parentId,
                        showSubItemIndicator: false,
                        inSelectMode: inSelectMode,
                        isSelected: selection.contains(row.item.id),
                        onSelectToggle: { toggleSelection(row.item.id) }
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .transition(.opacity)
                }
                .onMove { source, destination in
                    handleMove(source: source, destination: destination, in: rows)
                }
            } header: {
                if name != Self.uncategorized {
                    HStack {
                        Text(name.uppercased())
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .background(
                        // Drop-target hit area covers the whole section header.
                        Color.clear
                            .overlay(
                                hoveredId == Self.sectionPrefix + name
                                ? Rectangle().fill(ListsTokens.listColor(list.color).opacity(0.18))
                                    .padding(-8)
                                : nil
                            )
                    )
                    .dropTarget(Self.sectionPrefix + name)
                }
            }
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

    private var sections: [String] {
        var seen: [String] = []
        var sawUncategorized = false
        for item in visibleItems {
            if let s = item.section {
                if !seen.contains(s) { seen.append(s) }
            } else {
                sawUncategorized = true
            }
        }
        return (sawUncategorized ? [Self.uncategorized] : []) + seen
    }

    private func items(in section: String) -> [Item] {
        if section == Self.uncategorized {
            return visibleItems.filter { $0.section == nil }
        }
        return visibleItems.filter { $0.section == section }
    }

    /// The previous row's id + parentId for a given row id within `rows`.
    /// Returns `nil` for the first row. Used to feed `ItemRow`'s indent
    /// gesture so a fresh row indents to the level of the row above it
    /// rather than diving one deeper when that row is itself a sub-item.
    private func previousMeta(for id: UUID, in rows: [(item: Item, indent: Int)]) -> (id: UUID, parentId: UUID?)? {
        guard let idx = rows.firstIndex(where: { $0.item.id == id }), idx > 0 else { return nil }
        let prev = rows[idx - 1].item
        return (prev.id, prev.parentId)
    }

    /// SwiftUI `.onMove` handler. Computes the post-drag flat order, snaps
    /// children back under their parents (so a sub-item can't escape its
    /// group via drag — that's what the indent/outdent swipe is for), then
    /// flips sort to `.manual` and writes the new sortIndex sequence.
    private func handleMove(source: IndexSet, destination: Int, in rows: [(item: Item, indent: Int)]) {
        var ids = rows.map(\.item.id)
        ids.move(fromOffsets: source, toOffset: destination)
        let regrouped = Self.regroupRespectingParents(ids, allItems: store.items)
        let listId = list.id
        Task { @MainActor in
            if prefs.sort(for: listId) != .manual {
                prefs.setSort(.manual, for: listId)
            }
            try? await store.reorderItems(in: listId, flatOrderedIds: regrouped)
        }
    }

    /// Re-emits ids so each parent is followed immediately by its children
    /// in the order those children appear in `newOrder`. Top-level items
    /// keep the new top-level order. Drag stays scoped to siblings; cross-
    /// parent drops snap the dragged item back into its original group at
    /// the new visual position.
    private static func regroupRespectingParents(_ newOrder: [UUID], allItems: [Item]) -> [UUID] {
        let byId = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        var topOrder: [UUID] = []
        var childrenOrder: [UUID: [UUID]] = [:]
        for id in newOrder {
            guard let it = byId[id] else { continue }
            if let pid = it.parentId {
                childrenOrder[pid, default: []].append(id)
            } else {
                topOrder.append(id)
            }
        }
        var out: [UUID] = []
        func emit(_ id: UUID) {
            out.append(id)
            for child in childrenOrder[id] ?? [] {
                emit(child)
            }
        }
        for top in topOrder { emit(top) }
        return out
    }

    private func flatten(_ parents: [Item]) -> [(item: Item, indent: Int)] {
        var out: [(Item, Int)] = []
        for parent in parents {
            out.append((parent, 0))
            for child in childrenOf(parent.id) {
                out.append((child, 1))
                for g in childrenOf(child.id) {
                    out.append((g, 2))
                }
            }
        }
        return out
    }

    private func childrenOf(_ id: UUID) -> [Item] {
        let showCompleted = prefs.showCompleted(for: list.id)
        let kids = store.items.filter { item in
            item.parentId == id
                && item.deletedAt == nil
                && (showCompleted || !item.isComplete || lingeringIds.contains(item.id))
        }
        return applySort(kids)
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
        items.sortedBy(prefs.sort(for: list.id))
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
