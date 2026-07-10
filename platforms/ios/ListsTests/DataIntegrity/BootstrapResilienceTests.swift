import Foundation
import Testing
@testable import Lists

/// Bootstrap must never leave the app wedged on "Loading…", must surface
/// quarantined files, and must not re-seed sample data on top of a library
/// that loaded partially.
@MainActor
struct BootstrapResilienceTests {

    private struct LegacyRestoreJournal: Encodable {
        let kind: FileStore.RestoreJournal.Kind
        let rootId: String
        let deletedAt: Date
    }

    private struct IncompleteVersionedRestoreJournal: Encodable {
        let kind: FileStore.RestoreJournal.Kind
        let rootId: String
        let deletedAt: Date
        let expectedItemIds: [String]
        let expectedListIds: [String]
        let formatVersion: Int
    }

    private func freshRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsBootstrap-\(UUID().uuidString)")
    }

    private func makeList(
        id: String,
        name: String,
        parentId: String? = nil,
        deletedAt: Date? = nil
    ) -> ItemList {
        ItemList(
            id: id,
            name: name,
            icon: "tray",
            color: .blue,
            createdAt: .now,
            modifiedAt: .now,
            position: 0,
            parentId: parentId,
            deletedAt: deletedAt
        )
    }

    private func appendStoredParentId(_ parentId: String, to listId: String, in store: FileStore) async throws {
        let dir = try await store.listDirectory(for: listId)
        let url = dir.appendingPathComponent(".list.yml")
        let current = try String(contentsOf: url, encoding: .utf8)
        try (current + "\nparent_id: \(parentId)\n").write(to: url, atomically: true, encoding: .utf8)
    }

    @Test
    func corruptFileIsSurfacedAndDoesNotReSeed() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(ItemList(id: "l1", name: "Work", icon: "tray", color: .blue,
                                           createdAt: .now, modifiedAt: .now, position: 0))
        try await setup.writeItem(Item(type: .task, title: "good", listId: "l1"))
        let dir = try await setup.listDirectory(for: "l1")
        try "broken".write(to: dir.appendingPathComponent("\(UUID().uuidString).md"),
                           atomically: true, encoding: .utf8)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.isLoaded, "isLoaded must be set even with a partial failure")
        #expect(store.loadIssues.count == 1)
        #expect(store.items.map(\.title) == ["good"])
        #expect(store.lists.map(\.id) == ["l1"], "a quarantine-only / non-empty load must not re-seed sample data")
    }

    @Test
    func duplicateItemRecoveryKeepsArrayAndIndexConsistent() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))

        let id = UUID()
        let older = Item(
            id: id,
            type: .task,
            title: "Older",
            listId: "A",
            createdAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = Item(
            id: id,
            type: .task,
            title: "Newer",
            listId: "B",
            createdAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        try await setup.writeItem(older)
        try await setup.writeItem(newer)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.items.filter { $0.id == id }.count == 1)
        #expect(store.itemsById.count == store.items.count)
        #expect(store.item(id)?.title == "Newer")
        #expect(store.loadIssues.count == 1)
        #expect(store.lists.contains { $0.id == ItemList.inboxId } == false,
                "recovery must not seed samples over the existing library")
    }

    @Test
    func emptyRootStillSeeds() async throws {
        let store = ItemStore(store: FileStore(root: freshRoot()))
        try await store.bootstrap()

        #expect(store.isLoaded)
        #expect(store.loadIssues.isEmpty)
        #expect(store.lists.isEmpty == false, "a genuinely empty library still seeds sample data")
    }

    @Test
    func malformedRestoreJournalRemainsARecoveryBarrierWithoutSeeding() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        let journalURL = root.appendingPathComponent(".restore-journal.json")
        let malformedData = Data("not valid restore journal json".utf8)
        try malformedData.write(to: journalURL, options: .atomic)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.isLoaded)
        #expect(store.loadIssues.isEmpty)
        #expect(store.hasPendingRestoreRecovery)
        #expect(store.lists.isEmpty, "journal recovery must not seed a replacement library")
        #expect(store.items.isEmpty)
        #expect(try Data(contentsOf: journalURL) == malformedData)

        let restarted = ItemStore(store: FileStore(root: root))
        try await restarted.bootstrap()
        #expect(restarted.hasPendingRestoreRecovery)
        #expect(restarted.lists.isEmpty,
                "later launches must not mistake an unreadable restore for a new library")
        #expect(restarted.items.isEmpty)
        #expect(try Data(contentsOf: journalURL) == malformedData)
    }

    @Test
    func legacyRestoreJournalWithoutManifestRemainsARecoveryBarrier() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        let deletedAt = Date.now
        var item = Item(type: .task, title: "Legacy restore", listId: "A")
        item.deletedAt = deletedAt
        item.modifiedAt = deletedAt
        try await setup.writeItem(item)

        let legacy = LegacyRestoreJournal(
            kind: .item,
            rootId: item.id.uuidString,
            deletedAt: deletedAt
        )
        try JSONEncoder().encode(legacy).write(
            to: root.appendingPathComponent(".restore-journal.json"),
            options: .atomic
        )

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.hasPendingRestoreRecovery)
        #expect(abs(try #require(store.item(item.id)?.deletedAt)
            .timeIntervalSince(deletedAt)) < 0.001)
        #expect(try await FileStore(root: root).pendingRestore() != nil)

        let restarted = ItemStore(store: FileStore(root: root))
        try await restarted.bootstrap()
        #expect(restarted.hasPendingRestoreRecovery)
        #expect(abs(try #require(restarted.item(item.id)?.deletedAt)
            .timeIntervalSince(deletedAt)) < 0.001)
        #expect(try await FileStore(root: root).pendingRestore() != nil)
    }

    @Test
    func versionedJournalWithoutRootInManifestRemainsARecoveryBarrier() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        let deletedAt = Date.now
        var item = Item(type: .task, title: "Incomplete journal", listId: "A")
        item.deletedAt = deletedAt
        item.modifiedAt = deletedAt
        try await setup.writeItem(item)

        let incomplete = IncompleteVersionedRestoreJournal(
            kind: .item,
            rootId: item.id.uuidString,
            deletedAt: deletedAt,
            expectedItemIds: [],
            expectedListIds: [],
            formatVersion: 1
        )
        try JSONEncoder().encode(incomplete).write(
            to: root.appendingPathComponent(".restore-journal.json"),
            options: .atomic
        )

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.hasPendingRestoreRecovery)
        #expect(abs(try #require(store.item(item.id)?.deletedAt)
            .timeIntervalSince(deletedAt)) < 0.001)
        #expect(try await FileStore(root: root).pendingRestore() != nil)
    }

    @Test
    func pendingRestoreWaitsWhileBatchMemberIsQuarantined() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        let batchDate = Calendar.current.date(
            byAdding: .day,
            value: -31,
            to: .now
        )!
        try await setup.writeList(
            makeList(id: "A", name: "Alpha", deletedAt: batchDate)
        )
        try await setup.writeList(
            makeList(id: "B", name: "Bravo", parentId: "A")
        )

        var batchItem = Item(type: .task, title: "Batch member", listId: "B")
        batchItem.deletedAt = batchDate
        batchItem.modifiedAt = batchDate
        try await setup.writeItem(batchItem)
        let childDirectory = try await setup.listDirectory(for: "B")
        let batchItemURL = childDirectory.appendingPathComponent(
            "\(batchItem.id.uuidString).md"
        )
        try Data("broken batch member".utf8).write(to: batchItemURL, options: .atomic)

        let journal = FileStore.RestoreJournal(
            kind: .list,
            rootId: "A",
            deletedAt: batchDate,
            expectedItemIds: [batchItem.id.uuidString],
            expectedListIds: ["A", "B"]
        )
        _ = try await setup.beginRestore(journal)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.isLoaded)
        #expect(store.loadIssues.count == 1)
        #expect(store.hasPendingRestoreRecovery)
        #expect(store.loadIssues.first?.hasSuffix("/\(batchItem.id.uuidString).md") == true)
        #expect(store.lists.first { $0.id == "A" }?.deletedAt != nil,
                "the incomplete restore must not resume while a member is quarantined")
        #expect(store.lists.first { $0.id == "B" }?.deletedAt == nil)
        #expect(store.lists.first { $0.id == "B" }?.parentId == "A",
                "hierarchy repair must wait until restore recovery is complete")
        #expect(store.item(batchItem.id) == nil)

        let pending = try #require(try await FileStore(root: root).pendingRestore())
        #expect(pending.kind == .list)
        #expect(pending.rootId == "A")
        #expect(abs(pending.deletedAt.timeIntervalSince(batchDate)) < 0.001)

        let reloaded = try await FileStore(root: root).loadAll()
        #expect(reloaded.lists.first { $0.list.id == "A" }?.list.deletedAt != nil)
        #expect(reloaded.lists.first { $0.list.id == "B" }?.list.parentId == "A")

        // The corrupt member has now moved to quarantine, so a clean-looking
        // second load must still use the journal manifest to detect that the
        // restore batch is incomplete. Keep the journal active so hierarchy
        // repair and the 30-day purge remain blocked across every launch.
        let restarted = ItemStore(store: FileStore(root: root))
        try await restarted.bootstrap()
        #expect(restarted.loadIssues.isEmpty)
        #expect(restarted.hasPendingRestoreRecovery)
        #expect(restarted.lists.first { $0.id == "A" }?.deletedAt != nil)
        #expect(restarted.lists.first { $0.id == "B" }?.parentId == "A")
        #expect(try await FileStore(root: root).pendingRestore() != nil)

        let protected = ItemStore(store: FileStore(root: root))
        try await protected.bootstrap()
        #expect(protected.hasPendingRestoreRecovery)
        #expect(protected.lists.first { $0.id == "A" }?.deletedAt != nil,
                "expiry purge must not consume a batch the user asked to restore")
        #expect(protected.lists.first { $0.id == "B" }?.parentId == "A",
                "hierarchy repair must not overwrite the interrupted batch")
        #expect(try await FileStore(root: root).pendingRestore() != nil)

        let quarantineURL = root.appendingPathComponent(".quarantine", isDirectory: true)
        let preservedNames = try Set(FileManager.default.contentsOfDirectory(
            at: quarantineURL,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent))
        #expect(preservedNames.contains { $0.contains(batchItem.id.uuidString) })
        #expect(preservedNames.contains { $0.contains(".restore-journal") } == false)
    }

    @Test
    func openItemCountUsesProductCompletionAndPastEventRules() async throws {
        let root = freshRoot()
        let now = Date()
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "l1", name: "Inbox"))
        try await setup.writeItem(Item(type: .task, title: "Open task", listId: "l1"))
        try await setup.writeItem(Item(type: .task, title: "Done task", listId: "l1", done: true))
        try await setup.writeItem(Item(
            type: .habit,
            title: "Done habit",
            listId: "l1",
            frequency: .daily,
            completions: [HabitCompletion(at: now)]
        ))
        try await setup.writeItem(Item(
            type: .note,
            title: "Stale done note",
            listId: "l1",
            done: true
        ))
        try await setup.writeItem(Item(
            type: .event,
            title: "Past event",
            listId: "l1",
            due: cal.date(byAdding: .hour, value: 9, to: yesterday),
            end: cal.date(byAdding: .hour, value: 10, to: yesterday)
        ))
        try await setup.writeItem(Item(
            type: .event,
            title: "Future event",
            listId: "l1",
            due: cal.date(byAdding: .hour, value: 9, to: tomorrow),
            end: cal.date(byAdding: .hour, value: 10, to: tomorrow)
        ))
        try await setup.writeItem(Item(type: .task, title: "Deleted", listId: "l1", deletedAt: now))

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.openItemCount(in: "l1", now: now) == 3)
    }

    @Test
    func openItemCountRespectsItemTypePolicy() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(ItemList(id: "l1", name: "Work", icon: "tray", color: .blue,
                                           createdAt: .now, modifiedAt: .now, position: 0))
        try await setup.writeItem(Item(type: .task, title: "Task", listId: "l1"))
        try await setup.writeItem(Item(type: .habit, title: "Habit", listId: "l1"))

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.openItemCount(in: "l1") == 2)
        #expect(store.openItemCount(
            in: "l1",
            itemTypePolicy: ItemTypePolicy(habitsEnabled: false)
        ) == 1)
    }

    @Test
    func reloadFromDiskReplacesInMemorySnapshot() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(ItemList(id: "l1", name: "Work", icon: "tray", color: .blue,
                                           createdAt: .now, modifiedAt: .now, position: 0))
        try await setup.writeItem(Item(type: .task, title: "Before", listId: "l1"))

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        #expect(store.items.map(\.title) == ["Before"])

        try await setup.writeItem(Item(type: .task, title: "After", listId: "l1"))
        try await store.reloadFromDisk()

        #expect(Set(store.items.map(\.title)) == Set(["Before", "After"]))
        #expect(store.isLoaded)
        #expect(store.loadIssues.isEmpty)
    }

    @Test
    func bootstrapPurgesExpiredDeletedListSubtree() async throws {
        let root = freshRoot()
        let old = Calendar.current.date(byAdding: .day, value: -31, to: .now)!
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(ItemList(
            id: "parent",
            name: "Parent",
            icon: "tray",
            color: .blue,
            createdAt: old,
            modifiedAt: old,
            position: 0,
            deletedAt: old
        ))
        try await setup.writeList(ItemList(
            id: "child",
            name: "Child",
            icon: "tray",
            color: .blue,
            createdAt: old,
            modifiedAt: old,
            position: 0,
            parentId: "parent",
            deletedAt: old
        ))
        var item = Item(type: .task, title: "Child item", listId: "child")
        item.deletedAt = old
        try await setup.writeItem(item)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.lists.contains { $0.id == "parent" } == false)
        #expect(store.lists.contains { $0.id == "child" } == false)
        #expect(store.item(item.id) == nil)
        #expect(store.isLoaded)

        let coldReload = try await FileStore(root: root).loadAll()
        #expect(coldReload.lists.contains { $0.list.id == "parent" } == false)
        #expect(coldReload.lists.contains { $0.list.id == "child" } == false)
        #expect(coldReload.lists.flatMap(\.items).contains { $0.id == item.id } == false)
    }

    @Test
    func bootstrapKeepsExpiredItemWhenFileDeletionFails() async throws {
        let root = freshRoot()
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "work", name: "Work"))
        var expired = Item(type: .task, title: "Expired", listId: "work")
        expired.deletedAt = old
        expired.modifiedAt = old
        try await setup.writeItem(expired)

        let fileManager = FileManager.default
        let directory = try await setup.listDirectory(for: "work")
        let originalPermissions = try #require(
            fileManager.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        )
        let probeURL = directory.appendingPathComponent("delete-probe")
        try Data().write(to: probeURL)
        try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {
            try? fileManager.setAttributes(
                [.posixPermissions: originalPermissions],
                ofItemAtPath: directory.path
            )
            try? fileManager.removeItem(at: root)
        }

        #expect(throws: (any Error).self) {
            try fileManager.removeItem(at: probeURL)
        }

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let retained = try #require(store.item(expired.id))
        #expect(retained.deletedAt == old)
        let coldReload = try await FileStore(root: root).loadAll()
        let persisted = try #require(
            coldReload.lists.flatMap(\.items).first { $0.id == expired.id }
        )
        #expect(persisted.deletedAt == old)
    }

    @Test
    func bootstrapDefersDestructivePurgeWhileRecoveryIssuesRemain() async throws {
        let root = freshRoot()
        let old = Calendar.current.date(byAdding: .day, value: -31, to: .now)!
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        let expired = makeList(id: "expired", name: "Expired", deletedAt: old)
        try await setup.writeList(expired)
        try await setup.writeList(makeList(id: "work", name: "Work"))
        let retainedItem = Item(type: .task, title: "Keep during recovery", listId: "work")
        try await setup.writeItem(retainedItem)
        let workDirectory = try await setup.listDirectory(for: "work")
        try "broken".write(
            to: workDirectory.appendingPathComponent("\(UUID().uuidString).md"),
            atomically: true,
            encoding: .utf8
        )

        let first = ItemStore(store: FileStore(root: root))
        try await first.bootstrap()
        #expect(first.loadIssues.isEmpty == false)
        #expect(first.lists.contains { $0.id == expired.id },
                "automatic purge must wait until recovery is clean")
        do {
            try await first.deleteList(expired.id)
            Issue.record("permanent list deletion must be blocked during recovery")
        } catch let error as ItemStore.DataSafetyError {
            #expect(error == .unresolvedRecoveryIssues)
        }
        do {
            try await first.delete(retainedItem.id)
            Issue.record("permanent item deletion must be blocked during recovery")
        } catch let error as ItemStore.DataSafetyError {
            #expect(error == .unresolvedRecoveryIssues)
        }
        #expect(first.item(retainedItem.id) != nil)

        let stillOnDisk = try await FileStore(root: root).loadAll()
        #expect(stillOnDisk.lists.contains { $0.list.id == expired.id })

        let second = ItemStore(store: FileStore(root: root))
        try await second.bootstrap()
        #expect(second.loadIssues.isEmpty)
        #expect(second.lists.contains { $0.id == expired.id } == false,
                "the next clean launch may safely finish deferred purge")
    }

    @Test
    func bootstrapRepairsLoadedListWithMissingParentAndWritesBack() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "orphan", name: "Orphan", parentId: "missing"))

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.lists.first { $0.id == "orphan" }?.parentId == nil)

        let reloaded = try await FileStore(root: root).loadAll()
        #expect(reloaded.lists.map(\.list).first { $0.id == "orphan" }?.parentId == nil)
    }

    @Test
    func bootstrapRepairsLoadedActiveListUnderDeletedParent() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        let deletedAt = Calendar.current.date(byAdding: .day, value: -31, to: .now)!
        try await setup.writeList(makeList(id: "parent", name: "Parent", deletedAt: deletedAt))
        try await setup.writeList(makeList(id: "child", name: "Child", parentId: "parent"))

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.lists.first { $0.id == "child" }?.parentId == nil)
        #expect(store.lists.contains { $0.id == "parent" } == false)

        let reloaded = try await FileStore(root: root).loadAll()
        #expect(reloaded.lists.map(\.list).first { $0.id == "child" }?.parentId == nil)
        #expect(reloaded.lists.contains { $0.list.id == "parent" } == false)
    }

    @Test
    func bootstrapRepairsLoadedListParentCycle() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))
        try await appendStoredParentId("B", to: "A", in: setup)
        try await appendStoredParentId("A", to: "B", in: setup)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.lists.first { $0.id == "A" }?.parentId == nil)
        #expect(store.lists.first { $0.id == "B" }?.parentId == nil)
    }

    @Test
    func bootstrapRepairsLoadedItemWithMissingParentAndStaleSection() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(ItemList(id: "l1", name: "Work", icon: "tray", color: .blue,
                                           createdAt: .now, modifiedAt: .now, position: 0))
        let item = Item(
            type: .task,
            title: "Visible again",
            listId: "l1",
            section: UUID().uuidString,
            parentId: UUID()
        )
        try await setup.writeItem(item)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.item(item.id)?.parentId == nil)
        #expect(store.item(item.id)?.section == nil)

        let reloaded = try await FileStore(root: root).loadAll()
        let repaired = reloaded.lists.flatMap(\.items).first { $0.id == item.id }
        #expect(repaired?.parentId == nil)
        #expect(repaired?.section == nil)
    }

    @Test
    func bootstrapTombstonesActiveItemsInsideDeletedList() async throws {
        let root = freshRoot()
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(ItemList(id: "l1", name: "Work", icon: "tray", color: .blue,
                                           createdAt: .now, modifiedAt: .now, position: 0,
                                           deletedAt: deletedAt))
        let item = Item(type: .task, title: "Should be deleted too", listId: "l1")
        try await setup.writeItem(item)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.item(item.id)?.deletedAt == deletedAt)
        #expect(store.deletedItems.map(\.id) == [item.id])

        let reloaded = try await FileStore(root: root).loadAll()
        let repaired = reloaded.lists.flatMap(\.items).first { $0.id == item.id }
        #expect(repaired?.deletedAt == deletedAt)
    }

    @Test
    func bootstrapPreservesLoadedHabitMarkdownBody() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(ItemList(id: "l1", name: "Habits", icon: "repeat", color: .green,
                                           createdAt: .now, modifiedAt: .now, position: 0))
        let habit = Item(type: .habit, title: "Stretch", body: "Legacy notes", listId: "l1",
                         frequency: .daily)
        try await setup.writeItem(habit)
        let beforeBootstrap = try await setup.loadAll()
        let original = try #require(beforeBootstrap.lists.flatMap(\.items).first { $0.id == habit.id })

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.item(habit.id)?.body == original.body)

        let reloaded = try await FileStore(root: root).loadAll()
        let repaired = reloaded.lists.flatMap(\.items).first { $0.id == habit.id }
        #expect(repaired?.body == original.body)
    }

    @Test
    func bootstrapRepairsLoadedEventStartAndEnd() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(ItemList(id: "l1", name: "Events", icon: "calendar", color: .blue,
                                           createdAt: .now, modifiedAt: .now, position: 0))
        let event = Item(type: .event, title: "Undated event", listId: "l1")
        try await setup.writeItem(event)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let live = try #require(store.item(event.id))
        let due = try #require(live.due)
        let end = try #require(live.end)
        #expect(end > due)

        let reloaded = try await FileStore(root: root).loadAll()
        let repaired = try #require(reloaded.lists.flatMap(\.items).first { $0.id == event.id })
        #expect(repaired.due != nil)
        #expect(repaired.end != nil)
    }

    @Test
    func bootstrapRepairsLoadedChildSectionFromParent() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        let section = ListSection(name: "Active", position: 0)
        try await setup.writeList(ItemList(id: "l1", name: "Work", icon: "tray", color: .blue,
                                           createdAt: .now, modifiedAt: .now, position: 0,
                                           sections: [section]))
        let parent = Item(type: .task, title: "Parent", listId: "l1", section: section.id.uuidString)
        let child = Item(
            type: .task,
            title: "Child",
            listId: "l1",
            section: UUID().uuidString,
            parentId: parent.id
        )
        try await setup.writeItem(parent)
        try await setup.writeItem(child)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.item(child.id)?.parentId == parent.id)
        #expect(store.item(child.id)?.section == section.id.uuidString)

        let reloaded = try await FileStore(root: root).loadAll()
        let repaired = reloaded.lists.flatMap(\.items).first { $0.id == child.id }
        #expect(repaired?.section == section.id.uuidString)
    }

    @Test
    func bootstrapRepeatsHierarchyRepairUntilChildrenFollowRepairedParents() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(ItemList(id: "l1", name: "Work", icon: "tray", color: .blue,
                                           createdAt: .now, modifiedAt: .now, position: 0))
        let staleSection = UUID().uuidString
        let parent = Item(type: .task, title: "Parent", listId: "l1", section: staleSection)
        let child = Item(type: .task, title: "Child", listId: "l1",
                         section: staleSection, parentId: parent.id)
        try await setup.writeItem(child)
        try await setup.writeItem(parent)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.item(parent.id)?.section == nil)
        #expect(store.item(child.id)?.section == nil)

        let reloaded = try await FileStore(root: root).loadAll()
        let repaired = reloaded.lists.flatMap(\.items).first { $0.id == child.id }
        #expect(repaired?.section == nil)
    }
}
