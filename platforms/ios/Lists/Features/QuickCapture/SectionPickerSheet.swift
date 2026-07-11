import SwiftUI

/// Sub-sheet for choosing or creating a section. Sections are first-class on
/// `ItemList.sections`; the picker writes a `ListSection.id` (UUID string) into
/// the bound `section` field on the item being captured.
///
/// "None" clears the section. The trailing row creates a new `ListSection`
/// via the store and selects it.
struct SectionPickerSheet: View {
    let store: ItemStore
    let listId: String
    @Binding var section: String?

    @Environment(\.dismiss) private var dismiss
    @State private var newSectionName: String = ""
    @State private var isCreatingSection = false
    @State private var creationFailure: String?
    @FocusState private var newSectionFocused: Bool

    private var sections: [ListSection] {
        guard let list = store.lists.first(where: { $0.id == listId }) else { return [] }
        return list.sections.sorted { $0.position < $1.position }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        section = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("None")
                                .foregroundStyle(.primary)
                            Spacer()
                            if section == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityIdentifier("section.none")
                }

                if !sections.isEmpty {
                    Section("Sections in \(selectedListName)") {
                        ForEach(sections) { s in
                            Button {
                                section = s.id.uuidString
                                dismiss()
                            } label: {
                                HStack {
                                    Text(s.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if section == s.id.uuidString {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .accessibilityIdentifier(
                                "section.option.\(s.id.uuidString.lowercased())"
                            )
                        }
                    }
                }

                Section("New Section") {
                    HStack {
                        TextField("Name", text: $newSectionName)
                            .focused($newSectionFocused)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { commitNew() }
                            .disabled(isCreatingSection)
                            .accessibilityIdentifier("section.name")
                        if !newSectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                commitNew()
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                                    .imageScale(.large)
                            }
                            .disabled(isCreatingSection)
                            .accessibilityIdentifier("section.create")
                        }
                    }
                }
            }
            .navigationTitle("Section")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel("Cancel")
                    }
                    .tint(.primary)
                    .disabled(isCreatingSection)
                    .accessibilityIdentifier("section.cancel")
                }
            }
            .defaultFocus($newSectionFocused, sections.isEmpty && section == nil)
            .disabled(isCreatingSection)
            .alert(
                "Couldn’t Create Section",
                isPresented: Binding(
                    get: { creationFailure != nil },
                    set: { if !$0 { creationFailure = nil } }
                )
            ) {
                Button("Try Again") { commitNew() }
                    .accessibilityIdentifier("section.create.error.retry")
                Button("Not Now", role: .cancel) {}
                    .accessibilityIdentifier("section.create.error.dismiss")
            } message: {
                if let creationFailure { Text(creationFailure) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isCreatingSection)
    }

    private func commitNew() {
        let trimmed = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isCreatingSection else { return }
        let listId = self.listId
        isCreatingSection = true
        creationFailure = nil
        Task {
            do {
                guard let created = try await store.addSection(in: listId, name: trimmed) else {
                    isCreatingSection = false
                    creationFailure = "The selected list is no longer available."
                    return
                }
                isCreatingSection = false
                section = created.id.uuidString
                dismiss()
            } catch {
                isCreatingSection = false
                creationFailure = error.localizedDescription
            }
        }
    }

    private var selectedListName: String {
        store.lists.first(where: { $0.id == listId })?.name ?? "Current List"
    }
}
