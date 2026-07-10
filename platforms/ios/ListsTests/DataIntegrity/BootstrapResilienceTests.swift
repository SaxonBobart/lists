import Foundation
import Testing
@testable import Lists

/// Bootstrap must never leave the app wedged on "Loading…", must surface
/// quarantined files, and must not re-seed sample data on top of a library
/// that loaded partially.
@MainActor
struct BootstrapResilienceTests {

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
    func emptyRootStillSeeds() async throws {
        let store = ItemStore(store: FileStore(root: freshRoot()))
        try await store.bootstrap()

        #expect(store.isLoaded)
        #expect(store.loadIssues.isEmpty)
        #expect(store.lists.isEmpty == false, "a genuinely empty library still seeds sample data")
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
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try await setup.writeList(makeList(id: "parent", name: "Parent", deletedAt: deletedAt))
        try await setup.writeList(makeList(id: "child", name: "Child", parentId: "parent"))

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.lists.first { $0.id == "child" }?.parentId == nil)

        let reloaded = try await FileStore(root: root).loadAll()
        #expect(reloaded.lists.map(\.list).first { $0.id == "child" }?.parentId == nil)
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
