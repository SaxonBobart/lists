import SwiftUI

/// Full-screen tree picker for choosing a new parent item. Shown from:
///   - the Indent swipe action on any list row
///   - the "parent" button on the inline-edit keyboard toolbar
///   - the breadcrumb pill inside the item detail sheet
struct MoveToParentPicker: View {
    let item: Item
    let store: ItemStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button(action: { reparent(to: nil) }) {
                    HStack {
                        Image(systemName: "tray.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        Text("Top Level")
                            .foregroundStyle(.primary)
                        Spacer()
                        if item.parentId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }

                ForEach(flatTree, id: \.item.id) { row in
                    let disabled = disabledIds.contains(row.item.id)
                    Button(action: { if !disabled { reparent(to: row.item.id) } }) {
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
                            if item.parentId == row.item.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .disabled(disabled)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Move to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func reparent(to parentId: UUID?) {
        guard var updated = store.item(item.id) else { dismiss(); return }
        updated.parentId = parentId
        Task { try? await store.update(updated) }
        dismiss()
    }

    private var flatTree: [(item: Item, indent: Int)] {
        let roots = store.items
            .filter { $0.listId == item.listId && $0.parentId == nil && $0.deletedAt == nil }
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
}
