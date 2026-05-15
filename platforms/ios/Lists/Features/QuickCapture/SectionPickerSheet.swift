import SwiftUI

/// Sub-sheet for choosing or creating a section. Sections are stored as
/// free-form strings on `Item.section`; the existing-sections list comes from
/// the items already in the current list. A trailing "New section" row lets
/// the user create one inline.
struct SectionPickerSheet: View {
    @Binding var section: String?
    let existingSections: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var newSectionName: String = ""
    @FocusState private var newSectionFocused: Bool

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

                if !existingSections.isEmpty {
                    Section("Sections in this list") {
                        ForEach(existingSections, id: \.self) { name in
                            Button {
                                section = name
                                dismiss()
                            } label: {
                                HStack {
                                    Text(name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if section == name {
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
                }
            }
            .onAppear {
                if existingSections.isEmpty && section == nil {
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
        section = trimmed
        dismiss()
    }
}
