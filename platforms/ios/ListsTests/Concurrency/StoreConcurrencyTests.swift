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

    private struct SectionedHierarchy {
        let store: ItemStore
        let fileStore: FileStore
        let list: ItemList
        let section: ListSection
        let rootItem: Item
        let childItem: Item
    }

    private func sectionedHierarchy() async throws -> SectionedHierarchy {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcCascade-\(UUID().uuidString)")
        let fileStore = FileStore(root: root)
        let store = ItemStore(store: fileStore)
        try await store.bootstrap()

        let section = ListSection(name: "Focused", position: 1_000)
        let list = ItemList(
            id: "cascade-\(UUID().uuidString)",
            name: "Cascade",
            icon: "square.stack.3d.up",
            color: .blue,
            createdAt: .now,
            modifiedAt: .now,
            position: 10_000,
            sections: [section]
        )
        try await store.addList(list)

        let rootItem = Item(type: .task, title: "Root", listId: list.id)
        try await store.add(rootItem)
        let childItem = Item(
            type: .task,
            title: "Child",
            listId: list.id,
            parentId: rootItem.id
        )
        try await store.add(childItem)

        return SectionedHierarchy(
            store: store,
            fileStore: fileStore,
            list: list,
            section: section,
            rootItem: try #require(store.item(rootItem.id)),
            childItem: try #require(store.item(childItem.id))
        )
    }

    private func itemURL(_ item: Item, in context: SectionedHierarchy) async throws -> URL {
        try await context.fileStore.listDirectory(for: item.listId)
            .appendingPathComponent("\(item.id.uuidString).md")
    }

    private func sabotageMarkdownPath(_ url: URL) throws -> Data {
        let originalBytes = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return originalBytes
    }

    private func repairMarkdownPath(_ url: URL, originalBytes: Data) throws {
        try FileManager.default.removeItem(at: url)
        try originalBytes.write(to: url, options: .atomic)
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

    // MARK: - Awaited item updates publish only committed state

    @Test func failedUpdateDoesNotPublishAndRetryAfterPathRepairSucceeds() async throws {
        let context = try await sectionedHierarchy()
        let itemURL = try await itemURL(context.rootItem, in: context)
        let originalBytes = try sabotageMarkdownPath(itemURL)
        var edited = context.rootItem
        edited.title = "Committed title"

        do {
            try await context.store.update(edited)
            Issue.record("a sabotaged item path must reject update")
        } catch {}

        #expect(context.store.item(edited.id) == context.rootItem,
                "a failed root write must not publish the edit to memory")

        try repairMarkdownPath(itemURL, originalBytes: originalBytes)
        try await context.store.update(edited)

        let persisted = try await context.fileStore.readItem(at: itemURL)
        #expect(context.store.item(edited.id)?.title == edited.title)
        #expect(persisted.title == edited.title)
    }

    @Test func crossListMoveRetryRollsBackCopyAfterSourceRemovalFailure() async throws {
        let context = try await sectionedHierarchy()
        let sourceURL = try await itemURL(context.rootItem, in: context)
        let sourceDirectory = sourceURL.deletingLastPathComponent()
        let destinationDirectory = try await context.fileStore.listDirectory(
            for: ItemList.inboxId
        )
        let destinationURL = destinationDirectory
            .appendingPathComponent("\(context.rootItem.id.uuidString).md")
        let fileManager = FileManager.default
        let originalSourceBytes = try Data(contentsOf: sourceURL)
        let originalPermissions = try #require(
            try fileManager.attributesOfItem(atPath: sourceDirectory.path)[.posixPermissions]
                as? NSNumber
        )
        var permissionsRestored = false
        defer {
            if !permissionsRestored {
                try? fileManager.setAttributes(
                    [.posixPermissions: originalPermissions],
                    ofItemAtPath: sourceDirectory.path
                )
            }
        }

        var moved = context.rootItem
        moved.listId = ItemList.inboxId
        moved.section = nil

        // Destination creation is allowed, but removing the captured source
        // requires write permission on its parent directory and must fail.
        try fileManager.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: sourceDirectory.path
        )
        do {
            try await context.store.update(moved)
            Issue.record("source cleanup failure must reject the cross-list move")
        } catch {}

        #expect(context.store.item(moved.id) == context.rootItem,
                "an incomplete move must not publish the destination list")
        #expect(fileManager.fileExists(atPath: sourceURL.path))
        #expect(fileManager.fileExists(atPath: destinationURL.path) == false,
                "a runtime cleanup failure must roll back its new destination copy")

        let persistedSource = try await context.fileStore.readItem(at: sourceURL)
        #expect(try Data(contentsOf: sourceURL) == originalSourceBytes,
                "failed cleanup must leave the source bytes untouched")
        #expect(persistedSource.id == context.rootItem.id)
        #expect(persistedSource.listId == context.rootItem.listId)

        try fileManager.setAttributes(
            [.posixPermissions: originalPermissions],
            ofItemAtPath: sourceDirectory.path
        )
        permissionsRestored = true
        try await context.store.update(moved)

        #expect(fileManager.fileExists(atPath: sourceURL.path) == false)
        let persistedDestination = try await context.fileStore.readItem(at: destinationURL)
        let live = try #require(context.store.item(moved.id))
        #expect(persistedDestination.id == moved.id)
        #expect(persistedDestination.listId == ItemList.inboxId)
        #expect(persistedDestination.title == moved.title)
        #expect(live.id == persistedDestination.id)
        #expect(live.listId == persistedDestination.listId)
        #expect(live.title == persistedDestination.title)
        #expect(abs(live.modifiedAt.timeIntervalSince(persistedDestination.modifiedAt)) < 0.001)
    }

    @Test func crossListMoveFinishesAgainstEquivalentCrashResidue() async throws {
        let context = try await sectionedHierarchy()
        let sourceURL = try await itemURL(context.rootItem, in: context)
        let destinationDirectory = try await context.fileStore.listDirectory(
            for: ItemList.inboxId
        )
        let destinationURL = destinationDirectory
            .appendingPathComponent("\(context.rootItem.id.uuidString).md")

        // Model the deliberate copy-first crash window: both source and
        // destination exist, and the first payload has an older modifiedAt
        // than the fresh retry ItemStore will stamp.
        var firstPayload = context.rootItem
        firstPayload.listId = ItemList.inboxId
        firstPayload.section = nil
        firstPayload.modifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await context.fileStore.writeItem(firstPayload)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(FileManager.default.fileExists(atPath: destinationURL.path))

        var retry = context.rootItem
        retry.listId = ItemList.inboxId
        retry.section = nil
        try await context.store.update(retry)

        #expect(FileManager.default.fileExists(atPath: sourceURL.path) == false)
        let persisted = try await context.fileStore.readItem(at: destinationURL)
        let live = try #require(context.store.item(retry.id))
        #expect(persisted.listId == ItemList.inboxId)
        #expect(abs(persisted.modifiedAt.timeIntervalSince(firstPayload.modifiedAt)) < 0.001)
        #expect(live.listId == persisted.listId)
        #expect(abs(live.modifiedAt.timeIntervalSince(persisted.modifiedAt)) < 0.001)
    }

    @Test func failedCascadeRootDoesNotPublishAndRetryAfterPathRepairSucceeds() async throws {
        let context = try await sectionedHierarchy()
        let rootURL = try await itemURL(context.rootItem, in: context)
        let childURL = try await itemURL(context.childItem, in: context)
        let originalBytes = try sabotageMarkdownPath(rootURL)
        let sectionId = context.section.id.uuidString
        var editedRoot = context.rootItem
        editedRoot.section = sectionId

        do {
            try await context.store.updateWithSubtreeCascades(editedRoot)
            Issue.record("a sabotaged root path must reject subtree update")
        } catch {}

        #expect(context.store.item(editedRoot.id) == context.rootItem)
        #expect(context.store.item(context.childItem.id) == context.childItem)

        try repairMarkdownPath(rootURL, originalBytes: originalBytes)
        try await context.store.updateWithSubtreeCascades(editedRoot)

        let persistedRoot = try await context.fileStore.readItem(at: rootURL)
        let persistedChild = try await context.fileStore.readItem(at: childURL)
        #expect(context.store.item(editedRoot.id)?.section == sectionId)
        #expect(context.store.item(context.childItem.id)?.section == sectionId)
        #expect(persistedRoot.section == sectionId)
        #expect(persistedChild.section == sectionId)
    }

    @Test func retryingIdenticalRootEditRepairsChildAfterPartialCascadeFailure() async throws {
        let context = try await sectionedHierarchy()
        let rootURL = try await itemURL(context.rootItem, in: context)
        let childURL = try await itemURL(context.childItem, in: context)
        let childBytes = try sabotageMarkdownPath(childURL)
        let sectionId = context.section.id.uuidString
        var editedRoot = context.rootItem
        editedRoot.section = sectionId

        do {
            try await context.store.updateWithSubtreeCascades(editedRoot)
            Issue.record("a sabotaged child path must stop the cascade")
        } catch {}

        #expect(context.store.item(editedRoot.id)?.section == sectionId,
                "the successful root write remains committed")
        #expect(context.store.item(context.childItem.id) == context.childItem,
                "the failed child write must not publish to memory")
        let persistedRoot = try await context.fileStore.readItem(at: rootURL)
        #expect(persistedRoot.section == sectionId)

        try repairMarkdownPath(childURL, originalBytes: childBytes)
        let repairedChild = try await context.fileStore.readItem(at: childURL)
        #expect(repairedChild.section == nil,
                "repair restores the child's pre-cascade bytes")

        try await context.store.updateWithSubtreeCascades(editedRoot)

        let persistedChild = try await context.fileStore.readItem(at: childURL)
        #expect(context.store.item(context.childItem.id)?.section == sectionId,
                "an identical root retry must still reconcile descendants")
        #expect(persistedChild.section == sectionId)
    }
}
