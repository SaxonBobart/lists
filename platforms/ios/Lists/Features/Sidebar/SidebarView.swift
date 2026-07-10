import SwiftUI

private struct SearchSuggestionRow {
    let id: String
    let title: String
    let icon: String
    let query: String
}

private struct SidebarContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Sidebar / Home — the NavigationStack root.
///
/// Layout:
/// 1. **Auto-Lists** — full-width colored tiles: Today / Scheduled / Flagged /
///    Alarms / Completed / All. Colors match Apple Reminders.
/// 2. **My Lists** — user-created lists rendered as a collapsible tree with
///    circular icons (a `SidebarListsCollectionView`), then Recently Deleted
///    pinned at the bottom of the same card.
///
/// Sidebar gestures (always available — no edit mode):
/// - Tap row → navigate
/// - Long-press → drag to reorder / nest (drag right to indent, drop onto a
///   row to nest under it), or dwell for the context menu (New Sub-List Here /
///   Move to… / Edit / Delete) — the same long-press drag as items in a list.
/// - Swipe trailing → Delete + Edit
/// - Tap chevron → expand/collapse sub-list group
/// - Top ••• → Edit Pinned Lists / Settings.
///
/// Search is a permanent bottom Liquid Glass field, matching Apple Notes. The
/// separate trailing bottom button is + while browsing and an X while search
/// is active.
struct SidebarView: View {
    let store: ItemStore

    @State private var path = NavigationPath()
    @State private var showingNewList = false
    @State private var newSubListParent: ItemList?
    @State private var showingSettings = false
    @State private var editingList: ItemList?
    @State private var movingList: ItemList?
    @State private var captureTarget: CaptureTarget?
    @State private var detailItem: Item?
    @State private var searchText: String = ""
    @State private var isSearchActive = false
    @State private var listsBridge = SidebarListsBridge()
    @State private var sidebarListsHeight: CGFloat = 0
    @State private var sidebarContentHeight: CGFloat = 0
    @State private var sidebarViewportHeight: CGFloat = 0
    @State private var hoveredListId: String?
    @State private var fabIsInteracting = false
    @State private var autoListPrefs = AutoListPreferences()
    @State private var listViewPrefs = ListViewPreferences()
    @State private var showingEditLists = false
    @State private var moveSession = ItemMoveSession()
    @State private var documentLinkSession = DocumentLinkSession()
    @AppStorage(CorePluginPreferences.habitsEnabledKey) private var habitsPluginEnabled = true
    /// Ids of expandable lists whose children are currently *hidden*. Lists
    /// default to expanded; collapsed state persists across launches via
    /// UserDefaults.
    @State private var collapsed: Set<String> = Self.loadCollapsed()
    @FocusState private var searchFieldFocused: Bool

    private static let collapsedDefaultsKey = "sidebar.collapsed.v1"
    private static let bottomControlsScrollClearance: CGFloat = 32

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if isSearchActive {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        searchSuggestions
                            .padding(.bottom, Self.bottomControlsScrollClearance)
                    } else {
                        SearchResultsView(
                            store: store,
                            query: searchText,
                            moveSession: moveSession,
                            documentLinkSession: documentLinkSession,
                            habitsPluginEnabled: habitsPluginEnabled
                        ) {
                            isSearchActive = false
                            searchText = ""
                        }
                            .padding(.bottom, Self.bottomControlsScrollClearance)
                    }
                } else {
                    sidebarList
                }
                if !isDestinationModeActive {
                    bottomSearchControls
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .offset(y: geometry.safeAreaInsets.bottom)
                }
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
                if !isDestinationModeActive {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showingEditLists = true
                            } label: {
                                Label("Edit Pinned Lists", systemImage: "pin.fill")
                            }
                            .accessibilityIdentifier("sidebar.menu.editPinned")
                            Button {
                                showingSettings = true
                            } label: {
                                Label("Settings", systemImage: "gear")
                            }
                            .accessibilityIdentifier("sidebar.menu.settings")
                        } label: {
                            Image(systemName: "ellipsis")
                                .accessibilityLabel("More")
                        }
                        .accessibilityIdentifier("sidebar.menu")
                    }
                }
            }
            .navigationDestination(for: SmartList.self) { smartList in
                switch smartList {
                case .today:
                    TodayView(
                        store: store,
                        defaultNewItemType: effectiveDefaultNewItemType,
                        moveSession: moveSession,
                        documentLinkSession: documentLinkSession,
                        habitsPluginEnabled: habitsPluginEnabled
                    )
                case .tags:
                    TagsOverviewView(
                        store: store,
                        moveSession: moveSession,
                        documentLinkSession: documentLinkSession,
                        habitsPluginEnabled: habitsPluginEnabled
                    )
                default:
                    SmartListScreen(
                        store: store,
                        smartList: smartList,
                        defaultNewItemType: effectiveDefaultNewItemType,
                        moveSession: moveSession,
                        documentLinkSession: documentLinkSession,
                        habitsPluginEnabled: habitsPluginEnabled
                    )
                }
            }
            .navigationDestination(for: ItemList.self) { list in
                ListDetailView(
                    store: store,
                    list: list,
                    autoListPrefs: autoListPrefs,
                    moveSession: moveSession,
                    documentLinkSession: documentLinkSession,
                    habitsPluginEnabled: habitsPluginEnabled
                )
            }
            .navigationDestination(for: SystemDestination.self) { dest in
                switch dest {
                case .tags:
                    TagsOverviewView(
                        store: store,
                        moveSession: moveSession,
                        documentLinkSession: documentLinkSession,
                        habitsPluginEnabled: habitsPluginEnabled
                    )
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
            // Full-screen because moving a list can involve navigating the
            // nested list tree.
            .fullScreenCover(item: $movingList) { list in
                ParentPickerSheet(
                    store: store,
                    movingListId: list.id,
                    initialSelection: list.parentId
                ) { newParent in
                    Task { try? await store.moveList(list.id, toParent: newParent) }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(store: store, autoListPrefs: autoListPrefs)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showingEditLists) {
                EditListsSheet(store: store, autoListPrefs: autoListPrefs)
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
            .itemDetailCover(
                item: $detailItem,
                store: store,
                onBeginMove: beginMove,
                onBeginDocumentLink: beginDocumentLink
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if moveSession.isActive {
                MoveShelfView(session: moveSession, store: store)
            } else if documentLinkSession.isActive {
                DocumentLinkShelfView(session: documentLinkSession, store: store)
            }
        }
        .tint(.primary)
    }

    // MARK: - Bottom search controls

    private var bottomSearchControls: some View {
        HStack(spacing: 12) {
            bottomSearchBar
            bottomSearchAccessory
        }
    }

    private var bottomSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($searchFieldFocused)
                .onChange(of: searchFieldFocused) { _, focused in
                    if focused { isSearchActive = true }
                }
                .onChange(of: searchText) { _, newValue in
                    if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        isSearchActive = true
                    }
                }
                .accessibilityIdentifier("sidebar.search.field")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var bottomSearchAccessory: some View {
        if isSearchActive {
            Button("Close Search", systemImage: "xmark", action: cancelSearch)
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 48, height: 48)
                .glassEffect(.regular, in: Circle())
                .accessibilityIdentifier("sidebar.search.close")
        } else {
            FloatingAddButton(
                tint: hoveredListTint ?? defaultCaptureListColor,
                size: 48,
                action: startDefaultCapture,
                onDragChanged: { location in
                    let id = listsBridge.highlightListUnderFAB(globalPoint: location)
                    if hoveredListId != id { hoveredListId = id }
                },
                onDragEnded: { location in
                    if let listId = listsBridge.listIdUnderFAB(globalPoint: location) {
                        captureTarget = CaptureTarget(listId: listId, section: nil)
                    }
                    listsBridge.cancelFABDragCue()
                    hoveredListId = nil
                },
                isInteracting: $fabIsInteracting
            )
                .opacity(defaultCaptureList == nil ? 0.4 : 1)
                .allowsHitTesting(defaultCaptureList != nil)
        }
    }

    private var searchSuggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ListsSpacing.s3) {
                Text("Suggested")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ListsTokens.Foreground.primary)
                    .padding(.horizontal, ListsSpacing.s4)

                VStack(spacing: 0) {
                    ForEach(Array(searchSuggestionRows.enumerated()), id: \.element.title) { index, row in
                        Button {
                            searchText = row.query
                            searchFieldFocused = true
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: row.icon)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(ListsTokens.Foreground.secondary)
                                    .frame(width: 30)
                                Text(row.title)
                                    .font(ListsTypography.body)
                                    .foregroundStyle(ListsTokens.Foreground.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, ListsSpacing.s4)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("search.suggestion.\(row.id)")

                        if index < searchSuggestionRows.count - 1 {
                            Divider()
                                .background(ListsTokens.Separator.translucent)
                                .padding(.leading, 60)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
                        .fill(ListsTokens.Background.elevated)
                )
                .padding(.horizontal, ListsSpacing.s4)
            }
            .padding(.top, ListsSpacing.s6)
        }
        .background(ListsTokens.Background.grouped)
    }

    private var searchSuggestionRows: [SearchSuggestionRow] {
        var rows = [
            SearchSuggestionRow(id: "tasks", title: "Tasks", icon: "checkmark.circle", query: "task"),
            SearchSuggestionRow(id: "notes", title: "Notes", icon: "text.document", query: "note"),
            SearchSuggestionRow(id: "events", title: "Events", icon: "calendar", query: "event"),
            SearchSuggestionRow(id: "tags", title: "Items with Tags", icon: "number", query: "#"),
            SearchSuggestionRow(id: "flagged", title: "Flagged Items", icon: "flag", query: "!")
        ]
        if habitsPluginEnabled {
            rows.insert(
                SearchSuggestionRow(id: "habits", title: "Habits", icon: "repeat", query: "habit"),
                at: 1
            )
        }
        return rows
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

    private func startDefaultCapture() {
        if let id = defaultCaptureList?.id {
            captureTarget = CaptureTarget(listId: id, section: nil)
        }
    }

    private var isDestinationModeActive: Bool {
        moveSession.isActive || documentLinkSession.isActive
    }

    private func beginMove(_ item: Item) {
        documentLinkSession.cancel()
        moveSession.begin(item: item)
    }

    private func beginDocumentLink(_ source: DocumentLinkSource) {
        moveSession.cancel()
        cancelSearch()
        documentLinkSession.begin(source: source)
    }

    // MARK: - List body

    private var sidebarList: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    pinnedTilesStack
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                    myListsHeader
                        .padding(.horizontal, 32)
                        .padding(.bottom, 6)

                    SidebarListsCollectionView(
                        store: store,
                        lists: store.lists,
                        collapsed: collapsed,
                        deletedCount: deletedCount,
                        itemTypePolicy: itemTypePolicy,
                        isMoveMode: isDestinationModeActive,
                        bridge: listsBridge,
                        measuredHeight: $sidebarListsHeight,
                        onTapList: { path.append($0) },
                        onToggleCollapse: { toggleCollapsed($0) },
                        onTapRecentlyDeleted: { path.append(SystemDestination.recentlyDeleted) },
                        onNewSubList: { newSubListParent = $0 },
                        onMoveTo: { movingList = $0 },
                        onEditList: { editingList = $0 },
                        onDeleteList: { id in Task { try? await store.softDeleteList(id) } }
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                }
                .background {
                    GeometryReader { contentProxy in
                        Color.clear.preference(
                            key: SidebarContentHeightKey.self,
                            value: contentProxy.size.height
                        )
                    }
                }
                .padding(.bottom, sidebarBottomScrollPadding)
            }
            .onAppear { sidebarViewportHeight = proxy.size.height }
            .onChange(of: proxy.size.height) { _, newValue in
                sidebarViewportHeight = newValue
            }
            .onPreferenceChange(SidebarContentHeightKey.self) { height in
                sidebarContentHeight = height
            }
            .scrollDisabled(fabIsInteracting)
        }
    }

    private var sidebarBottomScrollPadding: CGFloat {
        if isDestinationModeActive { return 16 }
        return sidebarContentHeight > sidebarViewportHeight ? Self.bottomControlsScrollClearance : 0
    }

    /// "My Lists" section header — title + add button. The old pencil reorder
    /// toggle is gone: lists now reorder via long-press drag, like items, so
    /// there's no edit mode to enter.
    private var myListsHeader: some View {
        HStack(spacing: 12) {
            Text("My Lists")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if !isDestinationModeActive {
                Button { showingNewList = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color(.label), Color(.systemFill))
                        .accessibilityLabel("New List")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.list.new")
            }
        }
    }

    private func toggleCollapsed(_ id: String) {
        if collapsed.contains(id) {
            collapsed.remove(id)
        } else {
            collapsed.insert(id)
        }
        Self.saveCollapsed(collapsed)
    }

    /// Auto-list tiles + Tags pseudo-tile — rendered as a freestanding VStack
    /// of colored tiles, NOT wrapped in a List section. This avoids the
    /// insetGrouped section's corner mask creating "black cuts" at the
    /// top/bottom edges of the tile block.
    @ViewBuilder
    private var pinnedTilesStack: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(autoListPrefs.visible) { smartList in
                pinnedTileButton(smartList)
            }

        }
    }

    @ViewBuilder
    private func pinnedTileButton(_ smartList: SmartList) -> some View {
        let button = Button {
            path.append(smartList)
        } label: {
            SmartListTile(
                smartList: smartList,
                count: tileCount(for: smartList),
                hideCount: !autoListPrefs.showTileCounts
                    || smartList == .completed
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.smartlist.\(smartList.rawValue)")

        if isDestinationModeActive {
            button
        } else {
            button.contextMenu {
                Button {
                    autoListPrefs.setHidden(smartList, true)
                } label: {
                    Label("Hide", systemImage: "eye.slash")
                }
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

    /// Count shown on a pinned tile, following the same visibility preferences
    /// as the screen the tile opens.
    private func tileCount(for smartList: SmartList) -> Int {
        let prefsKey = "smart:\(smartList.rawValue)"
        return SmartListTileCount.count(
            for: smartList,
            lists: store.lists,
            items: store.items,
            itemTypePolicy: itemTypePolicy,
            showCompleted: listViewPrefs.showCompleted(for: prefsKey),
            showOverdue: listViewPrefs.showOverdue(for: prefsKey),
            showPastEvents: listViewPrefs.showPastEvents(for: prefsKey),
            sortMode: listViewPrefs.sort(for: prefsKey),
            sortDirection: listViewPrefs.sortDirection(for: prefsKey)
        )
    }

    private var deletedCount: Int {
        store.deletedItems.count + store.deletedLists.count
    }

    /// Tint passed to the FAB. `nil` = neutral Liquid Glass (default on
    /// the sidebar). When the user drags the FAB over a list row, the
    /// list's color is returned so the glass picks it up live.
    private var hoveredListTint: Color? {
        guard
            let listId = hoveredListId,
            let list = store.lists.first(where: { $0.id == listId })
        else { return nil }
        return ListsTokens.listColor(list.color)
    }

    private var defaultCaptureList: ItemList? {
        autoListPrefs.resolvedDefaultCaptureList(in: store.lists)
    }

    private var defaultCaptureListColor: Color? {
        defaultCaptureList.map { ListsTokens.listColor($0.color) }
    }

    private var effectiveDefaultNewItemType: Item.ItemType {
        itemTypePolicy.effectiveDefaultType(autoListPrefs.defaultNewItemType)
    }

    private var availableItems: [Item] {
        store.items.filter { $0.isAvailable(in: itemTypePolicy) }
    }

    private var itemTypePolicy: ItemTypePolicy {
        ItemTypePolicy(habitsEnabled: habitsPluginEnabled)
    }
}
