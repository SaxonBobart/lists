import SwiftUI

/// Top-level Tags screen. Three rows of horizontally-scrolling tag chips
/// at the top; below them, an item list scoped by the current chip
/// selection. Tapping a chip toggles selection (filled accent vs.
/// outline). The leading "All" chip clears the selection and shows every
/// item that carries any tag.
///
/// Multi-select is AND: an item must carry every selected tag to appear.
/// Long-press a chip → Rename / Delete the tag across the whole library.
struct TagsOverviewView: View {
    let store: ItemStore

    @State private var selected: Set<String> = []
    @State private var renameTarget: String?
    @State private var renameDraft: String = ""
    @State private var deleteTarget: String?

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Group {
                if allTags.isEmpty {
                    ContentUnavailableView(
                        "No tags yet",
                        systemImage: "number",
                        description: Text("Add `#tag` to an item's title or use the tag chip in its detail sheet.")
                    )
                } else {
                    List {
                        Section {
                            TagChipCloud(
                                tags: allTags,
                                isAllSelected: selected.isEmpty,
                                isSelected: { selected.contains($0) },
                                counts: { tagCount($0) },
                                onAllTap: { selected.removeAll() },
                                onTap: { toggle($0) },
                                onRename: { tag in
                                    renameDraft = tag
                                    renameTarget = tag
                                },
                                onDelete: { deleteTarget = $0 }
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                        Section {
                            if visibleItems.isEmpty {
                                ContentUnavailableView(
                                    "Nothing to show",
                                    systemImage: "tray",
                                    description: Text(selected.isEmpty
                                        ? "No items have tags yet."
                                        : "No items carry every selected tag.")
                                )
                                .listRowBackground(Color.clear)
                            } else {
                                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { idx, item in
                                    ItemRow(
                                        item: item,
                                        isOverdue: isOverdue(item),
                                        store: store,
                                        onToggle: { Task { try? await store.toggleDone(item.id) } },
                                        onIncrementHabit: { Task { try? await store.incrementHabit(item.id) } },
                                        previousSiblingId: idx > 0 && visibleItems[idx - 1].listId == item.listId
                                            ? visibleItems[idx - 1].id
                                            : nil
                                    )
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets())
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarTitleColor(ListsTokens.tagAccent)
        .tint(ListsTokens.tagAccent)
        .alert(
            deleteTarget.map { "Delete #\($0)?" } ?? "",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
        ) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                if let tag = deleteTarget {
                    selected.remove(tag)
                    Task { try? await store.removeTag(tag) }
                }
                deleteTarget = nil
            }
        } message: {
            if let tag = deleteTarget {
                let n = tagCount(tag)
                Text("Removes #\(tag) from \(n) item\(n == 1 ? "" : "s"). The items stay.")
            }
        }
        .alert(
            "Rename tag",
            isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
        ) {
            TextField("New name", text: $renameDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                if let oldTag = renameTarget {
                    let newName = renameDraft
                    if selected.remove(oldTag) != nil, let cleaned = Tag.sanitize(newName) {
                        selected.insert(cleaned)
                    }
                    Task { try? await store.renameTag(from: oldTag, to: newName) }
                }
                renameTarget = nil
            }
        }
    }

    // MARK: - Data

    /// Tags ordered by relation (frequently co-occurring tags end up
    /// adjacent so the chip cloud reads more naturally).
    private var allTags: [String] {
        var seenLower: Set<String> = []
        var raw: [String] = []
        for item in store.items where item.deletedAt == nil {
            for tag in item.tags {
                let lower = tag.lowercased()
                if seenLower.insert(lower).inserted {
                    raw.append(tag)
                }
            }
        }
        let sets = store.items
            .filter { $0.deletedAt == nil }
            .map(\.tags)
        return Tag.orderByRelation(raw, itemTagSets: sets)
    }

    /// Items rendered under the chip cloud. With no selection, every
    /// non-deleted item that carries at least one tag. With a selection,
    /// items that carry *every* selected tag (AND-intersection).
    private var visibleItems: [Item] {
        let filtered: [Item]
        if selected.isEmpty {
            filtered = store.items.filter { item in
                item.deletedAt == nil && !item.tags.isEmpty
            }
        } else {
            let lowered = Set(selected.map { $0.lowercased() })
            filtered = store.items.filter { item in
                guard item.deletedAt == nil else { return false }
                let have = Set(item.tags.map { $0.lowercased() })
                return lowered.isSubset(of: have)
            }
        }
        return filtered.sorted { lhs, rhs in
            switch (lhs.due, rhs.due) {
            case let (l?, r?): return l == r ? lhs.title < rhs.title : l < r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return lhs.title < rhs.title
            }
        }
    }

    private func tagCount(_ tag: String) -> Int {
        let lower = tag.lowercased()
        return store.items.reduce(into: 0) { acc, item in
            guard item.deletedAt == nil, !item.done else { return }
            if item.tags.contains(where: { $0.lowercased() == lower }) { acc += 1 }
        }
    }

    private func toggle(_ tag: String) {
        if selected.contains(tag) {
            selected.remove(tag)
        } else {
            selected.insert(tag)
        }
    }

    private func isOverdue(_ item: Item) -> Bool {
        guard let due = item.due else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }
}

// MARK: - Chip cloud

/// Three rows of horizontally-scrolling chips. Tags are distributed
/// column-major (chip N → row N % 3) so the leftmost columns stay dense.
private struct TagChipCloud: View {
    let tags: [String]
    let isAllSelected: Bool
    let isSelected: (String) -> Bool
    let counts: (String) -> Int
    let onAllTap: () -> Void
    let onTap: (String) -> Void
    let onRename: (String) -> Void
    let onDelete: (String) -> Void

    private let rowCount = 3
    private let spacing: CGFloat = 8

    private var rows: [[String]] {
        var out: [[String]] = Array(repeating: [], count: rowCount)
        for (i, tag) in tags.enumerated() {
            out[i % rowCount].append(tag)
        }
        return out
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(0..<rowCount, id: \.self) { rowIndex in
                    HStack(spacing: spacing) {
                        if rowIndex == 0 {
                            AllTagsChip(isSelected: isAllSelected, onTap: onAllTap)
                        }
                        ForEach(rows[rowIndex], id: \.self) { tag in
                            TagFilterChip(
                                text: tag,
                                count: counts(tag),
                                isSelected: isSelected(tag),
                                onTap: { onTap(tag) },
                                onRename: { onRename(tag) },
                                onDelete: { onDelete(tag) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}

private struct AllTagsChip: View {
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "number")
                    .font(.caption.weight(.semibold))
                Text("All")
                    .font(.system(.callout, design: .monospaced))
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? ListsTokens.accent : Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TagFilterChip: View {
    let text: String
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text("#\(text)")
                    .font(.system(.callout, design: .monospaced))
                Text("\(count)")
                    .font(.system(.caption, design: .monospaced).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
            }
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    if isSelected {
                        Capsule().fill(ListsTokens.accent)
                    } else {
                        Capsule()
                            .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
    }
}
