import SwiftUI

/// Single user-list view (vertical layout). Shows the list's items grouped by
/// section if any exist, otherwise as a flat list. Reuses `ItemRow`.
struct ListDetailView: View {
    let store: ItemStore
    let list: ItemList

    var body: some View {
        ZStack {
            ListsTokens.Background.grouped.ignoresSafeArea()

            ScrollView {
                if visibleItems.isEmpty {
                    ContentUnavailableView(
                        "No items yet",
                        systemImage: list.icon,
                        description: Text("Add an item with the + button.")
                    )
                    .padding(.top, ListsSpacing.s8)
                } else {
                    VStack(alignment: .leading, spacing: ListsSpacing.s4) {
                        ForEach(sections, id: \.self) { sectionName in
                            section(named: sectionName)
                        }
                    }
                    .padding(.horizontal, ListsSpacing.s4)
                    .padding(.top, ListsSpacing.s4)
                    .padding(.bottom, ListsSpacing.s8)
                }
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func section(named name: String) -> some View {
        let entries = items(in: name)
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if name != Self.uncategorized {
                    Text(name)
                        .font(ListsTypography.footnote.weight(.semibold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                        .padding(.horizontal, ListsSpacing.s2)
                        .padding(.bottom, 2)
                }
                insetCard {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, item in
                        ItemRow(item: item, isOverdue: isOverdue(item)) {
                            Task { try? await store.toggleDone(item.id) }
                        }
                        if idx < entries.count - 1 {
                            Divider()
                                .background(ListsTokens.Separator.translucent)
                                .padding(.leading, ListsDensity.rowPadX + 28 + ListsSpacing.s3)
                        }
                    }
                }
            }
        }
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

    // MARK: - Data

    private static let uncategorized = "__uncategorized__"

    /// Items in this list, undeleted, sorted by section then position.
    private var visibleItems: [Item] {
        store.items
            .filter { $0.listId == list.id && !$0.done }
    }

    /// Distinct section names, with the "no section" bucket first when present.
    private var sections: [String] {
        var seen: [String] = []
        var sawUncategorized = false
        for item in visibleItems {
            if let s = item.section {
                if !seen.contains(s) { seen.append(s) }
            } else {
                sawUncategorized = true
            }
        }
        return (sawUncategorized ? [Self.uncategorized] : []) + seen
    }

    private func items(in section: String) -> [Item] {
        if section == Self.uncategorized {
            return visibleItems.filter { $0.section == nil }
        }
        return visibleItems.filter { $0.section == section }
    }

    private func isOverdue(_ item: Item) -> Bool {
        guard let due = item.due else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }
}
