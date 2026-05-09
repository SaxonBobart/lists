import SwiftUI

/// Sidebar / Home view — the NavigationStack root.
///
/// Layout per `screens-mobile.jsx#SidebarScreen`:
/// - Smart-list tiles (full-width, system-colored)
/// - "My Lists" — user-created lists in an inset card
/// - "System" — Tags / Recently Deleted
///
/// Tap a row → navigate. Drag the FAB onto a row → open QuickCaptureSheet
/// pre-targeted to that list. Tap the FAB → open QuickCaptureSheet generic.
struct SidebarView: View {
    let store: ItemStore

    @State private var showingNewList = false
    @State private var showingSettings = false
    @State private var editingList: ItemList?
    @State private var captureTarget: CaptureTarget?
    @State private var searchText: String = ""
    @State private var isSearchActive = false
    @State private var dropFrames: [DropTargetFrame] = []
    @State private var hoveredId: String?
    @State private var fabIsInteracting = false

    private static let smartListsOrder: [SmartList] = [
        .today, .scheduled, .flagged, .urgent, .completed, .all
    ]

    private static let smartIdPrefix = "smart:"
    private static let listIdPrefix = "list:"

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if isSearchActive && !searchText.isEmpty {
                SearchResultsView(store: store, query: searchText)
            } else {
                List {
                    smartListsSection
                    myListsSection
                    systemSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .scrollDisabled(fabIsInteracting)
                .onPreferenceChange(DropTargetFrameKey.self) { frames in
                    dropFrames = frames
                }
            }

            FloatingAddButton(
                tint: .accentColor,
                action: { captureTarget = CaptureTarget(listId: ItemList.inboxId, section: nil) },
                onDragChanged: { location in
                    let hit = dropFrames.first { $0.rect.contains(location) }
                    if hoveredId != hit?.id {
                        hoveredId = hit?.id
                    }
                },
                onDragEnded: { location in
                    if let hit = dropFrames.first(where: { $0.rect.contains(location) }) {
                        if let listId = parseList(hit.id) {
                            captureTarget = CaptureTarget(listId: listId, section: nil)
                        }
                    }
                    hoveredId = nil
                },
                isInteracting: $fabIsInteracting
            )
            .padding(.trailing, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, isPresented: $isSearchActive,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search items")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .accessibilityLabel("Settings")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewList = true
                } label: {
                    Image(systemName: "plus.circle")
                        .accessibilityLabel("New List")
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
        .sheet(isPresented: $showingNewList) {
            ListEditSheet(store: store)
        }
        .sheet(item: $editingList) { list in
            ListEditSheet(existing: list, store: store)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store)
        }
        .sheet(item: $captureTarget) { target in
            QuickCaptureSheet(store: store, defaultListId: target.listId, defaultSection: target.section)
        }
    }

    // MARK: - Sections

    private var smartListsSection: some View {
        Section {
            ForEach(Self.smartListsOrder) { smartList in
                NavigationLink(value: smartList) {
                    SmartListTile(
                        smartList: smartList,
                        count: store.items(for: smartList).count,
                        hideCount: smartList == .completed,
                        isHovered: hoveredId == Self.smartIdPrefix + smartList.rawValue
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .dropTarget(Self.smartIdPrefix + smartList.rawValue)
            }
        }
    }

    private var myListsSection: some View {
        Section("My Lists") {
            if userLists.isEmpty {
                Text("Tap + to create a list.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(userLists) { list in
                    NavigationLink(value: list) {
                        SidebarRow(
                            icon: list.icon,
                            hue: ListsTokens.listColor(list.color),
                            label: list.name,
                            count: openItemCount(for: list),
                            isHovered: hoveredId == Self.listIdPrefix + list.id
                        )
                    }
                    .dropTarget(Self.listIdPrefix + list.id)
                    .contextMenu {
                        Button { editingList = list } label: {
                            Label("Edit List", systemImage: "pencil")
                        }
                        if list.id != ItemList.inboxId {
                            Button(role: .destructive) {
                                Task { try? await store.softDeleteList(list.id) }
                            } label: {
                                Label("Delete List", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var systemSection: some View {
        Section("System") {
            NavigationLink(value: SystemDestination.tags) {
                SidebarRow(
                    icon: "tag",
                    hue: .gray,
                    label: "Tags",
                    count: tagsCount > 0 ? tagsCount : nil
                )
            }
            NavigationLink(value: SystemDestination.recentlyDeleted) {
                SidebarRow(
                    icon: "trash",
                    hue: .gray,
                    label: "Recently Deleted",
                    count: deletedCount > 0 ? deletedCount : nil
                )
            }
        }
    }

    // MARK: - Helpers

    private var userLists: [ItemList] {
        store.lists
            .filter { $0.deletedAt == nil }
            .sorted { $0.position < $1.position }
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
        if id.hasPrefix(Self.smartIdPrefix) {
            // Drop on a smart-list tile → fall back to inbox (smart lists
            // aren't real lists; can't add to them directly).
            return ItemList.inboxId
        }
        return nil
    }
}

/// Hashable handle used for sheet(item:) presentation when the FAB drops
/// on a list / section.
struct CaptureTarget: Identifiable, Hashable {
    var id: String { "\(listId)#\(section ?? "")" }
    let listId: String
    let section: String?
}
