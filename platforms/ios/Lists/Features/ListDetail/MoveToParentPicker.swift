import SwiftUI

/// One "Move to" experience for the whole app. The same rich list tree —
/// sidebar-style rows (icon badge + name + open count + nesting, collapsible) —
/// backs every move:
///   • moving an **item**: opens straight into the item's current list (the
///     common case is re-parenting within the same list); its items render with
///     the real `ItemRow` — chevrons, depth-capped — so it matches the regular
///     list. Tap an item to make it the parent, or "None" for the list's top
///     level. The back button goes out to the list-of-lists to move it into a
///     different list; cross-list moves carry the subtree.
///   • moving a **list**: the same view, **lists only** (no items) — tap a list
///     to make it the new parent, or "None" for the root.
///
/// Presented full-screen from the inline toolbar / row swipe (items) and from
/// the sidebar swipe / context menu / list editor (lists). Depth-capped at
/// `ListsNesting.maxDisplayDepth` like everywhere else.
struct MoveToPicker: View {
    let store: ItemStore
    let mode: Mode
    /// List mode only: the list's current parent — used to auto-expand to
    /// context (no longer drawn as a checkmark).
    var currentListParent: String?

    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []
    @State private var expanded: Set<String> = []
    @State private var didAutoExpand = false
    /// Local, picker-only collapse state for the drill-in item tree. Kept out
    /// of `ListViewPreferences` so browsing the picker never changes the real
    /// list's saved expand/collapse state.
    @State private var collapsedItems: Set<UUID> = []

    enum Mode {
        /// Move an item — drill into a list's items to pick a parent.
        case item(Item)
        /// Move (or parent) a list — pick a list, or root. `onPick` is the
        /// commit seam: the editor sets `parentId`, the sidebar commits a move.
        case list(movingId: String?, onPick: (String?) -> Void)
    }

    // MARK: Inits (match the call sites they replace)

    /// Item move — drop-in for the old `MoveToParentPicker(item:store:)`.
    /// Opens drilled straight into the item's current list; the back button
    /// goes out to the list-of-lists to move it elsewhere.
    init(item: Item, store: ItemStore) {
        self.store = store
        self.mode = .item(item)
        self.currentListParent = nil
        let listExists = store.lists.contains { $0.id == item.listId && $0.deletedAt == nil }
        _path = State(initialValue: listExists ? [item.listId] : [])
    }

    /// List move / parent — drop-in for `ParentPickerSheet(...)`.
    init(store: ItemStore, movingListId: String?, initialSelection: String?,
         onPick: @escaping (String?) -> Void) {
        self.store = store
        self.mode = .list(movingId: movingListId, onPick: onPick)
        self.currentListParent = initialSelection
    }

    private var isListMode: Bool { if case .list = mode { return true } else { return false } }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // List mode can move to the root; item mode always lands inside
                // a list, so its "None" lives on the per-list screen.
                if isListMode {
                    Section { rootRow }
                }
                Section {
                    ForEach(listTreeRows) { row in
                        listRow(row)
                    }
                } header: {
                    if isListMode { Text("Lists") }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(isListMode ? "Move to…" : "Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: String.self) { listId in
                listItemsScreen(listId)   // item mode only
            }
            .onAppear(perform: autoExpand)
        }
        .presentationDetents([.large])   // keep sheet presentations near-full-screen
    }

    // MARK: - List tree (shared backbone)

    private struct ListRow: Identifiable {
        let list: ItemList
        let depth: Int
        let hasChildren: Bool
        var id: String { list.id }
    }

    /// Lists flattened depth-first, honoring `expanded`.
    private var listTreeRows: [ListRow] {
        var out: [ListRow] = []
        func children(of parentId: String?) -> [ItemList] {
            store.lists
                .filter { $0.parentId == parentId && $0.deletedAt == nil }
                .sorted { $0.position < $1.position }
        }
        func emit(_ list: ItemList, _ depth: Int) {
            let kids = children(of: list.id)
            out.append(ListRow(list: list, depth: depth, hasChildren: !kids.isEmpty))
            guard !kids.isEmpty, expanded.contains(list.id) else { return }
            for kid in kids { emit(kid, depth + 1) }
        }
        for root in children(of: nil) { emit(root, 0) }
        return out
    }

    @ViewBuilder
    private func listRow(_ row: ListRow) -> some View {
        let blocked = blockedListIds.contains(row.list.id)
        HStack(spacing: 0) {
            Button {
                if isListMode {
                    if !blocked { pickList(row.list.id) }
                } else {
                    path.append(row.list.id)   // drill into this list's items
                }
            } label: {
                SidebarRow(
                    icon: row.list.icon,
                    hue: ListsTokens.listColor(row.list.color),
                    label: row.list.name,
                    count: openCount(row.list.id) > 0 ? openCount(row.list.id) : nil,
                    indent: row.depth,
                    iconShape: .circle
                )
            }
            .buttonStyle(.plain)
            .disabled(blocked)
            .opacity(blocked ? 0.4 : 1)

            if row.hasChildren {
                Button { toggleExpanded(row.list.id) } label: {
                    Image(systemName: expanded.contains(row.list.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
    }

    /// The no-parent option for **list** mode — moves the list to the root.
    private var rootRow: some View {
        Button { pickList(nil) } label: {
            HStack {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Text("None")
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)   // use our own colors, not the List's button tint
    }

    // MARK: - A chosen list's items (item mode)

    private func listItemsScreen(_ listId: String) -> some View {
        List {
            // "None" pinned on top — its own section, matching list mode.
            Section { noneItemRow(listId) }
            Section {
                ForEach(visibleItemTree(for: listId), id: \.item.id) { row in
                    let blocked = blockedItemIds.contains(row.item.id)
                    ItemRow(
                        item: row.item,
                        isOverdue: false,
                        store: store,
                        onToggle: {},
                        indent: row.indent,
                        showSubItemIndicator: false,
                        showCollapseControl: true,
                        isExpanded: !collapsedItems.contains(row.item.id),
                        onToggleCollapse: { toggleItemCollapsed(row.item.id) },
                        onShowDetail: nil,
                        onBeginInlineEdit: nil,
                        onPick: { _ in moveItem(toList: listId, parent: row.item.id) }
                    )
                    .disabled(blocked)
                    .opacity(blocked ? 0.4 : 1)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            } header: {
                Text(listName(listId))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Move to…")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Full-screen presentation has no pull-to-dismiss; keep Cancel
            // reachable. Trailing so it doesn't collide with the back button.
            ToolbarItem(placement: .topBarTrailing) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    /// The no-parent option for **item** mode — moves the item to this list's
    /// top level (no parent item).
    private func noneItemRow(_ listId: String) -> some View {
        Button { moveItem(toList: listId, parent: nil) } label: {
            HStack {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Text("None")
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)   // match rootRow — neutral, not accent-tinted
    }

    // MARK: - Commit

    private func pickList(_ id: String?) {
        if case .list(_, let onPick) = mode { onPick(id) }
        dismiss()
    }

    private func moveItem(toList listId: String, parent parentId: UUID?) {
        guard case .item(let item) = mode, var updated = store.item(item.id) else { dismiss(); return }
        let movedAcrossLists = updated.listId != listId
        updated.listId = listId
        updated.parentId = parentId
        // Sections are per-list UUIDs — a cross-list move can't keep the old one.
        if movedAcrossLists { updated.section = nil }
        Task {
            try? await store.update(updated)
            // Drag the whole subtree along so descendants aren't orphaned.
            if movedAcrossLists {
                store.applyListCascadeSync(toDescendantsOf: item.id, listId: listId)
            }
        }
        dismiss()
    }

    // MARK: - Data

    private func listName(_ listId: String) -> String {
        store.lists.first(where: { $0.id == listId })?.name ?? "List"
    }

    private func openCount(_ listId: String) -> Int {
        store.items.filter { $0.listId == listId && !$0.done && $0.deletedAt == nil }.count
    }

    private func toggleExpanded(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func toggleItemCollapsed(_ id: UUID) {
        if collapsedItems.contains(id) { collapsedItems.remove(id) } else { collapsedItems.insert(id) }
    }

    /// Expand the ancestors of the relevant list so the user opens onto context.
    private func autoExpand() {
        guard !didAutoExpand else { return }
        didAutoExpand = true
        var cursor: String? = {
            switch mode {
            case .item(let item): return item.listId
            case .list:           return currentListParent
            }
        }()
        while let id = cursor, let list = store.lists.first(where: { $0.id == id }) {
            expanded.insert(id)
            cursor = list.parentId
        }
    }

    /// Lists the moving list can't become a child of — itself and its subtree.
    private var blockedListIds: Set<String> {
        guard case .list(let movingId, _) = mode, let movingId else { return [] }
        return Set([movingId] + store.descendantIds(of: movingId))
    }

    /// Items the moving item can't become a child of — itself and its subtree.
    private var blockedItemIds: Set<UUID> {
        guard case .item(let item) = mode else { return [] }
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

    private func visibleItemTree(for listId: String) -> [(item: Item, indent: Int)] {
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
            // Collapsed parents hide their subtree (local to the picker —
            // never touches the real list's saved expand state).
            guard !collapsedItems.contains(current.id) else { continue }
            let children = store.items
                .filter { $0.parentId == current.id && $0.deletedAt == nil }
                .sorted { $0.sortIndex < $1.sortIndex }
            for child in children.reversed() {
                stack.append((child, depth + 1))
            }
        }
        return result
    }
}

/// Back-compat shim — items move via the unified `MoveToPicker`.
struct MoveToParentPicker: View {
    let item: Item
    let store: ItemStore
    var body: some View { MoveToPicker(item: item, store: store) }
}
