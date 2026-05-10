import SwiftUI

/// Sidebar / Home — the NavigationStack root.
///
/// Layout (per Saxon's restructure):
/// 1. **Auto-Lists** — full-width colored tiles: Today / Scheduled / Flagged /
///    Urgent / Completed / All. Colors match Apple Reminders.
/// 2. **My Lists** — Tags pinned at the top (toggleable in Edit Lists), then
///    user-created lists with circular icons (Apple Reminders style), then
///    Recently Deleted pinned at the bottom of the same section.
///
/// Auto-list tiles use Button + NavigationPath to avoid the auto-disclosure
/// chevron that NavigationLink in a List always adds. My Lists rows keep the
/// chevron because they're standard iOS-style nav rows.
///
/// Search (per Saxon's spec): invoked from the top-trailing overflow Menu.
/// When active, a custom Liquid Glass search bar appears at the bottom — the
/// trailing X button takes the FAB's spot, and the FAB hides while searching.
struct SidebarView: View {
    let store: ItemStore

    @State private var path = NavigationPath()
    @State private var showingNewList = false
    @State private var showingSettings = false
    @State private var editingList: ItemList?
    @State private var captureTarget: CaptureTarget?
    @State private var searchText: String = ""
    @State private var isSearchActive = false
    @State private var dropFrames: [DropTargetFrame] = []
    @State private var hoveredId: String?
    @State private var fabIsInteracting = false
    @State private var autoListPrefs = AutoListPreferences()
    @State private var showingEditLists = false
    @FocusState private var searchFieldFocused: Bool

    private static let smartIdPrefix = "smart:"
    private static let listIdPrefix = "list:"
    private static let tagsId = "tags"

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
                            Label("Edit Lists", systemImage: "slider.horizontal.3")
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
                    Button {
                        showingEditLists = true
                    } label: {
                        Label("Edit Lists…", systemImage: "pencil")
                    }
                }
            }

        }
    }

    private var myListsSection: some View {
        Section {
            myListsContent
        } header: {
            HStack {
                Text("My Lists")
                Spacer()
                Button { showingNewList = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color(.label), Color(.systemFill))
                        .accessibilityLabel("New List")
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var myListsContent: some View {
        if !autoListPrefs.tagsHidden {
            NavigationLink(value: SystemDestination.tags) {
                SidebarRow(
                    icon: "number",
                    hue: Color(red: 0x6A / 255.0, green: 0x84 / 255.0, blue: 0xB8 / 255.0),
                    label: "Tags",
                    count: tagsCount > 0 ? tagsCount : nil,
                    iconShape: .roundedSquare
                )
            }
        }
        if myLists.isEmpty {
            Text("Tap + to create a list.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        } else {
            ForEach(myLists) { list in
                NavigationLink(value: list) {
                    SidebarRow(
                        icon: list.icon,
                        hue: ListsTokens.listColor(list.color),
                        label: list.name,
                        count: openItemCount(for: list),
                        iconShape: .circle
                    )
                }
                .dropTarget(Self.listIdPrefix + list.id)
                .listRowBackground(
                    hoveredId == Self.listIdPrefix + list.id
                        ? ListsTokens.listColor(list.color).opacity(0.30)
                        : nil
                )
                .contextMenu { listContextMenu(for: list) }
            }
        }
        NavigationLink(value: SystemDestination.recentlyDeleted) {
            SidebarRow(
                icon: "trash.fill",
                hue: Color(.systemGray4),
                label: "Recently Deleted",
                count: deletedCount > 0 ? deletedCount : nil,
                iconShape: .roundedSquare,
                iconGlyphColor: Color(.secondaryLabel)
            )
        }
    }

    /// Shared context menu for any user list — Edit shortcut and a
    /// destructive Delete (Inbox can be deleted; the user can always
    /// recreate it from Recently Deleted or by adding a new list).
    @ViewBuilder
    private func listContextMenu(for list: ItemList) -> some View {
        Button { editingList = list } label: {
            Label("Edit List", systemImage: "pencil")
        }
        Button {
            showingEditLists = true
        } label: {
            Label("Edit Lists…", systemImage: "slider.horizontal.3")
        }
        Button(role: .destructive) {
            Task { try? await store.softDeleteList(list.id) }
        } label: {
            Label("Delete List", systemImage: "trash")
        }
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
