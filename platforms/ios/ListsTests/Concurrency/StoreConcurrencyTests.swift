import Foundation
import Testing
@testable import Lists

/// Store mutation ordering is hard to prove with sleeps, so these tests lock the
/// observable promises: bootstrapping is idempotent, bulk edits update every
/// carrier, and deferred writes cannot overwrite newer user edits.
@MainActor
struct StoreConcurrencyTests {

    private func emptyStore() async throws -> (store: ItemStore, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConc-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        return (store, root)
    }

    // Two bootstraps racing on a fresh root must not both seed.
    @Test func concurrentBootstrapSeedsInboxOnce() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcBoot-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        async let first: Void = store.bootstrap()
        async let second: Void = store.bootstrap()
        _ = try await (first, second)
        #expect(store.lists.filter { $0.id == ItemList.inboxId }.count == 1,
                "a re-entrant bootstrap must not seed a second Inbox")
    }

    // Rename updates every carrier; re-fetch must not drop items.
    @Test func renameTagUpdatesEveryItem() async throws {
        let (store, _) = try await emptyStore()
        let a = Item(type: .task, title: "A", listId: ItemList.inboxId, tags: ["work"])
        let b = Item(type: .task, title: "B", listId: ItemList.inboxId, tags: ["work", "home"])
        try await store.add(a)
        try await store.add(b)

        try await store.renameTag(from: "work", to: "office")

        #expect(store.items.first { $0.id == a.id }?.tags == ["office"])
        #expect(Set(store.items.first { $0.id == b.id }?.tags ?? []) == Set(["office", "home"]))
    }

    @Test func removeTagStripsFromEveryItem() async throws {
        let (store, _) = try await emptyStore()
        let a = Item(type: .task, title: "A", listId: ItemList.inboxId, tags: ["work", "alarm"])
        try await store.add(a)

        try await store.removeTag("work")

        #expect(store.items.first { $0.id == a.id }?.tags == ["alarm"])
    }

    // After a mutation the in-memory value must match a cold reload from disk.
    @Test func toggleDoneIsConsistentWithDisk() async throws {
        let (store, root) = try await emptyStore()
        let task = Item(type: .task, title: "T", listId: ItemList.inboxId)
        try await store.add(task)

        try await store.toggleDone(task.id)
        #expect(store.items.first { $0.id == task.id }?.done == true)

        let reloaded = try await FileStore(root: root).loadAll()
            .lists.flatMap(\.items).first { $0.id == task.id }
        #expect(reloaded?.done == true, "in-memory done must match the persisted file")
    }

    // MARK: - Deferred writes are FIFO-ordered with newer writes

    /// `addInlineItem` defers its disk write; the user immediately types a
    /// title, which `applyUpdateSync` also defers. Whatever the interleaving,
    /// the file on disk must hold the newer value so the typed title does not
    /// silently revert on next launch.
    @Test func inlineAddThenImmediateUpdatePersistsTheTypedTitle() async throws {
        let (store, root) = try await emptyStore()

        let id = store.addInlineItem(type: .task, listId: ItemList.inboxId, section: nil)
        var typed = try #require(store.item(id))
        typed.title = "Typed title"
        store.applyUpdateSync(typed)
        try await store.flushPendingWrites()

        let onDisk = try await FileStore(root: root).loadAll()
            .lists.flatMap(\.items).first { $0.id == id }
        #expect(try #require(onDisk).title == "Typed title",
                "the deferred inline-add write must not clobber the newer typed title")
    }

    /// Same hazard on the drag path: a deferred reorder write racing an
    /// awaited update of the same item must not resurrect the old sortIndex.
    @Test func deferredReorderThenUpdateKeepsBothChanges() async throws {
        let (store, root) = try await emptyStore()
        let a = Item(type: .task, title: "First", listId: ItemList.inboxId, sortIndex: 0)
        let b = Item(type: .task, title: "Second", listId: ItemList.inboxId, sortIndex: 1)
        try await store.add(a)
        try await store.add(b)

        store.applyReorderItemsSync(in: ItemList.inboxId, flatOrderedIds: [b.id, a.id])
        var renamed = try #require(store.item(a.id))
        renamed.title = "First (renamed)"
        try await store.update(renamed)
        try await store.flushPendingWrites()

        let onDisk = try await FileStore(root: root).loadAll()
            .lists.flatMap(\.items).first { $0.id == a.id }
        let loaded = try #require(onDisk)
        #expect(loaded.title == "First (renamed)", "the awaited update is the newest value")
        #expect(loaded.sortIndex == 1, "the earlier deferred reorder is not lost either")
    }

    @Test func deferredFailureSurfacesWithoutPoisoningLaterWrites() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcFailure-\(UUID().uuidString)")
        let fileStore = FileStore(root: root)
        let store = ItemStore(store: fileStore)
        try await store.bootstrap()

        let safeList = ItemList(
            id: "safe-after-failure",
            name: "Safe after failure",
            icon: "checkmark.shield",
            color: .green,
            createdAt: .now,
            modifiedAt: .now,
            position: 10_000
        )
        try await store.addList(safeList)

        let inboxDirectory = try await fileStore.listDirectory(for: ItemList.inboxId)
        try FileManager.default.removeItem(at: inboxDirectory)
        try Data("not a directory".utf8).write(to: inboxDirectory)

        var blocked = try #require(store.items.first { $0.listId == ItemList.inboxId })
        blocked.title = "This write must fail"
        store.applyUpdateSync(blocked)
        let laterId = store.addInlineItem(
            type: .task,
            listId: safeList.id,
            section: nil
        )
        var later = try #require(store.item(laterId))
        later.title = "Later write"
        store.applyUpdateSync(later)

        do {
            try await store.flushPendingWrites()
            Issue.record("flush must surface a deferred write failure")
        } catch {
            #expect(error.localizedDescription.contains("couldn't finish saving"))
        }

        let loadedLater = try await fileStore.loadAll()
            .lists.flatMap(\.items).first { $0.id == laterId }
        #expect(try #require(loadedLater).title == "Later write",
                "a queued failure must not poison its already-queued successors")

        do {
            try await store.reloadFromDisk()
            Issue.record("reload must not replace live state with a stale disk snapshot")
        } catch {
            #expect(error.localizedDescription.contains("couldn't finish saving"))
        }
        #expect(store.item(blocked.id)?.title == blocked.title,
                "a rejected reload must leave the live edit untouched")

        do {
            try await store.flushPendingWrites()
            Issue.record("the earlier persistence failure must remain visible")
        } catch {
            #expect(error.localizedDescription.contains("couldn't finish saving"))
        }
    }
}
