import SwiftUI

/// Sheet for renaming, reordering, and deleting sections on a single list.
/// Mirrors the reference design: nav bar with cancel (X) and confirm (✓),
/// inset-grouped list of section rows with drag handles and swipe-to-delete.
///
/// Edits are accumulated in a local draft (`drafts` + `deletedIds`) and
/// committed atomically via `ItemStore.commitSectionEdits`. Items in deleted
/// sections are soft-deleted alongside the section after a confirmation alert.
struct EditSectionsSheet: View {
    let store: ItemStore
    let list: ItemList

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [Draft] = []
    @State private var deletedIds: [UUID] = []
    @State private var pendingDelete: Draft?
    @FocusState private var focusedId: UUID?

    private struct Draft: Identifiable, Equatable {
        let id: UUID
        var name: String
        /// Number of non-deleted items currently in this section. Used in the
        /// delete-confirmation alert.
        var itemCount: Int
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($drafts) { $draft in
                        HStack {
                            TextField("Section name", text: $draft.name)
                                .focused($focusedId, equals: draft.id)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                        }
                        .accessibilityIdentifier("editsections.section.\(draft.id.uuidString)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                pendingDelete = draft
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .accessibilityIdentifier("editsections.section.\(draft.id.uuidString).swipe.delete")
                        }
                    }
                    .onMove { from, to in
                        drafts.move(fromOffsets: from, toOffset: to)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("editsections.cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { commit() }
                        .fontWeight(.semibold)
                        .disabled(!hasChanges)
                        .accessibilityIdentifier("editsections.done")
                }
            }
            .alert(item: $pendingDelete) { draft in
                Alert(
                    title: Text("Delete \"\(draft.name)\"?"),
                    message: deleteMessage(for: draft),
                    primaryButton: .destructive(Text("Delete")) {
                        deletedIds.append(draft.id)
                        drafts.removeAll { $0.id == draft.id }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .onAppear(perform: loadDrafts)
    }

    private func loadDrafts() {
        drafts = list.sections
            .sorted { $0.position < $1.position }
            .map { section in
                Draft(
                    id: section.id,
                    name: section.name,
                    itemCount: store.items.filter {
                        $0.listId == list.id
                            && $0.section == section.id.uuidString
                            && $0.deletedAt == nil
                    }.count
                )
            }
        deletedIds = []
    }

    private var hasChanges: Bool {
        if !deletedIds.isEmpty { return true }
        if drafts.count != list.sections.count { return true }
        let originalById = Dictionary(uniqueKeysWithValues: list.sections.map { ($0.id, $0) })
        for (idx, draft) in drafts.enumerated() {
            guard let orig = originalById[draft.id] else { return true }
            let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != orig.name { return true }
            // Order changed?
            let originalOrder = list.sections.sorted { $0.position < $1.position }
            if originalOrder.indices.contains(idx),
               originalOrder[idx].id != draft.id {
                return true
            }
        }
        return false
    }

    private func commit() {
        // Fall back to the original name if the user emptied the field —
        // silently dropping the section would orphan its items (they'd still
        // reference the now-missing UUID and disappear from the renderer).
        let originalById = Dictionary(uniqueKeysWithValues: list.sections.map { ($0.id, $0) })
        let kept = drafts.map { draft -> ListSection in
            let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmed.isEmpty ? (originalById[draft.id]?.name ?? "Section") : trimmed
            return ListSection(id: draft.id, name: name, position: 0)
        }
        let listId = list.id
        let deleted = deletedIds
        Task {
            try? await store.commitSectionEdits(in: listId, kept: kept, deleted: deleted)
            await MainActor.run { dismiss() }
        }
    }

    private func deleteMessage(for draft: Draft) -> Text? {
        guard draft.itemCount > 0 else {
            return Text("This section will be removed.")
        }
        let n = draft.itemCount
        let noun = n == 1 ? "item" : "items"
        return Text("This section and its \(n) \(noun) will move to Recently Deleted.")
    }
}
