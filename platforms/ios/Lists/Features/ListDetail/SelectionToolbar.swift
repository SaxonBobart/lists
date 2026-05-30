import SwiftUI

/// Floating liquid-glass action bar shown while the list is in "Select
/// Reminders" mode. Acts on the current `selection`: move to another list,
/// move to / create a section, add a tag, flag, or delete. Buttons disable
/// when nothing is selected. Reuses `SectionPickerSheet` (which already
/// supports creating a new section) and the bulk `ItemStore` operations.
struct SelectionToolbar: View {
    let store: ItemStore
    let listId: String
    @Binding var selection: Set<UUID>
    @Binding var inSelectMode: Bool

    @State private var showSectionPicker = false
    @State private var showTagSheet = false
    @State private var newTag = ""
    @State private var pendingSection: String?

    private let pillHeight: CGFloat = 44
    private let buttonHeight: CGFloat = 38
    private let horizontalInset: CGFloat = 14

    private var isEmpty: Bool { selection.isEmpty }

    var body: some View {
        HStack(spacing: 0) {
            moveToListMenu
            barButton("Section", "square.dashed", id: "selection.section") { showSectionPicker = true }
            barButton("Tag", "number", id: "selection.tag") { showTagSheet = true }
            barButton("Flag", "flag", id: "selection.flag") { applyFlag() }
            barButton("Delete", "trash", id: "selection.delete", destructive: true) { applyDelete() }
        }
        .frame(height: pillHeight)
        .padding(.horizontal, horizontalInset)
        .glassEffect(.regular, in: Capsule())
        .sheet(isPresented: $showSectionPicker) {
            SectionPickerSheet(store: store, listId: listId, section: sectionBinding)
                .tint(.primary)
        }
        .sheet(isPresented: $showTagSheet) { tagSheet }
    }

    // MARK: Buttons

    private var moveToListMenu: some View {
        Menu {
            ForEach(activeLists, id: \.id) { list in
                Button {
                    applyMoveToList(list.id)
                } label: {
                    Label(list.name, systemImage: list.icon)
                }
            }
        } label: {
            barLabel("Move", "folder", destructive: false)
        }
        .disabled(isEmpty)
        .accessibilityIdentifier("selection.move")
    }

    private func barButton(
        _ title: String,
        _ symbol: String,
        id: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            barLabel(title, symbol, destructive: destructive)
        }
        .buttonStyle(.plain)
        .disabled(isEmpty)
        .accessibilityIdentifier(id)
    }

    private func barLabel(_ title: String, _ symbol: String, destructive: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .regular))
            .frame(maxWidth: .infinity)
            .frame(height: buttonHeight)
            .foregroundStyle(tint(destructive: destructive))
            .accessibilityLabel(title)
            .contentShape(Rectangle())
    }

    private func tint(destructive: Bool) -> Color {
        if isEmpty { return ListsTokens.Foreground.tertiary }
        return destructive ? .red : ListsTokens.Foreground.primary
    }

    private var tagSheet: some View {
        NavigationStack {
            Form {
                Section("Add Tag") {
                    TextField("Tag", text: $newTag)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { applyTag() }
                        .accessibilityIdentifier("selection.tag.input")
                }
            }
            .navigationTitle("Add Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showTagSheet = false } label: {
                        Image(systemName: "xmark").accessibilityLabel("Cancel")
                    }
                    .tint(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { applyTag() } label: {
                        Image(systemName: "checkmark").fontWeight(.semibold).accessibilityLabel("Add")
                    }
                    .tint(.primary)
                    .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: Actions

    private var sectionBinding: Binding<String?> {
        Binding(get: { pendingSection }, set: { applyMoveToSection($0) })
    }

    private var activeLists: [ItemList] {
        store.lists.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }

    private func applyMoveToList(_ id: String) {
        let sel = selection
        Task { try? await store.bulkMove(sel, toListId: id) }
        clear()
    }

    private func applyMoveToSection(_ section: String?) {
        let sel = selection
        Task { try? await store.bulkMove(sel, toSection: section) }
        clear()
    }

    private func applyFlag() {
        let sel = selection
        Task { try? await store.bulkSetFlagged(sel, true) }
        clear()
    }

    private func applyTag() {
        let clean = newTag
        let sel = selection
        Task { try? await store.bulkAddTag(sel, tag: clean) }
        newTag = ""
        showTagSheet = false
        clear()
    }

    private func applyDelete() {
        let sel = selection
        Task { try? await store.bulkSoftDelete(sel) }
        clear()
        inSelectMode = false
    }

    private func clear() {
        selection.removeAll()
    }
}
