import SwiftUI

/// All items carrying a specific tag. Reuses `ItemRow` so the experience
/// matches Today / smart-list / list-detail flows.
struct TaggedItemsView: View {
    let store: ItemStore
    let tag: String

    var body: some View {
        ZStack {
            ListsTokens.Background.grouped.ignoresSafeArea()

            ScrollView {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No items",
                        systemImage: "tag",
                        description: Text("Items tagged #\(tag) will appear here.")
                    )
                    .padding(.top, ListsSpacing.s8)
                } else {
                    insetCard {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            ItemRow(item: item, isOverdue: isOverdue(item), store: store) {
                                Task { try? await store.toggleDone(item.id) }
                            }
                            if idx < items.count - 1 {
                                Divider()
                                    .background(ListsTokens.Separator.translucent)
                                    .padding(.leading, ListsDensity.rowPadX + 28 + ListsSpacing.s3)
                            }
                        }
                    }
                    .padding(.horizontal, ListsSpacing.s4)
                    .padding(.top, ListsSpacing.s4)
                    .padding(.bottom, ListsSpacing.s8)
                }
            }
        }
        .navigationTitle("#\(tag)")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func insetCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
                .fill(ListsTokens.Background.elevated)
        )
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
}
