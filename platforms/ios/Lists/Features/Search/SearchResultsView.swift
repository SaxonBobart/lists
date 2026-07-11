import SwiftUI

/// Shows full-text search results across active items. Used as an overlay on
/// SidebarView when the search field has text.
struct SearchResultsView: View {
    let store: ItemStore
    let query: String
    let scope: ItemSearch.Scope?
    let moveSession: ItemMoveSession
    let documentLinkSession: DocumentLinkSession
    let habitsPluginEnabled: Bool
    var onMoveStarted: () -> Void = {}

    @State private var detailItem: Item?
    @State private var lingeringIds: Set<UUID> = []
    @State private var rowMutationError: String?

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
                                    onMutationFailure: { rowMutationError = $0 },
                                    showMetadata: !documentLinkSession.isActive,
                                    onShowDetail: openOrLink,
                                    onPick: documentLinkSession.isActive ? { picked in
                                        if documentLinkSession.canPick(picked) {
                                            documentLinkSession.commit(to: picked, store: store)
                                        }
                                    } : nil,
                                    enablesHierarchySwipeActions: false,
                                    isReadOnly: moveSession.isActive
                                )
                                .disabled(documentLinkSession.isActive && !documentLinkSession.canPick(item))
                                .opacity(documentLinkSession.isActive && !documentLinkSession.canPick(item) ? 0.35 : 1)
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
        .itemDetailCover(
            item: $detailItem,
            store: store,
            onBeginMove: beginMove,
            onBeginDocumentLink: beginDocumentLink
        )
        .itemMutationErrorAlert($rowMutationError)
    }

    // MARK: - Hint

    private var hint: some View {
        VStack(spacing: ListsSpacing.s3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(ListsTokens.Foreground.tertiary)
            Text("Search items by title, body, or tags.")
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
            in: availableItems,
            scope: scope ?? .fullText(query),
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
        documentLinkSession.cancel()
        moveSession.begin(item: item)
        onMoveStarted()
    }

    private func beginDocumentLink(_ source: DocumentLinkSource) {
        moveSession.cancel()
        documentLinkSession.begin(source: source)
    }

    private func openOrLink(_ item: Item) {
        if documentLinkSession.isActive {
            documentLinkSession.commit(to: item, store: store)
        } else {
            detailItem = item
        }
    }

    private func isOverdue(_ item: Item) -> Bool {
        item.isOverdue()
    }

    private func toggleAndLinger(_ item: Item) {
        ItemCompletionLinger.toggle(
            item,
            store: store,
            showCompleted: false,
            lingeringIds: $lingeringIds,
            startLinger: startLinger,
            onFailure: { rowMutationError = $0 }
        )
    }

    private func incrementHabitAndLinger(_ item: Item) {
        ItemCompletionLinger.incrementHabit(
            item,
            store: store,
            showCompleted: false,
            lingeringIds: $lingeringIds,
            startLinger: startLinger,
            onFailure: { rowMutationError = $0 }
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
