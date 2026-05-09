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
        let parents = items(in: name)
        if !parents.isEmpty {
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
                    let rows = flatten(parents)
                    ForEach(Array(rows.enumerated()), id: \.element.item.id) { idx, row in
                        ItemRow(
                            item: row.item,
                            isOverdue: isOverdue(row.item),
                            store: store,
                            onToggle: { Task { try? await store.toggleDone(row.item.id) } },
                            indent: row.indent
                        )
                        if idx < rows.count - 1 {
                            Divider()
                                .background(ListsTokens.Separator.translucent)
                                .padding(.leading, ListsDensity.rowPadX + 28 + ListsSpacing.s3 + CGFloat(row.indent) * 24)
                        }
                    }
                }
            }
        }
    }

    /// Walks parent → children → grandchildren depth-first, capping at H3
    /// per spec §2.3 (depth ≤ 2 children deep).
    private func flatten(_ parents: [Item]) -> [(item: Item, indent: Int)] {
        var out: [(Item, Int)] = []
        for parent in parents {
            out.append((parent, 0))
            let children = childrenOf(parent.id)
            for child in children {
                out.append((child, 1))
                let grandchildren = childrenOf(child.id)
                for g in grandchildren {
                    out.append((g, 2))
                }
            }
        }
        return out
    }

    private func childrenOf(_ id: UUID) -> [Item] {
        store.items
            .filter { $0.parentId == id && $0.deletedAt == nil && !$0.done }
            .sorted { lhs, rhs in
                (lhs.due ?? .distantFuture) < (rhs.due ?? .distantFuture)
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

    /// TOP-LEVEL items in this list (children render under parents).
    private var visibleItems: [Item] {
        store.items
            .filter { $0.listId == list.id && !$0.done && $0.deletedAt == nil && $0.parentId == nil }
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
