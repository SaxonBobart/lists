import SwiftUI

/// Sheet for picking a parent list when nesting / moving lists.
///
/// Used in two flows:
/// 1. **Create new list** — `ListEditSheet`'s Parent row opens this picker
///    to choose where the new list should live (`movingListId` is `nil`).
/// 2. **Move existing list** — `SidebarView`'s long-press "Move to…" opens
///    this with `movingListId = list.id` so we can grey out cycle-creating
///    targets (the list itself and all its descendants).
///
/// Single-select tree with a "Root" option pinned at the top. Tap commits
/// immediately via `onPick` and dismisses.
struct ParentPickerSheet: View {
    let store: ItemStore
    /// The list being moved. Nil when picking a parent for a brand-new list
    /// (no cycle-guard needed in that case).
    let movingListId: String?
    let initialSelection: String?
    let onPick: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var expanded: Set<String> = []

    init(
        store: ItemStore,
        movingListId: String? = nil,
        initialSelection: String? = nil,
        onPick: @escaping (String?) -> Void
    ) {
        self.store = store
        self.movingListId = movingListId
        self.initialSelection = initialSelection
        self.onPick = onPick
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    rootRow
                }
                Section {
                    ForEach(flatRows) { row in
                        treeRow(row)
                    }
                } header: {
                    Text("Lists")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(movingListId == nil ? "Pick Parent" : "Move To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // Auto-expand the ancestors of the current selection so the
                // user sees their starting point.
                if let start = initialSelection {
                    var cursor: String? = start
                    while let id = cursor,
                          let list = store.lists.first(where: { $0.id == id })
                    {
                        expanded.insert(id)
                        cursor = list.parentId
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Rows

    private var rootRow: some View {
        Button {
            commit(parent: nil)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "minus.circle")
                    .font(.body)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
                Text("None")
                    .foregroundStyle(.primary)
                Spacer()
                if selection == nil {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func treeRow(_ row: PickerRow) -> some View {
        let isBlocked = blockedIds.contains(row.list.id)
        let isSelected = selection == row.list.id
        HStack(spacing: 4) {
            chevron(for: row)
            Button {
                guard !isBlocked else { return }
                commit(parent: row.list.id)
            } label: {
                HStack(spacing: 12) {
                    IconBadge(
                        systemName: row.list.icon,
                        hue: ListsTokens.listColor(row.list.color),
                        shape: .circle
                    )
                    Text(row.list.name)
                        .foregroundStyle(isBlocked ? .secondary : .primary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.leading, CGFloat(row.depth) * 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBlocked)
            .opacity(isBlocked ? 0.45 : 1)
        }
    }

    @ViewBuilder
    private func chevron(for row: PickerRow) -> some View {
        if row.hasChildren {
            let isExpanded = expanded.contains(row.list.id)
            Button {
                if isExpanded {
                    expanded.remove(row.list.id)
                } else {
                    expanded.insert(row.list.id)
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        } else {
            Color.clear.frame(width: 18, height: 30)
        }
    }

    // MARK: - Tree

    private struct PickerRow: Identifiable {
        let list: ItemList
        let depth: Int
        let hasChildren: Bool
        var id: String { list.id }
    }

    private var rootLists: [ItemList] {
        store.lists
            .filter { $0.deletedAt == nil && $0.parentId == nil }
            .sorted { $0.position < $1.position }
    }

    private func children(of id: String) -> [ItemList] {
        store.lists
            .filter { $0.deletedAt == nil && $0.parentId == id }
            .sorted { $0.position < $1.position }
    }

    private var flatRows: [PickerRow] {
        var out: [PickerRow] = []
        func emit(_ list: ItemList, depth: Int) {
            let kids = children(of: list.id)
            out.append(PickerRow(list: list, depth: depth, hasChildren: !kids.isEmpty))
            guard !kids.isEmpty, expanded.contains(list.id) else { return }
            for kid in kids { emit(kid, depth: depth + 1) }
        }
        for root in rootLists { emit(root, depth: 0) }
        return out
    }

    /// Ids the user can't pick — the list being moved, plus all of its
    /// descendants (else we'd build a cycle).
    private var blockedIds: Set<String> {
        guard let id = movingListId else { return [] }
        return Set([id] + store.descendantIds(of: id))
    }

    // MARK: - Commit

    private func commit(parent: String?) {
        selection = parent
        onPick(parent)
        dismiss()
    }
}
