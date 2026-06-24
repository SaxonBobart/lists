import Foundation

enum ItemMoveDragPayload {
    static let typeIdentifier = "io.github.saxonbobart.lists.item-move"

    static func itemProvider(for itemId: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: typeIdentifier,
            visibility: .ownProcess
        ) { completion in
            completion(itemId.uuidString.data(using: .utf8), nil)
            return nil
        }
        return provider
    }

    @MainActor
    static func movingItem(from payload: Data, store: ItemStore) -> Item? {
        guard let raw = String(data: payload, encoding: .utf8),
              let id = UUID(uuidString: raw),
              let item = store.item(id),
              item.deletedAt == nil else {
            return nil
        }
        return item
    }
}
