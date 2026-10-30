import SwiftUI

/// Saved views are projections of existing items. They never manufacture a
/// second collection or change hierarchy just because a filter/group changes.
struct DatabaseItemsView: View {
    let store: ItemStore
    let list: ItemList
    let view: DatabaseView
    let onOpen: (Item) -> Void
    let onMove: (Item) -> Void
    let onAdd: () -> Void
    var body: some View {
        DatabaseItemsContent(store: store, list: list, view: view, onOpen: onOpen, onMove: onMove, onAdd: onAdd,
            fields: store.databaseFields(in: list),
            parents: Set(store.items.filter { $0.deletedAt == nil }.compactMap(\.parentId)))
    }
}

private struct DatabaseItemsContent: View {
    let store: ItemStore
    let list: ItemList
    let view: DatabaseView
    let onOpen: (Item) -> Void
    let onMove: (Item) -> Void
    let onAdd: () -> Void
    let fields: [DatabaseField]
    let parents: Set<UUID>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var titleWidth = 240.0
    @ScaledMetric(relativeTo: .body) private var valueWidth = 150.0
    @ScaledMetric(relativeTo: .body) private var rowHeight = 52.0
    @ScaledMetric(relativeTo: .subheadline) private var headerHeight = 44.0
    @ScaledMetric(relativeTo: .caption) private var errorHeight = 100.0
    @State private var collapsed = Set<UUID>()
    @State private var lingering: [UUID: UUID] = [:]
    @State private var valueDrafts = DatabaseValueDraftCache()
    @State private var editing: Cell?
    @State private var failure: String?
    private struct Cell: Identifiable { let itemID: UUID; let key: String; var id: String { itemID.uuidString + key } }
    private struct Group: Identifiable { let id: String; let title: String; let rows: [DatabaseQuery.Row] }
    private var rows: [DatabaseQuery.Row] { DatabaseQuery.rows(items: store.items, view: view, list: list, fields: fields, collapsed: collapsed, retaining: Set(lingering.keys)) }
    private var keys: [String] { ["title"] + view.columns.filter { key in key != "title" && (DatabaseSchema.builtins.contains(key) || fields.contains(where: { $0.key == key })) } }
    private var groups: [Group] {
        guard let groupBy = view.groupBy else { return [.init(id: "", title: "", rows: rows)] }
        var grouped: [String: [DatabaseQuery.Row]] = [:]
        var current = ""
        for row in rows {
            if row.depth == 0 {
                current = groupBy == "section" ? row.item.section ?? "" : DatabaseSchema.raw(groupBy, item: row.item, list: list, fields: fields)
            }
            grouped[current, default: []].append(row)
        }
        var order: [String] = []
        if groupBy == "section" { order = list.sections.sorted { $0.position < $1.position }.map { $0.id.uuidString } }
        else if let field = fields.first(where: { $0.key == groupBy }), field.kind == .select { order = field.options.map { $0.id.uuidString } }
        else if groupBy == "type" { order = Item.ItemType.compactMenuOrder.map(\.rawValue) }
        for key in grouped.keys.sorted() where !order.contains(key) { order.append(key) }
        if !order.contains("") { order.append("") }
        return order.map { key in
            let title: String
            if key.isEmpty { title = "No " + DatabaseSchema.label(groupBy, fields: fields) }
            else if groupBy == "section" { title = list.sections.first { $0.id.uuidString == key }?.name ?? "Unavailable section" }
            else if let field = fields.first(where: { $0.key == groupBy }) { title = DatabaseSchema.display(key, field: field) }
            else { title = key.capitalized }
            return Group(id: key, title: title, rows: grouped[key] ?? [])
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            if view.layout == "columns" { board }
            else if view.layout == "list" { listContent }
            else { table }
            HStack {
                Text("\(rows.filter { !$0.isContext }.count) items").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Button(action: onAdd) {
                    if dynamicTypeSize.isAccessibilitySize { Image(systemName: "plus").frame(width: 44, height: 44) }
                    else { Label("New Item", systemImage: "plus") }
                }.accessibilityLabel("New Item").frame(minHeight: 44)
                    .accessibilityIdentifier("database.item.add")
            }.padding(.horizontal, 16).background(Color(.systemBackground))
        }
        .sheet(item: $editing) { cell in cellEditor(cell).presentationDetents([.medium, .large]) }
        .itemMutationErrorAlert($failure)
        .accessibilityIdentifier("database.\(view.layout)")
    }
    private var tableLines: [DatabaseTableLine] {
        // Draft validation changes row sizing only when an error appears.
        _ = valueDrafts.sizingRevision
        return groups.flatMap { group in
            var lines: [DatabaseTableLine] = []
            if !group.title.isEmpty { lines.append(.init(id: "group." + group.id, title: group.title, row: nil)) }
            lines += group.rows.map { row in
                let hasError = fields.contains { field in
                    valueDrafts.existingDraft(for: row.id.uuidString + field.key)?.error != nil
                }
                return .init(id: row.id.uuidString, title: nil, row: row, minimumHeight: hasError ? rowHeight + errorHeight : nil)
            }
            return lines
        }
    }
    private var table: some View {
        BoundedDatabaseTable(lines: tableLines, keys: keys, fields: fields,
            contentWidth: titleWidth + CGFloat(max(0, keys.count - 1)) * valueWidth,
            rowHeight: rowHeight, headerHeight: headerHeight,
            dynamicTypeSize: dynamicTypeSize, colorScheme: colorScheme) {
                HStack(spacing: 0) {
                    ForEach(keys, id: \.self) { key in
                        Label(DatabaseSchema.label(key, fields: fields), systemImage: headerSymbol(key))
                            .font(.subheadline.weight(.semibold)).lineLimit(1)
                            .padding(.horizontal, 12).frame(width: key == "title" ? titleWidth : valueWidth, height: headerHeight, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading).background(Color(.secondarySystemBackground))
            } rowContent: { line in
                if let row = line.row {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(keys, id: \.self) { key in
                                cell(row, key: key).frame(width: key == "title" ? titleWidth : valueWidth, alignment: .leading).clipped()
                            }
                            Spacer(minLength: 0)
                        }.frame(maxHeight: .infinity)
                        Divider()
                    }.opacity(row.isContext ? 0.65 : 1)
                } else {
                    Text(line.title ?? "").font(.headline).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).background(Color(.secondarySystemBackground))
                }
            }
    }
    private func headerSymbol(_ key: String) -> String {
        if let field = fields.first(where: { $0.key == key }) { return field.kind?.symbol ?? "questionmark.square" }
        switch key {
        case "title": return "textformat"
        case "type": return "square.stack"
        case "date": return "calendar"
        case "done": return "checkmark.circle"
        case "flag": return "flag"
        case "priority": return "exclamationmark"
        case "tags": return "number"
        case "section": return "rectangle.3.group"
        default: return "text.alignleft"
        }
    }
    private var listContent: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        itemRow(row).padding(.leading, CGFloat(row.depth) * 20)
                    }
                } header: { if !group.title.isEmpty { Text(group.title) } }
            }
        }.listStyle(.plain)
    }
    private var board: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(group.title.isEmpty ? list.name : group.title).font(.headline).padding(12)
                        Divider()
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(group.rows) { row in itemRow(row).padding(.horizontal, 10).draggable(row.item.id.uuidString) }
                            }.frame(maxWidth: .infinity, minHeight: 120, alignment: .top)
                        }
                    }
                    .frame(width: 280).frame(maxHeight: .infinity)
                    .background(Color(.secondarySystemBackground).opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    .dropDestination(for: String.self, isEnabled: view.groupBy != nil) { values, _ in _ = move(values.first, to: group.id) }
                    .accessibilityIdentifier("database.group.\(group.id.isEmpty ? "none" : group.id.lowercased())")
                }
            }.padding(12)
        }
    }
    private func itemRow(_ row: DatabaseQuery.Row) -> some View {
        ItemRow(item: row.item, isOverdue: row.item.isOverdue(), store: store,
            onToggle: { toggleCompletion(row) },
            onMutationFailure: { failure = $0 }, onShowDetail: onOpen, onMoveItem: { onMove(row.item) })
            .opacity(row.isContext ? 0.65 : 1)
            .accessibilityIdentifier("database.item.\(row.id.uuidString.lowercased())")
    }
    @ViewBuilder private func cell(_ row: DatabaseQuery.Row, key: String) -> some View {
        if key == "title" {
            HStack(spacing: 8) {
                if row.item.type != .note {
                    ItemRowLeadingControl(item: row.item, onToggle: { toggleCompletion(row) }, onShowDetail: { onOpen(row.item) }, onEditEventTime: { editing = Cell(itemID: row.id, key: "date") },
                        eventShowsCompletion: false)
                }
                Button { onOpen(row.item) } label: {
                    Text(row.item.title.isEmpty ? "Untitled" : row.item.title).lineLimit(2).fixedSize(horizontal: false, vertical: true).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain).accessibilityIdentifier("database.open.\(row.id.uuidString.lowercased())")
                if parents.contains(row.id) {
                    Button {
                        if collapsed.contains(row.id) { collapsed.remove(row.id) } else { collapsed.insert(row.id) }
                    } label: { Image(systemName: collapsed.contains(row.id) ? "chevron.right" : "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 44, height: 44) }
                    .accessibilityLabel(collapsed.contains(row.id) ? "Expand subitems" : "Collapse subitems")
                    .accessibilityIdentifier("database.expand.\(row.id.uuidString.lowercased())")
                }
            }.padding(.leading, 12 + CGFloat(min(row.depth, 4)) * 16).padding(.trailing, 8)
        } else if let field = fields.first(where: { $0.key == key }) {
            DatabasePropertyValue(field: field, value: DatabaseSchema.property(field, in: row.item)?.value ?? "",
                identifier: "database.cell." + row.id.uuidString.lowercased() + "." + key,
                draft: valueDrafts.draft(for: row.id.uuidString + key, value: DatabaseSchema.property(field, in: row.item)?.value ?? ""),
                onSave: { raw in try await store.updateDatabaseValue(raw, field: field, itemID: row.id) },
                onEdit: { raw in store.applyDatabaseValueSync(raw, field: field, itemID: row.id) },
                onSaveDefinition: { updated in
                    guard let current = store.lists.first(where: { $0.id == list.id }) else { throw DatabaseValueError.invalidValue }
                    var definitions = store.databaseFields(in: current)
                    if let index = definitions.firstIndex(where: { $0.id == updated.id }) { definitions[index] = updated }
                    try await store.saveDatabaseFields(definitions, in: list.id)
                })
                .padding(.horizontal, 12)
                .disabled(row.item.hasCustomPropertyStorageConflict)
        } else if key == "flag" || key == "done" {
            Button {
                if key == "done" { toggleCompletion(row); return }
                Task {
                    do {
                        if let latest = store.item(row.id) { var updated = latest; updated.flagged.toggle(); try await store.update(updated) }
                    } catch { failure = error.localizedDescription }
                }
            } label: {
                Image(systemName: key == "flag" ? (row.item.flagged ? "flag.fill" : "flag") : (row.item.isComplete ? "checkmark.square.fill" : "square"))
                    .foregroundStyle(key == "flag" && row.item.flagged ? Color.orange : Color.secondary)
                    .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain).disabled(key == "done" && !(row.item.type == .task || (row.item.type == .event && row.item.completable)))
                .accessibilityLabel(key == "flag" ? "Flag" : "Completion")
                .accessibilityIdentifier("database.cell." + row.id.uuidString.lowercased() + "." + key)
        } else {
            Button { editing = Cell(itemID: row.id, key: key) } label: {
                Text(display(key, item: row.item)).lineLimit(2).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("database.cell.\(row.id.uuidString.lowercased()).\(key)")
        }
    }
    private func toggleCompletion(_ row: DatabaseQuery.Row) {
        let token = UUID()
        if !row.item.isComplete { lingering[row.id] = token }
        else { lingering.removeValue(forKey: row.id) }
        Task {
            do {
                try await store.toggleDone(row.id)
                try? await Task.sleep(for: .seconds(1.5))
            } catch { failure = error.localizedDescription }
            if lingering[row.id] == token { lingering.removeValue(forKey: row.id) }
        }
    }

    private func display(_ key: String, item: Item) -> String {
        let raw = DatabaseSchema.raw(key, item: item, list: list, fields: fields)
        if raw.isEmpty { return "—" }
        if let field = fields.first(where: { $0.key == key }) { return DatabaseSchema.display(raw, field: field) }
        if key == "date", let due = item.due { return due.formatted(date: .abbreviated, time: .omitted) }
        if key == "done" || key == "flag" { return raw == "true" ? "Yes" : "No" }
        return raw.capitalized
    }
    @ViewBuilder private func cellEditor(_ cell: Cell) -> some View {
        if let item = store.item(cell.itemID), let field = fields.first(where: { $0.key == cell.key }) {
            DatabaseValueEditor(field: field, raw: DatabaseSchema.property(field, in: item)?.value ?? "") { raw in
                guard var latest = store.item(cell.itemID), latest.deletedAt == nil,
                      DatabaseSchema.set(raw, field: field, in: &latest) else { throw DatabaseValueError.invalidValue }
                try await store.update(latest)
            }
        } else if let item = store.item(cell.itemID), cell.key == "date" {
            InlineDateTimePopover(item: item, store: store)
        } else if let item = store.item(cell.itemID) {
            DatabaseBuiltinEditor(store: store, item: item, key: cell.key, onOpen: onOpen)
        }
    }
    private func move(_ rawID: String?, to group: String) -> Bool {
        guard let rawID, let id = UUID(uuidString: rawID), let item = store.item(id), item.listId == list.id,
              let groupBy = view.groupBy else { return false }
        if groupBy == "section" {
            return store.applyMoveSync(itemId: id, toListId: list.id, parentId: nil, sectionOverride: .some(group.isEmpty ? nil : group))
        }
        guard item.parentId == nil else { return false }
        var updated = item
        if groupBy == "type", let type = Item.ItemType(rawValue: group) {
            ItemTypeTransition.apply(type, to: &updated); return store.applyUpdateSync(updated)
        }
        if groupBy == "priority", let priority = Item.Priority(rawValue: group) {
            updated.priority = priority; return store.applyUpdateSync(updated)
        }
        if groupBy == "flag" { updated.flagged = group == "true"; return store.applyUpdateSync(updated) }
        if groupBy == "done", !group.isEmpty {
            if item.isComplete != (group == "true") {
                Task { do { try await store.toggleDone(id) } catch { failure = error.localizedDescription } }
            }
            return true
        }
        guard let field = fields.first(where: { $0.key == groupBy }), field.kind == .select || field.kind == .checkbox else { return false }
        var latest = item
        guard DatabaseSchema.set(group, field: field, in: &latest) else { return false }
        store.applyUpdateSync(latest)
        return true
    }
}

private struct DatabaseBuiltinEditor: View {
    let store: ItemStore
    let item: Item
    let key: String
    let onOpen: (Item) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var tags: [String]
    init(store: ItemStore, item: Item, key: String, onOpen: @escaping (Item) -> Void) {
        self.store = store; self.item = item; self.key = key; self.onOpen = onOpen
        _tags = State(initialValue: item.tags)
    }
    var body: some View {
        NavigationStack {
            Form {
                if key == "tags" {
                    TagInputView(tags: $tags).accessibilityIdentifier("database.builtin.tags")
                    Button("Save Tags") { update { $0.tags = tags } }.accessibilityIdentifier("database.builtin.tags.save")
                } else if key == "section", item.parentId == nil {
                    Button("No Section") { moveToSection(nil) }.accessibilityIdentifier("database.builtin.section.none")
                    ForEach(store.lists.first(where: { $0.id == item.listId })?.sections ?? []) { section in
                        Button(section.name) { moveToSection(section.id.uuidString) }
                            .accessibilityIdentifier("database.builtin.section.\(section.id.uuidString.lowercased())")
                    }
                } else if key == "type" {
                    ForEach(Item.ItemType.compactMenuOrder, id: \.self) { type in
                        Button(type.documentDisplayName) { update { ItemTypeTransition.apply(type, to: &$0) } }
                            .accessibilityIdentifier("database.builtin.type.\(type.rawValue)")
                    }
                } else if key == "done" || key == "flag" {
                    Button(key == "done" ? "Toggle Completion" : "Toggle Flag") {
                        if key == "flag" { update { $0.flagged.toggle() } }
                        else { Task { do { try await store.toggleDone(item.id); dismiss() } catch { self.error = error.localizedDescription } } }
                    }.accessibilityIdentifier("database.builtin.toggle")
                } else if key == "priority" {
                    ForEach(Item.Priority.allCases, id: \.self) { priority in
                        Button(priority.displayName) { update { $0.priority = priority } }
                            .accessibilityIdentifier("database.builtin.priority.\(priority.rawValue)")
                    }
                } else {
                    Button("Edit in Document") { dismiss(); onOpen(store.item(item.id) ?? item) }
                        .accessibilityIdentifier("database.builtin.document")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(key.capitalized).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly).accessibilityIdentifier("database.builtin.cancel")
            } }
        }
    }
    private func moveToSection(_ section: String?) {
        if store.applyMoveSync(itemId: item.id, toListId: item.listId, parentId: nil, sectionOverride: .some(section)) { dismiss() }
    }
    private func update(_ transform: (inout Item) -> Void) {
        guard var latest = store.item(item.id), latest.deletedAt == nil else { return }
        transform(&latest)
        let updated = latest
        Task { do { try await store.update(updated); dismiss() } catch { self.error = error.localizedDescription } }
    }
}
