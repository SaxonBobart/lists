import SwiftUI

/// Shows full-text search results across all items. Used as an overlay on
/// SidebarView when the search field has text.
struct SearchResultsView: View {
    let store: ItemStore
    let query: String

    var body: some View {
        Group {
            if query.isEmpty {
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
                    ForEach(groupedByList, id: \.0) { listName, items in
                        Section {
                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                                ItemRow(
                                    item: item, isOverdue: false, store: store,
                                    onToggle: { Task { try? await store.toggleDone(item.id) } },
                                    onIncrementHabit: { Task { try? await store.incrementHabit(item.id) } },
                                    previousSiblingId: idx > 0 ? items[idx - 1].id : nil
                                )
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                                .accessibilityIdentifier("search.result.\(item.id.uuidString)")
                            }
                        } header: {
                            Text(listName)
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

    private var results: [Item] {
        let needle = query.lowercased()
        return store.items.filter { item in
            guard item.deletedAt == nil else { return false }
            if item.title.lowercased().contains(needle) { return true }
            if item.body.lowercased().contains(needle) { return true }
            if item.tags.contains(where: { $0.lowercased().contains(needle) }) { return true }
            return false
        }
    }

    private var groupedByList: [(String, [Item])] {
        let dict = Dictionary(grouping: results) { item in
            store.lists.first(where: { $0.id == item.listId })?.name ?? item.listId
        }
        return dict.sorted { lhs, rhs in lhs.key < rhs.key }
            .map { ($0.key, $0.value.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }) }
    }
}
