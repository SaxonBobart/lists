import SwiftUI

/// Edit Lists sheet — manages the Sidebar layout: auto-list visibility +
/// order, the Tags row toggle, and the user-list order. Reorder via drag
/// handles in EditMode.
///
/// Three sections:
/// 1. **Auto-Lists**: each row has a leading checkbox + drag handle.
///    Uncheck → hides the tile in the sidebar; reordering controls
///    sidebar tile order.
/// 2. **Tags**: single toggle row. Uncheck → hides the Tags row from My
///    Lists.
/// 3. **My Lists**: user-created lists. Tap the leading red minus circle
///    to delete any list (Inbox included — the user can recreate one any
///    time). Tap the trailing info button to open the list edit sheet.
///    Drag to reorder.
struct EditListsSheet: View {
    let store: ItemStore
    @Bindable var autoListPrefs: AutoListPreferences

    @Environment(\.dismiss) private var dismiss
    @State private var editingList: ItemList?

    var body: some View {
        NavigationStack {
            List {
                autoListsSection
                tagsSection
                myListsSection
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .accessibilityLabel("Done")
                    }
                }
            }
            .sheet(item: $editingList) { list in
                ListEditSheet(existing: list, store: store)
            }
        }
    }

    // MARK: - Auto-lists section

    private var autoListsSection: some View {
        Section {
            ForEach(autoListPrefs.order) { smartList in
                let visible = !autoListPrefs.hidden.contains(smartList)
                HStack(spacing: 12) {
                    Button {
                        autoListPrefs.setHidden(smartList, visible)
                    } label: {
                        Image(systemName: visible ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(visible ? ListsTokens.accent : Color.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    IconBadge(
                        systemName: smartList.iconName,
                        hue: ListsTokens.smartColor(smartList),
                        shape: .circle
                    )
                    Text(smartList.displayName)
                    Spacer()
                }
            }
            .onMove { source, destination in
                autoListPrefs.move(fromOffsets: source, toOffset: destination)
            }
        } header: {
            Text("Auto-Lists")
        } footer: {
            Text("Auto-lists are stuck at the top. Uncheck to hide.")
        }
    }

    // MARK: - Tags toggle

    private var tagsSection: some View {
        Section {
            let visible = !autoListPrefs.tagsHidden
            HStack(spacing: 12) {
                Button {
                    autoListPrefs.tagsHidden = visible
                } label: {
                    Image(systemName: visible ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(visible ? ListsTokens.accent : Color.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                IconBadge(
                    systemName: "number",
                    hue: ListsTokens.tagAccent,
                    shape: .roundedSquare
                )
                Text("Tags")
                Spacer()
            }
        } footer: {
            Text("Tags pins to the top of My Lists. Uncheck to hide.")
        }
    }

    // MARK: - My Lists

    private var myListsSection: some View {
        Section("My Lists") {
            ForEach(activeLists) { list in
                listRow(list)
            }
            .onDelete { offsets in
                let toDelete = offsets.map { activeLists[$0] }
                for list in toDelete {
                    Task { try? await store.softDeleteList(list.id) }
                }
            }
            .onMove { source, destination in
                Task { await reorder(activeLists, source: source, destination: destination) }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func listRow(_ list: ItemList) -> some View {
        HStack(spacing: 12) {
            IconBadge(
                systemName: list.icon,
                hue: ListsTokens.listColor(list.color),
                shape: .circle
            )
            Text(list.name)
            Spacer()
            Button {
                editingList = list
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(ListsTokens.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Helpers

    private var activeLists: [ItemList] {
        store.lists
            .filter { $0.deletedAt == nil }
            .sorted { $0.position < $1.position }
    }

    /// Re-stripe positions for the reordered subset while leaving
    /// non-affected lists untouched.
    private func reorder(_ subset: [ItemList], source: IndexSet, destination: Int) async {
        var reordered = subset
        reordered.move(fromOffsets: source, toOffset: destination)
        let basis = subset.map(\.position).min() ?? 0
        for (offset, list) in reordered.enumerated() {
            var copy = list
            copy.position = basis + Double(offset)
            try? await store.updateList(copy)
        }
    }
}
