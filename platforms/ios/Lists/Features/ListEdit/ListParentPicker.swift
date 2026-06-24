import SwiftUI

/// Full-screen picker for choosing a list parent when nesting or moving lists.
/// Item moving uses `ItemMoveSession` and the in-place bottom shelf instead.
struct ListParentPicker: View {
    let store: ItemStore
    let movingListId: String?
    let initialSelection: String?
    let onPick: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<String> = []
    @State private var didAutoExpand = false

    init(store: ItemStore,
         movingListId: String?,
         initialSelection: String?,
         onPick: @escaping (String?) -> Void) {
        self.store = store
        self.movingListId = movingListId
        self.initialSelection = initialSelection
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            List {
                Section { rootRow }
                Section {
                    ForEach(listTreeRows) { row in
                        listRow(row)
                    }
                } header: {
                    Text("Lists")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Parent List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .cancel) { dismiss() }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("list.parentPicker.close")
                }
            }
            .onAppear(perform: autoExpand)
        }
    }

    // MARK: - List tree

    private typealias ListRow = ListHierarchy.FlatRow

    /// Lists flattened depth-first, honoring `expanded`.
    private var listTreeRows: [ListRow] {
        ListHierarchy.flattenedRows(in: store.lists) { expanded.contains($0) }
    }

    private func listRow(_ row: ListRow) -> some View {
        let blocked = blockedListIds.contains(row.list.id)
        let count = openCount(row.list.id)
        return HStack(spacing: 0) {
            Button {
                if !blocked { pickList(row.list.id) }
            } label: {
                SidebarRow(
                    icon: row.list.icon,
                    hue: ListsTokens.listColor(row.list.color),
                    label: row.list.name,
                    count: count > 0 ? count : nil,
                    indent: row.depth,
                    iconShape: .circle
                )
            }
            .buttonStyle(.plain)
            .disabled(blocked)
            .accessibilityLabel(row.list.name)
            .accessibilityHint(blocked ? "This list cannot be moved inside itself or its descendants." : "")
            .accessibilityIdentifier("list.parentPicker.list.\(row.list.id)")

            if row.hasChildren {
                Button { toggleExpanded(row.list.id) } label: {
                    Image(systemName: expanded.contains(row.list.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(expanded.contains(row.list.id) ? "Collapse \(row.list.name)" : "Expand \(row.list.name)")
                .accessibilityIdentifier("list.parentPicker.list.\(row.list.id).chevron")
            } else {
                DecorativeChevron()
            }
        }
        .opacity(blocked ? 0.4 : 1)
    }

    /// The no-parent option for list mode — moves the list to the root.
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
        .buttonStyle(.plain)
        .accessibilityLabel("No parent")
        .accessibilityIdentifier("list.parentPicker.none")
    }

    // MARK: - Commit

    private func pickList(_ id: String?) {
        onPick(id)
        dismiss()
    }

    // MARK: - Data

    private func openCount(_ listId: String) -> Int {
        store.openItemCount(in: listId)
    }

    private func toggleExpanded(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// Expand the ancestors of the current parent so the picker opens onto context.
    private func autoExpand() {
        guard !didAutoExpand else { return }
        didAutoExpand = true
        var cursor = initialSelection
        while let id = cursor, let list = store.lists.first(where: { $0.id == id }) {
            expanded.insert(id)
            cursor = list.parentId
        }
    }

    /// Lists the moving list can't become a child of — itself and its subtree.
    private var blockedListIds: Set<String> {
        guard let movingListId else { return [] }
        return Set([movingListId] + store.descendantIds(of: movingListId))
    }
}
