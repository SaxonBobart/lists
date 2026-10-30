import Foundation

@MainActor extension ItemStore {
    func databaseFields(in list: ItemList) -> [DatabaseField] {
        DatabaseSchema.fields(for: list, items: items, knownFields: lists.flatMap(\.databaseFields))
    }
    /// Bind legacy identities before saving renamed definitions. Each write is
    /// recoverable on its own: the property carries its type/options too.
    func saveDatabaseFields(_ fields: [DatabaseField], in listID: String) async throws {
        guard let original = lists.first(where: { $0.id == listID && $0.deletedAt == nil }) else { throw CocoaError(.fileNoSuchFile) }
        let previous = databaseFields(in: original)
        for id in items.filter({ $0.listId == listID && $0.deletedAt == nil }).map(\.id) {
            guard var item = item(id), !item.hasCustomPropertyStorageConflict else { continue }
            let baseline = item
            for field in previous {
                guard let property = DatabaseSchema.property(field, in: item), property.fieldID == nil,
                      let index = item.customProperties.firstIndex(where: { $0.id == property.id }) else { continue }
                item.customProperties[index].fieldID = field.id
                item.customProperties[index].fieldType = field.type
                item.customProperties[index].fieldOptions = field.options
            }
            if item != baseline { try await update(item) }
        }
        guard var list = lists.first(where: { $0.id == listID && $0.deletedAt == nil }) else { throw CocoaError(.fileNoSuchFile) }
        list.databaseFields = fields
        try await updateList(list)
    }
}
