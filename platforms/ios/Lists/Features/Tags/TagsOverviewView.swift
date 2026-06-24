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
    let moveSession: ItemMoveSession

    @State private var selected: Set<String> = []
    @State private var renameTarget: String?
    @State private var renameDraft: String = ""
    @State private var deleteTarget: String?
    @State private var detailItem: Item?
    @State private var lingeringIds: Set<UUID> = []

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
                                allowsEditing: !moveSession.isActive,
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
                                        ? "No active tagged items."
                                        : "No active items carry every selected tag.")
                                )
                                .listRowBackground(Color.clear)
                            } else {
                                ForEach(visibleItems, id: \.id) { item in
                                    ItemRow(
                                        item: item,
                                        isOverdue: isOverdue(item),
                                        store: store,
                                        onToggle: { toggleAndLinger(item) },
                                        onIncrementHabit: { incrementHabitAndLinger(item) },
                                        onShowDetail: { detailItem = $0 },
                                        enablesHierarchySwipeActions: false,
                                        isReadOnly: moveSession.isActive
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
        .itemDetailCover(item: $detailItem, store: store, onBeginMove: beginMove)
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
                let n = tagTotalCount(tag)
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
        Tag.activeTagNames(in: store.items, lingering: lingeringIds)
    }

    /// Items rendered under the chip cloud. Tags are an active-work surface:
    /// completed items and rolled-off calendar events are hidden by default.
    private var visibleItems: [Item] {
        Tag.activeItems(matching: selected, in: store.items, lingering: lingeringIds)
    }

    private func tagCount(_ tag: String) -> Int {
        Tag.openItemCount(for: tag, in: store.items, lingering: lingeringIds)
    }

    private func tagTotalCount(_ tag: String) -> Int {
        Tag.totalItemCount(for: tag, in: store.items)
    }

    private func toggle(_ tag: String) {
        if selected.contains(tag) {
            selected.remove(tag)
        } else {
            selected.insert(tag)
        }
    }

    private func beginMove(_ item: Item) {
        moveSession.begin(item: item)
    }

    private func isOverdue(_ item: Item) -> Bool {
        item.isOverdue()
    }

    private func toggleAndLinger(_ item: Item) {
        ItemCompletionLinger.toggle(
            item,
            store: store,
            showCompleted: false,
            lingeringIds: &lingeringIds,
            startLinger: startLinger
        )
    }

    private func incrementHabitAndLinger(_ item: Item) {
        ItemCompletionLinger.incrementHabit(
            item,
            store: store,
            showCompleted: false,
            startLinger: startLinger
        )
    }

    private func startLinger(for id: UUID) {
        lingeringIds.insert(id)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.18)) {
                _ = lingeringIds.remove(id)
            }
        }
    }
}
