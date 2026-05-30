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
                }

                if !sections.isEmpty {
                    Section("Sections in this list") {
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
                        if !newSectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                commitNew()
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                                    .imageScale(.large)
                            }
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
                }
            }
            .onAppear {
                if sections.isEmpty && section == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        newSectionFocused = true
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func commitNew() {
        let trimmed = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let listId = self.listId
        Task {
            if let created = try? await store.addSection(in: listId, name: trimmed) {
                await MainActor.run {
                    section = created.id.uuidString
                    dismiss()
                }
            }
        }
    }
}
