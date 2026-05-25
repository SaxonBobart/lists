import XCTest
@testable import Lists

/// CONC family. CONC-4 (bootstrap re-entrancy) is deterministically testable
/// here. CONC-1 (in-memory-first mutators) and CONC-2 (bulk-loop re-fetch) are
/// hardening against lost updates whose race isn't deterministically
/// reproducible without a FileStore injection seam; these tests lock the
/// single-threaded correctness that the reorder/re-fetch must preserve, and the
/// in-memory↔disk consistency the ordering protects.
@MainActor
final class StoreConcurrencyTests: XCTestCase {

    private func emptyStore() async throws -> (store: ItemStore, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConc-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        return (store, root)
    }

    // CONC-4: two bootstraps racing on a fresh root must not both seed.
    func testConcurrentBootstrapSeedsInboxOnce() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcBoot-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        async let first: () = store.bootstrap()
        async let second: () = store.bootstrap()
        _ = try await (first, second)
        XCTAssertEqual(store.lists.filter { $0.id == ItemList.inboxId }.count, 1,
                       "a re-entrant bootstrap must not seed a second Inbox")
    }

    // CONC-2: rename updates every carrier; re-fetch must not drop items.
    func testRenameTagUpdatesEveryItem() async throws {
        let (store, _) = try await emptyStore()
        let a = Item(type: .task, title: "A", listId: ItemList.inboxId, tags: ["work"])
        let b = Item(type: .task, title: "B", listId: ItemList.inboxId, tags: ["work", "home"])
        try await store.add(a)
        try await store.add(b)

        try await store.renameTag(from: "work", to: "office")

        XCTAssertEqual(store.items.first { $0.id == a.id }?.tags, ["office"])
        XCTAssertEqual(Set(store.items.first { $0.id == b.id }?.tags ?? []), Set(["office", "home"]))
    }

    func testRemoveTagStripsFromEveryItem() async throws {
        let (store, _) = try await emptyStore()
        let a = Item(type: .task, title: "A", listId: ItemList.inboxId, tags: ["work", "urgent"])
        try await store.add(a)

        try await store.removeTag("work")

        XCTAssertEqual(store.items.first { $0.id == a.id }?.tags, ["urgent"])
    }

    // CONC-1: after a mutation the in-memory value must match a cold reload from
    // disk — the consistency property the in-memory-first ordering protects.
    func testToggleDoneIsConsistentWithDisk() async throws {
        let (store, root) = try await emptyStore()
        let task = Item(type: .task, title: "T", listId: ItemList.inboxId)
        try await store.add(task)

        try await store.toggleDone(task.id)
        XCTAssertEqual(store.items.first { $0.id == task.id }?.done, true)

        let reloaded = try await FileStore(root: root).loadAll()
            .lists.flatMap(\.items).first { $0.id == task.id }
        XCTAssertEqual(reloaded?.done, true, "in-memory done must match the persisted file")
    }
}
