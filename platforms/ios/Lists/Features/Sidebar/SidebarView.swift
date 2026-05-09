import SwiftUI

/// Sidebar / Home view — the NavigationStack root. Mirrors design
/// `SidebarScreen` in `screens-mobile.jsx`.
///
/// Layout:
/// - Smart-list tiles (full-width, coloured): Today / Scheduled / Flagged /
///   Urgent / Completed / All
/// - "My Lists" section — user-created lists in an inset card
/// - "System" section — Tags / Recently Deleted
struct SidebarView: View {
    let store: ItemStore

    @State private var showingNewList = false
    @State private var showingSettings = false
    @State private var editingList: ItemList?
    @State private var searchText: String = ""
    @State private var isSearchActive = false

    private static let smartListsOrder: [SmartList] = [
        .today, .scheduled, .flagged, .urgent, .completed, .all
    ]

    var body: some View {
        ZStack {
            ListsTokens.Background.grouped.ignoresSafeArea()

            if isSearchActive && !searchText.isEmpty {
                SearchResultsView(store: store, query: searchText)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        smartListsBlock

                        sectionHeader("My Lists")
                        listsBlock

                        sectionHeader("System")
                        systemBlock

                        Spacer().frame(height: ListsSpacing.s8)
                    }
                    .padding(.top, ListsSpacing.s2)
                }
            }
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
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(ListsTokens.accent)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewList = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(ListsTokens.accent)
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
            case .tags:
                TagsOverviewView(store: store)
            case .recentlyDeleted:
                RecentlyDeletedView(store: store)
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
    }

    // MARK: - Blocks

    private var smartListsBlock: some View {
        VStack(spacing: 10) {
            ForEach(Self.smartListsOrder) { smartList in
                NavigationLink(value: smartList) {
                    SmartListTile(
                        smartList: smartList,
                        count: store.items(for: smartList).count,
                        hideCount: smartList == .completed
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ListsSpacing.s4)
    }

    private var listsBlock: some View {
        let items = userLists
        return Group {
            if items.isEmpty {
                Text("No lists yet")
                    .font(ListsTypography.subheadline)
                    .foregroundStyle(ListsTokens.Foreground.tertiary)
                    .padding(.horizontal, ListsSpacing.s5)
                    .padding(.vertical, ListsSpacing.s3)
            } else {
                insetCard {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, list in
                        NavigationLink(value: list) {
                            SidebarRow(
                                icon: list.icon,
                                hue: hue(for: list.color),
                                label: list.name,
                                count: openItemCount(for: list)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editingList = list
                            } label: {
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
                        if idx < items.count - 1 {
                            Divider()
                                .background(ListsTokens.Separator.translucent)
                                .padding(.leading, 50)
                        }
                    }
                }
            }
        }
    }

    private var systemBlock: some View {
        insetCard {
            NavigationLink(value: SystemDestination.tags) {
                SidebarRow(
                    icon: "tag",
                    hue: ListsTokens.Hue.grey,
                    label: "Tags",
                    count: tagsCount
                )
            }
            .buttonStyle(.plain)
            Divider()
                .background(ListsTokens.Separator.translucent)
                .padding(.leading, 50)
            NavigationLink(value: SystemDestination.recentlyDeleted) {
                SidebarRow(
                    icon: "trash",
                    hue: ListsTokens.Hue.grey,
                    label: "Recently Deleted",
                    count: deletedCount > 0 ? deletedCount : nil
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        VStack(spacing: 0) {
            Divider()
                .background(ListsTokens.Separator.translucent)
                .padding(.horizontal, ListsSpacing.s4)
                .padding(.top, ListsSpacing.s4)
            HStack {
                Text(title)
                    .font(ListsTypography.footnote.weight(.semibold))
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                Spacer()
            }
            .padding(.horizontal, ListsSpacing.s5)
            .padding(.vertical, ListsSpacing.s2)
        }
    }

    @ViewBuilder
    private func insetCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, ListsSpacing.s4)
    }

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

    private func hue(for color: ItemList.ListColor) -> Color {
        switch color {
        case .sage:   return ListsTokens.accent
        case .blue:   return ListsTokens.Hue.blue
        case .teal:   return ListsTokens.Hue.teal
        case .green:  return ListsTokens.Hue.green
        case .amber:  return ListsTokens.Hue.amber
        case .orange: return ListsTokens.Hue.orange
        case .pink:   return ListsTokens.Hue.pink
        case .purple: return ListsTokens.Hue.purple
        case .grey:   return ListsTokens.Hue.grey
        }
    }
}
