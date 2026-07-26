import Foundation
import Testing
@testable import Lists

/// Store mutation ordering is hard to prove with sleeps, so these tests lock the
/// observable promises: bootstrapping is idempotent, bulk edits update every
/// carrier, and deferred writes cannot overwrite newer user edits.
@MainActor
struct StoreConcurrencyTests {

    private struct NoopNotificationScheduler: NotificationScheduling {
        func schedule(_ item: Item) async {}
        func cancel(_ id: UUID) async {}
    }

    private actor RecordingNotificationScheduler: NotificationScheduling {
        enum Event: Equatable, Sendable {
            case schedule(Item)
            case cancel(UUID)
        }

        private var events: [Event] = []

        func schedule(_ item: Item) {
            events.append(.schedule(item))
        }

        func cancel(_ id: UUID) {
            events.append(.cancel(id))
        }

        func reset() {
            events.removeAll()
        }

        func recordedEvents() -> [Event] {
            events
        }
    }

    private actor ReconciliationNotificationScheduler: NotificationScheduling {
        private var snapshots: [[Item]] = []
        private var scheduledItems: [Item] = []

        func schedule(_ item: Item) { scheduledItems.append(item) }
        func cancel(_ id: UUID) {}
        func reconcile(_ items: [Item]) {
            snapshots.append(items)
        }

        func reconciledSnapshots() -> [[Item]] {
            snapshots
        }

        func individuallyScheduledItems() -> [Item] {
            scheduledItems
        }
    }

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
        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler()
        )
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
        let store = ItemStore(
            store: fileStore,
            scheduler: NoopNotificationScheduler()
        )
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
            .appendingPathComponent(FileStore.documentBaseFileName(for: item))
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

    /// Block a not-yet-created readable filename. Title-changing writes move
    /// to a new public path, so sabotaging only the old file no longer models
    /// a failure at the actual destination.
    private func blockMarkdownPath(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    private func unblockMarkdownPath(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    // Two bootstraps racing on a fresh root must not both seed.
    @Test func concurrentBootstrapSeedsInboxOnce() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcBoot-\(UUID().uuidString)")
        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler()
        )
        async let first: Void = store.bootstrap()
        async let second: Void = store.bootstrap()
        _ = try await (first, second)
        #expect(store.lists.filter { $0.id == ItemList.inboxId }.count == 1,
                "a re-entrant bootstrap must not seed a second Inbox")
    }

    @Test func bootstrapAndReloadReconcileNotificationsFromDurableItems() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcNotificationReconcile-\(UUID().uuidString)")
        let notifications = ReconciliationNotificationScheduler()
        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: notifications
        )

        try await store.bootstrap()
        let bootstrappedItems = store.items
        var snapshots = await notifications.reconciledSnapshots()
        #expect(snapshots == [bootstrappedItems])

        try await store.reloadFromDisk()
        snapshots = await notifications.reconciledSnapshots()
        #expect(snapshots.count == 2)
        #expect(snapshots.first == bootstrappedItems)
        #expect(snapshots.last == store.items)
    }

    @Test func partialBootstrapRefreshesKnownRemindersWithoutDestructiveReconcile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcPartialNotification-\(UUID().uuidString)")
        let fileStore = FileStore(root: root)
        try await fileStore.ensureRoot()
        let list = ItemList(
            id: "partial-reminders",
            name: "Partial reminders",
            icon: "bell",
            color: .orange,
            createdAt: .now,
            modifiedAt: .now,
            position: 1
        )
        try await fileStore.writeList(list)
        let valid = Item(
            type: .task,
            title: "Known reminder",
            listId: list.id,
            due: .now.addingTimeInterval(3_600),
            reminder: Reminder(enabled: true)
        )
        try await fileStore.writeItem(valid)
        let directory = try await fileStore.listDirectory(for: list.id)
        try Data("broken".utf8).write(
            to: directory.appendingPathComponent("\(UUID().uuidString).md"),
            options: .atomic
        )
        let notifications = ReconciliationNotificationScheduler()
        let store = ItemStore(store: FileStore(root: root), scheduler: notifications)

        try await store.bootstrap()

        #expect(store.loadIssues.count == 1)
        #expect(await notifications.reconciledSnapshots().isEmpty)
        #expect(await notifications.individuallyScheduledItems().map(\.id) == [valid.id])
    }

    @Test(.timeLimit(.minutes(1)))
    func reloadDefersAwaitedAddUntilItsSnapshotIsCommitted() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcReloadAdd-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler(),
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
            scheduler: NoopNotificationScheduler(),
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
    func reloadWaitsForRecurringCompletionToAdvanceItsDocument() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcReloadRecurrence-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler(),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                recurringOccurrenceCommitted: { await gate.pauseAfterMutationWrite() },
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
        let optimistic = try #require(store.item(recurring.id))
        #expect(optimistic.done == false)
        #expect(try #require(optimistic.due) > due)
        #expect(optimistic.recurrenceOccurrences.map(\.status) == [.completed, .open])

        async let reload: Void = store.reloadFromDisk()
        await gate.waitUntilReloadIsWaitingForMutations()
        gate.finishMutation()
        try await toggle
        try await reload

        let liveSeries = store.items.filter { $0.title == recurring.title }
        #expect(liveSeries.count == 1)
        let live = try #require(liveSeries.first)
        #expect(live.id == recurring.id)
        #expect(live.done == false)
        #expect(live.recurrenceOccurrences.map(\.status) == [.completed, .open])

        let cold = try await FileStore(root: root).loadAll()
        let coldSeries = cold.lists.flatMap(\.items).filter { $0.title == recurring.title }
        #expect(coldSeries.count == 1)
        let coldItem = try #require(coldSeries.first)
        #expect(coldItem.id == recurring.id)
        #expect(coldItem.done == false)
        #expect(coldItem.recurrenceOccurrences.map(\.status) == [.completed, .open])
        #expect(abs(
            try #require(coldItem.due).timeIntervalSince(try #require(live.due))
        ) < 0.001)
    }

    @Test(.timeLimit(.minutes(1)))
    func recurringDocumentKeepsAnEditMadeWhileCompletionPersists() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcRecurrenceEdit-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler(),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                recurringOccurrenceCommitted: { await gate.pauseAfterMutationWrite() }
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

        #expect(store.items.filter { $0.id == recurring.id }.count == 1)
        let advanced = try #require(store.item(recurring.id))
        #expect(advanced.title == edited.title)
        #expect(advanced.body == edited.body)
        #expect(advanced.tags == edited.tags)
        #expect(advanced.modifiedAt >= editModifiedAt)
        #expect(try #require(advanced.due) > due)
        #expect(advanced.recurrenceOccurrences.map(\.status) == [.completed, .open])
        #expect(advanced.recurrenceSourceId == nil)
        #expect(advanced.recurrenceSuccessorId == nil)

        let cold = try await FileStore(root: root).loadAll().lists.flatMap(\.items)
        #expect(cold.filter { $0.id == recurring.id }.count == 1)
        let coldItem = try #require(cold.first { $0.id == recurring.id })
        #expect(coldItem.title == edited.title)
        #expect(coldItem.body.trimmingCharacters(in: .newlines) == edited.body)
        #expect(coldItem.tags == edited.tags)
        #expect(coldItem.recurrenceOccurrences.map(\.status) == [.completed, .open])
        #expect(coldItem.recurrenceSourceId == nil)
        #expect(coldItem.recurrenceSuccessorId == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func reloadReplaysDeferredSynchronousEditBeforeReopening() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcReloadSync-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler(),
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
            scheduler: NoopNotificationScheduler(),
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
            scheduler: NoopNotificationScheduler(),
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
            scheduler: NoopNotificationScheduler(),
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
        let blockedURL = inboxDirectory.appendingPathComponent(
            FileStore.documentBaseFileName(for: blocked)
        )
        let blockedBytes = try sabotageMarkdownPath(blockedURL)

        var blockedEdit = blocked
        blockedEdit.title = "Fails during replay"
        let blockedEditURL = inboxDirectory.appendingPathComponent(
            FileStore.documentBaseFileName(for: blockedEdit)
        )
        try blockMarkdownPath(blockedEditURL)
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
        let laterURL = inboxDirectory.appendingPathComponent(
            FileStore.documentBaseFileName(for: laterEdit)
        )
        let persistedLater = try await fileStore.readItem(at: laterURL)
        #expect(persistedLater.title == laterEdit.title)
        try unblockMarkdownPath(blockedEditURL)
        try repairMarkdownPath(blockedURL, originalBytes: blockedBytes)
    }

    @Test(.timeLimit(.minutes(1)))
    func concurrentReloadCallerAwaitsAndReceivesTheSameFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcReloadJoin-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler(),
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

    @Test func failedInlineAddIsReconciledByTheFirstSuccessfulEdit() async throws {
        let (store, root) = try await emptyStore()
        let list = ItemList(
            id: "inline-retry-\(UUID().uuidString)",
            name: "Inline retry",
            icon: "arrow.clockwise",
            color: .blue,
            createdAt: .now,
            modifiedAt: .now,
            position: 10_000
        )
        try await store.addList(list)
        let fileStore = FileStore(root: root)
        _ = try await fileStore.loadAll()
        let directory = try await fileStore.listDirectory(for: list.id)
        let headerURL = directory.appendingPathComponent(".list.yml")
        let headerBytes = try Data(contentsOf: headerURL)
        try FileManager.default.removeItem(at: directory)
        try Data("not a directory".utf8).write(to: directory)

        let id = store.addInlineItem(type: .task, listId: list.id, section: nil)
        do {
            try await store.flushPendingWrites()
            Issue.record("the sabotaged inline add must fail")
        } catch {}
        #expect(store.item(id) != nil, "the editable shell remains available for retry")

        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try headerBytes.write(to: headerURL, options: .atomic)
        var edited = try #require(store.item(id))
        edited.title = "Recovered inline item"
        store.applyUpdateSync(edited)
        try await store.flushPendingWrites()

        let cold = try await FileStore(root: root).loadAll().lists.flatMap(\.items)
        #expect(cold.first { $0.id == id }?.title == edited.title)
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
        let store = ItemStore(
            store: fileStore,
            scheduler: NoopNotificationScheduler()
        )
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

        let originalBlocked = try #require(store.items.first {
            $0.listId == ItemList.inboxId
        })
        var blocked = originalBlocked
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

        // `loadAll` quarantined the deliberately invalid path above. Reload's
        // durability boundary can now replay the retained edit into a valid
        // mapped folder instead of requiring the UI to emit it again.
        try await store.reloadFromDisk()
        #expect(store.item(blocked.id)?.title == blocked.title,
                "reload must include the replayed live edit")

        try await store.flushPendingWrites()
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

        let restarted = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler()
        )
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
        let editedURL = itemURL.deletingLastPathComponent()
            .appendingPathComponent(FileStore.documentBaseFileName(for: edited))
        try blockMarkdownPath(editedURL)

        do {
            try await context.store.update(edited)
            Issue.record("a sabotaged item path must reject update")
        } catch {}

        #expect(context.store.item(edited.id) == context.rootItem,
                "a failed root write must not publish the edit to memory")

        try unblockMarkdownPath(editedURL)
        try repairMarkdownPath(itemURL, originalBytes: originalBytes)
        try await context.store.update(edited)

        let persisted = try await context.fileStore.readItem(at: editedURL)
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
        let notifications = RecordingNotificationScheduler()
        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: notifications,
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                flagWriteCommitted: { await gate.pauseAfterMutationWrite() }
            )
        )
        try await store.bootstrap()
        let item = Item(type: .task, title: "Before", listId: ItemList.inboxId)
        try await store.add(item)
        await notifications.reset()

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
        let events = await notifications.recordedEvents()
        #expect(events == [.schedule(live)])
    }

    @Test(.timeLimit(.minutes(1)))
    func failedFlagTogglePreservesAConcurrentEditWithoutPublishingTheFlag() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcFlagFailureEdit-\(UUID().uuidString)")
        let gate = FailingFlagGate()
        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler(),
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

    @Test func failedSynchronousUpdateDoesNotChangeNotifications() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcUpdateNotificationFailure-\(UUID().uuidString)")
        let fileStore = FileStore(root: root)
        let notifications = RecordingNotificationScheduler()
        let store = ItemStore(store: fileStore, scheduler: notifications)
        try await store.bootstrap()
        let due = Calendar.current.date(byAdding: .day, value: 1, to: .now)
        let item = Item(
            type: .task,
            title: "Original reminder",
            listId: ItemList.inboxId,
            due: due,
            reminder: Reminder(enabled: true)
        )
        try await store.add(item)
        let original = try #require(store.item(item.id))
        await notifications.reset()

        let directory = try await fileStore.listDirectory(for: item.listId)
        let itemURL = directory.appendingPathComponent(FileStore.documentBaseFileName(for: item))
        let originalBytes = try sabotageMarkdownPath(itemURL)
        var edited = item
        edited.title = "Must not be scheduled"
        var latestEdit = edited
        latestEdit.title = "Latest failed edit"
        let editedURL = directory.appendingPathComponent(
            FileStore.documentBaseFileName(for: edited)
        )
        let latestURL = directory.appendingPathComponent(
            FileStore.documentBaseFileName(for: latestEdit)
        )
        try blockMarkdownPath(editedURL)
        try blockMarkdownPath(latestURL)
        store.applyUpdateSync(edited)
        store.applyUpdateSync(latestEdit)

        do {
            try await store.flushPendingWrites()
            Issue.record("the sabotaged synchronous update must fail")
        } catch {}

        let events = await notifications.recordedEvents()
        #expect(events.isEmpty)
        #expect(store.item(item.id)?.title == latestEdit.title)

        try unblockMarkdownPath(editedURL)
        try unblockMarkdownPath(latestURL)
        try repairMarkdownPath(itemURL, originalBytes: originalBytes)
        #expect(try await fileStore.readItem(at: itemURL).title == original.title)
        try await store.flushPendingWrites()

        let live = try #require(store.item(item.id))
        #expect(live.title == latestEdit.title)
        #expect(try await fileStore.readItem(at: latestURL).title == latestEdit.title)
        let retriedEvents = await notifications.recordedEvents()
        #expect(retriedEvents == [.schedule(live)])
    }

    @Test func newerAwaitedEditSupersedesAnOlderRetainedEditorWrite() async throws {
        let (store, root) = try await emptyStore()
        let fileStore = FileStore(root: root)
        let item = Item(
            type: .task,
            title: "Original",
            listId: ItemList.inboxId
        )
        try await store.add(item)
        _ = try await fileStore.loadAll()
        let directory = try await fileStore.listDirectory(for: item.listId)
        let itemURL = directory.appendingPathComponent(FileStore.documentBaseFileName(for: item))
        let originalBytes = try sabotageMarkdownPath(itemURL)

        var retained = try #require(store.item(item.id))
        retained.title = "Older retained editor value"
        let retainedURL = directory.appendingPathComponent(
            FileStore.documentBaseFileName(for: retained)
        )
        try blockMarkdownPath(retainedURL)
        store.applyUpdateSync(retained)
        do {
            try await store.flushPendingWrites()
            Issue.record("the sabotaged editor write must remain retained")
        } catch {}

        try unblockMarkdownPath(retainedURL)
        try repairMarkdownPath(itemURL, originalBytes: originalBytes)
        var newest = try #require(store.item(item.id))
        newest.title = "Newer awaited value"
        let newestURL = directory.appendingPathComponent(
            FileStore.documentBaseFileName(for: newest)
        )
        try await store.update(newest)
        try await store.flushPendingWrites()

        #expect(store.item(item.id)?.title == newest.title)
        #expect(try await fileStore.readItem(at: newestURL).title == newest.title)
    }

    @Test(.timeLimit(.minutes(1)))
    func synchronousEditorValueWinsAnOlderSuspendedAwaitedUpdate() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcItemIntent-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler(),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                itemWriteCommitted: { await gate.pauseAfterMutationWrite() }
            )
        )
        try await store.bootstrap()
        let item = Item(
            type: .task,
            title: "Original",
            listId: ItemList.inboxId
        )
        try await store.add(item)

        var older = item
        older.title = "Older awaited value"
        let awaitedBody = "Independent awaited notes"
        older.body = awaitedBody
        async let update: Void = store.update(older)
        await gate.waitUntilMutationWriteIsCommitted()

        var newest = try #require(store.item(item.id))
        newest.title = "Newer synchronous value"
        store.applyUpdateSync(newest)
        gate.finishMutation()
        try await update
        try await store.flushPendingWrites()

        #expect(store.item(item.id)?.title == newest.title)
        #expect(store.item(item.id)?.body == awaitedBody)
        let cold = try await FileStore(root: root).loadAll().lists.flatMap(\.items)
        #expect(cold.first { $0.id == item.id }?.title == newest.title)
        #expect(
            cold.first { $0.id == item.id }?.body
                .trimmingCharacters(in: .newlines) == awaitedBody
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func newerSynchronousMoveAdvancesFromTheAwaitedMovesDurableLocation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcMoveIntent-\(UUID().uuidString)")
        let gate = ReloadGate()
        let fileStore = FileStore(root: root)
        let store = ItemStore(
            store: fileStore,
            scheduler: NoopNotificationScheduler(),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                itemWriteCommitted: { await gate.pauseAfterMutationWrite() }
            )
        )
        try await store.bootstrap()
        let firstDestination = ItemList(
            id: "move-intent-first-\(UUID().uuidString)",
            name: "First destination",
            icon: "1.circle",
            color: .blue,
            createdAt: .now,
            modifiedAt: .now,
            position: 10_000
        )
        let finalDestination = ItemList(
            id: "move-intent-final-\(UUID().uuidString)",
            name: "Final destination",
            icon: "2.circle",
            color: .green,
            createdAt: .now,
            modifiedAt: .now,
            position: 11_000
        )
        try await store.addList(firstDestination)
        try await store.addList(finalDestination)
        let item = Item(
            type: .task,
            title: "Moving item",
            listId: ItemList.inboxId
        )
        try await store.add(item)
        let sourceURL = try await fileStore.listDirectory(for: ItemList.inboxId)
            .appendingPathComponent(FileStore.documentBaseFileName(for: item))
        let firstURL = try await fileStore.listDirectory(for: firstDestination.id)
            .appendingPathComponent(FileStore.documentBaseFileName(for: item))

        var olderMove = item
        olderMove.listId = firstDestination.id
        async let update: Void = store.update(olderMove)
        await gate.waitUntilMutationWriteIsCommitted()

        var newestMove = try #require(store.item(item.id))
        newestMove.listId = finalDestination.id
        newestMove.title = "Latest destination value"
        let finalURL = try await fileStore.listDirectory(for: finalDestination.id)
            .appendingPathComponent(FileStore.documentBaseFileName(for: newestMove))
        store.applyUpdateSync(newestMove)
        gate.finishMutation()
        try await update
        try await store.flushPendingWrites()

        #expect(FileManager.default.fileExists(atPath: sourceURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: firstURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: finalURL.path))
        let coldMatches = try await FileStore(root: root).loadAll()
            .lists.flatMap(\.items).filter { $0.id == item.id }
        #expect(coldMatches.count == 1)
        #expect(coldMatches.first?.listId == finalDestination.id)
        #expect(coldMatches.first?.title == newestMove.title)
    }

    @Test func laterFlagWriteReconcilesRetainedReminderEdit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcRetainedReminderFlag-\(UUID().uuidString)")
        let fileStore = FileStore(root: root)
        let notifications = RecordingNotificationScheduler()
        let store = ItemStore(store: fileStore, scheduler: notifications)
        try await store.bootstrap()
        let item = Item(
            type: .task,
            title: "Original reminder",
            listId: ItemList.inboxId,
            due: .now.addingTimeInterval(3_600),
            reminder: Reminder(enabled: true)
        )
        try await store.add(item)
        await notifications.reset()
        let directory = try await fileStore.listDirectory(for: item.listId)
        let itemURL = directory.appendingPathComponent(FileStore.documentBaseFileName(for: item))
        let originalBytes = try sabotageMarkdownPath(itemURL)
        var edited = try #require(store.item(item.id))
        edited.title = "Retained reminder edit"
        let editedURL = directory.appendingPathComponent(
            FileStore.documentBaseFileName(for: edited)
        )
        try blockMarkdownPath(editedURL)
        store.applyUpdateSync(edited)

        do {
            try await store.flushPendingWrites()
            Issue.record("the sabotaged reminder edit must remain pending")
        } catch {}
        #expect(await notifications.recordedEvents().isEmpty)

        try unblockMarkdownPath(editedURL)
        try repairMarkdownPath(itemURL, originalBytes: originalBytes)
        try await store.toggleFlagged(item.id)
        try await store.flushPendingWrites()

        let live = try #require(store.item(item.id))
        #expect(live.title == edited.title)
        #expect(live.flagged)
        #expect(await notifications.recordedEvents() == [.schedule(live)])
    }

    @Test func failedSynchronousReorderReplaysWithoutAnotherDrag() async throws {
        let (store, root) = try await emptyStore()
        let fileStore = FileStore(root: root)
        let first = Item(
            type: .task,
            title: "First",
            listId: ItemList.inboxId,
            sortIndex: 0
        )
        let second = Item(
            type: .task,
            title: "Second",
            listId: ItemList.inboxId,
            sortIndex: 1
        )
        try await store.add(first)
        try await store.add(second)
        _ = try await fileStore.loadAll()
        let directory = try await fileStore.listDirectory(for: ItemList.inboxId)
        let firstURL = directory.appendingPathComponent(FileStore.documentBaseFileName(for: first))
        let originalBytes = try sabotageMarkdownPath(firstURL)

        store.applyReorderItemsSync(
            in: ItemList.inboxId,
            flatOrderedIds: [second.id, first.id]
        )
        do {
            try await store.flushPendingWrites()
            Issue.record("the sabotaged reorder must remain pending")
        } catch {}

        #expect(store.item(second.id)?.sortIndex == 0)
        #expect(store.item(first.id)?.sortIndex == 1)

        try repairMarkdownPath(firstURL, originalBytes: originalBytes)
        try await store.flushPendingWrites()

        let cold = try await FileStore(root: root).loadAll().lists.flatMap(\.items)
        #expect(try #require(cold.first { $0.id == second.id }).sortIndex == 0)
        #expect(try #require(cold.first { $0.id == first.id }).sortIndex == 1)
    }

    @Test func failedSidebarReorderReplaysWithoutAnotherDrag() async throws {
        let (store, root) = try await emptyStore()
        let first = ItemList(
            id: "sidebar-a-\(UUID().uuidString)",
            name: "Sidebar A",
            icon: "a.circle",
            color: .blue,
            createdAt: .now,
            modifiedAt: .now,
            position: 10_000
        )
        let second = ItemList(
            id: "sidebar-b-\(UUID().uuidString)",
            name: "Sidebar B",
            icon: "b.circle",
            color: .green,
            createdAt: .now,
            modifiedAt: .now,
            position: 11_000
        )
        try await store.addList(first)
        try await store.addList(second)
        let fileStore = FileStore(root: root)
        _ = try await fileStore.loadAll()
        let firstDirectory = try await fileStore.listDirectory(for: first.id)
        let headerURL = firstDirectory.appendingPathComponent(".list.yml")
        let originalBytes = try sabotageMarkdownPath(headerURL)

        #expect(store.applyListReorderSync(
            movedId: second.id,
            toParent: nil,
            flatOrderedIds: [second.id, first.id]
        ))
        do {
            try await store.flushPendingWrites()
            Issue.record("the sabotaged sidebar reorder must remain pending")
        } catch {}

        try repairMarkdownPath(headerURL, originalBytes: originalBytes)
        try await store.flushPendingWrites()

        let coldLists = try await FileStore(root: root).loadAll().lists.map(\.list)
        #expect(try #require(coldLists.first { $0.id == second.id }).position == 1)
        #expect(try #require(coldLists.first { $0.id == first.id }).position == 2)
    }

    @Test func failedListReparentBlocksDeletingItsDurableSourceSubtree() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcListMoveDelete-\(UUID().uuidString)")
        let fileStore = FileStore(root: root)
        let store = ItemStore(store: fileStore, scheduler: NoopNotificationScheduler())
        try await store.bootstrap()
        let source = ItemList(
            id: "list-move-source-\(UUID().uuidString)",
            name: "Source",
            icon: "folder",
            color: .orange,
            createdAt: .now,
            modifiedAt: .now,
            position: 1
        )
        let destination = ItemList(
            id: "list-move-destination-\(UUID().uuidString)",
            name: "Destination",
            icon: "folder",
            color: .blue,
            createdAt: .now,
            modifiedAt: .now,
            position: 2
        )
        let moved = ItemList(
            id: "list-moved-\(UUID().uuidString)",
            name: "Moved",
            icon: "folder",
            color: .green,
            createdAt: .now,
            modifiedAt: .now,
            position: 1,
            parentId: source.id
        )
        try await store.addList(source)
        try await store.addList(destination)
        try await store.addList(moved)
        let item = Item(
            type: .task,
            title: "Must move with its list",
            listId: moved.id
        )
        try await store.add(item)

        let destinationDirectory = try await fileStore.listDirectory(for: destination.id)
        let fileManager = FileManager.default
        let originalPermissions = try #require(
            try fileManager.attributesOfItem(atPath: destinationDirectory.path)[.posixPermissions]
                as? NSNumber
        )
        var permissionsRestored = false
        defer {
            if !permissionsRestored {
                try? fileManager.setAttributes(
                    [.posixPermissions: originalPermissions],
                    ofItemAtPath: destinationDirectory.path
                )
            }
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: destinationDirectory.path
        )

        #expect(store.applyListReorderSync(
            movedId: moved.id,
            toParent: destination.id,
            flatOrderedIds: [source.id, destination.id, moved.id]
        ))
        do {
            try await store.flushPendingWrites()
            Issue.record("the sabotaged list move must remain pending")
        } catch {}

        await #expect(throws: (any Error).self) {
            try await store.deleteList(source.id)
        }
        #expect(store.lists.contains { $0.id == source.id })
        #expect(store.lists.first { $0.id == moved.id }?.parentId == destination.id)
        #expect(store.item(item.id) != nil)

        try fileManager.setAttributes(
            [.posixPermissions: originalPermissions],
            ofItemAtPath: destinationDirectory.path
        )
        permissionsRestored = true
        try await store.deleteList(source.id)
        try await store.flushPendingWrites()

        let cold = try await FileStore(root: root).loadAll()
        #expect(cold.lists.contains { $0.list.id == source.id } == false)
        #expect(cold.lists.first { $0.list.id == moved.id }?.list.parentId == destination.id)
        #expect(cold.lists.flatMap(\.items).first { $0.id == item.id }?.listId == moved.id)
    }

    @Test(.timeLimit(.minutes(1)))
    func synchronousSidebarMutationWinsAnOlderSuspendedListUpdate() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcListIntent-\(UUID().uuidString)")
        let gate = ReloadGate()
        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler(),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                listWriteCommitted: { await gate.pauseAfterMutationWrite() }
            )
        )
        try await store.bootstrap()
        let first = ItemList(
            id: "list-intent-a-\(UUID().uuidString)",
            name: "First",
            icon: "a.circle",
            color: .blue,
            createdAt: .now,
            modifiedAt: .now,
            position: 10_000
        )
        let second = ItemList(
            id: "list-intent-b-\(UUID().uuidString)",
            name: "Second",
            icon: "b.circle",
            color: .green,
            createdAt: .now,
            modifiedAt: .now,
            position: 11_000
        )
        try await store.addList(first)
        try await store.addList(second)

        var olderAwaited = try #require(store.lists.first { $0.id == first.id })
        let awaitedName = "Older awaited rename"
        olderAwaited.name = awaitedName
        async let update: Void = store.updateList(olderAwaited)
        await gate.waitUntilMutationWriteIsCommitted()

        #expect(store.applyListReorderSync(
            movedId: first.id,
            toParent: nil,
            flatOrderedIds: [second.id, first.id]
        ))
        gate.finishMutation()
        try await update
        try await store.flushPendingWrites()

        #expect(store.lists.first { $0.id == first.id }?.position == 2)
        #expect(store.lists.first { $0.id == first.id }?.name == awaitedName)
        let cold = try await FileStore(root: root).loadAll().lists.map(\.list)
        let coldFirst = try #require(cold.first { $0.id == first.id })
        #expect(coldFirst.position == 2)
        #expect(coldFirst.name == awaitedName)
        #expect(try #require(cold.first { $0.id == second.id }).position == 1)
    }

    @Test func failedSectionReorderReplaysWithoutAnotherDrag() async throws {
        let (store, root) = try await emptyStore()
        let firstSection = ListSection(name: "First", position: 1_000)
        let secondSection = ListSection(name: "Second", position: 2_000)
        let list = ItemList(
            id: "section-reorder-\(UUID().uuidString)",
            name: "Section reorder",
            icon: "rectangle.3.group",
            color: .purple,
            createdAt: .now,
            modifiedAt: .now,
            position: 12_000,
            sections: [firstSection, secondSection]
        )
        try await store.addList(list)
        let fileStore = FileStore(root: root)
        _ = try await fileStore.loadAll()
        let directory = try await fileStore.listDirectory(for: list.id)
        let headerURL = directory.appendingPathComponent(".list.yml")
        let originalBytes = try sabotageMarkdownPath(headerURL)

        store.applyReorderSectionsSync(
            in: list.id,
            orderedIds: [secondSection.id, firstSection.id]
        )
        do {
            try await store.flushPendingWrites()
            Issue.record("the sabotaged section reorder must remain pending")
        } catch {}

        try repairMarkdownPath(headerURL, originalBytes: originalBytes)
        try await store.flushPendingWrites()

        let coldList = try #require(
            try await FileStore(root: root).loadAll().lists
                .map(\.list)
                .first { $0.id == list.id }
        )
        #expect(coldList.sections.map(\.id) == [secondSection.id, firstSection.id])
    }

    @Test func sectionEditRetryFinishesAfterAnItemDeleteWriteFails() async throws {
        let (store, root) = try await emptyStore()
        let section = ListSection(name: "Temporary", position: 1_000)
        let list = ItemList(
            id: "section-item-failure-\(UUID().uuidString)",
            name: "Section item failure",
            icon: "rectangle.3.group",
            color: .purple,
            createdAt: .now,
            modifiedAt: .now,
            position: 12_000,
            sections: [section]
        )
        try await store.addList(list)
        let item = Item(
            type: .task,
            title: "Delete with section",
            listId: list.id,
            section: section.id.uuidString
        )
        try await store.add(item)

        let fileStore = FileStore(root: root)
        _ = try await fileStore.loadAll()
        let directory = try await fileStore.listDirectory(for: list.id)
        let itemURL = directory.appendingPathComponent(FileStore.documentBaseFileName(for: item))
        let originalBytes = try sabotageMarkdownPath(itemURL)

        await #expect(throws: (any Error).self) {
            try await store.commitSectionEdits(
                in: list.id,
                kept: [],
                deleted: [section.id]
            )
        }
        #expect(store.item(item.id)?.deletedAt == nil)
        #expect(store.lists.first { $0.id == list.id }?.sections.map(\.id) == [section.id])

        try repairMarkdownPath(itemURL, originalBytes: originalBytes)
        try await store.commitSectionEdits(
            in: list.id,
            kept: [],
            deleted: [section.id]
        )
        try await store.flushPendingWrites()

        #expect(store.item(item.id)?.deletedAt != nil)
        #expect(store.lists.first { $0.id == list.id }?.sections.isEmpty == true)
        let cold = try await FileStore(root: root).loadAll()
        #expect(cold.lists.first { $0.list.id == list.id }?.list.sections.isEmpty == true)
        #expect(cold.lists.flatMap(\.items).first { $0.id == item.id }?.deletedAt != nil)
    }

    @Test func sectionEditRetryFinishesAfterTheListHeaderWriteFails() async throws {
        let (store, root) = try await emptyStore()
        let section = ListSection(name: "Temporary", position: 1_000)
        let list = ItemList(
            id: "section-header-failure-\(UUID().uuidString)",
            name: "Section header failure",
            icon: "rectangle.3.group",
            color: .purple,
            createdAt: .now,
            modifiedAt: .now,
            position: 12_000,
            sections: [section]
        )
        try await store.addList(list)
        let item = Item(
            type: .task,
            title: "Delete before header",
            listId: list.id,
            section: section.id.uuidString
        )
        try await store.add(item)

        let fileStore = FileStore(root: root)
        _ = try await fileStore.loadAll()
        let directory = try await fileStore.listDirectory(for: list.id)
        let headerURL = directory.appendingPathComponent(".list.yml")
        let originalBytes = try sabotageMarkdownPath(headerURL)

        await #expect(throws: (any Error).self) {
            try await store.commitSectionEdits(
                in: list.id,
                kept: [],
                deleted: [section.id]
            )
        }
        #expect(store.item(item.id)?.deletedAt != nil)
        #expect(store.lists.first { $0.id == list.id }?.sections.map(\.id) == [section.id])

        try repairMarkdownPath(headerURL, originalBytes: originalBytes)
        try await store.commitSectionEdits(
            in: list.id,
            kept: [],
            deleted: [section.id]
        )
        try await store.flushPendingWrites()

        #expect(store.item(item.id)?.deletedAt != nil)
        #expect(store.lists.first { $0.id == list.id }?.sections.isEmpty == true)
        let cold = try await FileStore(root: root).loadAll()
        #expect(cold.lists.first { $0.list.id == list.id }?.list.sections.isEmpty == true)
        #expect(cold.lists.flatMap(\.items).first { $0.id == item.id }?.deletedAt != nil)
    }

    @Test func failedSynchronousDeleteRollsBackAndReplayCancelsCommittedItems() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsConcDeleteNotificationFailure-\(UUID().uuidString)")
        let fileStore = FileStore(root: root)
        let notifications = RecordingNotificationScheduler()
        let store = ItemStore(store: fileStore, scheduler: notifications)
        try await store.bootstrap()
        let due = Calendar.current.date(byAdding: .day, value: 1, to: .now)
        let parent = Item(
            type: .task,
            title: "Reminder parent",
            listId: ItemList.inboxId,
            due: due,
            reminder: Reminder(enabled: true)
        )
        let child = Item(
            type: .task,
            title: "Reminder child",
            listId: ItemList.inboxId,
            parentId: parent.id,
            due: due,
            reminder: Reminder(enabled: true)
        )
        try await store.add(parent)
        try await store.add(child)
        await notifications.reset()

        let directory = try await fileStore.listDirectory(for: parent.listId)
        let parentURL = directory.appendingPathComponent(FileStore.documentBaseFileName(for: parent))
        let childURL = directory.appendingPathComponent(FileStore.documentBaseFileName(for: child))
        let parentBytes = try sabotageMarkdownPath(parentURL)
        store.applySoftDeleteSync(parent.id)

        do {
            try await store.flushPendingWrites()
            Issue.record("the sabotaged synchronous delete must fail")
        } catch {}

        #expect(try #require(store.item(parent.id)).deletedAt == nil)
        #expect(try #require(store.item(child.id)).deletedAt == nil)
        let failedEvents = await notifications.recordedEvents()
        #expect(failedEvents.isEmpty)
        #expect(try await fileStore.readItem(at: childURL).deletedAt == nil)

        await notifications.reset()
        try repairMarkdownPath(parentURL, originalBytes: parentBytes)
        try await store.flushPendingWrites()

        #expect(store.item(parent.id)?.deletedAt != nil)
        #expect(store.item(child.id)?.deletedAt != nil)
        let retriedEvents = await notifications.recordedEvents()
        #expect(retriedEvents == [
            .cancel(parent.id),
            .cancel(child.id)
        ])
        let cold = try await FileStore(root: root).loadAll().lists.flatMap(\.items)
        #expect(cold.first { $0.id == parent.id }?.deletedAt != nil)
        #expect(cold.first { $0.id == child.id }?.deletedAt != nil)
    }

    @Test func partialSynchronousDeleteKeepsOneRestorableBatchTimestamp() async throws {
        let (store, root) = try await emptyStore()
        let fileStore = FileStore(root: root)
        let parent = Item(
            type: .task,
            title: "Root-first parent",
            listId: ItemList.inboxId
        )
        let child = Item(
            type: .task,
            title: "Root-first child",
            listId: ItemList.inboxId,
            parentId: parent.id
        )
        try await store.add(parent)
        try await store.add(child)
        _ = try await fileStore.loadAll()
        let directory = try await fileStore.listDirectory(for: ItemList.inboxId)
        let childURL = directory.appendingPathComponent(FileStore.documentBaseFileName(for: child))
        let childBytes = try sabotageMarkdownPath(childURL)

        store.applySoftDeleteSync(parent.id)
        do {
            try await store.flushPendingWrites()
            Issue.record("the sabotaged child must interrupt the root-first batch")
        } catch {}

        let batchTimestamp = try #require(store.item(parent.id)?.deletedAt)
        #expect(store.item(child.id)?.deletedAt == nil)

        try repairMarkdownPath(childURL, originalBytes: childBytes)
        try await store.flushPendingWrites()

        let deletedChildAt = try #require(store.item(child.id)?.deletedAt)
        #expect(abs(deletedChildAt.timeIntervalSince(batchTimestamp)) < 0.001)

        try await store.restore(parent.id)
        #expect(store.item(parent.id)?.deletedAt == nil)
        #expect(store.item(child.id)?.deletedAt == nil)
        let cold = try await FileStore(root: root).loadAll().lists.flatMap(\.items)
        #expect(try #require(cold.first { $0.id == parent.id }).deletedAt == nil)
        #expect(try #require(cold.first { $0.id == child.id }).deletedAt == nil)
    }

    @Test func crossListMoveRetryRollsBackCopyAfterSourceRemovalFailure() async throws {
        let context = try await sectionedHierarchy()
        let sourceURL = try await itemURL(context.rootItem, in: context)
        let sourceDirectory = sourceURL.deletingLastPathComponent()
        let destinationDirectory = try await context.fileStore.listDirectory(
            for: ItemList.inboxId
        )
        let destinationURL = destinationDirectory
            .appendingPathComponent(FileStore.documentBaseFileName(for: context.rootItem))
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

    @Test func failedSynchronousMoveRetainsItsDurableSourceForAutomaticRetry() async throws {
        let context = try await sectionedHierarchy()
        let sourceURL = try await itemURL(context.rootItem, in: context)
        let sourceDirectory = sourceURL.deletingLastPathComponent()
        let destinationDirectory = try await context.fileStore.listDirectory(
            for: ItemList.inboxId
        )
        let fileManager = FileManager.default
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

        try fileManager.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: sourceDirectory.path
        )
        var moved = context.rootItem
        moved.listId = ItemList.inboxId
        moved.section = nil
        context.store.applyUpdateSync(moved)
        var latest = try #require(context.store.item(moved.id))
        latest.title = "Latest destination edit"
        let destinationURL = destinationDirectory
            .appendingPathComponent(FileStore.documentBaseFileName(for: latest))
        context.store.applyUpdateSync(latest)

        do {
            try await context.store.flushPendingWrites()
            Issue.record("source cleanup failure must keep the sync move pending")
        } catch {}

        #expect(context.store.item(moved.id)?.listId == ItemList.inboxId)
        #expect(context.store.item(moved.id)?.title == latest.title)
        #expect(fileManager.fileExists(atPath: sourceURL.path))
        #expect(fileManager.fileExists(atPath: destinationURL.path) == false)

        try fileManager.setAttributes(
            [.posixPermissions: originalPermissions],
            ofItemAtPath: sourceDirectory.path
        )
        permissionsRestored = true
        try await context.store.flushPendingWrites()

        #expect(fileManager.fileExists(atPath: sourceURL.path) == false)
        let persisted = try await context.fileStore.readItem(at: destinationURL)
        #expect(persisted.listId == ItemList.inboxId)
        #expect(persisted.title == latest.title)
        let coldMatches = try await context.fileStore.loadAll()
            .lists.flatMap(\.items).filter { $0.id == moved.id }
        #expect(coldMatches.count == 1)
        #expect(coldMatches.first?.listId == ItemList.inboxId)
    }

    @Test func deletingMoveSourceWaitsUntilTheMovedItemIsDurable() async throws {
        let (store, root) = try await emptyStore()
        let sourceList = ItemList(
            id: "move-source-delete-\(UUID().uuidString)",
            name: "Move source",
            icon: "shippingbox",
            color: .orange,
            createdAt: .now,
            modifiedAt: .now,
            position: 20_000
        )
        try await store.addList(sourceList)
        let item = Item(
            type: .task,
            title: "Must survive its source list",
            listId: sourceList.id
        )
        try await store.add(item)

        let fileStore = FileStore(root: root)
        _ = try await fileStore.loadAll()
        let sourceDirectory = try await fileStore.listDirectory(for: sourceList.id)
        let fileManager = FileManager.default
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

        try fileManager.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: sourceDirectory.path
        )
        var moved = try #require(store.item(item.id))
        moved.listId = ItemList.inboxId
        store.applyUpdateSync(moved)
        do {
            try await store.flushPendingWrites()
            Issue.record("the source cleanup failure must keep the move pending")
        } catch {}

        await #expect(throws: (any Error).self) {
            try await store.softDeleteList(sourceList.id)
        }
        #expect(store.lists.first { $0.id == sourceList.id }?.deletedAt == nil)
        #expect(store.item(item.id)?.listId == ItemList.inboxId)

        try fileManager.setAttributes(
            [.posixPermissions: originalPermissions],
            ofItemAtPath: sourceDirectory.path
        )
        permissionsRestored = true
        try await store.softDeleteList(sourceList.id)
        try await store.flushPendingWrites()

        let cold = try await FileStore(root: root).loadAll()
        let coldMatches = cold.lists.flatMap(\.items).filter { $0.id == item.id }
        #expect(coldMatches.count == 1)
        #expect(coldMatches.first?.listId == ItemList.inboxId)
        #expect(coldMatches.first?.deletedAt == nil)
        #expect(cold.lists.first { $0.list.id == sourceList.id }?.list.deletedAt != nil)
    }

    @Test func deletingSourceSectionWaitsForPendingSectionMove() async throws {
        let (store, root) = try await emptyStore()
        let sourceSection = ListSection(name: "Source", position: 1_000)
        let destinationSection = ListSection(name: "Destination", position: 2_000)
        let list = ItemList(
            id: "pending-section-move-\(UUID().uuidString)",
            name: "Pending section move",
            icon: "rectangle.split.2x1",
            color: .teal,
            createdAt: .now,
            modifiedAt: .now,
            position: 21_000,
            sections: [sourceSection, destinationSection]
        )
        try await store.addList(list)
        let item = Item(
            type: .task,
            title: "Moved between sections",
            listId: list.id,
            section: sourceSection.id.uuidString
        )
        try await store.add(item)
        let fileStore = FileStore(root: root)
        _ = try await fileStore.loadAll()
        let directory = try await fileStore.listDirectory(for: list.id)
        let itemURL = directory.appendingPathComponent(FileStore.documentBaseFileName(for: item))
        let originalBytes = try sabotageMarkdownPath(itemURL)

        var moved = try #require(store.item(item.id))
        moved.section = destinationSection.id.uuidString
        store.applyUpdateSync(moved)
        do {
            try await store.flushPendingWrites()
            Issue.record("the sabotaged section move must remain pending")
        } catch {}

        await #expect(throws: (any Error).self) {
            try await store.deleteSection(sourceSection.id, in: list.id)
        }
        #expect(store.lists.first { $0.id == list.id }?.sections.contains {
            $0.id == sourceSection.id
        } == true)

        try repairMarkdownPath(itemURL, originalBytes: originalBytes)
        try await store.deleteSection(sourceSection.id, in: list.id)
        try await store.flushPendingWrites()

        let cold = try await FileStore(root: root).loadAll()
        let coldList = try #require(cold.lists.first { $0.list.id == list.id }?.list)
        let coldItem = try #require(cold.lists.flatMap(\.items).first { $0.id == item.id })
        #expect(!coldList.sections.contains { $0.id == sourceSection.id })
        #expect(coldItem.section == destinationSection.id.uuidString)
        #expect(coldItem.deletedAt == nil)
    }

    @Test func crossListMoveFinishesAgainstEquivalentCrashResidue() async throws {
        let context = try await sectionedHierarchy()
        let sourceURL = try await itemURL(context.rootItem, in: context)
        let destinationDirectory = try await context.fileStore.listDirectory(
            for: ItemList.inboxId
        )
        let destinationURL = destinationDirectory
            .appendingPathComponent(FileStore.documentBaseFileName(for: context.rootItem))

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
