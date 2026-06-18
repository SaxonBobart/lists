import SwiftUI

/// Full-screen "Move to" browser. Picks a new home for `item`:
///   - a parent within the current list (or its top level), or
///   - via "Other Lists…", any item (or top level) in any other list.
///
/// Moving across lists relocates the item's whole subtree too — children render
/// under their parent regardless of their own `listId`, so the stored data has
/// to follow (see `ItemStore.applyListCascadeSync`).
///
/// Shown from the inline-edit keyboard toolbar's "Move to" button, the list
/// row's "Move to" swipe action, and the item detail sheet's breadcrumb pill.
struct MoveToParentPicker: View {
    let item: Item
    let store: ItemStore
    @Environment(\.dismiss) private var dismiss

    @State private var path: [Route] = []

    private enum Route: Hashable {
        case lists                 // the all-other-lists browser
        case listItems(String)     // a chosen list's item tree
    }

    var body: some View {
        NavigationStack(path: $path) {
            currentListScreen
                .navigationTitle("Move to…")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .lists:
                        listBrowserScreen
                    case .listItems(let listId):
                        listItemsScreen(listId)
                    }
                }
        }
    }

    // MARK: - Screens

    /// Root: pick a parent within the current list, or step out to any other.
    private var currentListScreen: some View {
        List {
            Section {
                topLevelRow(listId: item.listId, isCurrent: item.parentId == nil)
                ForEach(flatTree(for: item.listId), id: \.item.id) { row in
                    itemRow(row, listId: item.listId)
                }
            } header: {
                Text(listName(item.listId))
            }

            if hasOtherLists {
                Section {
                    NavigationLink(value: Route.lists) {
                        Label("Other Lists…", systemImage: "tray.full")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Every other list, as a tree. Pick one to choose a spot inside it.
    private var listBrowserScreen: some View {
        List {
            ForEach(otherListRows) { row in
                NavigationLink(value: Route.listItems(row.list.id)) {
                    HStack(spacing: 12) {
                        IconBadge(systemName: row.list.icon,
                                  hue: ListsTokens.listColor(row.list.color),
                                  shape: .circle)
                        Text(row.list.name).foregroundStyle(.primary)
                    }
                    .padding(.leading, CGFloat(row.depth) * 20)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Other Lists")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A chosen list's tree — pick its top level or any item as the new parent.
    private func listItemsScreen(_ listId: String) -> some View {
        List {
            Section {
                topLevelRow(listId: listId,
                            isCurrent: item.listId == listId && item.parentId == nil)
                ForEach(flatTree(for: listId), id: \.item.id) { row in
                    itemRow(row, listId: listId)
                }
            } header: {
                Text(listName(listId))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Move to…")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Rows

    private func topLevelRow(listId: String, isCurrent: Bool) -> some View {
        Button {
            move(toList: listId, parent: nil)
        } label: {
            HStack {
                Image(systemName: "tray.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Text("Top Level")
                    .foregroundStyle(.primary)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    @ViewBuilder
    private func itemRow(_ row: (item: Item, indent: Int), listId: String) -> some View {
        let disabled = disabledIds.contains(row.item.id)
        let isCurrent = item.listId == listId && item.parentId == row.item.id
        Button {
            if !disabled { move(toList: listId, parent: row.item.id) }
        } label: {
            HStack(spacing: 0) {
                Spacer()
                    .frame(width: CGFloat(min(row.indent, 6)) * 20)
                Image(systemName: "circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                    .frame(width: 20)
                    .padding(.trailing, 8)
                Text(row.item.title.isEmpty ? "Untitled" : row.item.title)
                    .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                    .lineLimit(2)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .disabled(disabled)
    }

    // MARK: - Move

    private func move(toList listId: String, parent parentId: UUID?) {
        guard var updated = store.item(item.id) else { dismiss(); return }
        let movedAcrossLists = updated.listId != listId
        updated.listId = listId
        updated.parentId = parentId
        // Sections are per-list UUIDs — a cross-list move can't keep the old one.
        if movedAcrossLists { updated.section = nil }
        Task {
            try? await store.update(updated)
            // Drag the whole subtree along so descendants aren't left orphaned
            // in the old list's folder.
            if movedAcrossLists {
                store.applyListCascadeSync(toDescendantsOf: item.id, listId: listId)
            }
        }
        dismiss()
    }

    // MARK: - Item tree

    private func listName(_ listId: String) -> String {
        store.lists.first(where: { $0.id == listId })?.name ?? "List"
    }

    private func flatTree(for listId: String) -> [(item: Item, indent: Int)] {
        let roots = store.items
            .filter { $0.listId == listId && $0.parentId == nil && $0.deletedAt == nil }
            .sorted { $0.sortIndex < $1.sortIndex }
        var result: [(Item, Int)] = []
        var stack = roots.reversed().map { ($0, 0) }
        var visited = Set<UUID>()
        while !stack.isEmpty {
            let (current, depth) = stack.removeLast()
            guard !visited.contains(current.id) else { continue }
            visited.insert(current.id)
            result.append((current, depth))
            let children = store.items
                .filter { $0.parentId == current.id && $0.deletedAt == nil }
                .sorted { $0.sortIndex < $1.sortIndex }
            for child in children.reversed() {
                stack.append((child, depth + 1))
            }
        }
        return result
    }

    // The item being moved and all its descendants — can't parent to own subtree.
    private var disabledIds: Set<UUID> {
        var ids: Set<UUID> = [item.id]
        var queue = [item.id]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            for child in store.items where child.parentId == next && child.deletedAt == nil {
                if ids.insert(child.id).inserted { queue.append(child.id) }
            }
        }
        return ids
    }

    // MARK: - List tree

    private struct ListRow: Identifiable {
        let list: ItemList
        let depth: Int
        var id: String { list.id }
    }

    private var hasOtherLists: Bool { !otherListRows.isEmpty }

    /// Every non-deleted list except the current one, depth-flattened. Sub-lists
    /// of the current list still appear (they're separate destinations).
    private var otherListRows: [ListRow] {
        var out: [ListRow] = []
        func emit(_ list: ItemList, depth: Int) {
            if list.id != item.listId {
                out.append(ListRow(list: list, depth: depth))
            }
            let kids = store.lists
                .filter { $0.deletedAt == nil && $0.parentId == list.id }
                .sorted { $0.position < $1.position }
            for kid in kids { emit(kid, depth: depth + 1) }
        }
        let roots = store.lists
            .filter { $0.deletedAt == nil && $0.parentId == nil }
            .sorted { $0.position < $1.position }
        for root in roots { emit(root, depth: 0) }
        return out
    }
}
