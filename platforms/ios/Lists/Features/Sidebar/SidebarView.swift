import SwiftUI

/// Sidebar / Home — the NavigationStack root.
///
/// Layout:
/// 1. **Auto-Lists** — full-width colored tiles: Today / Scheduled / Flagged /
///    Urgent / Completed / All. Colors match Apple Reminders.
/// 2. **My Lists** — Tags pinned at the top (toggleable in Edit Lists),
///    user-created lists rendered as a collapsible tree with circular icons,
///    then Recently Deleted pinned at the bottom of the same section.
///
/// Sidebar gestures (outside reorder mode):
/// - Tap row → navigate
/// - Long-press → context menu (New Sub-List Here / Move to… / Edit / Delete)
/// - Swipe trailing → Delete + Edit
/// - Tap chevron → expand/collapse sub-list group
///
/// Reorder mode (toggled by the pencil in the "My Lists" header):
/// - System drag handles appear (SwiftUI editMode).
/// - Drag between rows → reorder as sibling (parent-aware; rejects
///   cross-parent moves).
/// - Drag onto a row → nest under it (cycle guard in the store).
/// - Swipe + long-press disabled.
/// - Chevron expand/collapse still works.
///
/// Search (per Saxon's spec): invoked from the top-trailing overflow Menu.
/// When active, a custom Liquid Glass search bar appears at the bottom — the
/// trailing X button takes the FAB's spot, and the FAB hides while searching.
struct SidebarView: View {
    let store: ItemStore

    @State private var path = NavigationPath()
    @State private var showingNewList = false
    @State private var newSubListParent: ItemList?
    @State private var showingSettings = false
    @State private var editingList: ItemList?
    @State private var movingList: ItemList?
    @State private var captureTarget: CaptureTarget?
    @State private var searchText: String = ""
    @State private var isSearchActive = false
    @State private var dropFrames: [DropTargetFrame] = []
    @State private var hoveredId: String?
    @State private var fabIsInteracting = false
    @State private var autoListPrefs = AutoListPreferences()
    @State private var showingEditLists = false
    /// Reorder mode — when true, SwiftUI editMode is active, drag handles
    /// appear on rows, swipe/contextMenu are disabled. Toggled via the
    /// pencil button in the "My Lists" section header.
    @State private var inReorderMode = false
    /// Ids of expandable lists whose children are currently *hidden*. Lists
    /// default to expanded; collapsed state persists across launches via
    /// UserDefaults.
    @State private var collapsed: Set<String> = Self.loadCollapsed()
    @FocusState private var searchFieldFocused: Bool

    private static let smartIdPrefix = "smart:"
    private static let listIdPrefix = "list:"
    private static let tagsId = "tags"
    private static let collapsedDefaultsKey = "sidebar.collapsed.v1"

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if isSearchActive && !searchText.isEmpty {
                    SearchResultsView(store: store, query: searchText)
                        .padding(.bottom, 80)
                } else {
                    sidebarList
                }

                if isSearchActive {
                    bottomSearchBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    HStack {
                        Spacer()
                        FloatingAddButton(
                            tint: hoveredListTint,
                            action: {
                                if let id = store.defaultCaptureListId {
                                    captureTarget = CaptureTarget(listId: id, section: nil)
                                }
                            },
                            onDragChanged: { location in
                                let hit = dropFrames.first { $0.rect.contains(location) }
                                if hoveredId != hit?.id { hoveredId = hit?.id }
                            },
                            onDragEnded: { location in
                                if let hit = dropFrames.first(where: { $0.rect.contains(location) }),
                                   let listId = parseList(hit.id) {
                                    captureTarget = CaptureTarget(listId: listId, section: nil)
                                }
                                hoveredId = nil
                            },
                            isInteracting: $fabIsInteracting
                        )
                        .opacity(store.defaultCaptureListId == nil ? 0.4 : 1)
                        .allowsHitTesting(store.defaultCaptureListId != nil)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 0)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isSearchActive)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Lists")
                        .font(.title2.bold())
                        .fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activateSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .accessibilityLabel("Search")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingEditLists = true
                        } label: {
                            Label("Edit Pinned Lists", systemImage: "pin.fill")
                        }
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .accessibilityLabel("More")
                    }
                }
            }
            .navigationDestination(for: SmartList.self) { smartList in
                if smartList == .today {
                    TodayView(store: store)
                } else {
                    SmartListScreen(store: store, smartList: smartList)
                }
            }
            .navigationDestination(for: ItemList.self) { list in
                ListDetailView(store: store, list: list)
            }
            .navigationDestination(for: SystemDestination.self) { dest in
                switch dest {
                case .tags:            TagsOverviewView(store: store)
                case .recentlyDeleted: RecentlyDeletedView(store: store)
                }
            }
            .sheet(isPresented: $showingNewList) { ListEditSheet(store: store) }
            .sheet(item: $editingList) { list in
                ListEditSheet(existing: list, store: store)
            }
            .sheet(item: $newSubListParent) { parent in
                ListEditSheet(store: store, initialParentId: parent.id)
            }
            .sheet(item: $movingList) { list in
                ParentPickerSheet(
                    store: store,
                    movingListId: list.id,
                    initialSelection: list.parentId
                ) { newParent in
                    Task { try? await store.moveList(list.id, toParent: newParent) }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView(store: store) }
            .sheet(isPresented: $showingEditLists) {
                EditListsSheet(store: store, autoListPrefs: autoListPrefs)
            }
            .sheet(item: $captureTarget) { target in
                QuickCaptureSheet(store: store, defaultListId: target.listId, defaultSection: target.section)
            }
        }
        .tint(.primary)
    }

    // MARK: - Bottom search bar (Liquid Glass capsule, X covers FAB slot)

    private var bottomSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search items", text: $searchText)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($searchFieldFocused)
            Button {
                cancelSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Close Search")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: .infinity)
    }

    private func activateSearch() {
        isSearchActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            searchFieldFocused = true
        }
    }

    private func cancelSearch() {
        searchFieldFocused = false
        searchText = ""
        isSearchActive = false
    }

    // MARK: - List body

    private var sidebarList: some View {
        ScrollView {
            VStack(spacing: 0) {
                pinnedTilesStack
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                List {
                    myListsSection
                }
                .listStyle(.insetGrouped)
                .listSectionMargins(.horizontal, 8)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(minHeight: 600)
                .environment(\.editMode, .constant(inReorderMode ? .active : .inactive))
            }
        }
        .scrollDisabled(fabIsInteracting)
        .onPreferenceChange(DropTargetFrameKey.self) { dropFrames = $0 }
    }

    /// Auto-list tiles + Tags pseudo-tile — rendered as a freestanding VStack
    /// of colored tiles, NOT wrapped in a List section. This avoids the
    /// insetGrouped section's corner mask creating "black cuts" at the
    /// top/bottom edges of the tile block.
    @ViewBuilder
    private var pinnedTilesStack: some View {
        VStack(spacing: 8) {
            ForEach(autoListPrefs.visible) { smartList in
                Button {
                    path.append(smartList)
                } label: {
                    SmartListTile(
                        smartList: smartList,
                        count: store.items(for: smartList).count,
                        hideCount: smartList == .completed
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        autoListPrefs.setHidden(smartList, true)
                    } label: {
                        Label("Hide", systemImage: "eye.slash")
                    }
                }
            }

        }
    }

    private var myListsSection: some View {
        Section {
            myListsContent
        } header: {
            HStack(spacing: 12) {
                Text("My Lists")
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        inReorderMode.toggle()
                    }
                } label: {
                    Image(systemName: inReorderMode ? "checkmark.circle.fill" : "pencil.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color(.label), Color(.systemFill))
                        .accessibilityLabel(inReorderMode ? "Done Reordering" : "Reorder Lists")
                }
                .buttonStyle(.plain)
                Button { showingNewList = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color(.label), Color(.systemFill))
                        .accessibilityLabel("New List")
                }
                .buttonStyle(.plain)
                .disabled(inReorderMode)
                .opacity(inReorderMode ? 0.4 : 1)
            }
        }
    }

    @ViewBuilder
    private var myListsContent: some View {
        if !autoListPrefs.tagsHidden {
            Button {
                path.append(SystemDestination.tags)
            } label: {
                HStack(spacing: 0) {
                    SidebarRow(
                        icon: "number",
                        hue: ListsTokens.tagAccent,
                        label: "Tags",
                        count: tagsCount > 0 ? tagsCount : nil,
                        iconShape: .roundedSquare
                    )
                    leafTrailingChevron
                }
            }
            .buttonStyle(.plain)
        }
        if myLists.isEmpty {
            Text("Tap + to create a list.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        } else {
            ForEach(flatTreeRows) { row in
                treeRowEntry(row)
                    .dropTarget(Self.listIdPrefix + row.list.id)
                    .dropDestination(for: String.self) { droppedIds, _ in
                        guard inReorderMode,
                              let droppedId = droppedIds.first,
                              droppedId != row.list.id
                        else { return false }
                        Task { try? await store.moveList(droppedId, toParent: row.list.id) }
                        return true
                    }
                    .draggable(inReorderMode ? row.list.id : "")
                    .listRowBackground(
                        hoveredId == Self.listIdPrefix + row.list.id
                            ? ListsTokens.listColor(row.list.color).opacity(0.30)
                            : nil
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !inReorderMode {
                            Button(role: .destructive) {
                                Task { try? await store.softDeleteList(row.list.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                            Button {
                                editingList = row.list
                            } label: {
                                Label("Edit List", systemImage: "info.circle")
                            }
                            .tint(.gray)
                        }
                    }
                    .contextMenu {
                        if !inReorderMode {
                            listContextMenu(for: row.list)
                        }
                    }
            }
            .onMove { source, destination in
                handleSiblingReorder(source: source, destination: destination)
            }
        }
        Button {
            path.append(SystemDestination.recentlyDeleted)
        } label: {
            HStack(spacing: 0) {
                SidebarRow(
                    icon: "trash.fill",
                    hue: Color(.systemGray4),
                    label: "Recently Deleted",
                    count: deletedCount > 0 ? deletedCount : nil,
                    iconShape: .roundedSquare,
                    iconGlyphColor: Color(.secondaryLabel)
                )
                leafTrailingChevron
            }
        }
        .buttonStyle(.plain)
    }

    /// Shared context menu for any user list — sub-list creation,
    /// reparenting, edit, and a destructive Delete.
    @ViewBuilder
    private func listContextMenu(for list: ItemList) -> some View {
        Button {
            newSubListParent = list
        } label: {
            Label("New Sub-List Here", systemImage: "folder.badge.plus")
        }
        Button {
            movingList = list
        } label: {
            Label("Move to…", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
        }
        Button { editingList = list } label: {
            Label("Edit List", systemImage: "info.circle")
        }
        Button(role: .destructive) {
            Task { try? await store.softDeleteList(list.id) }
        } label: {
            Label("Delete List", systemImage: "trash")
        }
        .tint(.red)
    }

    // MARK: - Tree rendering

    /// One row in the rendered sidebar tree. Carries enough info to draw the
    /// row in a single pass without re-querying the store.
    private struct TreeRow: Identifiable {
        let list: ItemList
        let depth: Int
        let hasChildren: Bool
        var id: String { list.id }
    }

    /// Root user lists (parent_id == nil), non-deleted, sorted by position.
    private var rootLists: [ItemList] {
        store.lists
            .filter { $0.deletedAt == nil && $0.parentId == nil }
            .sorted { $0.position < $1.position }
    }

    private func childLists(of parentId: String) -> [ItemList] {
        store.lists
            .filter { $0.deletedAt == nil && $0.parentId == parentId }
            .sorted { $0.position < $1.position }
    }

    /// Tree → depth-tagged flat list, respecting per-list collapse state.
    /// Recomputed on every body re-evaluation; fine for the sidebar's scale.
    private var flatTreeRows: [TreeRow] {
        var out: [TreeRow] = []
        func emit(_ list: ItemList, depth: Int) {
            let kids = childLists(of: list.id)
            out.append(TreeRow(list: list, depth: depth, hasChildren: !kids.isEmpty))
            guard !kids.isEmpty, !collapsed.contains(list.id) else { return }
            for kid in kids { emit(kid, depth: depth + 1) }
        }
        for root in rootLists { emit(root, depth: 0) }
        return out
    }

    /// Tree row: a tap-to-act button (whole-row hit target) plus a
    /// trailing chevron column. Collapsible rows (those with children) get
    /// a blue chevron that toggles expand/collapse on tap. Leaf rows show a
    /// standard gray nav chevron (decorative — the row itself navigates).
    ///
    /// Tap behavior depends on reorder mode:
    /// - Idle mode → row body navigates into the list.
    /// - Reorder mode → row body opens the "Move to…" picker so the user
    ///   can nest under another list or pick "None" to un-nest to root.
    ///   System drag handles still appear on the right for sibling reorder.
    @ViewBuilder
    private func treeRowEntry(_ row: TreeRow) -> some View {
        HStack(spacing: 0) {
            Button {
                if inReorderMode {
                    movingList = row.list
                } else {
                    path.append(row.list)
                }
            } label: {
                SidebarRow(
                    icon: row.list.icon,
                    hue: ListsTokens.listColor(row.list.color),
                    label: row.list.name,
                    count: openItemCount(for: row.list),
                    indent: row.depth,
                    iconShape: .circle
                )
            }
            .buttonStyle(.plain)

            trailingChevron(for: row)
        }
    }

    @ViewBuilder
    private func trailingChevron(for row: TreeRow) -> some View {
        if row.hasChildren {
            let isCollapsed = collapsed.contains(row.list.id)
            Button {
                if isCollapsed {
                    collapsed.remove(row.list.id)
                } else {
                    collapsed.insert(row.list.id)
                }
                Self.saveCollapsed(collapsed)
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        } else {
            leafTrailingChevron
        }
    }

    /// Decorative right-side chevron used on leaf rows in `My Lists` —
    /// Tags, Recently Deleted, and any list without children. Matches the
    /// 30pt-wide column the collapsible chevron occupies on rows with
    /// children so the chevron edge lines up across the whole section.
    private var leafTrailingChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 30, height: 30)
    }

    // MARK: - Reorder

    /// Apply a SwiftUI `.onMove` over the flat tree rows. Only sibling moves
    /// within the same parent are accepted; cross-parent moves are rejected
    /// (use Move to… or drag-onto-row for those).
    private func handleSiblingReorder(source: IndexSet, destination: Int) {
        let rows = flatTreeRows
        guard let firstSource = source.first, firstSource < rows.count else { return }
        let movedParentId = rows[firstSource].list.parentId
        // Source and destination must share the same parent scope.
        for idx in source where idx < rows.count {
            if rows[idx].list.parentId != movedParentId { return }
        }
        // Find the sibling group's index range in `rows`.
        let siblingsInRows = rows.enumerated().filter { $0.element.list.parentId == movedParentId }
        guard let firstSiblingIdx = siblingsInRows.first?.offset,
              let lastSiblingIdx = siblingsInRows.last?.offset
        else { return }
        // Reject moves whose destination would leave the sibling group.
        // SwiftUI passes destination as the insertion index in the full ForEach;
        // map it back to the sibling group.
        guard destination >= firstSiblingIdx && destination <= lastSiblingIdx + 1 else { return }

        var siblings = childLists(of: movedParentId ?? "")
        if movedParentId == nil {
            siblings = rootLists
        }
        // Re-derive sibling ids from rows (more robust than re-querying since
        // we already validated the ForEach indices).
        var siblingIds = siblingsInRows.map { $0.element.list.id }
        let sourceOffsets = IndexSet(source.compactMap { idx -> Int? in
            guard let pos = siblingsInRows.firstIndex(where: { $0.offset == idx }) else { return nil }
            return pos
        })
        let destOffset = max(0, min(destination - firstSiblingIdx, siblingIds.count))
        siblingIds.move(fromOffsets: sourceOffsets, toOffset: destOffset)

        // Renumber sibling positions to the new order and persist.
        Task {
            for (newPos, id) in siblingIds.enumerated() {
                guard var list = siblings.first(where: { $0.id == id }) else { continue }
                let desired = Double(newPos + 1)
                if list.position == desired { continue }
                list.position = desired
                try? await store.updateList(list)
            }
        }
    }

    // MARK: - Collapse persistence

    private static func loadCollapsed() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: collapsedDefaultsKey) ?? [])
    }

    private static func saveCollapsed(_ value: Set<String>) {
        UserDefaults.standard.set(Array(value).sorted(), forKey: collapsedDefaultsKey)
    }

    // MARK: - Helpers

    /// All non-deleted user lists, ordered — rendered in "My Lists".
    private var myLists: [ItemList] {
        store.lists.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }

    private func openItemCount(for list: ItemList) -> Int {
        store.items.filter { $0.listId == list.id && !$0.done && $0.deletedAt == nil }.count
    }

    private var tagsCount: Int {
        Set(store.items.filter { $0.deletedAt == nil }.flatMap { $0.tags }).count
    }

    private var deletedCount: Int {
        store.deletedItems.count + store.deletedLists.count
    }

    private func parseList(_ id: String) -> String? {
        if id.hasPrefix(Self.listIdPrefix) {
            return String(id.dropFirst(Self.listIdPrefix.count))
        }
        return nil
    }

    /// Tint passed to the FAB. `nil` = neutral Liquid Glass (default on
    /// the sidebar). When the user drags the FAB over a list row, the
    /// list's color is returned so the glass picks it up live.
    private var hoveredListTint: Color? {
        guard
            let id = hoveredId,
            let listId = parseList(id),
            let list = store.lists.first(where: { $0.id == listId })
        else { return nil }
        return ListsTokens.listColor(list.color)
    }
}

/// Hashable handle used for sheet(item:) presentation when the FAB drops on
/// a list / section.
struct CaptureTarget: Identifiable, Hashable {
    var id: String { "\(listId)#\(section ?? "")" }
    let listId: String
    let section: String?
}
