import Foundation
import Observation

/// Shared in-place item move state. Starting a move puts one item "on the
/// shelf"; any list screen can then commit that item to its top level or one
/// of its rows as the new parent.
@MainActor
@Observable
final class ItemMoveSession {
    private(set) var movingItemId: UUID?
    private(set) var sourceListId: String?

    var isActive: Bool {
        movingItemId != nil
    }

    func begin(item: Item) {
        movingItemId = item.id
        sourceListId = item.listId
    }

    func cancel() {
        movingItemId = nil
        sourceListId = nil
    }

    func movingItem(in store: ItemStore) -> Item? {
        guard let movingItemId,
              let item = store.item(movingItemId),
              item.deletedAt == nil else {
            return nil
        }
        return item
    }

    func isMoving(_ itemId: UUID) -> Bool {
        movingItemId == itemId
    }

    func cancelIfMovingItemUnavailable(in store: ItemStore) {
        guard let movingItemId else { return }
        guard let item = store.item(movingItemId), item.deletedAt == nil else {
            cancel()
            return
        }
    }

    func canPickParent(_ parentId: UUID, in store: ItemStore) -> Bool {
        guard movingItem(in: store) != nil,
              let candidate = store.item(parentId),
              candidate.deletedAt == nil else {
            return false
        }
        return !blockedItemIds(in: store).contains(candidate.id)
    }

    func blockedItemIds(in store: ItemStore) -> Set<UUID> {
        guard let movingItemId, movingItem(in: store) != nil else { return [] }
        return Set([movingItemId] + store.itemDescendantIds(of: movingItemId))
    }

    func commit(toList listId: String, parent parentId: UUID?, store: ItemStore) {
        guard let moving = movingItem(in: store) else {
            cancel()
            return
        }
        if store.applyMoveSync(itemId: moving.id, toListId: listId, parentId: parentId) {
            cancel()
        }
    }
}
