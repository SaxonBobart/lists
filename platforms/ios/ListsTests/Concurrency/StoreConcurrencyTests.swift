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

    // MARK: - DI-4: deferred writes are FIFO-ordered with newer writes

    /// The classic DI-4 collision: `addInlineItem` defers its disk write; the
    /// user immediately types a title, which `applyUpdateSync` also defers.
    /// Whatever the interleaving, the file on disk must hold the NEWER value —
    /// before the write chain, the empty-title snapshot could land last and
    /// the typed title silently reverted on next launch.
    func testInlineAddThenImmediateUpdatePersistsTheTypedTitle() async throws {
        let (store, root) = try await emptyStore()

        let id = store.addInlineItem(type: .task, listId: ItemList.inboxId, section: nil)
        var typed = try XCTUnwrap(store.item(id))
        typed.title = "Typed title"
        store.applyUpdateSync(typed)
        await store.flushPendingWrites()

        let onDisk = try await FileStore(root: root).loadAll()
            .lists.flatMap(\.items).first { $0.id == id }
        XCTAssertEqual(try XCTUnwrap(onDisk).title, "Typed title",
                       "the deferred inline-add write must not clobber the newer typed title (DI-4)")
    }

    /// Same hazard on the drag path: a deferred reorder write racing an
    /// awaited update of the same item must not resurrect the old sortIndex.
    func testDeferredReorderThenUpdateKeepsBothChanges() async throws {
        let (store, root) = try await emptyStore()
        let a = Item(type: .task, title: "First", listId: ItemList.inboxId, sortIndex: 0)
        let b = Item(type: .task, title: "Second", listId: ItemList.inboxId, sortIndex: 1)
        try await store.add(a)
        try await store.add(b)

        store.applyReorderItemsSync(in: ItemList.inboxId, flatOrderedIds: [b.id, a.id])
        var renamed = try XCTUnwrap(store.item(a.id))
        renamed.title = "First (renamed)"
        try await store.update(renamed)
        await store.flushPendingWrites()

        let onDisk = try await FileStore(root: root).loadAll()
            .lists.flatMap(\.items).first { $0.id == a.id }
        let loaded = try XCTUnwrap(onDisk)
        XCTAssertEqual(loaded.title, "First (renamed)", "the awaited update is the newest value")
        XCTAssertEqual(loaded.sortIndex, 1, "the earlier deferred reorder is not lost either")
    }
}
