import Foundation
import SwiftUI
import Observation

/// Shared in-place item move state. Starting a move puts one item "on the
/// shelf"; any list screen can then commit that item to its top level or one
/// of its rows as the new parent.
@MainActor
@Observable
final class ItemMoveSession {
    private(set) var movingItemId: UUID?
    private(set) var movingFileID: String?
    private(set) var failure: String?
    private(set) var sourceListId: String?

    var isActive: Bool {
        movingItemId != nil || movingFileID != nil
    }

    func begin(item: Item) {
        cancel()
        movingItemId = item.id
        sourceListId = item.listId
    }

    func begin(file: StandaloneFile) {
        cancel()
        movingFileID = file.id
        sourceListId = file.listID
    }

    func movingTitle(in store: ItemStore) -> String? {
        if let item = movingItem(in: store) { return item.title.isEmpty ? "Untitled" : item.title }
        return movingFile(in: store)?.fileName
    }

    func movingFile(in store: ItemStore) -> StandaloneFile? {
        store.standaloneFiles.first { $0.id == movingFileID }
    }

    func dismissFailure() { failure = nil }

    func cancel() {
        movingItemId = nil
        movingFileID = nil
        failure = nil
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
        if movingFileID != nil {
            if movingFile(in: store) == nil { cancel() }
            return
        }
        guard let movingItemId else { return }
        guard let item = store.item(movingItemId), item.deletedAt == nil else {
            cancel()
            return
        }
    }

    func canPickParent(_ parentId: UUID, in store: ItemStore) -> Bool {
        guard movingItem(in: store) != nil || movingFile(in: store) != nil,
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

    func commit(toList listId: String, section: String?, store: ItemStore) {
        if movingFileID != nil { commitFile(toList: listId, section: section, parent: nil, store: store); return }
        guard let moving = movingItem(in: store) else { cancel(); return }
        if store.applyMoveSync(itemId: moving.id, toListId: listId, parentId: nil, sectionOverride: .some(section)) { cancel() }
    }

    func commit(toList listId: String, date: Date, preserveTime: Bool, allDay: Bool? = nil, store: ItemStore, calendar: Calendar = .current) {
        if movingFileID != nil { failure = "Choose a list or a document destination for this file."; return }
        guard let moving = movingItem(in: store) else { cancel(); return }
        var start = date
        if preserveTime, let due = moving.due {
            let time = calendar.dateComponents([.hour, .minute, .second], from: due)
            start = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: date) ?? date
        }
        if store.applyMoveSync(itemId: moving.id, toListId: listId, parentId: nil, schedule: start, allDay: allDay) { cancel() }
    }

    func commit(toList listId: String, parent parentId: UUID?, store: ItemStore) {
        if movingFileID != nil { commitFile(toList: listId, section: nil, parent: parentId, store: store); return }
        guard let moving = movingItem(in: store) else {
            cancel()
            return
        }
        if store.applyMoveSync(itemId: moving.id, toListId: listId, parentId: parentId) {
            cancel()
        }
    }
    private func commitFile(toList listId: String, section: String?, parent: UUID?, store: ItemStore) {
        guard let file = movingFile(in: store) else { cancel(); return }
        Task {
            do {
                if let parent { try await store.attachStandaloneFile(file, to: parent) }
                else { try await store.moveStandaloneFile(file, to: listId, section: section) }
                cancel()
            } catch { failure = error.localizedDescription }
        }
    }

}

private struct AttachmentMoveSessionKey: EnvironmentKey {
    static let defaultValue: ItemMoveSession? = nil
}
extension EnvironmentValues {
    var attachmentMoveSession: ItemMoveSession? {
        get { self[AttachmentMoveSessionKey.self] }
        set { self[AttachmentMoveSessionKey.self] = newValue }
    }
}
