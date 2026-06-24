import SwiftUI

/// Sidebar / Home — the NavigationStack root.
///
/// Layout:
/// 1. **Auto-Lists** — full-width colored tiles: Today / Scheduled / Flagged /
///    Urgent / Completed / All. Colors match Apple Reminders.
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
/// - ••• → Edit Pinned Lists / Settings.
///
/// Search is a dedicated top-trailing button. When active, a custom Liquid
/// Glass search bar appears at the bottom — the trailing X button takes the
/// FAB's spot, and the FAB hides while searching.
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
    @State private var listsBridge = SidebarListsBridge()
    @State private var sidebarListsHeight: CGFloat = 0
    @State private var hoveredListId: String?
    @State private var fabIsInteracting = false
    @State private var autoListPrefs = AutoListPreferences()
    @State private var showingEditLists = false
    @State private var moveSession = ItemMoveSession()
    /// Ids of expandable lists whose children are currently *hidden*. Lists
    /// default to expanded; collapsed state persists across launches via
    /// UserDefaults.
    @State private var collapsed: Set<String> = Self.loadCollapsed()
    @FocusState private var searchFieldFocused: Bool

    private static let collapsedDefaultsKey = "sidebar.collapsed.v1"

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if isSearchActive && !searchText.isEmpty {
                    SearchResultsView(
                        store: store,
                        query: searchText,
                        moveSession: moveSession
                    ) {
                        isSearchActive = false
                        searchText = ""
                    }
                        .padding(.bottom, 80)
                } else {
                    sidebarList
                }

                if isSearchActive {
                    bottomSearchBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !moveSession.isActive {
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
                        .opacity(store.defaultCaptureListId == nil ? 0.4 : 1)
                        .allowsHitTesting(store.defaultCaptureListId != nil)
                    }
                    .padding(.trailing, 16)
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
                if !moveSession.isActive {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 0) {
                            Button("Search", systemImage: "magnifyingglass") {
                                activateSearch()
                            }
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .accessibilityIdentifier("sidebar.search.toggle")

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
                                Label("More", systemImage: "ellipsis")
                                    .labelStyle(.iconOnly)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("sidebar.menu")
                        }
                    }
                }
            }
            .navigationDestination(for: SmartList.self) { smartList in
                switch smartList {
                case .today:
                    TodayView(
                        store: store,
                        defaultNewItemType: autoListPrefs.defaultNewItemType,
                        moveSession: moveSession
                    )
                case .tags:
                    TagsOverviewView(store: store, moveSession: moveSession)
                default:
                    SmartListScreen(
                        store: store,
                        smartList: smartList,
                        defaultNewItemType: autoListPrefs.defaultNewItemType,
                        moveSession: moveSession
                    )
                }
            }
            .navigationDestination(for: ItemList.self) { list in
                ListDetailView(
                    store: store,
                    list: list,
                    autoListPrefs: autoListPrefs,
                    moveSession: moveSession
                )
            }
            .navigationDestination(for: SystemDestination.self) { dest in
                switch dest {
                case .tags:            TagsOverviewView(store: store, moveSession: moveSession)
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
            .fullScreenCover(isPresented: $showingSettings) { SettingsView(store: store, autoListPrefs: autoListPrefs) }
            .sheet(isPresented: $showingEditLists) {
                EditListsSheet(store: store, autoListPrefs: autoListPrefs)
            }
            .sheet(item: $captureTarget) { target in
                QuickCaptureSheet(
                    store: store,
                    defaultListId: target.listId,
                    defaultSection: target.section,
                    defaultNewItemType: autoListPrefs.defaultNewItemType
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MoveShelfView(session: moveSession, store: store)
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
                .accessibilityIdentifier("sidebar.search.field")
            Button {
                cancelSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Close Search")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sidebar.search.close")
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

                myListsHeader
                    .padding(.horizontal, 32)
                    .padding(.bottom, 6)

                SidebarListsCollectionView(
                    store: store,
                    lists: store.lists,
                    collapsed: collapsed,
                    deletedCount: deletedCount,
                    isMoveMode: moveSession.isActive,
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
        }
        .scrollDisabled(fabIsInteracting)
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
            if !moveSession.isActive {
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

        if moveSession.isActive {
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

    /// Count shown on a pinned tile. Most lists count their matching items;
    /// Tags counts unique tags.
    private func tileCount(for smartList: SmartList) -> Int {
        switch smartList {
        case .tags:     return tagsCount
        default:        return store.items(for: smartList).count
        }
    }

    private var tagsCount: Int {
        Tag.activeTagNames(in: store.items).count
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
}
