import SwiftUI

struct DatabaseViewEditor: View {
    let fields: [DatabaseField]
    let onSave: (DatabaseView) async throws -> Void
    @State private var view: DatabaseView
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(view: DatabaseView, fields: [DatabaseField], onSave: @escaping (DatabaseView) async throws -> Void) {
        _view = State(initialValue: view); self.fields = fields; self.onSave = onSave
    }
    private var keys: [String] { DatabaseSchema.builtins + fields.map(\.key) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("View name", text: $view.name).accessibilityIdentifier("database.view.name")
                    Picker("Layout", selection: $view.layout) {
                        ForEach(ListViewPreferences.ViewMode.allCases, id: \.rawValue) { Label($0.label, systemImage: $0.systemImage).tag($0.rawValue) }
                    }.accessibilityIdentifier("database.view.layout")
                }
                Section("Properties") {
                    ForEach(keys, id: \.self) { key in
                        Toggle(DatabaseSchema.label(key, fields: fields), isOn: Binding(get: { view.columns.contains(key) }, set: { selected in
                            view.columns.removeAll { $0 == key }; if selected { view.columns.append(key) }
                        })).disabled(key == "title").accessibilityIdentifier("database.view.column.\(key)")
                    }
                }
                Section("Filter") {
                    if view.filters.count > 1 {
                        Picker("Match", selection: $view.matchAny) { Text("All rules").tag(false); Text("Any rule").tag(true) }
                            .accessibilityIdentifier("database.view.filter.match")
                    }
                    ForEach($view.filters) { $filter in
                        VStack(alignment: .leading) {
                            fieldPicker("Property", selection: $filter.field, identifier: "database.view.filter.field." + filter.id.uuidString.lowercased())
                            Picker("Condition", selection: $filter.operation) {
                                ForEach(filterOperations(filter.field), id: \.self) { Text(DatabaseFilter.label($0)).tag($0) }
                            }.accessibilityIdentifier("database.view.filter.operation.\(filter.id.uuidString.lowercased())")
                            if filter.operation != "empty" && filter.operation != "notEmpty" {
                                let field = fields.first { $0.key == filter.field }
                                if field?.kind == .date || filter.field == "date" {
                                    DatePicker("Value", selection: Binding(get: { ISO8601.date(from: filter.value) ?? .now },
                                        set: { filter.value = ISO8601.string(from: $0) }), displayedComponents: .date)
                                        .accessibilityIdentifier("database.view.filter.value.\(filter.id.uuidString.lowercased())")
                                } else if field?.kind == .checkbox || filter.field == "done" || filter.field == "flag" {
                                    Picker("Value", selection: $filter.value) { Text("Yes").tag("true"); Text("No").tag("false") }
                                        .accessibilityIdentifier("database.view.filter.value.\(filter.id.uuidString.lowercased())")
                                } else if let field, field.kind == .select {
                                    Picker("Value", selection: $filter.value) {
                                        Text("None").tag("")
                                        ForEach(field.options) { Text($0.name).tag($0.id.uuidString) }
                                    }.accessibilityIdentifier("database.view.filter.value.\(filter.id.uuidString.lowercased())")
                                } else {
                                    TextField("Value", text: $filter.value).accessibilityIdentifier("database.view.filter.value.\(filter.id.uuidString.lowercased())")
                                }
                            }
                        }
                        .onChange(of: filter.field) { _, key in
                            let field = fields.first { $0.key == key }
                            filter.operation = filterOperations(key).first ?? "contains"
                            filter.value = field?.kind == .date || key == "date" ? ISO8601.string(from: .now)
                                : field?.kind == .checkbox || key == "done" || key == "flag" ? "true" : ""
                        }
                    }.onDelete { view.filters.remove(atOffsets: $0) }
                    Button("Add Filter", systemImage: "plus") { view.filters.append(.init()) }
                        .accessibilityIdentifier("database.view.filter.add")
                }
                Section("Sort") {
                    ForEach($view.sorts) { $sort in
                        VStack {
                            fieldPicker("Property", selection: $sort.field, identifier: "database.view.sort.field." + sort.id.uuidString.lowercased())
                            Picker("Order", selection: $sort.ascending) { Text("Ascending").tag(true); Text("Descending").tag(false) }
                                .accessibilityIdentifier("database.view.sort.order.\(sort.id.uuidString.lowercased())")
                        }
                    }.onDelete { view.sorts.remove(atOffsets: $0) }
                    Button("Add Sort", systemImage: "plus") { view.sorts.append(.init()) }
                        .accessibilityIdentifier("database.view.sort.add")
                }
                Section("Group") {
                    Picker("Group by", selection: Binding(get: { view.groupBy ?? "" }, set: { view.groupBy = $0.isEmpty ? nil : $0 })) {
                        Text("None").tag("")
                        ForEach(["section", "type", "priority", "done", "flag"] + fields.filter { $0.kind == .select || $0.kind == .checkbox }.map(\.key), id: \.self) {
                            Text(DatabaseSchema.label($0, fields: fields)).tag($0)
                        }
                    }.accessibilityIdentifier("database.view.group")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Edit View").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly).accessibilityIdentifier("database.view.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        view.name = view.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        saving = true
                        Task {
                            defer { saving = false }
                            do { try await onSave(view); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }.labelStyle(.iconOnly).disabled(view.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                    .accessibilityIdentifier("database.view.save")
                }
            }.disabled(saving).interactiveDismissDisabled(saving)
        }.tint(ListsTokens.accent)
    }
    private func filterOperations(_ key: String) -> [String] {
        let kind = fields.first { $0.key == key }?.kind
        if kind == .date || kind == .number || key == "date" {
            return ["equals", "notEquals", "empty", "notEmpty", "greater", "less"]
        }
        if kind == .select || kind == .checkbox || key == "done" || key == "flag" {
            return ["equals", "notEquals", "empty", "notEmpty"]
        }
        return DatabaseFilter.operations
    }
    private func fieldPicker(_ title: String, selection: Binding<String>, identifier: String) -> some View {
        Picker(title, selection: selection) {
            ForEach(keys, id: \.self) { Text(DatabaseSchema.label($0, fields: fields)).tag($0) }
        }.accessibilityIdentifier(identifier)
    }
}

struct DatabaseViewManager: View {
    let store: ItemStore
    let listID: String
    let onSelect: (DatabaseView) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editingView: DatabaseView?
    @State private var editingField: DatabaseField?
    @State private var error: String?
    private var list: ItemList? { store.lists.first { $0.id == listID && $0.deletedAt == nil } }
    private var fields: [DatabaseField] { list.map { store.databaseFields(in: $0) } ?? [] }
    var body: some View {
        NavigationStack {
            List {
                if let list {
                    Section("Saved views") {
                        ForEach(list.databaseViews) { view in
                            HStack {
                                Button {
                                    onSelect(view); dismiss()
                                } label: { Label(view.name, systemImage: ListViewPreferences.ViewMode(rawValue: view.layout)?.systemImage ?? "tablecells") }
                                .accessibilityIdentifier("database.view.use.\(view.id.uuidString.lowercased())")
                                Spacer()
                                Menu {
                                    Button("Edit", systemImage: "pencil") { editingView = view }
                                        .accessibilityIdentifier("database.view.edit.\(view.id.uuidString.lowercased())")
                                    Button("Duplicate", systemImage: "doc.on.doc") {
                                        var copy = view; copy.id = UUID(); copy.name += " Copy"; editingView = copy
                                    }.accessibilityIdentifier("database.view.duplicate.\(view.id.uuidString.lowercased())")
                                    Button("Delete View", systemImage: "trash", role: .destructive) {
                                        Task {
                                            do {
                                                guard var latest = self.list else { return }
                                                latest.databaseViews.removeAll { $0.id == view.id }; try await store.updateList(latest)
                                            } catch { self.error = error.localizedDescription }
                                        }
                                    }.accessibilityIdentifier("database.view.delete.\(view.id.uuidString.lowercased())")
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                .accessibilityLabel("View options").accessibilityIdentifier("database.view.options.\(view.id.uuidString.lowercased())")
                            }
                        }
                        Button("New View", systemImage: "plus") {
                            var view = DatabaseView(); view.columns += fields.map(\.key); editingView = view
                        }.accessibilityIdentifier("database.view.add")
                    }
                    Section("Properties") {
                        ForEach(fields) { field in
                            Button { editingField = field } label: {
                                Label(field.name, systemImage: field.kind?.symbol ?? "questionmark.square")
                            }.accessibilityIdentifier("database.field.edit.\(field.key)")
                        }
                        Button("New Property", systemImage: "plus") { editingField = .init(name: "") }
                            .accessibilityIdentifier("database.field.add")
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Views & Properties").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") { dismiss() }.labelStyle(.iconOnly).accessibilityIdentifier("database.manager.done")
            } }
            .sheet(item: $editingView) { view in
                DatabaseViewEditor(view: view, fields: fields) { updated in
                    guard var list = self.list else { throw CocoaError(.fileNoSuchFile) }
                    if let index = list.databaseViews.firstIndex(where: { $0.id == updated.id }) { list.databaseViews[index] = updated }
                    else { list.databaseViews.append(updated) }
                    try await store.updateList(list)
                }
            }
            .sheet(item: $editingField) { field in
                DatabaseFieldEditor(field: field, existingFields: fields) { updated in
                    var definitions = fields
                    if let index = definitions.firstIndex(where: { $0.id == updated.id }) { definitions[index] = updated }
                    else { definitions.append(updated) }
                    try await store.saveDatabaseFields(definitions, in: listID)
                }
            }
        }.tint(ListsTokens.accent)
    }
}
