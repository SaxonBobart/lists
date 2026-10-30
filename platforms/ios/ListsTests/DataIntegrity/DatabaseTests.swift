import Foundation
import Testing
import Yams
@testable import Lists

struct DatabaseTests {
    @Test func typedValuesValidateWithoutCoercingLegacyText() throws {
        let number = DatabaseField(name: "Estimate", kind: .number)
        #expect(DatabaseSchema.decode("12.5", field: number) == .number(Decimal(string: "12.5")!))
        #expect(DatabaseSchema.decode("12oops", field: number) == nil)
        #expect(DatabaseSchema.decode("NaN", field: number) == nil)
        #expect(DatabaseSchema.decode("true", field: .init(name: "Approved", kind: .checkbox)) == .checkbox(true))
        #expect(DatabaseSchema.decode("yes", field: .init(name: "Approved", kind: .checkbox)) == nil)
        let option = DatabaseOption(name: "In Progress")
        let select = DatabaseField(name: "Status", kind: .select, options: [option])
        #expect(DatabaseSchema.decode(option.id.uuidString, field: select) == .select(option.id))
        #expect(DatabaseSchema.decode("In Progress", field: select) == nil)
        #expect(DatabaseSchema.display(option.id.uuidString, field: select) == "In Progress")
        let multi = DatabaseField(name: "Topics", kind: .multiSelect, options: [option])
        let encoded = String(data: try JSONEncoder().encode([option.id]), encoding: .utf8)!
        #expect(DatabaseSchema.decode(encoded, field: multi) == .multiSelect([option.id]))
        #expect(DatabaseSchema.decode("https://example.com/page", field: .init(name: "Source", kind: .url)) != nil)
        #expect(DatabaseSchema.decode("javascript:bad", field: .init(name: "Source", kind: .url)) == nil)
    }
    @Test func legacyNamesShareTextFieldsWithoutMergingDistinctAccentedNames() {
        let list = ItemList.makeInbox()
        var a = Item(type: .note, title: "A", listId: list.id)
        var b = Item(type: .note, title: "B", listId: list.id)
        a.customProperties = [.init(name: "Owner", value: "Alex"), .init(name: "Résumé", value: "One")]
        b.customProperties = [.init(name: "owner", value: "Sam"), .init(name: "Resume", value: "Two")]
        let fields = DatabaseSchema.fields(for: list, items: [a, b])
        #expect(fields.count == 3)
        let owner = fields.first { $0.name.lowercased() == "owner" }!
        #expect(DatabaseSchema.property(owner, in: a)?.value == "Alex")
        #expect(DatabaseSchema.property(owner, in: b)?.value == "Sam")
        #expect(fields.filter { DatabaseSchema.property($0, in: a)?.value == "One" }.count == 1)
        #expect(fields.filter { DatabaseSchema.property($0, in: b)?.value == "Two" }.count == 1)
    }
    @Test func propertyEditsKeepOriginalIdentityAndUnknownYAML() throws {
        var item = Item(type: .note, title: "Metadata", listId: ItemList.inboxId)
        let property = ItemCustomProperty(name: "Owner", value: "Original")
        item.customProperties = [property]
        item.frontmatterExtensions["custom_properties"] = """
        - id: \(property.id.uuidString)
          name: Owner
          value: Original
          vendor_key:
            nested: keep
        """
        item = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))
        let field = DatabaseField(id: property.id, name: "Owner")
        #expect(DatabaseSchema.set("Updated", field: field, in: &item))
        let source = try FrontmatterCodec.encode(item)
        let decoded = try FrontmatterCodec.decode(source)
        #expect(decoded.customProperties.first?.id == property.id)
        #expect(decoded.customProperties.first?.fieldID == field.id)
        #expect(decoded.customProperties.first?.value == "Updated")
        #expect(source.contains("nested: keep"))
        var future = field; future.type = "future-relation"
        let before = item
        #expect(!DatabaseSchema.set("something", field: future, in: &item))
        #expect(item == before)
        #expect(try YAMLDecoder().decode(DatabaseField.self, from: YAMLEncoder().encode(future)).type == "future-relation")
    }
    @Test func filtersRetainAncestorContextAndNumericSortUsesDeclaredTypes() {
        let list = ItemList.makeInbox()
        let field = DatabaseField(name: "Estimate", kind: .number)
        var parent = Item(type: .task, title: "Project", listId: list.id)
        var child = Item(type: .task, title: "Matching", listId: list.id, parentId: parent.id)
        var other = Item(type: .task, title: "Other", listId: list.id)
        #expect(DatabaseSchema.set("100", field: field, in: &parent))
        #expect(DatabaseSchema.set("2", field: field, in: &child))
        #expect(DatabaseSchema.set("10", field: field, in: &other))
        var view = DatabaseView()
        view.filters = [.init(field: "title", operation: "contains", value: "Matching")]
        let rows = DatabaseQuery.rows(items: [other, child, parent], view: view, list: list, fields: [field], collapsed: [parent.id])
        #expect(rows.map(\.id) == [parent.id, child.id])
        #expect(rows.map(\.depth) == [0, 1])
        #expect(rows.map(\.isContext) == [true, false])
        view.filters = []; view.sorts = [.init(field: field.key, ascending: true)]
        #expect(DatabaseQuery.sorted([parent, other, child], view: view, list: list, fields: [field]).map(\.id) == [child.id, other.id, parent.id])
        view.filters = [.init(field: field.key, operation: "greater", value: "9")]
        #expect(DatabaseQuery.matches(other, view: view, list: list, fields: [field]))
        #expect(!DatabaseQuery.matches(child, view: view, list: list, fields: [field]))
        view.filters = [.init(field: field.key, operation: "equals", value: "2.0")]
        #expect(DatabaseQuery.matches(child, view: view, list: list, fields: [field]))
        var removed = parent; removed.deletedAt = .now
        #expect(!DatabaseQuery.rows(items: [removed], view: view, list: list, fields: [field]).contains { $0.id == removed.id })
    }
}

@MainActor struct DatabasePersistenceTests {
    @Test func schemaViewsLegacyRenameMoveAndColdReloadPreserveValues() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Database-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = FileStore(root: root); try await files.ensureRoot(); try await files.writeList(.makeInbox())
        let destination = ItemList(id: "other", name: "Other", icon: "folder", color: .blue, createdAt: .now, modifiedAt: .now, position: 1)
        try await files.writeList(destination)
        let store = ItemStore(store: files); try await store.bootstrap()
        var item = Item(type: .note, title: "Legacy", listId: ItemList.inboxId)
        item.customProperties = [.init(name: "Owner", value: "Alex")]
        let bytes = Data("original,file,bytes\n1,2,3\n".utf8)
        let attachment = try await store.importAttachment(data: bytes, originalFileName: "original.csv")
        item.body = "[Plan](../\(attachment.relativePath))"
        try await store.add(item)
        var fields = store.databaseFields(in: .makeInbox())
        let oldPropertyID = item.customProperties[0].id
        fields[0].name = "Assignee"
        let option = DatabaseOption(name: "Doing")
        let status = DatabaseField(name: "Status", kind: .select, options: [option])
        fields.append(status)
        try await store.saveDatabaseFields(fields, in: ItemList.inboxId)
        var updated = try #require(store.item(item.id))
        #expect(DatabaseSchema.property(fields[0], in: updated)?.value == "Alex")
        #expect(updated.customProperties[0].id == oldPropertyID)
        #expect(DatabaseSchema.set(option.id.uuidString, field: status, in: &updated))
        try await store.update(updated)
        var list = try #require(store.lists.first { $0.id == ItemList.inboxId })
        var view = DatabaseView(); view.name = "Doing"; view.groupBy = status.key
        view.columns += [fields[0].key, status.key]
        view.filters = [.init(field: status.key, operation: "equals", value: option.id.uuidString)]
        list.databaseViews = [view]; try await store.updateList(list)
        #expect(store.applyMoveSync(itemId: item.id, toListId: destination.id, parentId: nil))
        try await store.flushPendingWrites()
        let reload = ItemStore(store: FileStore(root: root)); try await reload.bootstrap()
        let moved = try #require(reload.item(item.id))
        #expect(moved.listId == destination.id)
        let movedFields = reload.databaseFields(in: destination)
        #expect(movedFields.contains { $0.id == status.id && $0.kind == .select && $0.options == [option] })
        #expect(DatabaseSchema.property(status, in: moved)?.value == option.id.uuidString)
        #expect(try Data(contentsOf: await reload.attachmentURL(for: attachment.relativePath)) == bytes)
        #expect(LibrarySearch.results(query: "Doing", items: reload.items, lists: reload.lists, files: []).contains { $0.id == "item." + item.id.uuidString })
        let archive = try await reload.exportLibrary()
        defer { try? FileManager.default.removeItem(at: archive) }
        let exported = String(decoding: try Data(contentsOf: archive), as: UTF8.self)
        #expect(exported.contains("database_fields"))
        #expect(exported.contains("original,file,bytes"))
        let loadedList = try #require(reload.lists.first { $0.id == ItemList.inboxId })
        #expect(loadedList.databaseViews == [view])
        #expect(loadedList.databaseFields == fields)
    }
    @Test func savedViewSelectionIsLocalAndDoesNotChangeOtherLists() {
        let name = "DatabaseSelection-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = ListViewPreferences(defaults: defaults), id = UUID()
        prefs.selectSavedView(id, for: "work")
        #expect(ListViewPreferences(defaults: defaults).savedViewID(for: "work") == id)
        #expect(prefs.savedViewID(for: "other") == nil)
        prefs.selectSavedView(nil, for: "work")
        #expect(prefs.savedViewID(for: "work") == nil)
    }
}
