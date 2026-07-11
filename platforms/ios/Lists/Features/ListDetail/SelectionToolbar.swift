import SwiftUI

/// Floating liquid-glass action bar shown while the list is in multi-select
/// mode. Acts on the current `selection`: move to another list,
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
    @State private var activeOperation: BulkOperation?
    @State private var operationFailure: OperationFailure?

    private enum BulkOperation: Equatable {
        case moveToList(String)
        case moveToSection(String?)
        case flag
        case addTag(String)
        case delete

        var failureTitle: String {
            switch self {
            case .moveToList, .moveToSection: "Couldn’t Move Items"
            case .flag: "Couldn’t Flag Items"
            case .addTag: "Couldn’t Add Tag"
            case .delete: "Couldn’t Delete Items"
            }
        }
    }

    private struct OperationFailure: Equatable {
        let operation: BulkOperation
        let message: String
    }

    private let pillHeight: CGFloat = 44
    private let buttonHeight: CGFloat = 38
    private let horizontalInset: CGFloat = 14

    private var isEmpty: Bool { selection.isEmpty }
    private var isBusy: Bool { activeOperation != nil }

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
        .disabled(isBusy)
        .alert(
            operationFailure?.operation.failureTitle ?? "Couldn’t Update Items",
            isPresented: Binding(
                get: { operationFailure != nil },
                set: { if !$0 { operationFailure = nil } }
            )
        ) {
            Button("Try Again") { retryFailedOperation() }
                .accessibilityIdentifier("selection.persistence.error.retry")
            Button("Keep Selection", role: .cancel) {}
                .accessibilityIdentifier("selection.persistence.error.dismiss")
        } message: {
            if let operationFailure { Text(operationFailure.message) }
        }
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
        Label(title, systemImage: symbol)
            .labelStyle(.iconOnly)
            .font(.system(size: 22, weight: .regular))
            .frame(maxWidth: .infinity)
            .frame(height: buttonHeight)
            .foregroundStyle(tint(destructive: destructive))
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
                    Button("Cancel", systemImage: "xmark") { showTagSheet = false }
                        .labelStyle(.iconOnly)
                        .tint(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "checkmark") { applyTag() }
                        .labelStyle(.iconOnly)
                        .fontWeight(.semibold)
                        .tint(.primary)
                        .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isBusy)
        .disabled(isBusy)
    }

    // MARK: Actions

    private var sectionBinding: Binding<String?> {
        Binding(get: { pendingSection }, set: { applyMoveToSection($0) })
    }

    private var activeLists: [ItemList] {
        store.lists.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }

    private func applyMoveToList(_ id: String) {
        perform(.moveToList(id))
    }

    private func applyMoveToSection(_ section: String?) {
        pendingSection = section
        perform(.moveToSection(section))
    }

    private func applyFlag() {
        perform(.flag)
    }

    private func applyTag() {
        let clean = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        perform(.addTag(clean))
    }

    private func applyDelete() {
        perform(.delete)
    }

    private func perform(_ operation: BulkOperation) {
        guard activeOperation == nil, !selection.isEmpty else { return }
        let selectedIDs = selection
        activeOperation = operation
        operationFailure = nil

        Task {
            do {
                switch operation {
                case .moveToList(let listID):
                    try await store.bulkMove(selectedIDs, toListId: listID)
                case .moveToSection(let section):
                    try await store.bulkMove(selectedIDs, toSection: section)
                case .flag:
                    try await store.bulkSetFlagged(selectedIDs, true)
                case .addTag(let tag):
                    try await store.bulkAddTag(selectedIDs, tag: tag)
                case .delete:
                    try await store.bulkSoftDelete(selectedIDs)
                }

                activeOperation = nil
                selection.removeAll()
                if case .addTag = operation {
                    newTag = ""
                    showTagSheet = false
                }
                if operation == .delete {
                    inSelectMode = false
                }
            } catch {
                activeOperation = nil
                if case .addTag = operation {
                    showTagSheet = false
                }
                operationFailure = OperationFailure(
                    operation: operation,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func retryFailedOperation() {
        guard let operation = operationFailure?.operation else { return }
        operationFailure = nil
        perform(operation)
    }
}
