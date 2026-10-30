import SwiftUI

/// Retain invalid/failed input and serialize rapid live changes in user order.
@MainActor @Observable final class DatabaseValueDraft {
    var raw: String
    var error: String? {
        didSet { if (oldValue == nil) != (error == nil) { onErrorVisibilityChanged() } }
    }
    @ObservationIgnored var onErrorVisibilityChanged: () -> Void = {}
    private(set) var pendingSaves = 0
    @ObservationIgnored private var lastSave: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    init(raw: String) { self.raw = raw }

    func edit(_ value: String, field: DatabaseField, using onEdit: @MainActor (String) -> Bool) {
        raw = value
        generation &+= 1
        // Intermediate number/URL input stays local until it is valid.
        guard value.isEmpty || DatabaseSchema.decode(value, field: field) != nil else { error = nil; return }
        error = onEdit(value) ? nil : DatabaseValueError.itemUnavailable.localizedDescription
    }

    @discardableResult
    func validate(field: DatabaseField) -> Bool {
        guard raw.isEmpty || DatabaseSchema.decode(raw, field: field) != nil else {
            error = "Enter a valid \(field.kind?.label.lowercased() ?? "property") value."
            return false
        }
        return true
    }

    func save(_ value: String, field: DatabaseField,
              using onSave: @escaping @MainActor (String) async throws -> Void,
              onSuccess: @escaping @MainActor () -> Void = {}) {
        raw = value
        generation &+= 1
        let version = generation
        guard value.isEmpty || DatabaseSchema.decode(value, field: field) != nil else {
            error = "Enter a valid \(field.kind?.label.lowercased() ?? "property") value."
            return
        }
        error = nil
        pendingSaves += 1
        let previous = lastSave
        lastSave = Task {
            await previous?.value
            defer { pendingSaves -= 1 }
            do {
                try await onSave(value)
                if generation == version { error = nil; onSuccess() }
            } catch {
                if generation == version { self.error = error.localizedDescription }
            }
        }
    }

    func finishSaving() async { await lastSave?.value }
    func receive(_ value: String, editing: Bool) {
        if !editing && pendingSaves == 0 && error == nil { raw = value }
    }
}

/// Keep editing state and invalid drafts when native cells leave the viewport.
@MainActor @Observable final class DatabaseValueDraftCache {
    @ObservationIgnored private var values: [String: DatabaseValueDraft] = [:]
    private(set) var sizingRevision = 0
    func existingDraft(for key: String) -> DatabaseValueDraft? { values[key] }
    func draft(for key: String, value: String) -> DatabaseValueDraft {
        if let value = values[key] { return value }
        let draft = DatabaseValueDraft(raw: value)
        draft.onErrorVisibilityChanged = { [weak self] in self?.sizingRevision &+= 1 }
        values[key] = draft
        return draft
    }
}

/// Shared by document rows and table cells. Simple values edit in place.
struct DatabasePropertyValue: View {
    let field: DatabaseField
    let value: String
    let identifier: String
    let onSave: @MainActor (String) async throws -> Void
    var onEdit: (@MainActor (String) -> Bool)?
    var onSaveDefinition: (@MainActor (DatabaseField) async throws -> Void)?
    var onBeginEditing: () -> Void = {}
    @State private var draft: DatabaseValueDraft
    @State private var showingPicker = false
    @FocusState private var focused: Bool

    init(field: DatabaseField, value: String, identifier: String, draft: DatabaseValueDraft? = nil,
         onSave: @escaping @MainActor (String) async throws -> Void,
         onEdit: (@MainActor (String) -> Bool)? = nil,
         onSaveDefinition: (@MainActor (DatabaseField) async throws -> Void)? = nil,
         onBeginEditing: @escaping () -> Void = {}) {
        self.field = field; self.value = value; self.identifier = identifier
        self.onSave = onSave; self.onEdit = onEdit; self.onSaveDefinition = onSaveDefinition; self.onBeginEditing = onBeginEditing
        _draft = State(initialValue: draft ?? DatabaseValueDraft(raw: value))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            valueControl
            if let error = draft.error {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
                Button("Retry") {
                    if let onEdit { draft.edit(draft.raw, field: field, using: onEdit); draft.validate(field: field) }
                    else { draft.save(draft.raw, field: field, using: onSave) }
                }
                    .accessibilityIdentifier(identifier + ".retry")
            }
        }
        .onChange(of: value) { _, value in draft.receive(value, editing: focused) }
        .onChange(of: focused) { _, focused in
            if focused { onBeginEditing() }
            else if onEdit != nil { draft.validate(field: field) }
            else if draft.raw != value { draft.save(draft.raw, field: field, using: onSave) }
        }
        .contextMenu {
            if field.kind != nil {
                Button("Clear Value", systemImage: "minus.circle", role: .destructive) {
                    draft.save("", field: field, using: onSave)
                }.accessibilityIdentifier(identifier + ".clear")
            }
        }
    }

    @ViewBuilder private var valueControl: some View {
        if field.kind == .checkbox {
            Button {
                onBeginEditing()
                draft.save(draft.raw == "true" ? "false" : "true", field: field, using: onSave)
            } label: {
                Image(systemName: draft.raw == "true" ? "checkmark.square.fill" : "square")
                    .font(.body).frame(minWidth: 44, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain).foregroundStyle(draft.raw == "true" ? Color.blue : Color.secondary)
            .accessibilityLabel(field.name).accessibilityValue(draft.raw == "true" ? "Checked" : "Unchecked")
            .accessibilityIdentifier(identifier)
        } else if field.kind == .text || field.kind == .number || field.kind == .url {
            TextField("Empty", text: Binding(get: { draft.raw }, set: {
                if let onEdit { draft.edit($0, field: field, using: onEdit) }
                else { draft.raw = $0 }
            }), axis: field.kind == .text ? .vertical : .horizontal)
                .focused($focused).textFieldStyle(.plain).font(.subheadline)
                .keyboardType(field.kind == .number ? .numbersAndPunctuation : field.kind == .url ? .URL : .default)
                .textInputAutocapitalization(field.kind == .url ? .never : .sentences)
                .autocorrectionDisabled(field.kind != .text)
                .submitLabel(field.kind == .text ? .return : .done).lineLimit(1...2).frame(minHeight: 44)
                .onSubmit { focused = false }
                .accessibilityLabel(field.name).accessibilityIdentifier(identifier)
        } else if field.kind != nil {
            Button {
                onBeginEditing(); showingPicker = true
            } label: {
                DatabaseValueLabel(field: field, raw: draft.raw)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(field.name)
            .accessibilityValue(DatabaseSchema.display(draft.raw, field: field))
            .accessibilityIdentifier(identifier)
            .popover(isPresented: $showingPicker) {
                DatabaseValueEditor(field: field, raw: draft.raw, draft: draft, onSave: onSave, onSaveDefinition: onSaveDefinition)
                    .presentationCompactAdaptation(.sheet)
            }
        } else {
            Text(value.isEmpty ? "Empty" : value).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

struct DatabaseValueLabel: View {
    let field: DatabaseField
    let raw: String
    var body: some View {
        if field.kind == .select || field.kind == .multiSelect {
            let selected: [UUID] = field.kind == .select ? UUID(uuidString: raw).map { [$0] } ?? []
                : (try? JSONDecoder().decode([UUID].self, from: Data(raw.utf8))) ?? []
            if selected.isEmpty { Text("Empty").foregroundStyle(.tertiary) }
            else {
                WrapLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(selected, id: \.self) { id in
                        Text(field.options.first { $0.id == id }?.name ?? "Unavailable option")
                            .font(.subheadline).padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        } else { Text(raw.isEmpty ? "Empty" : DatabaseSchema.display(raw, field: field)).font(.subheadline).foregroundStyle(.secondary) }
    }
}

/// One contextual picker, with live changes and errors kept beside the value.
struct DatabaseValueEditor: View {
    @State private var field: DatabaseField
    @State private var draft: DatabaseValueDraft
    @State private var newOption = ""
    @State private var addingOption = false
    @State private var optionError: String?
    let onSave: @MainActor (String) async throws -> Void
    var onSaveDefinition: (@MainActor (DatabaseField) async throws -> Void)?
    @Environment(\.dismiss) private var dismiss
    init(field: DatabaseField, raw: String, draft: DatabaseValueDraft? = nil,
         onSave: @escaping @MainActor (String) async throws -> Void,
         onSaveDefinition: (@MainActor (DatabaseField) async throws -> Void)? = nil) {
        _field = State(initialValue: field); _draft = State(initialValue: draft ?? DatabaseValueDraft(raw: raw))
        self.onSave = onSave; self.onSaveDefinition = onSaveDefinition
    }
    private var selectedIDs: [UUID] {
        if field.kind == .select { return UUID(uuidString: draft.raw).map { [$0] } ?? [] }
        return (try? JSONDecoder().decode([UUID].self, from: Data(draft.raw.utf8))) ?? []
    }
    var body: some View {
        NavigationStack {
            Form {
                if field.kind == .select || field.kind == .multiSelect {
                    if !selectedIDs.isEmpty {
                        Section {
                            WrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                                ForEach(selectedIDs, id: \.self) { id in
                                    Button { toggle(id) } label: {
                                        HStack(spacing: 6) {
                                            Text(field.options.first { $0.id == id }?.name ?? "Unavailable option")
                                            Image(systemName: "xmark").font(.caption)
                                        }
                                        .fixedSize().padding(.horizontal, 8).padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                                        .frame(minHeight: 44)
                                    }.buttonStyle(.plain).accessibilityLabel("Remove selected option")
                                        .accessibilityIdentifier("database.value.selected." + id.uuidString.lowercased())
                                }
                            }
                        }
                    }
                    Section("Options") {
                        ForEach(field.options) { option in
                            Button { toggle(option.id) } label: {
                                HStack {
                                    Text(option.name).foregroundStyle(.primary)
                                    Spacer()
                                    if selectedIDs.contains(option.id) { Image(systemName: "checkmark").foregroundStyle(.blue) }
                                }.frame(minHeight: 36).contentShape(Rectangle())
                            }.accessibilityIdentifier("database.value.option." + option.id.uuidString.lowercased())
                        }
                        if onSaveDefinition != nil {
                            HStack {
                                TextField("New option", text: $newOption).accessibilityIdentifier("database.value.option.name")
                                Button("Add", systemImage: "plus", action: addOption)
                                    .labelStyle(.iconOnly).disabled(newOption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || addingOption)
                                    .accessibilityIdentifier("database.value.option.add")
                            }
                        }
                    }
                } else if field.kind == .date {
                    if draft.raw.isEmpty {
                        Button("Use Today") { draft.save(ISO8601.string(from: .now), field: field, using: onSave) }
                            .accessibilityIdentifier("database.value.date.today")
                    }
                    DatePicker("Date", selection: Binding(get: { ISO8601.date(from: draft.raw) ?? .now }, set: {
                        draft.save(ISO8601.string(from: $0), field: field, using: onSave)
                    }), displayedComponents: .date)
                    .datePickerStyle(.graphical).accessibilityIdentifier("database.value.date")
                }
                if let optionError {
                    Section {
                        Text(optionError).foregroundStyle(.red)
                        Button("Retry Adding Option", action: addOption).accessibilityIdentifier("database.value.option.retry")
                    }
                }
                if let error = draft.error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("Retry") { draft.save(draft.raw, field: field, using: onSave) }
                            .accessibilityIdentifier("database.value.retry")
                    }
                }
                Button("Clear Value", role: .destructive) {
                    draft.save("", field: field, using: onSave, onSuccess: { dismiss() })
                }.accessibilityIdentifier("database.value.clear")
            }
            .navigationTitle(field.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") { dismiss() }.labelStyle(.iconOnly)
                    .disabled(draft.pendingSaves > 0 || addingOption).accessibilityIdentifier("database.value.done")
            } }
        }
        .tint(.blue).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .interactiveDismissDisabled(draft.pendingSaves > 0 || addingOption)
    }
    private func toggle(_ id: UUID) {
        if field.kind == .select {
            let raw = selectedIDs.contains(id) ? "" : id.uuidString
            draft.save(raw, field: field, using: onSave, onSuccess: { dismiss() })
        } else {
            var ids = selectedIDs.filter { $0 != id }
            if !selectedIDs.contains(id) { ids.append(id) }
            guard let bytes = try? JSONEncoder().encode(ids), let raw = String(data: bytes, encoding: .utf8) else { return }
            draft.save(raw, field: field, using: onSave)
        }
    }
    private func addOption() {
        guard let onSaveDefinition else { return }
        let name = newOption.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = field.options.first(where: { DatabaseSchema.normalized($0.name) == DatabaseSchema.normalized(name) }) {
            newOption = ""; toggle(existing.id); return
        }
        addingOption = true
        optionError = nil
        let option = DatabaseOption(name: name)
        var updated = field; updated.options.append(option)
        Task {
            defer { addingOption = false }
            do { try await onSaveDefinition(updated); field = updated; newOption = ""; toggle(option.id) }
            catch { optionError = error.localizedDescription }
        }
    }
}

/// Name, type, options and an optional first value all live in one creation sheet.
struct DatabaseFieldEditor: View {
    let existingFields: [DatabaseField]
    let isExisting: Bool
    let includesInitialValue: Bool
    let onSave: @MainActor (DatabaseField, String) async throws -> Void
    @State private var field: DatabaseField
    @State private var raw = ""
    @State private var error: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    init(field: DatabaseField = .init(name: ""), existingFields: [DatabaseField],
         onSave: @escaping @MainActor (DatabaseField) async throws -> Void) {
        _field = State(initialValue: field); self.existingFields = existingFields
        isExisting = existingFields.contains { $0.id == field.id }; includesInitialValue = false
        self.onSave = { field, _ in try await onSave(field) }
    }
    init(existingFields: [DatabaseField], onCreate: @escaping @MainActor (DatabaseField, String) async throws -> Void) {
        _field = State(initialValue: DatabaseField(name: "")); self.existingFields = existingFields
        isExisting = false; includesInitialValue = true; onSave = onCreate
    }
    private var valid: Bool {
        let hasOptions = field.kind == .select || field.kind == .multiSelect
        return !DatabaseSchema.normalized(field.name).isEmpty
            && !existingFields.contains { $0.id != field.id && DatabaseSchema.normalized($0.name) == DatabaseSchema.normalized(field.name) }
            && (!hasOptions || (!field.options.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                && Set(field.options.map { DatabaseSchema.normalized($0.name) }).count == field.options.count))
            && (raw.isEmpty || DatabaseSchema.decode(raw, field: field) != nil)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: field.kind?.symbol ?? "questionmark.square").foregroundStyle(.secondary)
                        TextField("Property name", text: $field.name).accessibilityIdentifier("database.field.name")
                    }
                    Picker("Type", selection: $field.type) {
                        ForEach(DatabaseField.Kind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0.rawValue) }
                    }.pickerStyle(.menu).disabled(isExisting).accessibilityIdentifier("database.field.type")
                    if isExisting { Text("Existing values keep their property type.").font(.caption).foregroundStyle(.secondary) }
                }
                if field.kind == .select || field.kind == .multiSelect {
                    Section("Options") {
                        ForEach($field.options) { $option in
                            HStack {
                                TextField("Option", text: $option.name).accessibilityIdentifier("database.field.option." + option.id.uuidString.lowercased())
                                Button("Remove option", systemImage: "minus.circle", role: .destructive) { removeOption(option.id) }
                                    .labelStyle(.iconOnly).accessibilityIdentifier("database.field.option.remove." + option.id.uuidString.lowercased())
                            }
                        }
                        Button("Add Option", systemImage: "plus") { field.options.append(.init(name: "")) }
                            .accessibilityIdentifier("database.field.option.add")
                    }
                }
                if includesInitialValue { Section("Initial value") { initialValueControl } }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(isExisting ? "Edit Property" : "New Property").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly).accessibilityIdentifier("database.field.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isExisting ? "Save" : "Create", systemImage: "checkmark", action: save)
                        .labelStyle(.iconOnly).disabled(!valid || saving).accessibilityIdentifier("database.field.save")
                }
            }.disabled(saving).interactiveDismissDisabled(saving)
        }
        .tint(.blue).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    @ViewBuilder private var initialValueControl: some View {
        if field.kind == .checkbox {
            Toggle("Checked", isOn: Binding(get: { raw == "true" }, set: { raw = $0 ? "true" : "false" }))
                .accessibilityIdentifier("database.field.initial.checkbox")
        } else if field.kind == .date {
            Toggle("Include date", isOn: Binding(get: { !raw.isEmpty }, set: { raw = $0 ? ISO8601.string(from: .now) : "" }))
                .accessibilityIdentifier("database.field.initial.hasdate")
            if !raw.isEmpty {
                DatePicker("Date", selection: Binding(get: { ISO8601.date(from: raw) ?? .now }, set: { raw = ISO8601.string(from: $0) }), displayedComponents: .date)
                    .accessibilityIdentifier("database.field.initial.date")
            }
        } else if field.kind == .select || field.kind == .multiSelect {
            ForEach(field.options) { option in
                Button {
                    if field.kind == .select { raw = raw == option.id.uuidString ? "" : option.id.uuidString }
                    else {
                        var selected = (try? JSONDecoder().decode([UUID].self, from: Data(raw.utf8))) ?? []
                        if selected.contains(option.id) { selected.removeAll { $0 == option.id } } else { selected.append(option.id) }
                        raw = String(decoding: (try? JSONEncoder().encode(selected)) ?? Data(), as: UTF8.self)
                    }
                } label: {
                    HStack { Text(option.name); Spacer(); if raw.contains(option.id.uuidString) { Image(systemName: "checkmark") } }
                }.accessibilityIdentifier("database.field.initial.option." + option.id.uuidString.lowercased())
            }
        } else {
            TextField("Empty", text: $raw).keyboardType(field.kind == .number ? .numbersAndPunctuation : field.kind == .url ? .URL : .default)
                .textInputAutocapitalization(field.kind == .url ? .never : .sentences)
                .accessibilityIdentifier("database.field.initial.text")
        }
    }
    private func removeOption(_ id: UUID) {
        field.options.removeAll { $0.id == id }
        if field.kind == .select && UUID(uuidString: raw) == id { raw = "" }
        if field.kind == .multiSelect, let selected = try? JSONDecoder().decode([UUID].self, from: Data(raw.utf8)) {
            raw = String(decoding: (try? JSONEncoder().encode(selected.filter { $0 != id })) ?? Data(), as: UTF8.self)
        }
    }
    private func save() {
        field.name = field.name.trimmingCharacters(in: .whitespacesAndNewlines)
        saving = true
        Task {
            defer { saving = false }
            do { try await onSave(field, raw); dismiss() } catch { self.error = error.localizedDescription }
        }
    }
}

struct DocumentDatabasePropertiesView: View {
    let store: ItemStore
    let itemID: UUID
    private var item: Item? { store.item(itemID) }
    private var list: ItemList? { store.lists.first { $0.id == item?.listId && $0.deletedAt == nil } }
    private var fields: [DatabaseField] { list.map { store.databaseFields(in: $0) } ?? [] }
    var body: some View {
        DatabaseFieldEditor(existingFields: fields, onCreate: { field, raw in
            guard let list else { throw CocoaError(.fileNoSuchFile) }
            var definitions = fields
            if let index = definitions.firstIndex(where: { $0.id == field.id }) { definitions[index] = field }
            else { definitions.append(field) }
            try await store.saveDatabaseFields(definitions, in: list.id)
            if !raw.isEmpty { try await store.updateDatabaseValue(raw, field: field, itemID: itemID) }
        })
    }
}
