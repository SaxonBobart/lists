import SwiftUI

/// One editor is used by both document properties and table cells.
struct DatabaseValueEditor: View {
    let field: DatabaseField
    let onSave: (String) async throws -> Void
    @State private var raw: String
    @State private var error: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    init(field: DatabaseField, raw: String, onSave: @escaping (String) async throws -> Void) {
        self.field = field; self.onSave = onSave
        let initial = field.kind == .checkbox && raw.isEmpty ? "false"
            : field.kind == .select ? UUID(uuidString: raw)?.uuidString ?? raw : raw
        _raw = State(initialValue: initial)
    }
    private var selectedIDs: [UUID] {
        (try? JSONDecoder().decode([UUID].self, from: Data(raw.utf8))) ?? []
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(field.name) {
                    if field.kind == .checkbox {
                        Toggle("Checked", isOn: Binding(get: { raw == "true" }, set: { raw = $0 ? "true" : "false" }))
                            .accessibilityIdentifier("database.value.checkbox")
                    } else if field.kind == .date {
                        DatePicker("Date", selection: Binding(get: { ISO8601.date(from: raw) ?? .now },
                            set: { raw = ISO8601.string(from: $0) }), displayedComponents: .date)
                            .accessibilityIdentifier("database.value.date")
                            .onAppear { if raw.isEmpty { raw = ISO8601.string(from: .now) } }
                    } else if field.kind == .select {
                        Picker("Value", selection: $raw) {
                            Text("None").tag("")
                            ForEach(field.options) { Text($0.name).tag($0.id.uuidString) }
                        }.pickerStyle(.inline).accessibilityIdentifier("database.value.select")
                    } else if field.kind == .multiSelect {
                        ForEach(field.options) { option in
                            Toggle(option.name, isOn: Binding(get: { selectedIDs.contains(option.id) }, set: { selected in
                                var ids = selectedIDs.filter { $0 != option.id }
                                if selected { ids.append(option.id) }
                                raw = String(data: (try? JSONEncoder().encode(ids)) ?? Data(), encoding: .utf8) ?? ""
                            })).accessibilityIdentifier("database.value.option.\(option.id.uuidString.lowercased())")
                        }
                    } else if field.kind != nil {
                        TextField(field.kind == .number ? "Number" : field.kind == .url ? "https://example.com" : "Value", text: $raw, axis: .vertical)
                            .keyboardType(field.kind == .number ? .numbersAndPunctuation : field.kind == .url ? .URL : .default)
                            .textInputAutocapitalization(field.kind == .url ? .never : .sentences)
                            .accessibilityIdentifier("database.value.text")
                    } else { Text("This property type is preserved but cannot be edited in this version.") }
                }
                if !raw.isEmpty && field.kind != nil && DatabaseSchema.decode(raw, field: field) == nil {
                    Text("Enter a valid \(field.kind?.label.lowercased() ?? "property") value.").foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button("Clear Value", role: .destructive) { raw = "" }
                    .disabled(field.kind == nil).accessibilityIdentifier("database.value.clear")
            }
            .navigationTitle(field.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                        .accessibilityIdentifier("database.value.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        saving = true
                        Task {
                            defer { saving = false }
                            do { try await onSave(raw); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.labelStyle(.iconOnly)
                    .disabled(saving || field.kind == nil || (!raw.isEmpty && DatabaseSchema.decode(raw, field: field) == nil))
                    .accessibilityIdentifier("database.value.save")
                }
            }
            .disabled(saving).interactiveDismissDisabled(saving)
        }.tint(ListsTokens.accent)
    }
}

struct DatabaseFieldEditor: View {
    let existingFields: [DatabaseField]
    let isExisting: Bool
    let onSave: (DatabaseField) async throws -> Void
    @State private var field: DatabaseField
    @State private var error: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    init(field: DatabaseField = .init(name: ""), existingFields: [DatabaseField], onSave: @escaping (DatabaseField) async throws -> Void) {
        _field = State(initialValue: field); self.existingFields = existingFields
        isExisting = existingFields.contains { $0.id == field.id }; self.onSave = onSave
    }
    private var validName: Bool {
        !DatabaseSchema.normalized(field.name).isEmpty && !existingFields.contains { $0.id != field.id && DatabaseSchema.normalized($0.name) == DatabaseSchema.normalized(field.name) }
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Property name", text: $field.name).accessibilityIdentifier("database.field.name")
                Picker("Type", selection: $field.type) {
                    ForEach(DatabaseField.Kind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0.rawValue) }
                }.disabled(isExisting).accessibilityIdentifier("database.field.type")
                if isExisting { Text("Create a new property to use another type; existing values are kept.").font(.caption).foregroundStyle(.secondary) }
                if field.kind == .select || field.kind == .multiSelect {
                    Section("Options") {
                        ForEach($field.options) { $option in
                            TextField("Option", text: $option.name).accessibilityIdentifier("database.field.option.\(option.id.uuidString.lowercased())")
                        }
                        Button("Add Option", systemImage: "plus") { field.options.append(.init(name: "")) }
                            .accessibilityIdentifier("database.field.option.add")
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(isExisting ? "Edit Property" : "New Property").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly).accessibilityIdentifier("database.field.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        field.name = field.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        saving = true
                        Task {
                            defer { saving = false }
                            do { try await onSave(field); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }.labelStyle(.iconOnly)
                    .disabled(!validName || saving || field.options.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        || Set(field.options.map { DatabaseSchema.normalized($0.name) }).count != field.options.count)
                    .accessibilityIdentifier("database.field.save")
                }
            }.disabled(saving).interactiveDismissDisabled(saving)
        }.tint(ListsTokens.accent)
    }
}


struct DocumentDatabasePropertiesView: View {
    let store: ItemStore
    let itemID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var editingField: DatabaseField?
    @State private var creatingField = false
    private var item: Item? { store.item(itemID) }
    private var list: ItemList? { store.lists.first { $0.id == item?.listId && $0.deletedAt == nil } }
    private var fields: [DatabaseField] { list.map { store.databaseFields(in: $0) } ?? [] }
    var body: some View {
        NavigationStack {
            List {
                ForEach(fields) { field in
                    Button { editingField = field } label: {
                        HStack {
                            Label(field.name, systemImage: field.kind?.symbol ?? "questionmark.square")
                            Spacer()
                            if let item {
                                Text(DatabaseSchema.property(field, in: item).map { DatabaseSchema.display($0.value, field: field) } ?? "Add value")
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("document.field.choose.\(field.key)")
                }
                Button("New Property", systemImage: "plus") { creatingField = true }
                    .accessibilityIdentifier("document.field.create")
            }
            .navigationTitle("Properties").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") { dismiss() }.labelStyle(.iconOnly)
                    .accessibilityIdentifier("document.field.done")
            } }
            .sheet(item: $editingField) { field in
                DatabaseValueEditor(field: field, raw: item.flatMap { DatabaseSchema.property(field, in: $0)?.value } ?? "") { raw in
                    guard var item = store.item(itemID), item.deletedAt == nil,
                          DatabaseSchema.set(raw, field: field, in: &item) else { throw DatabaseValueError.invalidValue }
                    try await store.update(item)
                }
            }
            .sheet(isPresented: $creatingField) {
                DatabaseFieldEditor(existingFields: fields) { field in
                    guard let list else { throw CocoaError(.fileNoSuchFile) }
                    try await store.saveDatabaseFields(fields + [field], in: list.id)
                }
            }
        }.tint(ListsTokens.accent)
    }
}
