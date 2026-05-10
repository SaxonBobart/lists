import SwiftUI

/// All items carrying a specific tag. Reuses `ItemRow` so the experience
/// matches Today / smart-list / list-detail flows.
struct TaggedItemsView: View {
    let store: ItemStore
    let tag: String

    var body: some View {
        Group {
            if items.isEmpty {
                ZStack {
                    ListsTokens.Background.grouped.ignoresSafeArea()
                    ContentUnavailableView(
                        "No items",
                        systemImage: "tag",
                        description: Text("Items tagged #\(tag) will appear here.")
                    )
                }
            } else {
                List {
                    Section {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            ItemRow(
                                item: item, isOverdue: isOverdue(item), store: store,
                                onToggle: { Task { try? await store.toggleDone(item.id) } },
                                previousSiblingId: previousIdInSameList(at: idx, in: items)
                            )
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("#\(tag)")
        .navigationBarTitleDisplayMode(.large)
    }

    private var items: [Item] {
        store.items.filter { item in
            item.deletedAt == nil
            && !item.done
            && item.tags.contains(tag)
        }
        .sorted { lhs, rhs in
            (lhs.due ?? .distantFuture) < (rhs.due ?? .distantFuture)
        }
    }

    private func isOverdue(_ item: Item) -> Bool {
        guard let due = item.due else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    private func previousIdInSameList(at idx: Int, in items: [Item]) -> UUID? {
        guard idx > 0 else { return nil }
        let prev = items[idx - 1]
        return prev.listId == items[idx].listId ? prev.id : nil
    }
}
