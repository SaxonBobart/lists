import Foundation
import Testing
@testable import Lists

/// Store mutation ordering is hard to prove with sleeps, so these tests lock the
/// observable promises: bootstrapping is idempotent, bulk edits update every
/// carrier, and deferred writes cannot overwrite newer user edits.
@MainActor
struct StoreConcurrencyTests {

    private enum ReloadProbeError: Error, Equatable {
        case forcedFailure
    }

    private enum FlagProbeError: Error, Equatable {
        case forcedFailure
    }

    private final class OneShotSignal: Sendable {
        private let stream: AsyncStream<Void>
        private let continuation: AsyncStream<Void>.Continuation

        init() {
            let (stream, continuation) = AsyncStream<Void>.makeStream(
                bufferingPolicy: .bufferingNewest(1)
            )
            self.stream = stream
            self.continuation = continuation
        }

        deinit {
            continuation.finish()
        }

        func send() {
            continuation.yield()
            continuation.finish()
        }

        func wait() async {
            for await _ in stream { return }
        }
    }

    @MainActor
    private final class ReloadGate {
        private let snapshotCaptured = OneShotSignal()
        private let snapshotOpened = OneShotSignal()
        private let mutationDeferred = OneShotSignal()
        private let reloadCallerDeferred = OneShotSignal()
        private let mutationWriteCommitted = OneShotSignal()
        private let mutationCanFinish = OneShotSignal()
        private let reloadWaitingForMutations = OneShotSignal()

        func pauseAtSnapshot() async {
            snapshotCaptured.send()
            await snapshotOpened.wait()
        }

        func waitUntilSnapshotCaptured() async {
            await snapshotCaptured.wait()
        }

        func noteMutationDeferred() {
            mutationDeferred.send()
        }

        func waitUntilMutationDeferred() async {
            await mutationDeferred.wait()
        }

        func noteReloadCallerDeferred() {
            reloadCallerDeferred.send()
        }

        func waitUntilReloadCallerDeferred() async {
            await reloadCallerDeferred.wait()
        }

        func open() {
            snapshotOpened.send()
        }

        func pauseAfterMutationWrite() async {
            mutationWriteCommitted.send()
            await mutationCanFinish.wait()
        }

        func waitUntilMutationWriteIsCommitted() async {
            await mutationWriteCommitted.wait()
        }

        func finishMutation() {
            mutationCanFinish.send()
        }

        func noteReloadWaitingForMutations() {
            reloadWaitingForMutations.send()
        }

        func waitUntilReloadIsWaitingForMutations() async {
            await reloadWaitingForMutations.wait()
        }
    }

    @MainActor
    private final class FailingFlagGate {
        private let writeReached = OneShotSignal()
        private let writeReleased = OneShotSignal()
        private var shouldFail = true

        func pauseThenFailOnce() async throws {
            writeReached.send()
            await writeReleased.wait()
            guard shouldFail else { return }
            shouldFail = false
            throw FlagProbeError.forcedFailure
        }

        func waitUntilWriteReached() async {
            await writeReached.wait()
        }

        func releaseWrite() {
            writeReleased.send()
        }
    }

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

    @Test(.timeLimit(.minutes(1)))
    func reloadDefersAwaitedAddUntilItsSnapshotIsCommitted() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcReloadAdd-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                snapshotCaptured: { await gate.pauseAtSnapshot() },
                mutationDeferred: { gate.noteMutationDeferred() }
            )
        )
        try await store.bootstrap()

        async let reload: Void = store.reloadFromDisk()
        await gate.waitUntilSnapshotCaptured()
        let added = Item(
            type: .task,
            title: "Added during rebuild",
            listId: ItemList.inboxId
        )
        async let add: Void = store.add(added)
        await gate.waitUntilMutationDeferred()

        #expect(
            store.item(added.id) == nil,
            "a gated mutation must not optimistically change the captured snapshot")
        gate.open()
        try await reload
        try await add

        #expect(store.items.filter { $0.id == added.id }.count == 1)
        let cold = try await FileStore(root: root).loadAll()
        #expect(cold.lists.flatMap(\.items).filter { $0.id == added.id }.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func reloadWaitsForPostWriteMutationContinuationBeforeLoading() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcReloadScope-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                mutationWriteCommitted: { await gate.pauseAfterMutationWrite() },
                maintenanceWaitingForMutations: {
                    gate.noteReloadWaitingForMutations()
                }
            )
        )
        try await store.bootstrap()

        let added = Item(
            type: .task,
            title: "One committed item",
            listId: ItemList.inboxId
        )
        async let add: Void = store.add(added)
        await gate.waitUntilMutationWriteIsCommitted()
        #expect(store.items.filter { $0.id == added.id }.isEmpty)

        async let reload: Void = store.reloadFromDisk()
        await gate.waitUntilReloadIsWaitingForMutations()
        gate.finishMutation()
        try await add
        try await reload

        #expect(
            store.items.filter { $0.id == added.id }.count == 1,
            "reload must not race the caller's post-write append into a duplicate")
        let cold = try await FileStore(root: root).loadAll()
        #expect(cold.lists.flatMap(\.items).filter { $0.id == added.id }.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func reloadWaitsForRecurringCompletionToCreateItsSuccessor() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcReloadRecurrence-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                recurringSuccessorCommitted: { await gate.pauseAfterMutationWrite() },
                maintenanceWaitingForMutations: {
                    gate.noteReloadWaitingForMutations()
                }
            )
        )
        try await store.bootstrap()

        let due = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let recurring = Item(
            type: .task,
            title: "Recurring rebuild race",
            listId: ItemList.inboxId,
            due: due,
            recurrence: Recurrence(rrule: "FREQ=DAILY")
        )
        try await store.add(recurring)

        async let toggle: Void = store.toggleDone(recurring.id)
        await gate.waitUntilMutationWriteIsCommitted()
        #expect(store.item(recurring.id)?.done == true)

        async let reload: Void = store.reloadFromDisk()
        await gate.waitUntilReloadIsWaitingForMutations()
        gate.finishMutation()
        try await toggle
        try await reload

        let liveSeries = store.items.filter { $0.title == recurring.title }
        #expect(liveSeries.first { $0.id == recurring.id }?.done == true)
        #expect(liveSeries.filter { $0.id != recurring.id && !$0.done }.count == 1)

        let cold = try await FileStore(root: root).loadAll()
        let coldSeries = cold.lists.flatMap(\.items).filter { $0.title == recurring.title }
        #expect(coldSeries.first { $0.id == recurring.id }?.done == true)
        #expect(coldSeries.filter { $0.id != recurring.id && !$0.done }.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func recurringSuccessorInheritsAnEditMadeWhileCompletionPersists() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcRecurrenceEdit-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                recurringSuccessorCommitted: { await gate.pauseAfterMutationWrite() }
            )
        )
        try await store.bootstrap()

        let due = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let recurring = Item(
            type: .task,
            title: "Original recurring title",
            body: "Original notes",
            listId: ItemList.inboxId,
            due: due,
            recurrence: Recurrence(rrule: "FREQ=DAILY")
        )
        try await store.add(recurring)

        async let toggle: Void = store.toggleDone(recurring.id)
        await gate.waitUntilMutationWriteIsCommitted()

        var edited = try #require(store.item(recurring.id))
        edited.title = "Edited while saving"
        edited.body = "Latest notes"
        edited.tags = ["current"]
        store.applyUpdateSync(edited)
        #expect(store.item(recurring.id)?.title == edited.title)
        let editModifiedAt = try #require(store.item(recurring.id)?.modifiedAt)

        gate.finishMutation()
        try await toggle
        try await store.flushPendingWrites()

        let successor = try #require(store.items.first {
            $0.recurrenceSourceId == recurring.id
        })
        #expect(successor.title == edited.title)
        #expect(successor.body == edited.body)
        #expect(successor.tags == edited.tags)
        #expect(successor.modifiedAt >= editModifiedAt)
        #expect(store.item(recurring.id)?.recurrenceSuccessorId == successor.id)

        let cold = try await FileStore(root: root).loadAll().lists.flatMap(\.items)
        let coldSuccessor = try #require(cold.first { $0.id == successor.id })
        #expect(coldSuccessor.title == edited.title)
        #expect(coldSuccessor.body.trimmingCharacters(in: .newlines) == edited.body)
        #expect(coldSuccessor.tags == edited.tags)
        #expect(cold.first { $0.id == recurring.id }?.recurrenceSuccessorId == successor.id)
    }

    @Test(.timeLimit(.minutes(1)))
    func reloadReplaysDeferredSynchronousEditBeforeReopening() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcReloadSync-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                snapshotCaptured: { await gate.pauseAtSnapshot() },
                mutationDeferred: { gate.noteMutationDeferred() }
            )
        )
        try await store.bootstrap()
        let original = try #require(store.items.first { $0.listId == ItemList.inboxId })

        async let reload: Void = store.reloadFromDisk()
        await gate.waitUntilSnapshotCaptured()
        var edited = original
        edited.title = "Edited during rebuild"
        store.applyUpdateSync(edited)
        await gate.waitUntilMutationDeferred()

        #expect(store.item(original.id)?.title == original.title)
        gate.open()
        try await reload
        try await store.flushPendingWrites()

        #expect(store.item(original.id)?.title == edited.title)
        let cold = try await FileStore(root: root).loadAll()
        #expect(cold.lists.flatMap(\.items).first { $0.id == original.id }?.title == edited.title)
    }

    @Test(.timeLimit(.minutes(1)))
    func failedReloadStillReplaysAnAcceptedSynchronousEdit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcReloadFailedSync-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                snapshotCaptured: {
                    await gate.pauseAtSnapshot()
                    throw ReloadProbeError.forcedFailure
                },
                mutationDeferred: { gate.noteMutationDeferred() }
            )
        )
        try await store.bootstrap()
        let original = try #require(store.items.first { $0.listId == ItemList.inboxId })

        async let reload: Void = store.reloadFromDisk()
        await gate.waitUntilSnapshotCaptured()
        var edited = original
        edited.title = "Preserved despite failed rebuild"
        store.applyUpdateSync(edited)
        await gate.waitUntilMutationDeferred()
        gate.open()

        do {
            try await reload
            Issue.record("reload must surface its injected failure")
        } catch let error as ReloadProbeError {
            #expect(error == .forcedFailure)
        }
        try await store.flushPendingWrites()

        #expect(store.item(original.id)?.title == edited.title)
        let cold = try await FileStore(root: root).loadAll()
        #expect(cold.lists.flatMap(\.items).first { $0.id == original.id }?.title == edited.title)
    }

    @Test(.timeLimit(.minutes(1)))
    func exportUsesOneSnapshotAndReplaysMutationsInArrivalOrder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcExportOrdering-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                mutationDeferred: { gate.noteMutationDeferred() },
                exportSnapshotReady: { await gate.pauseAtSnapshot() }
            )
        )
        try await store.bootstrap()
        let original = Item(
            type: .task,
            title: "Export snapshot original",
            listId: ItemList.inboxId
        )
        try await store.add(original)

        async let exportURL: URL = store.exportLibrary()
        await gate.waitUntilSnapshotCaptured()

        let awaitedTitle = "First awaited edit"
        var awaitedEdit = original
        awaitedEdit.title = awaitedTitle
        async let awaitedUpdate: Void = store.update(awaitedEdit)
        await gate.waitUntilMutationDeferred()

        let synchronousTitle = "Second synchronous edit"
        var synchronousEdit = original
        synchronousEdit.title = synchronousTitle
        store.applyUpdateSync(synchronousEdit)
        gate.open()

        let archive = try await exportURL
        try await awaitedUpdate
        try await store.flushPendingWrites()

        let archiveText = String(decoding: try Data(contentsOf: archive), as: UTF8.self)
        #expect(archiveText.contains(original.title))
        #expect(!archiveText.contains(awaitedTitle))
        #expect(!archiveText.contains(synchronousTitle))
        #expect(store.item(original.id)?.title == synchronousTitle)

        let cold = try await FileStore(root: root).loadAll()
        #expect(
            cold.lists.flatMap(\.items).first { $0.id == original.id }?.title
                == synchronousTitle
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func failedDeferredFlushStillDrainsANewlyAcceptedEdit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcReloadDrainFailure-\(UUID().uuidString)")
        let gate = ReloadGate()
        let fileStore = FileStore(root: root)
        let store = ItemStore(
            store: fileStore,
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                snapshotCaptured: { await gate.pauseAtSnapshot() },
                mutationDeferred: { gate.noteMutationDeferred() },
                deferredDrainWillFlush: { await gate.pauseAfterMutationWrite() }
            )
        )
        try await store.bootstrap()
        let blocked = Item(type: .task, title: "Blocked write", listId: ItemList.inboxId)
        let later = Item(type: .task, title: "Later write", listId: ItemList.inboxId)
        try await store.add(blocked)
        try await store.add(later)

        async let reload: Void = store.reloadFromDisk()
        await gate.waitUntilSnapshotCaptured()

        let inboxDirectory = try await fileStore.listDirectory(for: ItemList.inboxId)
        let blockedURL = inboxDirectory.appendingPathComponent("\(blocked.id.uuidString).md")
        let blockedBytes = try sabotageMarkdownPath(blockedURL)

        var blockedEdit = blocked
        blockedEdit.title = "Fails during replay"
        store.applyUpdateSync(blockedEdit)
        await gate.waitUntilMutationDeferred()
        gate.open()

        await gate.waitUntilMutationWriteIsCommitted()
        var laterEdit = later
        laterEdit.title = "Accepted after the failed replay write"
        store.applyUpdateSync(laterEdit)
        gate.finishMutation()

        do {
            try await reload
            Issue.record("the failed deferred write must fail the rebuild")
        } catch {
            #expect(error.localizedDescription.contains("couldn't finish saving"))
        }

        #expect(store.item(later.id)?.title == laterEdit.title)
        let laterURL = inboxDirectory.appendingPathComponent("\(later.id.uuidString).md")
        let persistedLater = try await fileStore.readItem(at: laterURL)
        #expect(persistedLater.title == laterEdit.title)
        try repairMarkdownPath(blockedURL, originalBytes: blockedBytes)
    }

    @Test(.timeLimit(.minutes(1)))
    func concurrentReloadCallerAwaitsAndReceivesTheSameFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcReloadJoin-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                snapshotCaptured: {
                    await gate.pauseAtSnapshot()
                    throw ReloadProbeError.forcedFailure
                },
                reloadCallerDeferred: { gate.noteReloadCallerDeferred() }
            )
        )
        try await store.bootstrap()

        async let first: Void = store.reloadFromDisk()
        await gate.waitUntilSnapshotCaptured()
        async let second: Void = store.reloadFromDisk()
        await gate.waitUntilReloadCallerDeferred()
        gate.open()

        do {
            try await first
            Issue.record("the owning reload must surface its injected failure")
        } catch let error as ReloadProbeError {
            #expect(error == .forcedFailure)
        }
        do {
            try await second
            Issue.record("a joined reload must not report false success")
        } catch let error as ReloadProbeError {
            #expect(error == .forcedFailure)
        }
        #expect(store.isReloadingFromDisk == false)
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

    @Test func activeRestoreRootCanRetryJournalCleanupInProcess() async throws {
        let (store, root) = try await emptyStore()
        let item = Item(type: .task, title: "Restore cleanup", listId: ItemList.inboxId)
        try await store.add(item)
        try await store.softDelete(item.id)
        let deleted = try #require(store.item(item.id))
        let deletedAt = try #require(deleted.deletedAt)

        let fileStore = FileStore(root: root)
        _ = try await fileStore.loadAll()
        let journal = FileStore.RestoreJournal(
            kind: .item,
            rootId: item.id.uuidString,
            deletedAt: deletedAt
        )
        _ = try await fileStore.beginRestore(journal)
        var active = deleted
        active.deletedAt = nil
        active.modifiedAt = .now
        try await fileStore.writeItem(active)

        let fileManager = FileManager.default
        let originalPermissions = try #require(
            fileManager.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        )
        var permissionsRestored = false
        defer {
            if !permissionsRestored {
                try? fileManager.setAttributes(
                    [.posixPermissions: originalPermissions],
                    ofItemAtPath: root.path
                )
            }
        }
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)

        let restarted = ItemStore(store: FileStore(root: root))
        await #expect(throws: (any Error).self) {
            try await restarted.bootstrap()
        }
        #expect(restarted.item(item.id)?.deletedAt == nil)
        #expect(restarted.pendingRestoreCleanup == .item(item.id))
        #expect(try await FileStore(root: root).pendingRestore() != nil)

        try fileManager.setAttributes(
            [.posixPermissions: originalPermissions],
            ofItemAtPath: root.path
        )
        permissionsRestored = true
        try await restarted.restore(item.id)
        try await restarted.flushPendingWrites()

        #expect(restarted.pendingRestoreCleanup == nil)
        #expect(try await FileStore(root: root).pendingRestore() == nil)
        #expect(restarted.item(item.id)?.deletedAt == nil)
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

    @Test func failedToggleRollsBackAndRetryAfterPathRepairSucceeds() async throws {
        let context = try await sectionedHierarchy()
        let itemURL = try await itemURL(context.rootItem, in: context)
        let originalBytes = try sabotageMarkdownPath(itemURL)

        do {
            try await context.store.toggleDone(context.rootItem.id)
            Issue.record("a sabotaged item path must reject completion")
        } catch {}

        #expect(context.store.item(context.rootItem.id) == context.rootItem)
        try repairMarkdownPath(itemURL, originalBytes: originalBytes)
        #expect(try await context.fileStore.readItem(at: itemURL).done == false)

        try await context.store.toggleDone(context.rootItem.id)

        #expect(context.store.item(context.rootItem.id)?.done == true)
        #expect(try await context.fileStore.readItem(at: itemURL).done == true)
    }

    @Test func failedFlagToggleStaysUnchangedAndRetryPersists() async throws {
        let context = try await sectionedHierarchy()
        let itemURL = try await itemURL(context.rootItem, in: context)
        let originalBytes = try sabotageMarkdownPath(itemURL)

        do {
            try await context.store.toggleFlagged(context.rootItem.id)
            Issue.record("a sabotaged item path must reject flagging")
        } catch {}

        #expect(context.store.item(context.rootItem.id) == context.rootItem)
        try repairMarkdownPath(itemURL, originalBytes: originalBytes)
        #expect(try await context.fileStore.readItem(at: itemURL).flagged == false)

        try await context.store.toggleFlagged(context.rootItem.id)

        #expect(context.store.item(context.rootItem.id)?.flagged == true)
        #expect(try await context.fileStore.readItem(at: itemURL).flagged == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func flagToggleDoesNotOverwriteAnEditMadeWhileItPersists() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcFlagEdit-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                flagWriteCommitted: { await gate.pauseAfterMutationWrite() }
            )
        )
        try await store.bootstrap()
        let item = Item(type: .task, title: "Before", listId: ItemList.inboxId)
        try await store.add(item)

        async let flag: Void = store.toggleFlagged(item.id)
        await gate.waitUntilMutationWriteIsCommitted()
        var edited = try #require(store.item(item.id))
        edited.title = "After"
        store.applyUpdateSync(edited)

        gate.finishMutation()
        try await flag
        try await store.flushPendingWrites()

        let live = try #require(store.item(item.id))
        #expect(live.title == "After")
        #expect(live.flagged == true)
        let cold = try await FileStore(root: root).loadAll().lists.flatMap(\.items)
        let persisted = try #require(cold.first { $0.id == item.id })
        #expect(persisted.title == "After")
        #expect(persisted.flagged == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func failedFlagTogglePreservesAConcurrentEditWithoutPublishingTheFlag() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcFlagFailureEdit-\(UUID().uuidString)")
        let gate = FailingFlagGate()
        let store = ItemStore(
            store: FileStore(root: root),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                flagWriteWillCommit: { try await gate.pauseThenFailOnce() }
            )
        )
        try await store.bootstrap()
        let item = Item(type: .task, title: "Before", listId: ItemList.inboxId)
        try await store.add(item)

        async let flag: Void = store.toggleFlagged(item.id)
        await gate.waitUntilWriteReached()
        var edited = try #require(store.item(item.id))
        edited.title = "After"
        store.applyUpdateSync(edited)
        gate.releaseWrite()

        do {
            try await flag
            Issue.record("the injected flag write failure must be surfaced")
        } catch let error as FlagProbeError {
            #expect(error == .forcedFailure)
        }
        do {
            try await store.flushPendingWrites()
            Issue.record("the failed flag operation must remain observable")
        } catch {}

        let live = try #require(store.item(item.id))
        #expect(live.title == "After")
        #expect(live.flagged == false)
        let cold = try await FileStore(root: root).loadAll().lists.flatMap(\.items)
        let persisted = try #require(cold.first { $0.id == item.id })
        #expect(persisted.title == "After")
        #expect(persisted.flagged == false)
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
