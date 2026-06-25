import SwiftUI

/// Shows full-text search results across active items. Used as an overlay on
/// SidebarView when the search field has text.
struct SearchResultsView: View {
    let store: ItemStore
    let query: String
    let moveSession: ItemMoveSession
    let habitsPluginEnabled: Bool
    var onMoveStarted: () -> Void = {}

    @State private var detailItem: Item?
    @State private var lingeringIds: Set<UUID> = []

    var body: some View {
        Group {
            if trimmedQuery.isEmpty {
                ScrollView {
                    hint
                }
                .background(ListsTokens.Background.grouped)
            } else if results.isEmpty {
                ScrollView {
                    ContentUnavailableView(
                        "No matches",
                        systemImage: "magnifyingglass",
                        description: Text("No items match \"\(query)\".")
                    )
                    .padding(.top, ListsSpacing.s8)
                    .accessibilityIdentifier("search.empty")
                }
                .background(ListsTokens.Background.grouped)
            } else {
                List {
                    ForEach(groupedByList, id: \.listName) { group in
                        Section {
                            ForEach(group.items, id: \.id) { item in
                                ItemRow(
                                    item: item, isOverdue: isOverdue(item), store: store,
                                    onToggle: { toggleAndLinger(item) },
                                    onIncrementHabit: { incrementHabitAndLinger(item) },
                                    onShowDetail: { detailItem = $0 },
                                    enablesHierarchySwipeActions: false,
                                    isReadOnly: moveSession.isActive
                                )
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                                .accessibilityIdentifier("search.result.\(item.id.uuidString)")
                            }
                        } header: {
                            Text(group.listName)
                                .font(ListsTypography.footnote.weight(.semibold))
                                .tracking(0.5)
                                .textCase(.uppercase)
                                .foregroundStyle(ListsTokens.Foreground.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .itemDetailCover(item: $detailItem, store: store, onBeginMove: beginMove)
    }

    // MARK: - Hint

    private var hint: some View {
        VStack(spacing: ListsSpacing.s3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(ListsTokens.Foreground.tertiary)
            Text("Search items by title, body, or #tag.")
                .font(ListsTypography.subheadline)
                .foregroundStyle(ListsTokens.Foreground.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, ListsSpacing.s8)
    }

    // MARK: - Search

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [Item] {
        ItemSearch.results(
            matching: query,
            in: availableItems,
            lingering: lingeringIds,
            itemTypePolicy: itemTypePolicy,
            now: Date.now,
            calendar: Calendar.current
        )
    }

    private var groupedByList: [ItemSearch.ListGroup] {
        ItemSearch.groupedByList(results, lists: store.lists)
    }

    private var availableItems: [Item] {
        store.items.filter { $0.isAvailable(in: itemTypePolicy) }
    }

    private var itemTypePolicy: ItemTypePolicy {
        ItemTypePolicy(habitsEnabled: habitsPluginEnabled)
    }

    private func beginMove(_ item: Item) {
        moveSession.begin(item: item)
        onMoveStarted()
    }

    private func isOverdue(_ item: Item) -> Bool {
        item.isOverdue()
    }

    private func toggleAndLinger(_ item: Item) {
        ItemCompletionLinger.toggle(
            item,
            store: store,
            showCompleted: false,
            lingeringIds: &lingeringIds,
            startLinger: startLinger
        )
    }

    private func incrementHabitAndLinger(_ item: Item) {
        ItemCompletionLinger.incrementHabit(
            item,
            store: store,
            showCompleted: false,
            startLinger: startLinger
        )
    }

    private func startLinger(for id: UUID) {
        lingeringIds.insert(id)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.18)) {
                _ = lingeringIds.remove(id)
            }
        }
    }
}
