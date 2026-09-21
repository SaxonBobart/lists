import SwiftUI
import EventKit

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
/// Search opens a top Liquid Glass field over the current home screen. The
/// separate trailing button is + while browsing and an X while search
/// is active.
struct SidebarView: View {
    let store: ItemStore
    let calendarPreferences: CalendarPreferences

    @State private var path = NavigationPath()
    @State private var showingNewList = false
    @State private var newSubListParent: ItemList?
    @State private var showingSettings = false
    @State private var editingList: ItemList?
    @State private var movingList: ItemList?
    @State private var captureTarget: CaptureTarget?
    @State private var detailItem: Item?
    @State private var searchText: String = ""
    @State private var searchScope: ItemSearch.Scope?
    @State private var showingCalendarConnections = false
    @State private var moveShelfHeight: CGFloat = 0
    @State private var searchWidth: CGFloat = 393
    @State private var isSearchActive = false
    @State private var dictation = SearchDictation()
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
    @State private var returnedLinkDocument: DocumentLinkSession.ReturnRequest?
    private let habitsPluginEnabled = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Ids of expandable lists whose children are currently *hidden*. Lists
    /// default to expanded; collapsed state persists across launches via
    /// UserDefaults.
    @State private var collapsed: Set<String> = Self.loadCollapsed()
    @FocusState private var searchFieldFocused: Bool

    private static let collapsedDefaultsKey = "sidebar.collapsed.v1"
    private static let bottomControlsScrollClearance: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        Color(.systemGroupedBackground).ignoresSafeArea()

                        sidebarList
                            .allowsHitTesting(!isSearchActive)
                            .accessibilityHidden(isSearchActive)

                        if isSearchActive && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                SearchResultsView(
                                    store: store,
                                    query: searchText,
                                    scope: searchScope,
                                    calendarPreferences: calendarPreferences,
                                    moveSession: moveSession,
                                    documentLinkSession: documentLinkSession,
                                    habitsPluginEnabled: habitsPluginEnabled,
                                    onMoveStarted: {
                                        cancelSearch()
                                    },
                                    onDocumentLinkStarted: {
                                        cancelSearch()
                                    },
                                    onOpenItem: { dictation.stop() }
                                )
                                    .background(Color(.systemBackground))
                        }
                    }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { searchWidth = $0 }
            .sheet(isPresented: $showingCalendarConnections) { CalendarConnectionSheet(store: store) }
            .task { await CalendarConnections.shared.refresh(store: store) }
            .task {
                for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                    try? await Task.sleep(for: .seconds(1))
                    await CalendarConnections.shared.refresh(store: store)
                }
            }
            .onDisappear { dictation.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { dictation.stop() }
                if phase == .active { Task { await CalendarConnections.shared.refresh(store: store) } }
            }
            .alert("Voice Search", isPresented: Binding(get: { dictation.error != nil }, set: { if !$0 { dictation.error = nil } })) {
                Button("OK", role: .cancel) { dictation.error = nil }
            } message: { Text(dictation.error ?? "") }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isDestinationModeActive && !isSearchActive {
                    BottomControlRow(aboveKeyboard: searchFieldFocused) { bottomSearchControls }
                }
            }
            .navigationTitle(!isSearchActive && dynamicTypeSize.isAccessibilitySize ? "Lists" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isSearchActive {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 10) { bottomSearchBar; bottomSearchAccessory }
                            .frame(width: max(100, searchWidth - 32))
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                if !isSearchActive && !dynamicTypeSize.isAccessibilitySize {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("Lists")
                            .font(.title2.bold())
                            .fixedSize()
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                if !isSearchActive && !documentLinkSession.isActive {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Connect Calendar", systemImage: "calendar.badge.plus") { showingCalendarConnections = true }
                                .disabled(moveSession.isActive)
                                .accessibilityIdentifier("sidebar.calendarconnection")
                            ClipboardUndoButton()
                            Button {
                                showingEditLists = true
                            } label: {
                                Label("Edit Pinned Lists", systemImage: "pin.fill")
                            }
                            .accessibilityIdentifier("sidebar.menu.editPinned")
                            .disabled(moveSession.isActive)
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
                        calendarPreferences: calendarPreferences,
                        moveSession: moveSession,
                        documentLinkSession: documentLinkSession,
                        habitsPluginEnabled: habitsPluginEnabled
                    )
                case .tags:
                    TagsOverviewView(
                        store: store,
                        calendarPreferences: calendarPreferences,
                        moveSession: moveSession,
                        documentLinkSession: documentLinkSession,
                        habitsPluginEnabled: habitsPluginEnabled
                    )
                default:
                    SmartListScreen(
                        store: store,
                        smartList: smartList,
                        defaultNewItemType: effectiveDefaultNewItemType,
                        calendarPreferences: calendarPreferences,
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
                    calendarPreferences: calendarPreferences,
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
                        calendarPreferences: calendarPreferences,
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
                SettingsView(
                    store: store,
                    autoListPrefs: autoListPrefs,
                    listViewPrefs: listViewPrefs,
                    calendarPreferences: calendarPreferences
                )
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
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { moveShelfHeight = $0 }
            } else if documentLinkSession.isActive {
                DocumentLinkShelfView(session: documentLinkSession, store: store)
            }
        }
        .onChange(of: documentLinkSession.returnRequest) { _, request in
            guard request != nil, let request = documentLinkSession.consumeReturnRequest(),
                  let item = store.item(request.itemId), item.deletedAt == nil else { return }
            returnedLinkDocument = request
        }
        .fullScreenCover(item: $returnedLinkDocument) { request in
            if let item = store.item(request.itemId) {
                ItemDetailSheet(item: item, store: store, initialEditorFocus: request.focus,
                                onBeginMove: { item in
                                    returnedLinkDocument = nil
                                    beginMove(item)
                                }, onBeginDocumentLink: { source in
                                    returnedLinkDocument = nil
                                    beginDocumentLink(source)
                                })
            }
        }
        .environment(\.moveShelfHeight, moveSession.isActive ? moveShelfHeight : 0)
        .tint(.primary)
    }

    // MARK: - Bottom search controls

    private var bottomSearchControls: some View {
        HStack(spacing: 12) {
            if isSearchActive {
                bottomSearchBar
            } else {
                Button("Search", systemImage: "magnifyingglass", action: activateSearch)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .frame(width: 64, height: 64)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityIdentifier("sidebar.search.open")
                Spacer(minLength: 0)
            }
            bottomSearchAccessory
        }
    }

    private var bottomSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.primary)
            TextField("Search", text: searchTextBinding)
                .textFieldStyle(.plain)
                .font(.body)
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
            if !searchText.isEmpty && !dictation.isListening {
                Button {
                    searchText = ""
                    searchScope = nil
                    searchFieldFocused = true
                } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 17)) }
                .accessibilityLabel("Clear Search")
                .accessibilityIdentifier("sidebar.search.clear")
            } else {
                Button {
                    if dictation.isListening { dictation.stop() }
                    else {
                        searchFieldFocused = true
                        Task { await dictation.start { searchText = $0; searchScope = nil } }
                    }
                } label: {
                    Image(systemName: dictation.isListening ? "stop.circle.fill" : "mic")
                        .font(.system(size: 20, weight: .regular))
                }
                .accessibilityLabel(dictation.isListening ? "Stop Voice Search" : "Voice Search")
                .accessibilityIdentifier("sidebar.search.microphone")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var bottomSearchAccessory: some View {
        if isSearchActive {
            Button(action: cancelSearch) {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .regular))
            }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Search")
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: Circle())
                .accessibilityIdentifier("sidebar.search.close")
        } else {
            FloatingAddButton(
                tint: hoveredListTint ?? defaultCaptureListColor,
                size: 64,
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
                onDragCancelled: {
                    listsBridge.cancelFABDragCue()
                    hoveredListId = nil
                },
                isInteracting: $fabIsInteracting
            )
                .opacity(defaultCaptureList == nil ? 0.4 : 1)
                .allowsHitTesting(defaultCaptureList != nil)
        }
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { searchText },
            set: { newValue in
                searchText = newValue
                searchScope = nil
            }
        )
    }

    private func activateSearch() {
        isSearchActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            searchFieldFocused = true
        }
    }

    private func cancelSearch() {
        dictation.stop()
        searchFieldFocused = false
        searchText = ""
        searchScope = nil
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
            columns: pinnedTileColumns,
            spacing: 8
        ) {
            ForEach(autoListPrefs.visible) { smartList in
                pinnedTileButton(smartList)
            }

        }
    }

    private var pinnedTileColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible())]
        } else {
            [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ]
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
            showHabits: smartList == .scheduled && calendarPreferences.showHabits,
            sortMode: listViewPrefs.sort(for: prefsKey),
            sortDirection: listViewPrefs.sortDirection(for: prefsKey)
        )
    }

    private var deletedCount: Int {
        store.recentlyDeletedItemRoots.count + store.recentlyDeletedListRoots.count
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
