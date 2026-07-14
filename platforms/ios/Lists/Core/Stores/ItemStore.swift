import Foundation
import Observation
import os

/// Main-actor coordinator over `FileStore`. Owns the in-memory snapshot of
/// lists + items the UI binds to.
@MainActor
@Observable
public final class ItemStore {
    @TaskLocal private static var bypassesMutationGate = false
    @TaskLocal private static var isInsideMutationScope = false

    public enum DataSafetyError: Error, Equatable, LocalizedError, Sendable {
        case unresolvedRecoveryIssues

        public var errorDescription: String? {
            "This data change is unavailable until library recovery is complete."
        }
    }

    public enum CreationError: Error, Equatable, LocalizedError, Sendable {
        case duplicateItemID(UUID)
        case duplicateListID(String)

        public var errorDescription: String? {
            switch self {
            case .duplicateItemID(let id):
                "An item with id \(id) already exists."
            case .duplicateListID(let id):
                "A list with id \(id) already exists."
            }
        }
    }

    public enum MutationConflictError: Error, Equatable, LocalizedError, Sendable {
        case listDeletionInProgress
        case inactiveDestinationList
        case deletedItemRequiresRestore
        case deletedListRequiresRestore
        case ancestorDeletionInProgress
        case itemDeletionInProgress

        public var errorDescription: String? {
            switch self {
            case .listDeletionInProgress:
                "That list is being deleted. Wait for deletion to finish before editing it."
            case .inactiveDestinationList:
                "That list is no longer available. Choose an active list and try again."
            case .deletedItemRequiresRestore:
                "Restore this item before editing it."
            case .deletedListRequiresRestore:
                "Restore this list before editing it."
            case .ancestorDeletionInProgress:
                "Wait for the parent deletion to finish, or restore the parent instead."
            case .itemDeletionInProgress:
                "That item is being deleted. Wait for deletion to finish before moving or editing its subtree."
            }
        }
    }

    public enum RestoreError: Error, Equatable, LocalizedError, Sendable {
        case noAvailableList
        case pendingRestoreMustFinish
        case recoveryIssues

        public var errorDescription: String? {
            switch self {
            case .noAvailableList:
                "This item can’t be restored because no active list is available."
            case .pendingRestoreMustFinish:
                "Finish the pending restore before deleting anything forever."
            case .recoveryIssues:
                "This restore is unavailable until library recovery is complete."
            }
        }
    }

    public enum PendingRestoreCleanup: Equatable, Sendable {
        case item(UUID)
        case list(String)
    }

    public private(set) var lists: [ItemList] = []
    public private(set) var items: [Item] = [] {
        didSet { itemsById = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new }) }
    }
    /// Id-to-item index kept in sync with `items`, so per-cell lookups in the
    /// collection-view bridges are O(1) instead of an O(items) linear scan on
    /// every row reconfigure.
    public private(set) var itemsById: [UUID: Item] = [:]
    public private(set) var documentFileNamesById: [UUID: String] = [:]

    /// O(1) item lookup by id. Prefer over `items.first(where: { $0.id == id })`.
    public func item(_ id: UUID) -> Item? { itemsById[id] }

    public private(set) var isLoaded: Bool = false
    /// Original paths of files that failed to load and were quarantined on the
    /// last `bootstrap`. Drives the "some files couldn't be opened" banner;
    /// empty on a clean load.
    public private(set) var loadIssues: [String] = []
    /// True when an interrupted restore cannot be resumed without changing or
    /// discarding members of its recorded batch. The durable journal remains
    /// in place so future launches keep hierarchy repair and expiry purge away
    /// from those files until the missing data is recoverable again.
    public private(set) var hasPendingRestoreRecovery = false
    public private(set) var hasPendingDeletionRecovery = false
    /// A restore whose user data is already active but whose journal could not
    /// be removed. Recently Deleted keeps a durable Retry affordance for this
    /// state even though the restored root is no longer one of its rows.
    public private(set) var pendingRestoreCleanup: PendingRestoreCleanup?
    /// Guards bootstrap against a re-entrant double `.task` fire seeding sample
    /// data twice. Set synchronously before the first await.
    private var isBootstrapping = false
    /// Visible rebuild state used to keep navigation and editing stationary;
    /// the maintenance gate below remains the data-integrity boundary.
    public private(set) var isReloadingFromDisk = false
    private var creatingItemIds: Set<UUID> = []
    private var creatingListIds: Set<String> = []

    private let store: FileStore
    private let scheduler: any NotificationScheduling
    private let maintenanceTestHooks: MaintenanceTestHooks

    struct MaintenanceTestHooks {
        var snapshotCaptured: (@MainActor @Sendable () async throws -> Void)?
        var mutationDeferred: (@MainActor @Sendable () -> Void)?
        var reloadCallerDeferred: (@MainActor @Sendable () -> Void)?
        var mutationWriteCommitted: (@MainActor @Sendable () async -> Void)?
        var itemWriteCommitted: (@MainActor @Sendable () async -> Void)?
        var recurringSuccessorCommitted: (@MainActor @Sendable () async throws -> Void)?
        var recurringRootWillCommit: (@MainActor @Sendable () async throws -> Void)?
        var flagWriteWillCommit: (@MainActor @Sendable () async throws -> Void)?
        var flagWriteCommitted: (@MainActor @Sendable () async -> Void)?
        var listWriteCommitted: (@MainActor @Sendable () async -> Void)?
        var maintenanceWaitingForMutations: (@MainActor @Sendable () -> Void)?
        var exportSnapshotReady: (@MainActor @Sendable () async -> Void)?
        var deferredDrainWillFlush: (@MainActor @Sendable () async -> Void)?
    }

    public init(store: FileStore, scheduler: NotificationScheduler = .shared) {
        self.store = store
        self.scheduler = scheduler
        self.maintenanceTestHooks = MaintenanceTestHooks()
    }

    init(
        store: FileStore,
        scheduler: any NotificationScheduling = NotificationScheduler.shared,
        maintenanceTestHooks: MaintenanceTestHooks
    ) {
        self.store = store
        self.scheduler = scheduler
        self.maintenanceTestHooks = maintenanceTestHooks
    }

    init(store: FileStore, scheduler: any NotificationScheduling) {
        self.store = store
        self.scheduler = scheduler
        self.maintenanceTestHooks = MaintenanceTestHooks()
    }

    // MARK: - Ordered persistence

    private static let log = Logger(
        subsystem: "io.github.saxonbobart.lists", category: "persistence")

    /// Every disk write is appended to one FIFO chain, so a deferred
    /// (fire-and-forget) write can never land after a newer write to the same
    /// file and silently revert it on the next launch. Awaited writes flow
    /// through the same chain, keeping ordering global across both kinds.
    private var writeChain: Task<Void, Never>?
    private var writeGeneration: UInt64 = 0
    private var pendingWriteFailures: [String: PendingWriteFailure] = [:]
    private var pendingWriteFailureOrder: [String] = []

    /// UIKit-backed editors and drag/drop must publish their new value before
    /// returning, so their writes cannot report an error to the caller. Keep a
    /// compact, replayable description of those accepted mutations until the
    /// corresponding files are durable. This is deliberately data, not an
    /// opaque closure, so a retry can coalesce onto the newest live item.
    private struct SynchronousDeletionPlan: Sendable {
        var original: Item
        var tombstone: Item
    }

    private enum RetainedSynchronousWrite {
        case itemUpdate(id: UUID, sourceListId: String?)
        case itemReorder(listId: String, targetIndexes: [UUID: Int])
        case itemSoftDelete(
            rootId: UUID,
            deletedAt: Date,
            plans: [SynchronousDeletionPlan],
            committedIds: Set<UUID>
        )
        case listUpdates(ids: Set<String>)
        case listSoftDelete(rootId: String, deletedAt: Date)
    }

    private struct PendingSynchronousWrite {
        var generation: UInt64
        var plan: RetainedSynchronousWrite
        var itemIntentGeneration: UInt64?
        var automaticRetryCount: Int
        var retryTask: Task<Void, Never>?
    }

    private enum ItemField: CaseIterable, Hashable {
        case type, title, body, canvasPath, listId, section, parentId, tags, sortIndex
        case createdAt, createdBy, done, completedAt, due, dueAllDay, dueTimeZone
        case end, completable, priority, flagged, reminder, recurrence, recurrenceOccurrences
        case recurrenceSourceId, recurrenceSuccessorId, triggers, frequency
        case goalPerCycle, completions, showStreak, flexibleGoal, deletedAt
    }

    private enum ListField: CaseIterable, Hashable {
        case name, icon, color, defaultItemType, groceryMode, createdAt
        case position, parentId, deletedAt, lamport, sections
    }

    private struct FieldIntent {
        var latestGeneration: UInt64 = 0
        var latestOptimisticGeneration: UInt64 = 0
    }

    private var synchronousWriteGeneration: UInt64 = 0
    private var itemIntentGeneration: UInt64 = 0
    private var latestItemFieldIntent: [UUID: [ItemField: FieldIntent]] = [:]
    private var listIntentGeneration: UInt64 = 0
    private var latestListFieldIntent: [String: [ListField: FieldIntent]] = [:]
    /// Exact list containing each successfully persisted item file. Memory may
    /// already show a newer optimistic move, so it cannot answer this safely.
    private var durableItemListIds: [UUID: String] = [:]
    private var pendingSynchronousWrites: [String: PendingSynchronousWrite] = [:]
    private var listDeletionRootsInFlight: Set<String> = []
    private var itemDeletionRootsInFlight: Set<UUID> = []
    private var reversedItemDeletionRoots: Set<UUID> = []
    private var reversedListDeletionRoots: Set<String> = []
    private var pendingDeletionItemIds: Set<UUID> = []
    private var pendingDeletionListIds: Set<String> = []
    /// Root identity from durable deletion journals. Member-only fences stop
    /// edits, but restore and hard-delete also need to distinguish reversing
    /// the exact requested root from accidentally canceling an ancestor's
    /// interrupted deletion.
    private var pendingItemDeletionMembersByRoot: [UUID: Set<UUID>] = [:]
    private var pendingListDeletionMembersByRoot: [String: Set<String>] = [:]

    // MARK: - Whole-operation maintenance gate

    /// Rebuild and export own a coherent library only after every public
    /// mutation scope has finished. This is deliberately wider than
    /// `writeChain`: recurring-item operations still have important MainActor
    /// continuations after their first file write completes.
    private var activeMutationScopes = 0
    private var maintenanceAccessRequested = false
    private var maintenanceHasExclusiveAccess = false
    private var maintenanceAccessWaiter: CheckedContinuation<Void, Never>?
    private var deferredMutations: [@MainActor @Sendable () async -> Void] = []

    /// Serializes rebuild and export themselves. Waits are intentionally
    /// non-cancellable: once maintenance or a user mutation reaches the store,
    /// it runs to a durable outcome instead of disappearing with a view task.
    private var exclusiveOperationClaimed = false
    private var exclusiveOperationWaiters: [CheckedContinuation<Void, Never>] = []
    private var concurrentReloadWaiters: [CheckedContinuation<Result<Void, any Error>, Never>] = []

    private struct PendingWriteFailure: LocalizedError, Sendable {
        let context: String
        let details: String

        var errorDescription: String? {
            "Lists couldn't finish saving changes (\(context))."
        }

        var failureReason: String? { details }
    }

    private func recordWriteFailure(_ error: Error, context: String) {
        let failure = PendingWriteFailure(
            context: context,
            details: String(describing: error)
        )
        if pendingWriteFailures[context] == nil {
            pendingWriteFailures[context] = failure
            pendingWriteFailureOrder.append(context)
        }
        Self.log.error("""
            Write (\(context, privacy: .public)) failed: \
            \(failure.details, privacy: .private)
            """)
    }

    /// A successful retry proves only that its exact mutation family has been
    /// reconciled. Keep failures from every other context sticky so export or
    /// reload cannot accidentally bless unrelated stale files.
    private func clearWriteFailure(context: String) {
        guard pendingWriteFailures.removeValue(forKey: context) != nil else { return }
        pendingWriteFailureOrder.removeAll { $0 == context }
    }

    private func withMutationScope<T: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> T
    ) async throws -> T {
        if Self.bypassesMutationGate || Self.isInsideMutationScope {
            return try await operation()
        }
        if maintenanceAccessRequested || maintenanceHasExclusiveAccess {
            maintenanceTestHooks.mutationDeferred?()
            let outcome: Result<T, any Error> = await withCheckedContinuation { continuation in
                deferredMutations.append {
                    do {
                        continuation.resume(returning: .success(try await operation()))
                    } catch {
                        continuation.resume(returning: .failure(error))
                    }
                }
            }
            return try outcome.get()
        }
        activeMutationScopes += 1
        defer { leaveMutationScope() }
        return try await Self.$isInsideMutationScope.withValue(true) {
            try await operation()
        }
    }

    private func beginSynchronousMutation(
        deferring operation: @escaping @MainActor @Sendable () -> Void
    ) -> Bool {
        if !Self.bypassesMutationGate,
           !Self.isInsideMutationScope,
           maintenanceAccessRequested || maintenanceHasExclusiveAccess {
            deferredMutations.append { operation() }
            maintenanceTestHooks.mutationDeferred?()
            return false
        }
        activeMutationScopes += 1
        return true
    }

    private func leaveMutationScope() {
        precondition(activeMutationScopes > 0)
        activeMutationScopes -= 1
        guard activeMutationScopes == 0,
              maintenanceAccessRequested,
              !maintenanceHasExclusiveAccess else { return }
        maintenanceHasExclusiveAccess = true
        let waiter = maintenanceAccessWaiter
        maintenanceAccessWaiter = nil
        waiter?.resume()
    }

    private func acquireExclusiveOperationClaim() async {
        if exclusiveOperationClaimed {
            await withCheckedContinuation { continuation in
                exclusiveOperationWaiters.append(continuation)
            }
            return
        }
        exclusiveOperationClaimed = true
    }

    private func releaseExclusiveOperationClaim() {
        if exclusiveOperationWaiters.isEmpty {
            exclusiveOperationClaimed = false
        } else {
            let next = exclusiveOperationWaiters.removeFirst()
            next.resume()
        }
    }

    private func acquireMaintenanceAccess() async {
        maintenanceAccessRequested = true
        if activeMutationScopes == 0 {
            maintenanceHasExclusiveAccess = true
            return
        }
        maintenanceTestHooks.maintenanceWaitingForMutations?()
        await withCheckedContinuation { continuation in
            maintenanceAccessWaiter = continuation
        }
    }

    private func drainDeferredMutations() async throws {
        var firstPersistenceError: (any Error)?
        while true {
            while !deferredMutations.isEmpty {
                let mutation = deferredMutations.removeFirst()
                await Self.$bypassesMutationGate.withValue(true) {
                    await mutation()
                }
            }
            if let deferredDrainWillFlush = maintenanceTestHooks.deferredDrainWillFlush {
                await deferredDrainWillFlush()
            }
            do {
                try await flushPendingWritesUngated()
            } catch {
                if firstPersistenceError == nil {
                    firstPersistenceError = error
                }
            }
            guard deferredMutations.isEmpty else { continue }
            break
        }
        if let firstPersistenceError {
            throw firstPersistenceError
        }
    }

    private func releaseMaintenanceAccess() {
        precondition(deferredMutations.isEmpty)
        maintenanceAccessRequested = false
        maintenanceHasExclusiveAccess = false
    }

    private func resumeConcurrentReloadCallers(with outcome: Result<Void, any Error>) {
        let reloadWaiters = concurrentReloadWaiters
        concurrentReloadWaiters.removeAll()
        for waiter in reloadWaiters {
            waiter.resume(returning: outcome)
        }
    }

    private func waitForCurrentReload() async throws {
        maintenanceTestHooks.reloadCallerDeferred?()
        let outcome = await withCheckedContinuation { continuation in
            concurrentReloadWaiters.append(continuation)
        }
        try outcome.get()
    }

    /// Append an ordered write and await its result.
    private func enqueueWrite<T: Sendable>(
        _ context: String,
        reconcilesPreviousFailure: Bool = false,
        _ op: @escaping @MainActor @Sendable () async throws -> T
    ) async throws -> T {
        let previous = writeChain
        writeGeneration &+= 1
        let task = Task<T, Error> {
            await previous?.value
            do {
                let result = try await op()
                if reconcilesPreviousFailure {
                    clearWriteFailure(context: context)
                }
                return result
            } catch {
                if !Self.isDomainRejection(error) {
                    recordWriteFailure(error, context: context)
                }
                throw error
            }
        }
        writeChain = Task { _ = try? await task.value }
        return try await task.value
    }

    private static func isDomainRejection(_ error: Error) -> Bool {
        if error is RestoreError { return true }
        return (error as? FileStore.RestoreJournalError) == .pendingOperation
    }

    /// Append an ordered write without awaiting it (the sync UIKit-bridge
    /// paths, where the data source must mutate before the drop animation).
    /// Failures are logged — never silently swallowed.
    private func enqueueDetachedWrite(
        _ context: String,
        reconcilesPreviousFailure: Bool = false,
        _ op: @escaping @MainActor @Sendable () async throws -> Void
    ) {
        let previous = writeChain
        writeGeneration &+= 1
        writeChain = Task {
            await previous?.value
            do {
                try await op()
                if reconcilesPreviousFailure {
                    clearWriteFailure(context: context)
                }
            } catch {
                recordWriteFailure(error, context: context)
            }
        }
    }

    private func retainSynchronousItemUpdate(
        _ id: UUID,
        sourceListId: String?,
        fields: Set<ItemField>
    ) {
        let context = "update \(id)"
        let retainedSourceListId: String?
        if let pending = pendingSynchronousWrites[context],
           case .itemUpdate(_, let existingSourceListId) = pending.plan {
            // A failed cross-list move leaves the live item at its destination
            // while the only durable file remains in the original list. Keep
            // that durable source until a move actually cleans it up.
            retainedSourceListId = existingSourceListId
        } else {
            retainedSourceListId = sourceListId
        }
        let intentGeneration = acceptItemIntent(
            for: id,
            fields: fields,
            optimistic: true
        )
        registerSynchronousWrite(
            .itemUpdate(id: id, sourceListId: retainedSourceListId),
            context: context,
            itemIntentGeneration: intentGeneration
        )
    }

    private func acceptItemIntent(
        for id: UUID,
        fields: Set<ItemField>,
        optimistic: Bool = false
    ) -> UInt64 {
        itemIntentGeneration &+= 1
        for field in fields {
            var intent = latestItemFieldIntent[id]?[field] ?? FieldIntent()
            intent.latestGeneration = itemIntentGeneration
            if optimistic {
                intent.latestOptimisticGeneration = itemIntentGeneration
            }
            latestItemFieldIntent[id, default: [:]][field] = intent
        }
        return itemIntentGeneration
    }

    private func acceptListIntent(
        for id: String,
        fields: Set<ListField>,
        optimistic: Bool = false
    ) -> UInt64 {
        listIntentGeneration &+= 1
        for field in fields {
            var intent = latestListFieldIntent[id]?[field] ?? FieldIntent()
            intent.latestGeneration = listIntentGeneration
            if optimistic {
                intent.latestOptimisticGeneration = listIntentGeneration
            }
            latestListFieldIntent[id, default: [:]][field] = intent
        }
        return listIntentGeneration
    }

    private func retainedSourceListId(for id: UUID) -> String? {
        let context = "update \(id)"
        guard let pending = pendingSynchronousWrites[context],
              case .itemUpdate(_, let sourceListId) = pending.plan else { return nil }
        return sourceListId
    }

    private static func sameItemPayload(_ lhs: Item, _ rhs: Item) -> Bool {
        var lhs = lhs
        lhs.modifiedAt = rhs.modifiedAt
        return lhs == rhs
    }

    private static func changedItemFields(
        from baseline: Item,
        to desired: Item
    ) -> Set<ItemField> {
        var fields: Set<ItemField> = []
        func note<Value: Equatable>(
            _ field: ItemField,
            _ keyPath: KeyPath<Item, Value>
        ) {
            if baseline[keyPath: keyPath] != desired[keyPath: keyPath] {
                fields.insert(field)
            }
        }
        note(.type, \.type); note(.title, \.title); note(.body, \.body)
        note(.canvasPath, \.canvasPath)
        note(.listId, \.listId); note(.section, \.section); note(.parentId, \.parentId)
        note(.tags, \.tags); note(.sortIndex, \.sortIndex); note(.createdAt, \.createdAt)
        note(.createdBy, \.createdBy); note(.done, \.done); note(.completedAt, \.completedAt)
        note(.due, \.due); note(.dueAllDay, \.dueAllDay); note(.dueTimeZone, \.dueTimeZone)
        note(.end, \.end); note(.completable, \.completable); note(.priority, \.priority)
        note(.flagged, \.flagged); note(.reminder, \.reminder); note(.recurrence, \.recurrence)
        note(.recurrenceOccurrences, \.recurrenceOccurrences)
        note(.recurrenceSourceId, \.recurrenceSourceId)
        note(.recurrenceSuccessorId, \.recurrenceSuccessorId)
        note(.triggers, \.triggers); note(.frequency, \.frequency)
        note(.goalPerCycle, \.goalPerCycle); note(.completions, \.completions)
        note(.showStreak, \.showStreak); note(.flexibleGoal, \.flexibleGoal)
        note(.deletedAt, \.deletedAt)
        return fields
    }

    private static func changedListFields(
        from baseline: ItemList,
        to desired: ItemList
    ) -> Set<ListField> {
        var fields: Set<ListField> = []
        func note<Value: Equatable>(
            _ field: ListField,
            _ keyPath: KeyPath<ItemList, Value>
        ) {
            if baseline[keyPath: keyPath] != desired[keyPath: keyPath] {
                fields.insert(field)
            }
        }
        note(.name, \.name); note(.icon, \.icon); note(.color, \.color)
        note(.defaultItemType, \.defaultItemType); note(.groceryMode, \.groceryMode)
        note(.createdAt, \.createdAt); note(.position, \.position)
        note(.parentId, \.parentId); note(.deletedAt, \.deletedAt)
        note(.lamport, \.lamport); note(.sections, \.sections)
        return fields
    }

    /// Three-way merge for overlapping actor operations. An older awaited
    /// mutation keeps each field it actually changed unless a newer accepted
    /// mutation changed that same field from the shared baseline.
    private static func mergingItemChanges(
        from desired: Item,
        basedOn baseline: Item,
        into latest: Item,
        allowedFields: Set<ItemField>? = nil,
        forceAllowedFields: Bool = false
    ) -> Item {
        guard desired.id == baseline.id, latest.id == baseline.id else {
            return latest
        }
        var merged = latest
        func apply<Value: Equatable>(
            _ field: ItemField,
            _ keyPath: WritableKeyPath<Item, Value>
        ) {
            if allowedFields.map({ $0.contains(field) }) ?? true,
               forceAllowedFields
                    || latest[keyPath: keyPath] == baseline[keyPath: keyPath] {
                merged[keyPath: keyPath] = desired[keyPath: keyPath]
            }
        }
        apply(.type, \.type); apply(.title, \.title); apply(.body, \.body)
        apply(.canvasPath, \.canvasPath)
        apply(.listId, \.listId); apply(.section, \.section); apply(.parentId, \.parentId)
        apply(.tags, \.tags); apply(.sortIndex, \.sortIndex); apply(.createdAt, \.createdAt)
        apply(.createdBy, \.createdBy); apply(.done, \.done); apply(.completedAt, \.completedAt)
        apply(.due, \.due); apply(.dueAllDay, \.dueAllDay); apply(.dueTimeZone, \.dueTimeZone)
        apply(.end, \.end); apply(.completable, \.completable); apply(.priority, \.priority)
        apply(.flagged, \.flagged); apply(.reminder, \.reminder); apply(.recurrence, \.recurrence)
        apply(.recurrenceOccurrences, \.recurrenceOccurrences)
        apply(.recurrenceSourceId, \.recurrenceSourceId)
        apply(.recurrenceSuccessorId, \.recurrenceSuccessorId)
        apply(.triggers, \.triggers); apply(.frequency, \.frequency)
        apply(.goalPerCycle, \.goalPerCycle); apply(.completions, \.completions)
        apply(.showStreak, \.showStreak); apply(.flexibleGoal, \.flexibleGoal)
        apply(.deletedAt, \.deletedAt)
        return merged
    }

    private static func mergingListChanges(
        from desired: ItemList,
        basedOn baseline: ItemList,
        into latest: ItemList,
        allowedFields: Set<ListField>? = nil,
        forceAllowedFields: Bool = false
    ) -> ItemList {
        guard desired.id == baseline.id, latest.id == baseline.id else {
            return latest
        }
        var merged = latest
        func apply<Value: Equatable>(
            _ field: ListField,
            _ keyPath: WritableKeyPath<ItemList, Value>
        ) {
            if allowedFields.map({ $0.contains(field) }) ?? true,
               forceAllowedFields
                    || latest[keyPath: keyPath] == baseline[keyPath: keyPath] {
                merged[keyPath: keyPath] = desired[keyPath: keyPath]
            }
        }
        apply(.name, \.name); apply(.icon, \.icon); apply(.color, \.color)
        apply(.defaultItemType, \.defaultItemType); apply(.groceryMode, \.groceryMode)
        apply(.createdAt, \.createdAt); apply(.position, \.position)
        apply(.parentId, \.parentId); apply(.deletedAt, \.deletedAt)
        apply(.lamport, \.lamport); apply(.sections, \.sections)
        return merged
    }

    private func discardRetainedItemUpdate(for id: UUID) {
        let context = "update \(id)"
        guard let pending = pendingSynchronousWrites[context],
              case .itemUpdate = pending.plan else { return }
        pending.retryTask?.cancel()
        pendingSynchronousWrites.removeValue(forKey: context)
        clearWriteFailure(context: context)
    }

    private func deleteItemAndRetainedSource(_ item: Item) async throws {
        let canvasPath = item.canvasPath
        let durableListId = durableItemListIds[item.id] ?? item.listId
        if let sourceListId = retainedSourceListId(for: item.id),
           sourceListId != durableListId {
            var sourceCopy = item
            sourceCopy.listId = sourceListId
            try await store.deleteItem(sourceCopy)
        }
        var durableCopy = item
        durableCopy.listId = durableListId
        try await store.deleteItem(durableCopy)
        if let canvasPath {
            try await store.deleteCanvasResource(at: canvasPath)
        }
        durableItemListIds[item.id] = nil
        latestItemFieldIntent[item.id] = nil
        discardRetainedItemUpdate(for: item.id)
    }

    /// Any successful write after an optimistic cross-list move must also
    /// finish removing the retained durable source. Otherwise a later toggle,
    /// tombstone, or edit can appear saved at the destination while leaving a
    /// second stale file behind for cold-load recovery to quarantine.
    @discardableResult
    private func persistItemResolvingRetainedUpdate(
        _ item: Item,
        from fallbackSourceListId: String? = nil,
        reconcilesConsumedNotification: Bool = false,
        writerIntentGeneration: UInt64? = nil
    ) async throws -> Item {
        let context = "update \(item.id)"
        let capturedGeneration: UInt64?
        let capturedIntentGeneration: UInt64?
        let retainedSourceListId: String?
        if let pending = pendingSynchronousWrites[context],
           case .itemUpdate(_, let sourceListId) = pending.plan {
            capturedGeneration = pending.generation
            capturedIntentGeneration = pending.itemIntentGeneration
            retainedSourceListId = sourceListId
        } else {
            capturedGeneration = nil
            capturedIntentGeneration = nil
            retainedSourceListId = nil
        }

        let sourceListId = durableItemListIds[item.id]
            ?? retainedSourceListId
            ?? fallbackSourceListId
        let persisted: Item
        if let sourceListId, sourceListId != item.listId {
            persisted = try await store.moveItem(item, fromListId: sourceListId)
        } else {
            try await store.writeItem(item)
            persisted = item
        }
        documentFileNamesById[item.id] = await store.documentFileName(for: item.id)
        durableItemListIds[item.id] = persisted.listId

        var reconciledRetainedUpdate = false
        if let capturedGeneration,
           var current = pendingSynchronousWrites[context],
           case .itemUpdate(let currentId, _) = current.plan,
           currentId == item.id {
            current.plan = .itemUpdate(id: item.id, sourceListId: persisted.listId)
            let matchesAcceptedLive = self.item(item.id).map {
                Self.sameItemPayload($0, persisted)
            } ?? false
            let writerSupersedesCapturedIntent: Bool
            if let writerIntentGeneration,
               let capturedIntentGeneration {
                writerSupersedesCapturedIntent = writerIntentGeneration >= capturedIntentGeneration
            } else {
                writerSupersedesCapturedIntent = false
            }
            if current.generation == capturedGeneration,
               matchesAcceptedLive || writerSupersedesCapturedIntent {
                current.retryTask?.cancel()
                pendingSynchronousWrites.removeValue(forKey: context)
                clearWriteFailure(context: context)
                reconciledRetainedUpdate = true
            } else {
                pendingSynchronousWrites[context] = current
            }
        }
        if reconciledRetainedUpdate && reconcilesConsumedNotification {
            await scheduler.schedule(persisted)
        }
        return persisted
    }

    /// Destructive operations must classify membership from durable hierarchy,
    /// not only from an optimistic item that has not saved yet. Reconcile every
    /// retained update whose current or recorded source list touches the
    /// operation before deciding which subtree, section, or list to remove.
    private func reconcileRetainedItemUpdates(
        _ listIds: Set<String>
    ) async throws {
        let plans: [(id: UUID, sourceListId: String)] = pendingSynchronousWrites
            .values
            .compactMap { pending in
                guard case .itemUpdate(let id, let sourceListId) = pending.plan,
                      let latest = item(id),
                      listIds.contains(latest.listId)
                        || sourceListId.map(listIds.contains) == true
                        || durableItemListIds[id].map(listIds.contains) == true
                else { return nil }
                return (id, durableItemListIds[id] ?? sourceListId ?? latest.listId)
            }

        for plan in plans {
            guard let latest = item(plan.id) else { continue }
            let persisted = try await persistItemResolvingRetainedUpdate(
                latest,
                from: plan.sourceListId
            )
            if self.item(plan.id) == latest {
                replaceItemInMemory(persisted)
            }
            await scheduler.schedule(persisted)
        }
    }

    private func retainSynchronousItemReorder(
        listId: String,
        targetIndexes: [UUID: Int]
    ) {
        let context = "item reorder in \(listId)"
        var mergedTargets: [UUID: Int] = [:]
        if let pending = pendingSynchronousWrites[context],
           case .itemReorder(_, let retainedTargets) = pending.plan {
            mergedTargets = retainedTargets
        }
        mergedTargets.merge(targetIndexes) { _, latest in latest }
        guard !mergedTargets.isEmpty else { return }
        registerSynchronousWrite(
            .itemReorder(listId: listId, targetIndexes: mergedTargets),
            context: context
        )
    }

    private func retainSynchronousSoftDelete(
        rootId: UUID,
        deletedAt: Date,
        plans: [SynchronousDeletionPlan],
        committedIds: Set<UUID> = []
    ) {
        let context = "soft-delete item subtree \(rootId)"
        guard !reversedItemDeletionRoots.contains(rootId) else {
            clearWriteFailure(context: context)
            return
        }
        let retainedPlan: RetainedSynchronousWrite
        if let pending = pendingSynchronousWrites[context],
           case .itemSoftDelete(
               let existingRootId,
               let existingDeletedAt,
               let existingPlans,
               let existingCommittedIds
           ) = pending.plan {
            retainedPlan = .itemSoftDelete(
                rootId: existingRootId,
                deletedAt: existingDeletedAt,
                plans: existingPlans,
                committedIds: existingCommittedIds.union(committedIds)
            )
        } else {
            retainedPlan = .itemSoftDelete(
                rootId: rootId,
                deletedAt: deletedAt,
                plans: plans,
                committedIds: committedIds
            )
        }
        registerSynchronousWrite(retainedPlan, context: context)
    }

    private func discardRetainedSoftDelete(rootId: UUID) {
        let context = "soft-delete item subtree \(rootId)"
        guard let pending = pendingSynchronousWrites[context],
              case .itemSoftDelete = pending.plan else { return }
        pending.retryTask?.cancel()
        pendingSynchronousWrites.removeValue(forKey: context)
        clearWriteFailure(context: context)
    }

    private func discardRetainedSoftDeletes(removing itemIds: Set<UUID>) {
        let roots = pendingSynchronousWrites.values.compactMap { pending -> UUID? in
            guard case .itemSoftDelete(let rootId, _, _, _) = pending.plan,
                  itemIds.contains(rootId) else { return nil }
            return rootId
        }
        for rootId in roots {
            discardRetainedSoftDelete(rootId: rootId)
        }
    }

    private func itemDeletionRoots(containing itemId: UUID) -> Set<UUID> {
        var roots = Set(itemDeletionRootsInFlight.filter {
            $0 == itemId || allItemDescendantIds(of: $0).contains(itemId)
        })
        roots.formUnion(pendingItemDeletionMembersByRoot.compactMap { rootId, memberIds in
            memberIds.contains(itemId) ? rootId : nil
        })
        for pending in pendingSynchronousWrites.values {
            guard case .itemSoftDelete(let rootId, _, _, _) = pending.plan,
                  rootId == itemId || allItemDescendantIds(of: rootId).contains(itemId)
            else { continue }
            roots.insert(rootId)
        }
        return roots
    }

    private func retainSynchronousListUpdates(
        _ ids: Set<String>,
        context: String
    ) {
        var mergedIds = ids
        if let pending = pendingSynchronousWrites[context],
           case .listUpdates(let retainedIds) = pending.plan {
            mergedIds.formUnion(retainedIds)
        }
        guard !mergedIds.isEmpty else { return }
        registerSynchronousWrite(
            .listUpdates(ids: mergedIds),
            context: context
        )
    }

    private func retainListSoftDelete(rootId: String, deletedAt: Date) {
        let context = "soft-delete list subtree \(rootId)"
        guard !reversedListDeletionRoots.contains(rootId) else {
            clearWriteFailure(context: context)
            return
        }
        let timestamp: Date
        if let pending = pendingSynchronousWrites[context],
           case .listSoftDelete(_, let existingTimestamp) = pending.plan {
            timestamp = existingTimestamp
        } else {
            timestamp = deletedAt
        }
        registerSynchronousWrite(
            .listSoftDelete(rootId: rootId, deletedAt: timestamp),
            context: context
        )
    }

    private func retainedListSoftDeleteTimestamp(for rootId: String) -> Date? {
        let context = "soft-delete list subtree \(rootId)"
        guard let pending = pendingSynchronousWrites[context],
              case .listSoftDelete(_, let deletedAt) = pending.plan else { return nil }
        return deletedAt
    }

    private func discardRetainedListSoftDelete(rootId: String) {
        let context = "soft-delete list subtree \(rootId)"
        guard let pending = pendingSynchronousWrites[context],
              case .listSoftDelete = pending.plan else { return }
        pending.retryTask?.cancel()
        pendingSynchronousWrites.removeValue(forKey: context)
        clearWriteFailure(context: context)
    }

    private func discardRetainedListSoftDelete(containing listId: String) {
        let roots = pendingSynchronousWrites.values.compactMap { pending -> String? in
            guard case .listSoftDelete(let rootId, _) = pending.plan,
                  rootId == listId || allDescendantIds(of: rootId).contains(listId)
            else { return nil }
            return rootId
        }
        for rootId in roots {
            discardRetainedListSoftDelete(rootId: rootId)
        }
    }

    private func listDeletionRoots(containing listId: String) -> Set<String> {
        var roots = Set(listDeletionRootsInFlight.filter {
            $0 == listId || allDescendantIds(of: $0).contains(listId)
        })
        roots.formUnion(pendingListDeletionMembersByRoot.compactMap { rootId, memberIds in
            memberIds.contains(listId) ? rootId : nil
        })
        for pending in pendingSynchronousWrites.values {
            guard case .listSoftDelete(let rootId, _) = pending.plan,
                  rootId == listId || allDescendantIds(of: rootId).contains(listId)
            else { continue }
            roots.insert(rootId)
        }
        return roots
    }

    /// A destructive list operation must resolve optimistic folder moves
    /// before asking FileStore to recursively remove or tombstone a subtree.
    /// FileStore's path registry then remains the single source of truth for
    /// each list's durable location.
    private func reconcileRetainedListUpdates() async throws {
        while let retained = pendingSynchronousWrites
            .sorted(by: { $0.key < $1.key })
            .first(where: { _, pending in
                if case .listUpdates = pending.plan { return true }
                return false
            }) {
            try await executeRetainedSynchronousWrite(
                context: retained.key,
                generation: retained.value.generation
            )
            if pendingSynchronousWrites[retained.key] == nil {
                clearWriteFailure(context: retained.key)
            }
        }
    }

    private func conflictsWithListDeletion(_ ids: Set<String>) -> Bool {
        ids.contains {
            pendingDeletionListIds.contains($0)
                || !listDeletionRoots(containing: $0).isEmpty
        }
    }

    private func conflictsWithItemDeletion(_ ids: Set<UUID>) -> Bool {
        ids.contains {
            pendingDeletionItemIds.contains($0)
                || !itemDeletionRoots(containing: $0).isEmpty
        }
    }

    private func registerSynchronousWrite(
        _ plan: RetainedSynchronousWrite,
        context: String,
        itemIntentGeneration: UInt64? = nil
    ) {
        pendingSynchronousWrites[context]?.retryTask?.cancel()
        synchronousWriteGeneration &+= 1
        let generation = synchronousWriteGeneration
        pendingSynchronousWrites[context] = PendingSynchronousWrite(
            generation: generation,
            plan: plan,
            itemIntentGeneration: itemIntentGeneration,
            automaticRetryCount: 0,
            retryTask: nil
        )
        enqueueRetainedSynchronousWrite(context: context, generation: generation)
    }

    private func enqueueRetainedSynchronousWrite(
        context: String,
        generation: UInt64
    ) {
        enqueueDetachedWrite(
            context,
            reconcilesPreviousFailure: true
        ) { [self] in
            do {
                try await executeRetainedSynchronousWrite(
                    context: context,
                    generation: generation
                )
            } catch {
                // Restore/hard-delete can deliberately retire a replay while
                // its file operation is suspended. A failure from that stale
                // generation must not recreate the cleared durability error.
                guard pendingSynchronousWrites[context]?.generation == generation else {
                    clearWriteFailure(context: context)
                    return
                }
                try? await refreshPendingDeletionRecoveryState()
                scheduleAutomaticRetryIfCurrent(
                    context: context,
                    generation: generation
                )
                throw error
            }
        }
    }

    private func executeRetainedSynchronousWrite(
        context: String,
        generation: UInt64
    ) async throws {
        guard let pending = pendingSynchronousWrites[context],
              pending.generation == generation else { return }

        switch pending.plan {
        case .itemUpdate(let id, let sourceListId):
            guard let latest = item(id) else {
                pendingSynchronousWrites.removeValue(forKey: context)?.retryTask?.cancel()
                return
            }
            let persisted: Item
            let durableSourceListId = durableItemListIds[id] ?? sourceListId
            if let durableSourceListId, durableSourceListId != latest.listId {
                persisted = try await store.moveItem(
                    latest,
                    fromListId: durableSourceListId
                )
            } else {
                try await store.writeItem(latest)
                persisted = latest
            }
            documentFileNamesById[id] = await store.documentFileName(for: id)
            durableItemListIds[id] = persisted.listId

            if let idx = items.firstIndex(where: { $0.id == id }),
               items[idx] == latest {
                items[idx] = persisted
            }

            guard var current = pendingSynchronousWrites[context],
                  case .itemUpdate(let currentId, _) = current.plan,
                  currentId == id else { return }
            // Even if a newer optimistic edit arrived while this write was in
            // flight, this successful move advances the durable source path
            // that its queued generation must use.
            current.plan = .itemUpdate(id: id, sourceListId: persisted.listId)
            if current.generation == generation {
                current.retryTask?.cancel()
                pendingSynchronousWrites.removeValue(forKey: context)
                await scheduler.schedule(persisted)
            } else {
                pendingSynchronousWrites[context] = current
            }

        case .itemReorder(let listId, let targetIndexes):
            for (id, targetIndex) in targetIndexes.sorted(by: {
                $0.key.uuidString < $1.key.uuidString
            }) {
                guard var latest = item(id), latest.listId == listId else { continue }
                latest.sortIndex = targetIndex
                try await persistItemResolvingRetainedUpdate(
                    latest,
                    reconcilesConsumedNotification: true
                )
            }
            if pendingSynchronousWrites[context]?.generation == generation {
                pendingSynchronousWrites.removeValue(forKey: context)?.retryTask?.cancel()
            }

        case .itemSoftDelete(
            let rootId,
            let requestedDeletedAt,
            let plans,
            let priorCommittedIds
        ):
            func rollbackUncommittedOptimisticTombstones() {
                for plan in plans where !priorCommittedIds.contains(plan.tombstone.id) {
                    if self.item(plan.tombstone.id) == plan.tombstone {
                        replaceItemInMemory(plan.original)
                    }
                }
            }
            guard try await store.pendingRestore() == nil else {
                rollbackUncommittedOptimisticTombstones()
                throw RestoreError.pendingRestoreMustFinish
            }
            let affectedItemIds = Set(plans.map { $0.tombstone.id })
            let otherDeletionRoots = Set(affectedItemIds.flatMap {
                itemDeletionRoots(containing: $0)
            }).subtracting([rootId])
            guard otherDeletionRoots.isEmpty else {
                rollbackUncommittedOptimisticTombstones()
                throw MutationConflictError.ancestorDeletionInProgress
            }
            guard !conflictsWithListDeletion(Set(plans.map { $0.tombstone.listId })) else {
                rollbackUncommittedOptimisticTombstones()
                throw MutationConflictError.listDeletionInProgress
            }
            let deletionJournal = try await store.beginDeletion(
                FileStore.DeletionJournal(
                    kind: .item,
                    rootId: rootId.uuidString,
                    deletedAt: requestedDeletedAt
                )
            )
            let deletedAt = deletionJournal.deletedAt
            var committedIds = priorCommittedIds
            do {
                try await reconcileRetainedItemUpdates(
                    Set(plans.map { $0.original.listId })
                )
            } catch {
                for plan in plans where !committedIds.contains(plan.tombstone.id) {
                    if self.item(plan.tombstone.id) == plan.tombstone {
                        replaceItemInMemory(plan.original)
                    }
                }
                throw error
            }
            for (index, plan) in plans.enumerated() {
                if committedIds.contains(plan.tombstone.id) { continue }
                guard let current = item(plan.tombstone.id) else {
                    committedIds.insert(plan.tombstone.id)
                    continue
                }
                if let currentDeletedAt = current.deletedAt,
                   !isSameDeletionBatch(currentDeletedAt, deletedAt) {
                    // A later independent deletion owns this member now.
                    committedIds.insert(plan.tombstone.id)
                    continue
                }

                let rollback = isSameDeletionBatch(current.deletedAt, deletedAt)
                    ? plan.original
                    : current
                var tombstone = current
                tombstone.deletedAt = deletedAt
                tombstone.modifiedAt = deletedAt
                replaceItemInMemory(tombstone)
                do {
                    let persisted = try await persistItemResolvingRetainedUpdate(tombstone)
                    committedIds.insert(plan.tombstone.id)
                    if self.item(plan.tombstone.id) == tombstone {
                        replaceItemInMemory(persisted)
                    }
                    if var currentPlan = pendingSynchronousWrites[context],
                       currentPlan.generation == generation {
                        currentPlan.plan = .itemSoftDelete(
                            rootId: rootId,
                            deletedAt: deletedAt,
                            plans: plans,
                            committedIds: committedIds
                        )
                        pendingSynchronousWrites[context] = currentPlan
                    }
                    await scheduler.cancel(plan.tombstone.id)
                } catch {
                    if self.item(plan.tombstone.id) == tombstone {
                        replaceItemInMemory(rollback)
                    }
                    for remaining in plans.suffix(from: index + 1)
                    where !committedIds.contains(remaining.tombstone.id) {
                        if self.item(remaining.tombstone.id) == remaining.tombstone {
                            replaceItemInMemory(remaining.original)
                        }
                    }
                    if var currentPlan = pendingSynchronousWrites[context],
                       currentPlan.generation == generation {
                        currentPlan.plan = .itemSoftDelete(
                            rootId: rootId,
                            deletedAt: deletedAt,
                            plans: plans,
                            committedIds: committedIds
                        )
                        pendingSynchronousWrites[context] = currentPlan
                    }
                    throw error
                }
            }
            try await store.finishDeletion(deletionJournal)
            try await refreshPendingDeletionRecoveryState()
            if pendingSynchronousWrites[context]?.generation == generation {
                pendingSynchronousWrites.removeValue(forKey: context)?.retryTask?.cancel()
            }

        case .listUpdates(let ids):
            let byId = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            func depth(of id: String) -> Int {
                var depth = 0
                var cursor = byId[id]?.parentId
                var visited: Set<String> = [id]
                while let current = cursor,
                      visited.insert(current).inserted {
                    depth += 1
                    cursor = byId[current]?.parentId
                }
                return depth
            }
            for id in ids.sorted(by: {
                let lhsDepth = depth(of: $0)
                let rhsDepth = depth(of: $1)
                return lhsDepth == rhsDepth ? $0 < $1 : lhsDepth < rhsDepth
            }) {
                guard let latest = lists.first(where: { $0.id == id }) else { continue }
                try await store.writeList(latest)
            }
            if pendingSynchronousWrites[context]?.generation == generation {
                pendingSynchronousWrites.removeValue(forKey: context)?.retryTask?.cancel()
            }

        case .listSoftDelete(let rootId, let deletedAt):
            try await persistListSoftDelete(
                rootId: rootId,
                deletedAt: deletedAt
            )
            if pendingSynchronousWrites[context]?.generation == generation {
                pendingSynchronousWrites.removeValue(forKey: context)?.retryTask?.cancel()
            }
        }
    }

    private func scheduleAutomaticRetryIfCurrent(
        context: String,
        generation: UInt64
    ) {
        guard var pending = pendingSynchronousWrites[context],
              pending.generation == generation,
              pending.automaticRetryCount < 5 else { return }
        let delays = [250, 500, 1_000, 2_000, 4_000]
        let delay = delays[pending.automaticRetryCount]
        pending.automaticRetryCount += 1
        pending.retryTask?.cancel()
        pending.retryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(delay))
            } catch {
                return
            }
            guard let self,
                  var current = self.pendingSynchronousWrites[context],
                  current.generation == generation else { return }
            current.retryTask = nil
            self.pendingSynchronousWrites[context] = current
            self.enqueueRetainedSynchronousWrite(
                context: context,
                generation: generation
            )
        }
        pendingSynchronousWrites[context] = pending
    }

    /// Await every queued disk write, including writes appended while this
    /// method is suspended. A recorded failure remains sticky until that exact
    /// operation context succeeds; exporting or reloading must never treat an
    /// unrelated potentially-stale file as clean.
    public func flushPendingWrites() async throws {
        try await withMutationScope { [self] in
            try await flushPendingWritesUngated()
        }
    }

    private func flushPendingWritesUngated() async throws {
        var retriedContexts: Set<String> = []
        while true {
            let observedGeneration = writeGeneration
            let observedChain = writeChain
            await observedChain?.value
            guard observedGeneration == writeGeneration else { continue }

            // A flush is an explicit durability boundary. Give every retained
            // synchronous mutation one immediate replay before surfacing its
            // sticky failure; this also makes scene/lifecycle flushes useful
            // without spinning forever on a genuinely broken path.
            let retryableContexts = pendingSynchronousWrites.keys
                .filter { !retriedContexts.contains($0) }
                .sorted()
            if !retryableContexts.isEmpty {
                for context in retryableContexts {
                    retriedContexts.insert(context)
                    guard var pending = pendingSynchronousWrites[context] else { continue }
                    pending.retryTask?.cancel()
                    pending.retryTask = nil
                    pendingSynchronousWrites[context] = pending
                    enqueueRetainedSynchronousWrite(
                        context: context,
                        generation: pending.generation
                    )
                }
                continue
            }

            if let context = pendingWriteFailureOrder.first,
               let failure = pendingWriteFailures[context] {
                throw failure
            }
            return
        }
    }

    // Ordered wrappers around the FileStore verbs. All ItemStore persistence
    // goes through these so the FIFO guarantee covers every write.
    private func writeItemOrdered(_ item: Item) async throws {
        try await enqueueWrite(
            "item \(item.id)",
            reconcilesPreviousFailure: true
        ) { [self] in
            _ = try await persistItemResolvingRetainedUpdate(
                item,
                reconcilesConsumedNotification: true
            )
        }
    }
    private func writeListOrdered(_ list: ItemList) async throws {
        try await enqueueWrite(
            "list \(list.id)",
            reconcilesPreviousFailure: true
        ) { [store] in
            try await store.writeList(list)
        }
    }

    @discardableResult
    private func persistAndCommitList(
        _ desired: ItemList,
        baseline: ItemList,
        fields: Set<ListField>,
        intentGeneration: UInt64
    ) async throws -> ItemList {
        guard let liveBeforeWrite = lists.first(where: { $0.id == desired.id }) else {
            return desired
        }
        let priorFields = Set(ListField.allCases.filter {
            (latestListFieldIntent[desired.id]?[$0]?.latestGeneration ?? 0)
                <= intentGeneration
        })
        let stateBeforeWriter = Self.mergingListChanges(
            from: liveBeforeWrite,
            basedOn: baseline,
            into: baseline,
            allowedFields: priorFields,
            forceAllowedFields: true
        )
        var persisted = Self.mergingListChanges(
            from: desired,
            basedOn: baseline,
            into: stateBeforeWriter,
            allowedFields: fields,
            forceAllowedFields: true
        )
        persisted.modifiedAt = .now
        try await store.writeList(persisted)
        if let listWriteCommitted = maintenanceTestHooks.listWriteCommitted {
            await listWriteCommitted()
        }
        guard let index = lists.firstIndex(where: { $0.id == desired.id }) else {
            return persisted
        }
        let latest = lists[index]
        let publishableFields = fields.filter { field in
            (latestListFieldIntent[desired.id]?[field]?
                .latestOptimisticGeneration ?? 0) <= intentGeneration
        }
        var committed = Self.mergingListChanges(
            from: persisted,
            basedOn: liveBeforeWrite,
            into: latest,
            allowedFields: publishableFields,
            forceAllowedFields: true
        )
        if latest.modifiedAt == liveBeforeWrite.modifiedAt {
            committed.modifiedAt = persisted.modifiedAt
        }
        lists[index] = committed
        return persisted
    }
    private func deleteItemOrdered(_ item: Item) async throws {
        try await enqueueWrite(
            "delete item \(item.id)",
            reconcilesPreviousFailure: true
        ) { [self] in
            try await deleteItemAndRetainedSource(item)
        }
    }
    /// Persist one ordinary item edit and publish it to observers only after
    /// the file operation succeeds. Call only from inside `enqueueWrite` so
    /// reading the previous path, writing, and committing memory share the
    /// same ordering boundary as every other store write.
    @discardableResult
    private func persistAndCommitItem(
        _ desired: Item,
        baseline: Item,
        fields: Set<ItemField>,
        intentGeneration: UInt64
    ) async throws -> Item {
        let liveBeforeWrite = self.item(desired.id) ?? baseline
        let priorFields = Set(ItemField.allCases.filter {
            (latestItemFieldIntent[desired.id]?[$0]?.latestGeneration ?? 0)
                <= intentGeneration
        })
        let stateBeforeWriter = Self.mergingItemChanges(
            from: liveBeforeWrite,
            basedOn: baseline,
            into: baseline,
            allowedFields: priorFields,
            forceAllowedFields: true
        )
        var updated = Self.mergingItemChanges(
            from: desired,
            basedOn: baseline,
            into: stateBeforeWriter,
            allowedFields: fields,
            forceAllowedFields: true
        )
        updated = normalizedForStorage(updated)
        updated.modifiedAt = .now
        let oldListId = durableItemListIds[desired.id] ?? liveBeforeWrite.listId

        updated = try await persistItemResolvingRetainedUpdate(
            updated,
            from: oldListId,
            writerIntentGeneration: intentGeneration
        )
        if let itemWriteCommitted = maintenanceTestHooks.itemWriteCommitted {
            await itemWriteCommitted()
        }

        // Merge a mutation accepted while the file write was suspended. Newer
        // changes win on fields they touched; independent edits compose.
        if let index = items.firstIndex(where: { $0.id == updated.id }) {
            let latest = items[index]
            let publishableFields = fields.filter { field in
                (latestItemFieldIntent[desired.id]?[field]?
                    .latestOptimisticGeneration ?? 0) <= intentGeneration
            }
            var committed = Self.mergingItemChanges(
                from: updated,
                basedOn: liveBeforeWrite,
                into: latest,
                allowedFields: publishableFields,
                forceAllowedFields: true
            )
            committed = normalizedForStorage(committed)
            if latest.modifiedAt == liveBeforeWrite.modifiedAt {
                committed.modifiedAt = updated.modifiedAt
            }
            items[index] = committed
        }
        return updated
    }

    /// A quarantined or incomplete recovery load is not authoritative about
    /// which item UUIDs still exist. Refresh reminders for every item we could
    /// decode, but do not let a partial snapshot delete notifications that may
    /// belong to preserved, recoverable files.
    private func reconcileNotificationsAfterLoad() async {
        if loadIssues.isEmpty,
           !hasPendingRestoreRecovery,
           !hasPendingDeletionRecovery {
            await scheduler.reconcile(items)
        } else {
            for item in items {
                if pendingDeletionItemIds.contains(item.id) {
                    await scheduler.cancel(item.id)
                } else {
                    await scheduler.schedule(item)
                }
            }
        }
    }

    private func deletionMemberItemIds(
        for journals: [FileStore.DeletionJournal]
    ) -> Set<UUID> {
        var ids: Set<UUID> = []
        for journal in journals {
            switch journal.kind {
            case .item:
                guard let rootId = UUID(uuidString: journal.rootId) else { continue }
                ids.insert(rootId)
                ids.formUnion(allItemDescendantIds(of: rootId))
            case .list:
                let listIds = Set([journal.rootId] + allDescendantIds(of: journal.rootId))
                ids.formUnion(items.lazy.filter {
                    listIds.contains($0.listId)
                }.map(\.id))
            }
        }
        return ids
    }

    private func deletionMemberListIds(
        for journals: [FileStore.DeletionJournal]
    ) -> Set<String> {
        var ids: Set<String> = []
        for journal in journals where journal.kind == .list {
            ids.insert(journal.rootId)
            ids.formUnion(allDescendantIds(of: journal.rootId))
        }
        return ids
    }

    private func installPendingDeletionRecoveryState(
        _ journals: [FileStore.DeletionJournal]
    ) {
        var itemMembersByRoot: [UUID: Set<UUID>] = [:]
        var listMembersByRoot: [String: Set<String>] = [:]

        for journal in journals {
            switch journal.kind {
            case .item:
                guard let rootId = UUID(uuidString: journal.rootId) else { continue }
                itemMembersByRoot[rootId] = Set(
                    [rootId] + allItemDescendantIds(of: rootId)
                )
            case .list:
                listMembersByRoot[journal.rootId] = Set(
                    [journal.rootId] + allDescendantIds(of: journal.rootId)
                )
            }
        }

        pendingItemDeletionMembersByRoot = itemMembersByRoot
        pendingListDeletionMembersByRoot = listMembersByRoot
        pendingDeletionItemIds = deletionMemberItemIds(for: journals)
        pendingDeletionListIds = deletionMemberListIds(for: journals)
        hasPendingDeletionRecovery = !journals.isEmpty
    }

    private func refreshPendingDeletionRecoveryState() async throws {
        let remaining = try await store.pendingDeletions()
        installPendingDeletionRecoveryState(remaining)
    }

    /// Continue any root-first soft deletion before hierarchy repair can
    /// detach its still-live suffix. The journal is created before the first
    /// tombstone write, so a process death cannot turn a requested deletion
    /// into resurfaced children on the next launch.
    private func resumePendingDeletionsAfterLoad(
        whileRestorePending: Bool
    ) async throws -> Bool {
        let journals: [FileStore.DeletionJournal]
        do {
            journals = try await store.pendingDeletions()
        } catch {
            let root = await store.rootURL()
            let journalPath = root
                .appendingPathComponent(".deletion-journals.json")
                .path
            if !loadIssues.contains(journalPath) {
                loadIssues.append(journalPath)
            }
            pendingDeletionItemIds = Set(items.map(\.id))
            pendingDeletionListIds = Set(lists.map(\.id))
            pendingItemDeletionMembersByRoot = [:]
            pendingListDeletionMembersByRoot = [:]
            hasPendingDeletionRecovery = true
            Self.log.error("Could not read deletion journal: \(String(describing: error), privacy: .private)")
            return false
        }
        installPendingDeletionRecoveryState(journals)
        guard !journals.isEmpty else {
            return true
        }
        guard loadIssues.isEmpty, !whileRestorePending else {
            hasPendingDeletionRecovery = true
            return false
        }

        var firstFailure: (any Error)?
        for journal in journals.sorted(by: {
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.rootId < $1.rootId
        }) {
            do {
                switch journal.kind {
                case .item:
                    try await resumePendingItemDeletion(journal)
                case .list:
                    guard lists.contains(where: { $0.id == journal.rootId }) else {
                        try await store.finishDeletion(journal)
                        continue
                    }
                    try await persistListSoftDelete(
                        rootId: journal.rootId,
                        deletedAt: journal.deletedAt
                    )
                }
            } catch {
                if firstFailure == nil { firstFailure = error }
                switch journal.kind {
                case .item:
                    break // resumePendingItemDeletion retained its exact suffix
                case .list:
                    retainListSoftDelete(
                        rootId: journal.rootId,
                        deletedAt: journal.deletedAt
                    )
                }
            }
        }

        let remaining = try await store.pendingDeletions()
        installPendingDeletionRecoveryState(remaining)
        return firstFailure == nil && remaining.isEmpty
    }

    private func resumePendingItemDeletion(
        _ journal: FileStore.DeletionJournal
    ) async throws {
        guard let rootId = UUID(uuidString: journal.rootId),
              item(rootId) != nil else {
            try await store.finishDeletion(journal)
            return
        }
        let ids = Self.parentFirstItemIds(
            [rootId] + allItemDescendantIds(of: rootId),
            in: items
        )
        var plans: [SynchronousDeletionPlan] = []
        for id in ids {
            guard let current = item(id), current.deletedAt == nil else { continue }
            var tombstone = current
            tombstone.deletedAt = journal.deletedAt
            tombstone.modifiedAt = journal.deletedAt
            plans.append(SynchronousDeletionPlan(
                original: current,
                tombstone: tombstone
            ))
        }

        var committedIds: Set<UUID> = []
        do {
            for plan in plans {
                let persisted = try await persistItemResolvingRetainedUpdate(
                    plan.tombstone
                )
                committedIds.insert(plan.tombstone.id)
                replaceItemInMemory(persisted)
                await scheduler.cancel(plan.tombstone.id)
            }
            try await store.finishDeletion(journal)
        } catch {
            retainSynchronousSoftDelete(
                rootId: rootId,
                deletedAt: journal.deletedAt,
                plans: plans,
                committedIds: committedIds
            )
            throw error
        }
    }

    /// Recovery operations are independent durable intents. A broken restore
    /// must not prevent us from reading deletion journals: even when replay is
    /// unsafe, installing their fences keeps edits and reminders away from the
    /// affected data for the rest of this launch.
    private func resumePendingRecoveryOperationsAfterLoad(
        _ pendingRestore: FileStore.RestoreJournal?
    ) async throws -> Bool {
        var firstFailure: (any Error)?
        let restoreCanRepair: Bool
        do {
            restoreCanRepair = try await resumePendingRestoreIfNeeded(pendingRestore)
        } catch {
            if pendingRestoreCleanup == nil {
                hasPendingRestoreRecovery = true
            }
            restoreCanRepair = false
            firstFailure = error
            Self.log.error(
                "Could not resume pending restore: \(String(describing: error), privacy: .private)"
            )
        }

        let deletionsCanRepair: Bool
        do {
            deletionsCanRepair = try await resumePendingDeletionsAfterLoad(
                whileRestorePending: !restoreCanRepair
            )
        } catch {
            hasPendingDeletionRecovery = true
            deletionsCanRepair = false
            if firstFailure == nil { firstFailure = error }
            Self.log.error(
                "Could not resume pending deletions: \(String(describing: error), privacy: .private)"
            )
        }

        if let firstFailure {
            await reconcileNotificationsAfterLoad()
            throw firstFailure
        }
        return restoreCanRepair && deletionsCanRepair
    }

    /// First-time bootstrap: ensure the Lists root exists, load whatever is
    /// already on disk, and (if empty) seed sample data.
    public func bootstrap() async throws {
        // A second bootstrap on the same store must not run; otherwise both
        // could observe an empty disk and seed.
        guard !isLoaded && !isBootstrapping else { return }
        isBootstrapping = true
        // Always finish "loading", even on a partial failure: showing an empty
        // sidebar + a banner beats hanging forever on "Loading…".
        defer { self.isLoaded = true; self.isBootstrapping = false }
        try await store.ensureRoot()
        let loaded = try await store.loadAll()
        self.loadIssues = loaded.quarantined.map(\.originalPath)
        self.hasPendingRestoreRecovery = false
        self.hasPendingDeletionRecovery = false
        self.pendingDeletionItemIds = []
        self.pendingDeletionListIds = []
        self.pendingItemDeletionMembersByRoot = [:]
        self.pendingListDeletionMembersByRoot = [:]
        self.pendingRestoreCleanup = nil
        let pendingRestore = await pendingRestoreForLoad()

        // Only seed a genuinely-empty library. A quarantine-only load is NOT
        // empty — re-seeding there would write sample data on top of the user's
        // (recoverable) files.
        if loaded.lists.isEmpty,
           loadIssues.isEmpty,
           pendingRestore == nil,
           !hasPendingRestoreRecovery {
            let inbox = ItemList.makeInbox()
            let extraLists = SampleData.seedLists()
            let allLists = [inbox] + extraLists
            for list in allLists {
                try await writeListOrdered(list)
            }
            let samples = SampleData.seedItems(inboxId: inbox.id)
            for sample in samples {
                try await writeItemOrdered(sample)
            }
            self.lists = allLists
            self.items = samples
        } else {
            self.lists = loaded.lists.map(\.list)
            self.items = loaded.lists.flatMap(\.items)
        }
        self.durableItemListIds = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0.listId) }
        )
        self.documentFileNamesById = await store.documentFileNames()
        self.latestItemFieldIntent.removeAll()
        self.latestListFieldIntent.removeAll()
        guard try await resumePendingRecoveryOperationsAfterLoad(pendingRestore) else {
            await reconcileNotificationsAfterLoad()
            return
        }
        await repairLoadedListHierarchy()
        if loadIssues.isEmpty {
            try await purgeExpiredTombstones()
        }
        for list in self.lists where list.deletedAt == nil {
            try? await migrateLegacySectionsIfNeeded(listId: list.id)
        }
        await repairLoadedItemHierarchy()
        try await persistPortableLinkRewrites(
            oldItems: items,
            oldLists: lists,
            oldDocumentFileNames: documentFileNamesById
        )
        await reconcileNotificationsAfterLoad()
    }

    /// Re-read the on-disk library and replace the in-memory snapshot.
    ///
    /// Files are the source of truth; this rebuilds the app's live view of
    /// them without seeding sample data into an empty folder.
    public func reloadFromDisk() async throws {
        if isReloadingFromDisk {
            try await waitForCurrentReload()
            return
        }
        isReloadingFromDisk = true
        await acquireExclusiveOperationClaim()
        await acquireMaintenanceAccess()

        var outcome: Result<Void, any Error>
        do {
            try await Self.$bypassesMutationGate.withValue(true) {
                try await performReloadFromDisk()
            }
            outcome = .success(())
        } catch {
            outcome = .failure(error)
        }
        do {
            try await drainDeferredMutations()
        } catch {
            if case .success = outcome {
                outcome = .failure(error)
            }
        }

        releaseMaintenanceAccess()
        releaseExclusiveOperationClaim()
        isReloadingFromDisk = false
        resumeConcurrentReloadCallers(with: outcome)
        try outcome.get()
    }

    private func performReloadFromDisk() async throws {
        try await flushPendingWritesUngated()
        try await store.ensureRoot()

        let loaded = try await store.loadAll()
        self.loadIssues = loaded.quarantined.map(\.originalPath)
        self.hasPendingRestoreRecovery = false
        self.hasPendingDeletionRecovery = false
        self.pendingDeletionItemIds = []
        self.pendingDeletionListIds = []
        self.pendingItemDeletionMembersByRoot = [:]
        self.pendingListDeletionMembersByRoot = [:]
        self.pendingRestoreCleanup = nil
        let pendingRestore = await pendingRestoreForLoad()
        if let snapshotCaptured = maintenanceTestHooks.snapshotCaptured {
            try await snapshotCaptured()
        }
        self.lists = loaded.lists.map(\.list)
        self.items = loaded.lists.flatMap(\.items)
        self.durableItemListIds = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0.listId) }
        )
        self.documentFileNamesById = await store.documentFileNames()
        self.latestItemFieldIntent.removeAll()
        self.latestListFieldIntent.removeAll()
        self.isLoaded = true

        guard try await resumePendingRecoveryOperationsAfterLoad(pendingRestore) else {
            await reconcileNotificationsAfterLoad()
            return
        }
        await repairLoadedListHierarchy()
        if loadIssues.isEmpty {
            try await purgeExpiredTombstones()
        }
        for list in self.lists where list.deletedAt == nil {
            try? await migrateLegacySectionsIfNeeded(listId: list.id)
        }
        await repairLoadedItemHierarchy()
        try await persistPortableLinkRewrites(
            oldItems: items,
            oldLists: lists,
            oldDocumentFileNames: documentFileNamesById
        )
        await reconcileNotificationsAfterLoad()
    }

    /// Flush pending writes and package the app-private Lists folder for sharing.
    public func exportLibrary() async throws -> URL {
        await acquireExclusiveOperationClaim()
        await acquireMaintenanceAccess()

        var outcome: Result<URL, any Error>
        do {
            try await flushPendingWritesUngated()
            try await store.ensureRoot()
            let root = await store.rootURL()
            if let exportSnapshotReady = maintenanceTestHooks.exportSnapshotReady {
                await exportSnapshotReady()
            }
            let archive = try await Task.detached(priority: .userInitiated) {
                try LibraryExporter.exportLibrary(at: root)
            }.value
            outcome = .success(archive)
        } catch {
            outcome = .failure(error)
        }
        do {
            try await drainDeferredMutations()
        } catch {
            if case .success = outcome {
                outcome = .failure(error)
            }
        }

        releaseMaintenanceAccess()
        releaseExclusiveOperationClaim()
        return try outcome.get()
    }

    public func importAttachment(
        data: Data,
        originalFileName: String?,
        preferredExtension: String? = nil
    ) async throws -> StoredAttachment {
        try await withMutationScope { [self] in
            try await enqueueWrite("import attachment") {
                try await self.store.importAttachment(
                    data: data,
                    originalFileName: originalFileName,
                    preferredExtension: preferredExtension
                )
            }
        }
    }

    public func attachmentURL(for relativePath: String) async throws -> URL {
        try await store.attachmentURL(for: relativePath)
    }

    public func importDrawing(sourceData: Data, previewPNGData: Data) async throws -> StoredDrawing {
        try await withMutationScope { [self] in
            try await enqueueWrite("import drawing") {
                try await self.store.importDrawing(
                    sourceData: sourceData,
                    previewPNGData: previewPNGData
                )
            }
        }
    }

    public func replaceDrawing(
        sourceRelativePath: String,
        previewRelativePath: String,
        sourceData: Data,
        previewPNGData: Data
    ) async throws -> StoredDrawing {
        try await withMutationScope { [self] in
            try await enqueueWrite("replace drawing") {
                try await self.store.replaceDrawing(
                    sourceRelativePath: sourceRelativePath,
                    previewRelativePath: previewRelativePath,
                    sourceData: sourceData,
                    previewPNGData: previewPNGData
                )
            }
        }
    }

    public func canvasDocument(at relativePath: String) async throws -> CanvasDocument {
        try await store.readCanvasDocument(at: relativePath)
    }

    public func nativeCanvasData(at relativePath: String) async throws -> Data {
        try await store.readNativeCanvasData(at: relativePath)
    }

    public func canvasPreviewURL(at relativePath: String) async throws -> URL? {
        try await store.canvasPreviewURL(at: relativePath)
    }

    public func saveCanvas(
        at relativePath: String,
        nativeData: Data,
        previewPNGData: Data,
        linkCards: [CanvasLinkCard] = []
    ) async throws {
        try await withMutationScope { [self] in
            try await enqueueWrite("save canvas \(relativePath)") {
                try await self.store.writeCanvas(
                    at: relativePath,
                    nativeData: nativeData,
                    previewPNGData: previewPNGData,
                    linkCards: linkCards
                )
            }
        }
    }

    /// Saves a first-class Canvas and keeps its portable bundle name aligned
    /// with the visible title. The new bundle is written before metadata is
    /// committed; only then is the superseded bundle removed. This makes a
    /// failed rename recoverable without exposing a half-moved Canvas.
    @discardableResult
    public func saveCanvasItem(
        _ id: UUID,
        title: String,
        nativeData: Data,
        previewPNGData: Data,
        linkCards: [CanvasLinkCard] = []
    ) async throws -> Item {
        try await withMutationScope { [self] in
            guard let baseline = item(id),
                  baseline.type == .canvas,
                  let oldCanvasPath = baseline.canvasPath else {
                throw CanvasStorageError.invalidPath
            }
            let oldItems = items
            let oldLists = lists
            let oldDocumentFileNames = documentFileNamesById
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = trimmed.isEmpty ? "Untitled Canvas" : trimmed

            return try await enqueueWrite(
                "save canvas item \(id)",
                reconcilesPreviousFailure: true
            ) { [self] in
                let target = try await store.availableCanvasResource(
                    title: resolvedTitle,
                    preserving: oldCanvasPath
                )
                try await store.writeCanvas(
                    at: target.canvasPath,
                    preservingDocumentFrom: oldCanvasPath,
                    nativeData: nativeData,
                    previewPNGData: previewPNGData,
                    linkCards: linkCards
                )

                var desired = baseline
                desired.title = resolvedTitle
                desired.canvasPath = target.canvasPath
                let fields = Self.changedItemFields(from: baseline, to: desired)
                let intentGeneration = acceptItemIntent(for: id, fields: fields)
                var metadataCommitted = false
                do {
                    let persisted = try await persistAndCommitItem(
                        desired,
                        baseline: baseline,
                        fields: fields,
                        intentGeneration: intentGeneration
                    )
                    metadataCommitted = true
                    await scheduler.schedule(persisted)
                    if baseline.title != desired.title
                        || baseline.canvasPath != desired.canvasPath {
                        try await persistPortableLinkRewrites(
                            oldItems: oldItems,
                            oldLists: oldLists,
                            oldDocumentFileNames: oldDocumentFileNames
                        )
                    }
                    if oldCanvasPath != target.canvasPath {
                        // Cleanup happens last. A failure here leaves only a
                        // harmless recoverable duplicate, never a missing live
                        // Canvas, so the successful save remains authoritative.
                        try? await store.deleteCanvasResource(at: oldCanvasPath)
                    }
                    return item(id) ?? persisted
                } catch {
                    if metadataCommitted == false,
                       oldCanvasPath != target.canvasPath {
                        try? await store.deleteCanvasResource(at: target.canvasPath)
                    }
                    throw error
                }
            }
        }
    }

    /// Maintenance entry point, intentionally separate from ordinary edits.
    /// Callers can show the quarantined paths before choosing whether to
    /// restore them; this method never permanently deletes user files.
    public func quarantineUnreferencedAttachments() async throws -> [String] {
        try await withMutationScope { [self] in
            let referenced = MarkdownAttachmentIndex.referencedPaths(in: items)
            return try await enqueueWrite("quarantine unreferenced attachments") {
                try await self.store.quarantineUnreferencedAttachments(referencedPaths: referenced)
            }
        }
    }

    public func restoreQuarantinedAttachment(fileName: String) async throws -> StoredAttachment {
        try await withMutationScope { [self] in
            try await enqueueWrite("restore attachment \(fileName)") {
                try await self.store.restoreQuarantinedAttachment(fileName: fileName)
            }
        }
    }

    /// Finish a root-last restore before hierarchy repair can mistake its
    /// durable active prefix for corruption and detach it from the tombstoned
    /// retry root. A journal left after the root itself committed is complete;
    /// only its final cleanup remains.
    private func pendingRestoreForLoad() async -> FileStore.RestoreJournal? {
        do {
            return try await store.pendingRestore()
        } catch {
            blockPendingRestoreRecovery(
                "Could not read pending restore: \(String(describing: error))"
            )
            return nil
        }
    }

    private func blockPendingRestoreRecovery(_ reason: String) {
        hasPendingRestoreRecovery = true
        Self.log.error("Pending restore needs recovery: \(reason, privacy: .private)")
    }

    private func finishRestore(
        _ journal: FileStore.RestoreJournal,
        cleanup: PendingRestoreCleanup
    ) async throws {
        do {
            try await store.finishRestore(journal)
            pendingRestoreCleanup = nil
        } catch {
            pendingRestoreCleanup = cleanup
            throw error
        }
    }

    @discardableResult
    private func resumePendingRestoreIfNeeded(
        _ journal: FileStore.RestoreJournal?
    ) async throws -> Bool {
        guard !hasPendingRestoreRecovery else { return false }
        guard let journal else { return loadIssues.isEmpty }
        guard loadIssues.isEmpty else {
            blockPendingRestoreRecovery(
                "One or more library files were quarantined while a restore was pending."
            )
            return false
        }
        guard journal.hasMemberManifest else {
            blockPendingRestoreRecovery(
                "The pending restore predates durable batch manifests."
            )
            return false
        }

        let loadedItemIds = Set(items.map { $0.id.uuidString })
        let loadedListIds = Set(lists.map(\.id))
        let missingItemIds = journal.expectedItemIds.filter { !loadedItemIds.contains($0) }
        let missingListIds = journal.expectedListIds.filter { !loadedListIds.contains($0) }
        if !missingItemIds.isEmpty || !missingListIds.isEmpty {
            blockPendingRestoreRecovery(
                "Pending restore members are missing (items: \(missingItemIds), lists: \(missingListIds))."
            )
            return false
        }

        switch journal.kind {
        case .item:
            guard let id = UUID(uuidString: journal.rootId), let root = item(id) else {
                blockPendingRestoreRecovery("Pending item restore root is missing.")
                return false
            }
            guard let rootDeletedAt = root.deletedAt else {
                try await finishRestore(journal, cleanup: .item(id))
                return true
            }
            guard isSameDeletionBatch(rootDeletedAt, journal.deletedAt) else {
                blockPendingRestoreRecovery("Pending item restore root changed.")
                return false
            }
            try await performRestore(id)

        case .list:
            guard let root = lists.first(where: { $0.id == journal.rootId }) else {
                blockPendingRestoreRecovery("Pending list restore root is missing.")
                return false
            }
            guard let rootDeletedAt = root.deletedAt else {
                try await finishRestore(journal, cleanup: .list(root.id))
                return true
            }
            guard isSameDeletionBatch(rootDeletedAt, journal.deletedAt) else {
                blockPendingRestoreRecovery("Pending list restore root changed.")
                return false
            }
            try await performRestoreList(root.id)
        }
        return true
    }

    // MARK: - Soft-deleted accessors

    public var deletedItems: [Item] {
        items.filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    public var deletedLists: [ItemList] {
        lists.filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    /// Best target for a "new item" capture: the active Inbox if it exists,
    /// otherwise the first non-deleted list by position. Returns nil when
    /// every list has been deleted — the UI should disable item creation in
    /// that case until the user adds a list back.
    public var defaultCaptureListId: String? {
        if let inbox = lists.first(where: { $0.id == ItemList.inboxId && $0.deletedAt == nil }) {
            return inbox.id
        }
        return lists
            .filter { $0.deletedAt == nil }
            .sorted { $0.position < $1.position }
            .first?.id
    }

    /// Count shown beside user lists. This follows the same product rule as
    /// list visibility: active items that are not complete and have not rolled
    /// off as past calendar events still need attention.
    public func openItemCount(
        in listId: String,
        now: Date = .now,
        itemTypePolicy: ItemTypePolicy = .allEnabled
    ) -> Int {
        items.filter { item in
            item.listId == listId
                && item.deletedAt == nil
                && item.isAvailable(in: itemTypePolicy)
                && !item.isComplete(at: now)
                && !item.isRolledOffPastEvent(now: now)
        }.count
    }

    public func toggleDone(_ id: UUID) async throws {
        try await withMutationScope { [self] in
            try await toggleDoneUngated(id)
        }
    }

    private func requireMutableItem(_ id: UUID) throws -> Item {
        guard let item = self.item(id), item.deletedAt == nil else {
            throw MutationConflictError.deletedItemRequiresRestore
        }
        guard lists.contains(where: {
            $0.id == item.listId && $0.deletedAt == nil
        }) else {
            throw MutationConflictError.inactiveDestinationList
        }
        guard !conflictsWithListDeletion([item.listId]) else {
            throw MutationConflictError.listDeletionInProgress
        }
        guard !conflictsWithItemDeletion([id]) else {
            throw MutationConflictError.itemDeletionInProgress
        }
        return item
    }

    private func toggleDoneUngated(_ id: UUID) async throws {
        _ = try requireMutableItem(id)
        try await enqueueWrite(
            "toggle item \(id)",
            reconcilesPreviousFailure: true
        ) { [self] in
            guard let original = self.item(id), original.deletedAt == nil else { return }
            guard lists.contains(where: {
                $0.id == original.listId && $0.deletedAt == nil
            }) else { return }
            // A non-completable event has no done state to toggle — when it
            // passes, it's simply past.
            if original.type == .event && !original.completable { return }

            let now = Date.now
            var toggled = original
            let isRecurringAction =
                (original.type == .task || (original.type == .event && original.completable))
                && original.recurrence != nil
                && original.due != nil

            if isRecurringAction,
               !original.done,
               let due = original.due,
               let rrule = original.recurrence?.rrule {
                let transition = RecurrenceEngine.completeCurrentOccurrence(
                    due: due,
                    rrule: rrule,
                    timeZone: original.dueTimeZone,
                    occurrences: original.recurrenceOccurrences,
                    at: now
                )
                let duration = original.end.map { $0.timeIntervalSince(due) }
                toggled.recurrenceOccurrences = transition.occurrences
                toggled.due = transition.due
                if let duration {
                    toggled.end = transition.due.addingTimeInterval(duration)
                }
                // An active repeating document immediately represents its next
                // occurrence. Only a rule whose final occurrence was just
                // completed becomes a conventionally completed item.
                toggled.done = transition.seriesEnded
                toggled.completedAt = transition.seriesEnded ? now : nil
                toggled.recurrenceSourceId = nil
                toggled.recurrenceSuccessorId = nil
            } else {
                toggled.done.toggle()
                toggled.completedAt = toggled.done ? now : nil
                if isRecurringAction,
                   !toggled.done,
                   let index = toggled.recurrenceOccurrences.lastIndex(where: {
                       $0.status == .completed
                   }) {
                    // Uncompleting a finished series corrects its final history
                    // record to missed. It does not synthesize or rewind a new
                    // scheduled occurrence.
                    toggled.recurrenceOccurrences[index].status = .missed
                    toggled.recurrenceOccurrences[index].completedAt = nil
                }
            }
            toggled.modifiedAt = now

            // Publish immediately so later UI edits inherit the new completion
            // state. If persistence fails, roll back only when no newer edit
            // has replaced this exact optimistic value.
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx] = toggled
            }

            do {
                let persistedRoot = try await persistItemResolvingRetainedUpdate(
                    toggled,
                    from: original.listId
                )
                if let idx = items.firstIndex(where: { $0.id == id }),
                   items[idx] == toggled {
                    items[idx] = persistedRoot
                }
            } catch {
                if let idx = items.firstIndex(where: { $0.id == id }),
                   items[idx].deletedAt == nil {
                    if items[idx] == toggled {
                        items[idx] = original
                    } else if items[idx].done == toggled.done,
                              items[idx].completedAt == toggled.completedAt {
                        // Keep any newer title/body/placement edit that landed
                        // while saving, but don't leave a failed completion
                        // published only in memory.
                        items[idx].done = original.done
                        items[idx].completedAt = original.completedAt
                        items[idx].due = original.due
                        items[idx].end = original.end
                        items[idx].recurrenceOccurrences = original.recurrenceOccurrences
                        items[idx].recurrenceSourceId = original.recurrenceSourceId
                        items[idx].recurrenceSuccessorId = original.recurrenceSuccessorId
                    }
                }
                throw error
            }

            if toggled.done {
                await scheduler.cancel(toggled.id)
            } else {
                // Scheduling the next due also clears every delivered revision
                // belonging to this item while preserving the new pending one.
                await scheduler.schedule(toggled)
            }
        }
    }

    private struct RecurringSuccessorPlan {
        var item: Item
        var needsInitialWrite: Bool
        var needsFinalization: Bool
    }

    /// Plan the next occurrence from the live value inside the ordered toggle
    /// transaction. A durable source id takes precedence over date matching so
    /// an interrupted retry cannot create a second successor days later.
    private func makeRecurringSuccessorPlan(
        for completed: Item,
        completedAt now: Date
    ) -> RecurringSuccessorPlan? {
        guard completed.type == .task || (completed.type == .event && completed.completable),
              let rrule = completed.recurrence?.rrule,
              let base = completed.due else { return nil }

        if let successorId = completed.recurrenceSuccessorId,
           let committed = item(successorId), committed.deletedAt == nil {
            return RecurringSuccessorPlan(
                item: committed,
                needsInitialWrite: false,
                needsFinalization: false
            )
        }

        if let existing = items.first(where: {
            $0.recurrenceSourceId == completed.id && $0.deletedAt == nil
        }) {
            return RecurringSuccessorPlan(
                item: existing,
                needsInitialWrite: false,
                needsFinalization: false
            )
        }

        // Roll long-overdue schedules forward from their original cadence so
        // the successor itself is not already overdue and reminder-less.
        let nextDue = nextRecurringDue(
            after: base,
            rrule: rrule,
            timeZone: completed.dueTimeZone,
            laterThan: now
        )
        guard let nextDue else { return nil }

        if let alreadySpawned = items.first(where: { candidate in
            candidate.id != completed.id
                && candidate.deletedAt == nil
                && !candidate.done
                && candidate.recurrenceSourceId == nil
                && candidate.recurrenceSuccessorId == nil
                && !items.contains {
                    $0.id != completed.id && $0.recurrenceSuccessorId == candidate.id
                }
                && candidate.type == completed.type
                && candidate.listId == completed.listId
                && candidate.title == completed.title
                && candidate.recurrence?.rrule == rrule
                && candidate.due == nextDue
        }) {
            var adopted = alreadySpawned
            adopted.recurrenceSourceId = completed.id
            adopted.modifiedAt = now
            return RecurringSuccessorPlan(
                item: adopted,
                needsInitialWrite: true,
                needsFinalization: false
            )
        }

        var successor = completed
        successor.id = UUID()
        successor.done = false
        successor.completedAt = nil
        successor.due = nextDue
        successor.recurrenceSourceId = completed.id
        successor.recurrenceSuccessorId = nil
        // A recurring event's span keeps its duration: end advances with due.
        successor.end = completed.end.map { nextDue.addingTimeInterval($0.timeIntervalSince(base)) }
        successor.createdAt = now
        successor.modifiedAt = now
        return RecurringSuccessorPlan(
            item: successor,
            needsInitialWrite: true,
            needsFinalization: true
        )
    }

    private func nextRecurringDue(
        after base: Date,
        rrule: String,
        timeZone: String?,
        laterThan now: Date
    ) -> Date? {
        let calendar = RecurrenceEngine.calendar(forTimeZone: timeZone)
        var nextDue = RecurrenceEngine.nextOccurrence(
            after: base,
            rrule: rrule,
            calendar: calendar
        )
        var hops = 0
        while let candidate = nextDue, candidate <= now, hops < 1000 {
            nextDue = RecurrenceEngine.nextOccurrence(
                after: candidate,
                rrule: rrule,
                calendar: calendar
            )
            hops += 1
        }
        return nextDue
    }

    private func completedRootSnapshot(
        _ id: UUID,
        fallback: Item,
        completedAt: Date
    ) -> Item {
        var root = item(id) ?? fallback
        root.done = true
        root.completedAt = completedAt
        if root.modifiedAt < completedAt {
            root.modifiedAt = completedAt
        }
        return root
    }

    /// Refresh an uncommitted successor from the latest source snapshot. The
    /// source does not link to it until the root-last write, so a restart can
    /// distinguish this retryable transaction from an intentional later untick.
    private func finalizeRecurringSuccessor(
        _ initial: Item,
        from sourceId: UUID,
        originalRoot: Item,
        completedAt: Date
    ) async throws -> (successor: Item?, root: Item) {
        var successor = initial

        while true {
            let root = completedRootSnapshot(
                sourceId,
                fallback: originalRoot,
                completedAt: completedAt
            )
            replaceItemInMemory(root)

            guard let rrule = root.recurrence?.rrule,
                  let base = root.due,
                  root.type == .task || (root.type == .event && root.completable),
                  let nextDue = nextRecurringDue(
                      after: base,
                      rrule: rrule,
                      timeZone: root.dueTimeZone,
                      laterThan: completedAt
                  ) else {
                try await deleteItemAndRetainedSource(successor)
                items.removeAll { $0.id == successor.id }
                await scheduler.cancel(successor.id)
                return (nil, root)
            }

            var refreshed = root
            refreshed.id = successor.id
            refreshed.done = false
            refreshed.completedAt = nil
            refreshed.due = nextDue
            refreshed.end = root.end.map {
                nextDue.addingTimeInterval($0.timeIntervalSince(base))
            }
            refreshed.createdAt = successor.createdAt
            refreshed.modifiedAt = max(root.modifiedAt, completedAt)
            refreshed.deletedAt = nil
            refreshed.recurrenceSourceId = sourceId
            refreshed.recurrenceSuccessorId = successor.recurrenceSuccessorId

            if refreshed != successor {
                refreshed = try await persistRecurringSuccessor(
                    refreshed,
                    replacing: successor
                )
                replaceItemInMemory(refreshed)
                successor = refreshed
            }

            await scheduler.schedule(successor)

            let latestRoot = completedRootSnapshot(
                sourceId,
                fallback: root,
                completedAt: completedAt
            )
            guard latestRoot == root else { continue }
            return (successor, root)
        }
    }

    private func persistRecurringSuccessor(
        _ successor: Item,
        replacing previous: Item
    ) async throws -> Item {
        try await persistItemResolvingRetainedUpdate(
            successor,
            from: previous.listId
        )
    }

    private func replaceItemInMemory(_ item: Item) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        } else {
            items.append(item)
        }
    }

    /// Toggle only the flag field from the latest ordered value. Row menus use
    /// this instead of persisting a captured full-item snapshot that could
    /// overwrite a completion or edit committed while the menu was open.
    public func toggleFlagged(_ id: UUID) async throws {
        try await withMutationScope { [self] in
            try await toggleFlaggedUngated(id)
        }
    }

    private func toggleFlaggedUngated(_ id: UUID) async throws {
        _ = try requireMutableItem(id)
        try await enqueueWrite(
            "toggle flag \(id)",
            reconcilesPreviousFailure: true
        ) { [self] in
            guard let original = self.item(id), original.deletedAt == nil else { return }
            guard lists.contains(where: {
                $0.id == original.listId && $0.deletedAt == nil
            }) else { return }
            let target = !original.flagged

            while let latest = self.item(id) {
                guard latest.deletedAt == nil,
                      lists.contains(where: {
                          $0.id == latest.listId && $0.deletedAt == nil
                      }) else { return }
                var flagged = latest
                flagged.flagged = target
                flagged.modifiedAt = .now
                if let flagWriteWillCommit = maintenanceTestHooks.flagWriteWillCommit {
                    try await flagWriteWillCommit()
                }
                let persistedFlagged = try await persistItemResolvingRetainedUpdate(
                    flagged,
                    reconcilesConsumedNotification: true
                )
                if let flagWriteCommitted = maintenanceTestHooks.flagWriteCommitted {
                    await flagWriteCommitted()
                }
                guard let current = self.item(id), current.deletedAt == nil else { return }
                guard current == latest else { continue }
                if let idx = items.firstIndex(where: { $0.id == id }) {
                    items[idx] = persistedFlagged
                }
                return
            }
        }
    }

    /// Apply a history edit as one ordered write. Computing from live memory
    /// inside the queue prevents concurrent completion edits from overwriting
    /// each other; publishing after the write prevents a failed add/delete
    /// from appearing successful until the next launch.
    private func mutateHabit(
        _ id: UUID,
        actionDate: Date,
        _ change: @escaping @Sendable (inout Item) -> Void
    ) async throws {
        try await withMutationScope { [self] in
            try await mutateHabitUngated(id, actionDate: actionDate, change)
        }
    }

    private func mutateHabitUngated(
        _ id: UUID,
        actionDate: Date,
        _ change: @escaping @Sendable (inout Item) -> Void
    ) async throws {
        _ = try requireMutableItem(id)
        try await enqueueWrite(
            "habit history \(id)",
            reconcilesPreviousFailure: true
        ) { [self] in
            guard var item = self.item(id),
                  item.type == .habit,
                  item.deletedAt == nil,
                  lists.contains(where: {
                      $0.id == item.listId && $0.deletedAt == nil
                  }) else { return }
            let original = item
            let frequency = (item.frequency ?? .daily).normalizedForHabit
            let currentCycleKey = HabitCycle.key(
                for: frequency,
                on: actionDate
            )
            func currentCycleCount(in candidate: Item) -> Int {
                candidate.completions.lazy.filter {
                    HabitCycle.key(for: frequency, on: $0.at) == currentCycleKey
                }.count
            }
            let originalCurrentCycleCount = currentCycleCount(in: item)
            change(&item)
            guard item != original else { return }
            let loggedCurrentCycleCompletion =
                currentCycleCount(in: item) > originalCurrentCycleCount
            item.modifiedAt = .now
            item = try await persistItemResolvingRetainedUpdate(
                item,
                reconcilesConsumedNotification: true
            )
            if let idx = items.firstIndex(where: { $0.id == id }),
               items[idx].deletedAt == nil {
                // A synchronous editor/delete may have published while the
                // habit write was suspended. Keep its unrelated fields and
                // publish only the completion history this operation owns.
                items[idx].completions = item.completions
                items[idx].modifiedAt = max(items[idx].modifiedAt, item.modifiedAt)
            }
            if loggedCurrentCycleCompletion, item.reminder?.enabled == true {
                await scheduler.acknowledgeDelivered(id)
            }
        }
    }

    /// Increment a habit's count for the current cycle (capped at goalPerCycle).
    /// Appends one timestamped completion event. No-op when already at goal.
    public func incrementHabit(_ id: UUID, now: Date = .now) async throws {
        try await mutateHabit(id, actionDate: now) { item in
            // Derive the cap inside the ordered mutation so rapid taps see the
            // completion committed by the preceding tap.
            let frequency = (item.frequency ?? .daily).normalizedForHabit
            let key = HabitCycle.key(for: frequency, on: now)
            guard (item.completionLog[key] ?? 0) < item.goalPerCycle else { return }
            item.completions.append(HabitCompletion(at: now))
        }
    }

    /// Log a completion at the action instant. Keeping this overload separate
    /// ensures the event timestamp and acknowledgement cycle share one captured
    /// clock read even if the queued write crosses a cycle boundary.
    public func addCompletion(_ id: UUID, now: Date = .now) async throws {
        try await mutateHabit(id, actionDate: now) {
            $0.completions.append(HabitCompletion(at: now))
        }
    }

    /// Log a completion at an arbitrary instant (the Log's dated entry flow).
    public func addCompletion(_ id: UUID, at date: Date) async throws {
        let actionDate = Date.now
        try await mutateHabit(id, actionDate: actionDate) {
            $0.completions.append(HabitCompletion(at: date))
        }
    }

    /// Log many completions at once — one event per supplied date — in a single
    /// write (the Add Completion sheet's "Date Range" backfill). No-op when empty.
    public func addCompletions(_ id: UUID, on dates: [Date]) async throws {
        guard !dates.isEmpty else { return }
        let actionDate = Date.now
        try await mutateHabit(id, actionDate: actionDate) { item in
            item.completions.append(contentsOf: dates.map { HabitCompletion(at: $0) })
        }
    }

    /// Delete one logged completion (swipe-to-delete in the Log).
    public func deleteCompletion(_ id: UUID, completionId: UUID) async throws {
        let actionDate = Date.now
        try await mutateHabit(id, actionDate: actionDate) {
            $0.completions.removeAll { $0.id == completionId }
        }
    }

    /// Retime / redate one logged completion (tap-to-edit in the Log). Because
    /// `at` is absolute, this handles both "edit the time" and "move to another day".
    public func updateCompletion(_ id: UUID, completionId: UUID, to date: Date) async throws {
        let actionDate = Date.now
        try await mutateHabit(id, actionDate: actionDate) { item in
            if let idx = item.completions.firstIndex(where: { $0.id == completionId }) {
                item.completions[idx].at = date
            }
        }
    }

    /// Remove the most recent completion in the cycle containing `cycleOf` (the −1
    /// correction on the progress ring).
    public func removeLatestCompletion(in cycleOf: Date, for id: UUID) async throws {
        let actionDate = Date.now
        try await mutateHabit(id, actionDate: actionDate) { item in
            let frequency = (item.frequency ?? .daily).normalizedForHabit
            let key = HabitCycle.key(for: frequency, on: cycleOf)
            let latest = item.completions
                .filter { HabitCycle.key(for: frequency, on: $0.at) == key }
                .max(by: { $0.at < $1.at })
            guard let latest else { return }
            item.completions.removeAll { $0.id == latest.id }
        }
    }

    public func add(_ item: Item) async throws {
        try await withMutationScope { [self] in
            try await addUngated(item)
        }
    }

    /// Creates the metadata item and its portable JSON Canvas document as one
    /// user operation. If item persistence fails, the newly created canvas
    /// files are removed so retrying cannot leave a phantom document behind.
    public func createCanvas(
        title: String = "Untitled Canvas",
        listId: String,
        section: String? = nil,
        tags: [String] = [],
        priority: Item.Priority = .none,
        flagged: Bool = false
    ) async throws -> Item {
        try await withMutationScope { [self] in
            let id = UUID()
            let resource = try await enqueueWrite("create canvas \(id)") {
                try await self.store.createCanvasResource(title: title)
            }
            let item = Item(
                id: id,
                type: .canvas,
                title: title,
                canvasPath: resource.canvasPath,
                listId: listId,
                section: section,
                tags: tags,
                priority: priority,
                flagged: flagged
            )
            do {
                try await addUngated(item)
                return self.item(id) ?? item
            } catch {
                try? await enqueueWrite("remove incomplete canvas \(id)") {
                    try await self.store.deleteCanvasResource(at: resource.canvasPath)
                }
                throw error
            }
        }
    }

    private func addUngated(_ item: Item) async throws {
        guard lists.contains(where: {
            $0.id == item.listId && $0.deletedAt == nil
        }) else {
            throw MutationConflictError.inactiveDestinationList
        }
        guard !conflictsWithListDeletion([item.listId]) else {
            throw MutationConflictError.listDeletionInProgress
        }
        if let parentId = item.parentId,
           conflictsWithItemDeletion([parentId]) {
            throw MutationConflictError.itemDeletionInProgress
        }
        guard itemsById[item.id] == nil,
              creatingItemIds.insert(item.id).inserted else {
            throw CreationError.duplicateItemID(item.id)
        }
        defer { creatingItemIds.remove(item.id) }

        var item = normalizedForStorage(item)
        item.modifiedAt = .now
        try await writeItemOrdered(item)
        if let mutationWriteCommitted = maintenanceTestHooks.mutationWriteCommitted {
            await mutationWriteCommitted()
        }
        items.append(item)
        await scheduler.schedule(item)
    }

    /// Create a new empty-title item for inline editing, appended at the END
    /// of its target group (top-level rows of `section`). `add()` defaults
    /// `sortIndex` to 0 and manual sort is ascending, so a naive new item would
    /// sort to the TOP — this computes `max(sortIndex)+1` so it lands at the
    /// bottom, Apple Reminders-style. Returns the new id so the caller can
    /// focus its inline editor. In-memory first; disk write + scheduling are
    /// fire-and-forget to keep the tap snappy (mirrors `applyUpdateSync`).
    @discardableResult
    public func addInlineItem(type: Item.ItemType, listId: String, section: String?) -> UUID {
        let id = UUID()
        guard beginSynchronousMutation(deferring: { [weak self] in
            _ = self?.addInlineItemNow(
                id: id,
                type: type,
                listId: listId,
                section: section
            )
        }) else { return id }
        defer { leaveMutationScope() }
        return addInlineItemNow(id: id, type: type, listId: listId, section: section)
    }

    private func addInlineItemNow(
        id: UUID,
        type: Item.ItemType,
        listId: String,
        section: String?
    ) -> UUID {
        guard lists.contains(where: {
            $0.id == listId && $0.deletedAt == nil
        }) else { return id }
        guard !conflictsWithListDeletion([listId]) else { return id }
        var item = normalizedForStorage(
            Item(id: id, type: type, title: "", listId: listId, section: section, sortIndex: 0)
        )
        let siblings = items.filter {
            $0.listId == item.listId && $0.section == item.section && $0.parentId == nil && $0.deletedAt == nil
        }
        item.sortIndex = (siblings.map(\.sortIndex).max() ?? -1) + 1
        if type == .habit {
            item.frequency = .daily
            item.goalPerCycle = 1
        }
        item.modifiedAt = .now
        items.append(item)
        retainSynchronousItemUpdate(
            item.id,
            sourceListId: nil,
            fields: Set(ItemField.allCases)
        )
        return item.id
    }

    /// Drag-to-reorder writeback: takes the flat user-visible sequence of
    /// item ids after a drag and renumbers `sortIndex` per parent group
    /// (top-level items sit in one group; each parent's direct children sit
    /// in their own). Items not in `flatOrderedIds` are left untouched. Only
    /// items whose new index actually differs are written.
    public func reorderItems(in listId: String, flatOrderedIds: [UUID]) async throws {
        try await withMutationScope { [self] in
            try await reorderItemsUngated(in: listId, flatOrderedIds: flatOrderedIds)
        }
    }

    private func reorderItemsUngated(in listId: String, flatOrderedIds: [UUID]) async throws {
        guard !conflictsWithListDeletion([listId]) else {
            throw MutationConflictError.listDeletionInProgress
        }
        guard !conflictsWithItemDeletion(Set(flatOrderedIds)) else {
            throw MutationConflictError.itemDeletionInProgress
        }
        var perGroupCounter: [UUID?: Int] = [:]
        for id in flatOrderedIds {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            let next = perGroupCounter[item.parentId, default: 0]
            perGroupCounter[item.parentId] = next + 1
            if item.sortIndex == next { continue }
            var copy = item
            copy.sortIndex = next
            copy.modifiedAt = .now
            let fields: Set<ItemField> = [.sortIndex]
            let intentGeneration = acceptItemIntent(for: id, fields: fields)
            try await enqueueWrite(
                "reorder item \(id)",
                reconcilesPreviousFailure: true
            ) { [self] in
                _ = try await persistAndCommitItem(
                    copy,
                    baseline: item,
                    fields: fields,
                    intentGeneration: intentGeneration
                )
            }
        }
    }

    /// Synchronous UI-bridge variant of `reorderItems` — updates the in-memory
    /// array immediately and persists to disk via a queued background write.
    /// Use from UIKit drag/drop coordinators where the data source must reflect
    /// the new state *before* `UICollectionViewDropCoordinator.drop(_:toItemAt:)`
    /// animates the preview, otherwise the animation lands on stale cells and
    /// the move visually snaps back.
    public func applyReorderItemsSync(in listId: String, flatOrderedIds: [UUID]) {
        guard !conflictsWithListDeletion([listId]) else { return }
        guard !conflictsWithItemDeletion(Set(flatOrderedIds)) else { return }
        guard beginSynchronousMutation(deferring: { [weak self] in
            self?.applyReorderItemsSync(in: listId, flatOrderedIds: flatOrderedIds)
        }) else { return }
        defer { leaveMutationScope() }
        var targetIndexes: [UUID: Int] = [:]
        var perGroupCounter: [UUID?: Int] = [:]
        for id in flatOrderedIds {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            let next = perGroupCounter[item.parentId, default: 0]
            perGroupCounter[item.parentId] = next + 1
            if item.sortIndex == next { continue }
            targetIndexes[id] = next
            var copy = item
            copy.sortIndex = next
            copy.modifiedAt = .now
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx] = copy
            }
            _ = acceptItemIntent(
                for: id,
                fields: [.sortIndex],
                optimistic: true
            )
        }
        retainSynchronousItemReorder(
            listId: listId,
            targetIndexes: targetIndexes
        )
    }

    public func update(_ item: Item) async throws {
        try await withMutationScope { [self] in
            try await updateUngated(item)
        }
    }

    private func updateUngated(_ item: Item) async throws {
        guard let baseline = self.item(item.id) else { return }
        let oldItems = items
        let oldLists = lists
        let oldDocumentFileNames = documentFileNamesById
        let changesDocumentPath = baseline.title != item.title || baseline.listId != item.listId
        var affectedItemIds: Set<UUID> = [item.id]
        if let parentId = item.parentId { affectedItemIds.insert(parentId) }
        if let parentId = baseline.parentId { affectedItemIds.insert(parentId) }
        guard !conflictsWithItemDeletion(affectedItemIds) else {
            throw MutationConflictError.itemDeletionInProgress
        }
        guard baseline.deletedAt == nil, item.deletedAt == nil else {
            throw MutationConflictError.deletedItemRequiresRestore
        }
        guard lists.contains(where: {
            $0.id == item.listId && $0.deletedAt == nil
        }) else {
            throw MutationConflictError.inactiveDestinationList
        }
        guard !conflictsWithListDeletion([baseline.listId, item.listId]) else {
            throw MutationConflictError.listDeletionInProgress
        }
        let fields = Self.changedItemFields(from: baseline, to: item)
        let intentGeneration = acceptItemIntent(for: item.id, fields: fields)
        try await enqueueWrite(
            "update item \(item.id)",
            reconcilesPreviousFailure: true
        ) { [self] in
            let updated = try await persistAndCommitItem(
                item,
                baseline: baseline,
                fields: fields,
                intentGeneration: intentGeneration
            )
            await scheduler.schedule(updated)
            if changesDocumentPath {
                try await persistPortableLinkRewrites(
                    oldItems: oldItems,
                    oldLists: oldLists,
                    oldDocumentFileNames: oldDocumentFileNames
                )
            }
        }
    }

    /// Update an item and keep its hierarchy coherent when the edit moves it.
    /// Detail screens use this for their list and section controls so stored
    /// data matches the visible hierarchy.
    public func updateWithSubtreeCascades(_ item: Item) async throws {
        try await withMutationScope { [self] in
            try await updateWithSubtreeCascadesUngated(item)
        }
    }

    private func updateWithSubtreeCascadesUngated(_ item: Item) async throws {
        guard let rootBaseline = self.item(item.id) else { return }
        let oldItems = items
        let oldLists = lists
        let oldDocumentFileNames = documentFileNamesById
        let changesDocumentPath = rootBaseline.title != item.title
            || rootBaseline.listId != item.listId
        var affectedItemIds: Set<UUID> = [item.id]
        if let parentId = item.parentId { affectedItemIds.insert(parentId) }
        if let parentId = rootBaseline.parentId { affectedItemIds.insert(parentId) }
        guard !conflictsWithItemDeletion(affectedItemIds) else {
            throw MutationConflictError.itemDeletionInProgress
        }
        guard rootBaseline.deletedAt == nil, item.deletedAt == nil else {
            throw MutationConflictError.deletedItemRequiresRestore
        }
        guard lists.contains(where: {
            $0.id == item.listId && $0.deletedAt == nil
        }) else {
            throw MutationConflictError.inactiveDestinationList
        }
        guard !conflictsWithListDeletion([rootBaseline.listId, item.listId]) else {
            throw MutationConflictError.listDeletionInProgress
        }
        let rootFields = Self.changedItemFields(from: rootBaseline, to: item)
        let rootIntentGeneration = acceptItemIntent(
            for: item.id,
            fields: rootFields
        )
        try await enqueueWrite(
            "update item subtree \(item.id)",
            reconcilesPreviousFailure: true
        ) { [self] in
            let root = try await persistAndCommitItem(
                item,
                baseline: rootBaseline,
                fields: rootFields,
                intentGeneration: rootIntentGeneration
            )
            await scheduler.schedule(root)

            // A newer live cascade can be accepted while the older root file
            // write is suspended. Its placement owns the descendants; the
            // queued newer operation will persist that subtree coherently.
            guard let cascadeRoot = self.item(root.id),
                  cascadeRoot.listId == root.listId,
                  cascadeRoot.section == root.section else { return }

            // Reconcile unconditionally. If an earlier multi-file attempt
            // stopped halfway, retrying the same visible edit must finish the
            // remaining descendants even though the root already matches.
            for id in itemDescendantIds(of: cascadeRoot.id) {
                guard let descendantBaseline = self.item(id),
                      descendantBaseline.listId != cascadeRoot.listId
                        || descendantBaseline.section != cascadeRoot.section else {
                    continue
                }
                var descendant = descendantBaseline
                descendant.listId = cascadeRoot.listId
                descendant.section = cascadeRoot.section
                let descendantFields: Set<ItemField> = [.listId, .section]
                let descendantIntentGeneration = acceptItemIntent(
                    for: descendant.id,
                    fields: descendantFields
                )
                let updated = try await persistAndCommitItem(
                    descendant,
                    baseline: descendantBaseline,
                    fields: descendantFields,
                    intentGeneration: descendantIntentGeneration
                )
                await scheduler.schedule(updated)
            }
            if changesDocumentPath {
                try await persistPortableLinkRewrites(
                    oldItems: oldItems,
                    oldLists: oldLists,
                    oldDocumentFileNames: oldDocumentFileNames
                )
            }
        }
    }

    /// Synchronous UI-bridge variant of `update(_:)` — same rationale as
    /// `applyReorderItemsSync`. Disk write and notification scheduling are
    /// both queued in the background.
    public func applyUpdateSync(_ item: Item) {
        guard let current = itemsById[item.id],
              current.deletedAt == nil,
              item.deletedAt == nil,
              lists.contains(where: {
                  $0.id == item.listId && $0.deletedAt == nil
              }) else { return }
        var affectedItemIds: Set<UUID> = [item.id]
        if let parentId = item.parentId { affectedItemIds.insert(parentId) }
        if let parentId = current.parentId { affectedItemIds.insert(parentId) }
        guard !conflictsWithItemDeletion(affectedItemIds) else { return }
        var affectedListIds: Set<String> = [item.listId]
        affectedListIds.insert(current.listId)
        guard !conflictsWithListDeletion(affectedListIds) else { return }
        guard beginSynchronousMutation(deferring: { [weak self] in
            self?.applyUpdateSync(item)
        }) else { return }
        defer { leaveMutationScope() }
        let original = current
        let oldItems = items
        let oldLists = lists
        let oldDocumentFileNames = documentFileNamesById
        var updated = normalizedForStorage(item)
        updated.modifiedAt = .now
        // Capture the old list id before the in-memory assignment, so a list
        // change deletes the stale file on the detached write.
        let oldListId = original.listId
        let changedFields = Self.changedItemFields(from: original, to: updated)
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = updated
        } else {
            items.append(updated)
        }
        if original.title != updated.title || original.listId != updated.listId {
            documentFileNamesById[updated.id] = predictedDocumentFileName(
                for: updated,
                oldItems: oldItems,
                oldDocumentFileNames: oldDocumentFileNames
            )
        }
        // Keep an unsaved edit visible if persistence fails. Its retained plan
        // coalesces onto the newest live value and retries without requiring a
        // text field or drag gesture to emit the same mutation again.
        retainSynchronousItemUpdate(
            updated.id,
            sourceListId: oldListId,
            fields: changedFields
        )
        if original.title != updated.title || original.listId != updated.listId {
            retainPortableLinkRewrites(
                oldItems: oldItems,
                oldLists: oldLists,
                oldDocumentFileNames: oldDocumentFileNames
            )
        }
    }

    private func predictedDocumentFileName(
        for item: Item,
        oldItems: [Item],
        oldDocumentFileNames: [UUID: String]
    ) -> String {
        if let old = oldItems.first(where: { $0.id == item.id }),
           old.listId == item.listId,
           old.title == item.title,
           let existing = oldDocumentFileNames[item.id] {
            return existing
        }
        let base = FileStore.sanitize(item.title)
        let occupied = Set(oldItems.compactMap { candidate -> String? in
            guard candidate.id != item.id,
                  candidate.listId == item.listId else { return nil }
            return oldDocumentFileNames[candidate.id]
        })
        var suffix = 1
        while true {
            let stem = suffix == 1 ? base : "\(base) (\(suffix))"
            let candidate = "\(stem).md"
            if occupied.contains(candidate) == false { return candidate }
            suffix += 1
        }
    }

    private func retainPortableLinkRewrites(
        oldItems: [Item],
        oldLists: [ItemList],
        oldDocumentFileNames: [UUID: String]
    ) {
        let newItems = items
        let newLists = lists
        let newDocumentFileNames = documentFileNamesById
        for current in newItems {
            guard let oldSource = oldItems.first(where: { $0.id == current.id }) else { continue }
            let rewritten = DocumentMarkdownIndex.rewritingPortableDestinations(
                in: current,
                oldSource: oldSource,
                oldItems: oldItems,
                oldLists: oldLists,
                oldDocumentFileNames: oldDocumentFileNames,
                newItems: newItems,
                newLists: newLists,
                newDocumentFileNames: newDocumentFileNames
            )
            guard rewritten != current.body else { continue }
            var copy = current
            copy.body = rewritten
            copy.modifiedAt = .now
            replaceItemInMemory(copy)
            retainSynchronousItemUpdate(
                copy.id,
                sourceListId: durableItemListIds[copy.id] ?? oldSource.listId,
                fields: [.body]
            )
        }
        enqueueDetachedWrite("rewrite canvas links") { [self] in
            try await persistPortableCanvasLinkRewrites(
                oldItems: oldItems,
                oldLists: oldLists,
                oldDocumentFileNames: oldDocumentFileNames,
                newItems: newItems,
                newLists: newLists,
                newDocumentFileNames: newDocumentFileNames
            )
        }
    }

    private func persistPortableLinkRewrites(
        oldItems: [Item],
        oldLists: [ItemList],
        oldDocumentFileNames: [UUID: String]
    ) async throws {
        let newItems = items
        let newLists = lists
        let newDocumentFileNames = documentFileNamesById
        for current in newItems {
            guard let oldSource = oldItems.first(where: { $0.id == current.id }) else { continue }
            let rewritten = DocumentMarkdownIndex.rewritingPortableDestinations(
                in: current,
                oldSource: oldSource,
                oldItems: oldItems,
                oldLists: oldLists,
                oldDocumentFileNames: oldDocumentFileNames,
                newItems: newItems,
                newLists: newLists,
                newDocumentFileNames: newDocumentFileNames
            )
            guard rewritten != current.body else { continue }
            var copy = current
            copy.body = rewritten
            copy.modifiedAt = .now
            let fields: Set<ItemField> = [.body]
            let generation = acceptItemIntent(for: copy.id, fields: fields)
            _ = try await persistAndCommitItem(
                copy,
                baseline: current,
                fields: fields,
                intentGeneration: generation
            )
        }
        try await persistPortableCanvasLinkRewrites(
            oldItems: oldItems,
            oldLists: oldLists,
            oldDocumentFileNames: oldDocumentFileNames,
            newItems: newItems,
            newLists: newLists,
            newDocumentFileNames: newDocumentFileNames
        )
    }

    private func persistPortableCanvasLinkRewrites(
        oldItems: [Item],
        oldLists: [ItemList],
        oldDocumentFileNames: [UUID: String],
        newItems: [Item],
        newLists: [ItemList],
        newDocumentFileNames: [UUID: String]
    ) async throws {
        for current in newItems where current.type == .canvas && current.deletedAt == nil {
            guard let oldSource = oldItems.first(where: { $0.id == current.id }),
                  let canvasPath = current.canvasPath else { continue }
            let nativeData: Data
            let previewData: Data
            do {
                nativeData = try await store.readNativeCanvasData(at: canvasPath)
                previewData = try await store.readCanvasPreviewData(at: canvasPath)
            } catch CanvasStorageError.missingNativeDocument {
                continue
            } catch CanvasStorageError.missingPreview {
                continue
            }
            var document = try CanvasPaperDocument(dataRepresentation: nativeData)
            let rewritten = DocumentMarkdownIndex.rewritingPortableDestinations(
                in: document.linkCards,
                oldSource: oldSource,
                oldItems: oldItems,
                oldLists: oldLists,
                oldDocumentFileNames: oldDocumentFileNames,
                newItems: newItems,
                newLists: newLists,
                newDocumentFileNames: newDocumentFileNames
            )
            guard rewritten != document.linkCards else { continue }
            document.linkCards = rewritten
            try await store.writeCanvas(
                at: canvasPath,
                nativeData: try await document.dataRepresentation(),
                previewPNGData: previewData,
                linkCards: rewritten
            )
        }
    }

    /// Synchronous UI-bridge variant of `updateWithSubtreeCascades(_:)` for
    /// live-apply UI.
    public func applyUpdateWithSubtreeCascadesSync(_ item: Item) {
        var affectedListIds: Set<String> = [item.listId]
        if let currentListId = itemsById[item.id]?.listId {
            affectedListIds.insert(currentListId)
        }
        guard !conflictsWithListDeletion(affectedListIds) else { return }
        guard beginSynchronousMutation(deferring: { [weak self] in
            self?.applyUpdateWithSubtreeCascadesSync(item)
        }) else { return }
        defer { leaveMutationScope() }
        let previous = items.first(where: { $0.id == item.id })
        let normalized = normalizedForStorage(item)
        applyUpdateSync(normalized)
        guard let previous else { return }
        if previous.listId != normalized.listId {
            applyListCascadeSync(toDescendantsOf: normalized.id, listId: normalized.listId)
        }
        if previous.section != normalized.section {
            applySectionCascadeSync(toDescendantsOf: normalized.id, section: normalized.section)
        }
    }

    /// Stored hierarchy invariant:
    /// - a child must point at a live parent in the same list,
    /// - a child inherits its parent's section,
    /// - a top-level item can only keep a section id that belongs to its list.
    /// UI flows may edit list/section from different surfaces; normalizing here
    /// keeps those surfaces from inventing subtly different product rules.
    private func normalizedForStorage(_ item: Item) -> Item {
        Self.normalizedForStorage(item, items: items, lists: lists)
    }

    /// Snapshot-based form used while planning a retryable multi-record
    /// restore. It applies the same rules without publishing partially
    /// restored parents to the observed arrays before their files succeed.
    private static func normalizedForStorage(
        _ item: Item,
        items: [Item],
        lists: [ItemList]
    ) -> Item {
        var normalized = item

        if normalized.type == .habit {
            normalized.frequency = normalized.frequency?.normalizedForHabit ?? .daily
            normalized.goalPerCycle = max(1, normalized.goalPerCycle)
        }

        if normalized.type == .event {
            EventDefaults.normalize(&normalized)
        } else {
            normalized.end = nil
            normalized.completable = false
        }

        if let parentId = normalized.parentId {
            let invalidParent = parentId == normalized.id
                || ItemHierarchy.descendantIds(of: normalized.id, in: items).contains(parentId)
            if invalidParent {
                normalized.parentId = nil
            } else if let parent = items.first(where: { $0.id == parentId }),
                      parent.deletedAt == nil,
                      parent.listId == normalized.listId {
                normalized.section = parent.section
            } else {
                normalized.parentId = nil
            }
        }

        guard normalized.parentId == nil,
              let section = normalized.section,
              !section.isEmpty,
              let list = lists.first(where: { $0.id == normalized.listId && $0.deletedAt == nil }) else {
            return normalized
        }

        if !list.sections.contains(where: { $0.id.uuidString == section }) {
            normalized.section = nil
        }
        return normalized
    }

    private static func parentFirstItemIds(_ ids: [UUID], in items: [Item]) -> [UUID] {
        let targetIds = Set(ids)
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var visiting: Set<UUID> = []
        var visited: Set<UUID> = []
        var ordered: [UUID] = []

        func appendWithParent(_ id: UUID) {
            guard targetIds.contains(id), !visited.contains(id) else { return }
            guard visiting.insert(id).inserted else { return }
            if let parentId = byId[id]?.parentId, targetIds.contains(parentId) {
                appendWithParent(parentId)
            }
            visiting.remove(id)
            if visited.insert(id).inserted {
                ordered.append(id)
            }
        }

        for id in ids {
            appendWithParent(id)
        }
        return ordered
    }

    /// Apply the same hierarchy invariant to data loaded from disk. Write
    /// paths already normalize, but imported, hand-edited, or older files can
    /// still contain invisible children or stale section ids.
    private func repairLoadedItemHierarchy() async {
        var changedIds: Set<UUID> = []
        var deletedListDates: [String: Date] = [:]
        for list in lists {
            if let deletedAt = list.deletedAt {
                deletedListDates[list.id] = deletedAt
            }
        }
        for idx in items.indices where items[idx].deletedAt == nil {
            if let deletedAt = deletedListDates[items[idx].listId] {
                items[idx].deletedAt = deletedAt
                items[idx].modifiedAt = .now
                changedIds.insert(items[idx].id)
            }
        }

        var didChange = true
        var remainingPasses = max(items.count, 1)
        while didChange && remainingPasses > 0 {
            didChange = false
            remainingPasses -= 1
            for idx in items.indices where items[idx].deletedAt == nil {
                let normalized = normalizedForStorage(items[idx])
                guard normalized != items[idx] else { continue }
                items[idx] = normalized
                changedIds.insert(normalized.id)
                didChange = true
            }
        }

        for id in changedIds {
            guard let item = item(id) else { continue }
            try? await writeItemOrdered(item)
            if item.deletedAt != nil {
                await scheduler.cancel(item.id)
            }
        }
    }

    /// Apply list-parent invariants to data loaded from disk. Write paths guard
    /// these already, but hand-edited or older `.list.yml` files can still point
    /// a visible list at a missing/deleted parent or into a cycle, which strands
    /// it outside the sidebar tree.
    private func repairLoadedListHierarchy() async {
        let byId = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let repairIndexes = lists.indices.filter { idx in
            guard let parentId = lists[idx].parentId else { return false }
            return ListHierarchy.invalidLoadedParent(parentId, for: lists[idx], in: byId)
        }

        var changedIds: [String] = []
        for idx in repairIndexes {
            lists[idx].parentId = nil
            lists[idx].modifiedAt = .now
            lists[idx].lamport += 1
            changedIds.append(lists[idx].id)
        }

        for id in changedIds {
            guard let list = lists.first(where: { $0.id == id }) else { continue }
            try? await writeListOrdered(list)
        }
    }

    /// Move or reparent one item using the app's hierarchy rules:
    /// - choosing a parent also inherits that parent's list and section,
    /// - choosing no parent inside the same list keeps the current section,
    /// - choosing no parent in another list clears the list-scoped section,
    /// - descendants follow the moved item's list/section so stored data matches
    ///   the visible tree.
    @discardableResult
    public func applyMoveSync(itemId: UUID, toListId listId: String, parentId: UUID?) -> Bool {
        var affectedItemIds: Set<UUID> = [itemId]
        if let parentId { affectedItemIds.insert(parentId) }
        guard !conflictsWithItemDeletion(affectedItemIds) else { return false }
        var affectedListIds: Set<String> = [listId]
        if let currentListId = item(itemId)?.listId {
            affectedListIds.insert(currentListId)
        }
        guard !conflictsWithListDeletion(affectedListIds) else { return false }
        guard beginSynchronousMutation(deferring: { [weak self] in
            _ = self?.applyMoveSync(
                itemId: itemId,
                toListId: listId,
                parentId: parentId
            )
        }) else { return true }
        defer { leaveMutationScope() }
        guard lists.contains(where: { $0.id == listId && $0.deletedAt == nil }),
              var moving = item(itemId),
              moving.deletedAt == nil else {
            return false
        }

        let targetSection: String?
        if let parentId {
            guard let parent = item(parentId),
                  parent.deletedAt == nil,
                  parent.listId == listId,
                  parent.id != itemId,
                  !itemDescendantIds(of: itemId).contains(parent.id) else {
                return false
            }
            targetSection = parent.section
        } else if moving.listId != listId {
            targetSection = nil
        } else {
            targetSection = moving.section
        }

        let movedAcrossLists = moving.listId != listId
        let sectionChanged = moving.section != targetSection
        moving.listId = listId
        moving.parentId = parentId
        moving.section = targetSection

        applyUpdateSync(moving)
        if movedAcrossLists {
            applyListCascadeSync(toDescendantsOf: itemId, listId: listId)
        }
        if sectionChanged {
            applySectionCascadeSync(toDescendantsOf: itemId, section: targetSection)
        }
        return true
    }

    /// Remove `tag` (case-insensitive) from every non-deleted item that
    /// carries it. The items themselves are kept; only the tag is stripped.
    public func removeTag(_ tag: String) async throws {
        try await withMutationScope { [self] in
            try await removeTagUngated(tag)
        }
    }

    private func removeTagUngated(_ tag: String) async throws {
        let lower = tag.lowercased()
        let affected = items.filter { item in
            item.deletedAt == nil
            && item.tags.contains { $0.lowercased() == lower }
        }
        for stale in affected {
            // Re-fetch the current value inside the loop so an edit made during
            // an earlier iteration's await isn't lost by writing the pre-loop
            // snapshot.
            guard var copy = items.first(where: { $0.id == stale.id }) else { continue }
            copy.tags.removeAll { $0.lowercased() == lower }
            try await update(copy)
        }
    }

    /// Rename `oldTag` → `newTag` across every non-deleted item. If an
    /// item already carries both, the duplicate is merged out. No-op when
    /// `newTag` sanitizes to nil or matches `oldTag` case-insensitively.
    public func renameTag(from oldTag: String, to newTag: String) async throws {
        try await withMutationScope { [self] in
            try await renameTagUngated(from: oldTag, to: newTag)
        }
    }

    private func renameTagUngated(from oldTag: String, to newTag: String) async throws {
        guard let cleanNew = Tag.sanitize(newTag),
              cleanNew.caseInsensitiveCompare(oldTag) != .orderedSame else { return }
        let lowerOld = oldTag.lowercased()
        let lowerNew = cleanNew.lowercased()
        let affected = items.filter { item in
            item.deletedAt == nil
            && item.tags.contains { $0.lowercased() == lowerOld }
        }
        for stale in affected {
            // Re-fetch the current value inside the loop (see removeTag).
            guard var copy = items.first(where: { $0.id == stale.id }) else { continue }
            var seen: Set<String> = []
            var rebuilt: [String] = []
            for t in copy.tags {
                let replaced = (t.lowercased() == lowerOld) ? cleanNew : t
                let key = replaced.lowercased()
                if key == lowerNew && seen.contains(lowerNew) { continue }
                if seen.insert(key).inserted {
                    rebuilt.append(replaced)
                }
            }
            copy.tags = rebuilt
            try await update(copy)
        }
    }

    // MARK: - Bulk operations (multi-select toolbar)
    //
    // Thin wrappers that loop the single-item APIs, re-fetching each item
    // inside the loop so an edit during an earlier iteration's await is not
    // lost by writing a pre-loop snapshot.

    /// Set the flag on every selected item.
    public func bulkSetFlagged(_ ids: Set<UUID>, _ flagged: Bool) async throws {
        try await withMutationScope { [self] in
            try await bulkSetFlaggedUngated(ids, flagged)
        }
    }

    private func bulkSetFlaggedUngated(_ ids: Set<UUID>, _ flagged: Bool) async throws {
        for id in ids {
            guard var copy = items.first(where: { $0.id == id }), copy.flagged != flagged else { continue }
            copy.flagged = flagged
            try await update(copy)
        }
    }

    /// Add a tag (case-insensitive, de-duplicated via `Tag.appending`) to every
    /// selected item. No-op when the tag sanitizes to nil.
    public func bulkAddTag(_ ids: Set<UUID>, tag: String) async throws {
        try await withMutationScope { [self] in
            try await bulkAddTagUngated(ids, tag: tag)
        }
    }

    private func bulkAddTagUngated(_ ids: Set<UUID>, tag: String) async throws {
        guard let clean = Tag.sanitize(tag) else { return }
        for id in ids {
            guard var copy = items.first(where: { $0.id == id }) else { continue }
            copy.tags = Tag.appending(clean, to: copy.tags)
            try await update(copy)
        }
    }

    /// Soft-delete every selected item.
    public func bulkSoftDelete(_ ids: Set<UUID>) async throws {
        try await withMutationScope { [self] in
            try await bulkSoftDeleteUngated(ids)
        }
    }

    private func bulkSoftDeleteUngated(_ ids: Set<UUID>) async throws {
        for id in ids {
            try await softDelete(id)
        }
    }

    /// Move selected item roots to another list. Descendants of a selected root
    /// move with that root; a selected child whose parent is not selected becomes
    /// top-level in the destination list.
    public func bulkMove(_ ids: Set<UUID>, toListId newListId: String) async throws {
        try await withMutationScope { [self] in
            try await bulkMoveUngated(ids, toListId: newListId)
        }
    }

    private func bulkMoveUngated(_ ids: Set<UUID>, toListId newListId: String) async throws {
        guard lists.contains(where: { $0.id == newListId && $0.deletedAt == nil }) else { return }
        for id in selectedItemRoots(from: ids) {
            guard var copy = items.first(where: { $0.id == id }),
                  copy.listId != newListId else { continue }
            copy.listId = newListId
            copy.section = nil
            if copy.parentId != nil {
                copy.parentId = nil
            }
            try await updateWithSubtreeCascades(copy)
        }
    }

    /// Assign every selected item to `section` (nil = Others) within their list.
    public func bulkMove(_ ids: Set<UUID>, toSection section: String?) async throws {
        try await withMutationScope { [self] in
            try await bulkMoveUngated(ids, toSection: section)
        }
    }

    private func bulkMoveUngated(_ ids: Set<UUID>, toSection section: String?) async throws {
        for id in selectedItemRoots(from: ids) {
            guard var copy = items.first(where: { $0.id == id }), copy.section != section else { continue }
            copy.section = section
            try await updateWithSubtreeCascades(copy)
        }
    }

    /// Selected descendants are carried by their selected ancestor's subtree move.
    /// Returning only roots avoids applying the same bulk hierarchy operation twice
    /// in nondeterministic `Set` order.
    private func selectedItemRoots(from ids: Set<UUID>) -> [UUID] {
        ItemHierarchy.selectedRoots(from: ids, in: items)
    }

    /// Every non-deleted descendant item id of `parentId` (children,
    /// grandchildren, …). The item analogue of the list-scoped
    /// `descendantIds(of:)`.
    public func itemDescendantIds(of parentId: UUID) -> [UUID] {
        ItemHierarchy.descendantIds(of: parentId, in: items)
    }

    /// Every descendant item id of `parentId`, including tombstoned items.
    /// Recently Deleted uses this for permanent-delete copy and hard-delete
    /// uses it to remove the whole on-disk subtree.
    public func allItemDescendantIds(of parentId: UUID) -> [UUID] {
        ItemHierarchy.descendantIds(of: parentId, in: items, includingDeleted: true)
    }

    /// Keep a moved item's whole subtree in its section. A child always shares
    /// its parent's section (children render under the parent regardless of
    /// their own `section`), so a move that reassigned only the parent left its
    /// descendants pointing at the OLD section — and deleting that section then
    /// soft-deleted them even though they'd visually followed the move. Call on
    /// every move-to-section so the stored data matches what's on screen.
    public func applySectionCascadeSync(toDescendantsOf parentId: UUID, section: String?) {
        guard beginSynchronousMutation(deferring: { [weak self] in
            self?.applySectionCascadeSync(
                toDescendantsOf: parentId,
                section: section
            )
        }) else { return }
        defer { leaveMutationScope() }
        for id in itemDescendantIds(of: parentId) {
            guard let current = items.first(where: { $0.id == id }), current.section != section else { continue }
            var copy = current
            copy.section = section
            applyUpdateSync(copy)
        }
    }

    /// Keep a moved item's whole subtree in its new list. Children render under
    /// their parent regardless of their own `listId`, so a cross-list move that
    /// reassigned only the parent left its descendants written to the OLD list's
    /// folder — orphaned, and swept up if that list is later deleted. Clears each
    /// descendant's `section` too (section ids are scoped to the source list).
    /// Call on every cross-list move so the stored data matches what's on screen.
    public func applyListCascadeSync(toDescendantsOf parentId: UUID, listId: String) {
        guard beginSynchronousMutation(deferring: { [weak self] in
            self?.applyListCascadeSync(
                toDescendantsOf: parentId,
                listId: listId
            )
        }) else { return }
        defer { leaveMutationScope() }
        for id in itemDescendantIds(of: parentId) {
            guard let current = items.first(where: { $0.id == id }),
                  current.listId != listId || current.section != nil else { continue }
            var copy = current
            copy.listId = listId
            copy.section = nil
            applyUpdateSync(copy)
        }
    }

    public func delete(_ id: UUID) async throws {
        try await withMutationScope { [self] in
            try await deleteUngated(id)
        }
    }

    private func deleteUngated(_ id: UUID) async throws {
        guard !isBootstrapping,
              !hasPendingRestoreRecovery,
              loadIssues.isEmpty else {
            throw DataSafetyError.unresolvedRecoveryIssues
        }
        guard let requestedRoot = item(id) else { return }
        let canceledDeletionRoots = itemDeletionRoots(containing: id)
        guard canceledDeletionRoots.allSatisfy({ $0 == id }) else {
            throw MutationConflictError.ancestorDeletionInProgress
        }
        reversedItemDeletionRoots.formUnion(canceledDeletionRoots)
        for rootId in canceledDeletionRoots.union([id]) {
            discardRetainedSoftDelete(rootId: rootId)
        }
        let expectedDeletedAt = requestedRoot.deletedAt

        try await enqueueWrite(
            "delete item subtree \(id)",
            reconcilesPreviousFailure: true
        ) { [self] in
            // The journal check and destructive file operations must share one
            // FIFO boundary. Checking before enqueueing leaves a reentrancy
            // window where a restore can begin between the check and delete.
            guard try await store.pendingRestore() == nil else {
                throw RestoreError.pendingRestoreMustFinish
            }
            try await store.cancelDeletion(kind: .item, rootId: id.uuidString)
            try await refreshPendingDeletionRecoveryState()
            guard let currentRoot = item(id),
                  currentRoot.deletedAt == expectedDeletedAt else {
                // A queued restore won the race and changed the selected row.
                return
            }
            try await reconcileRetainedItemUpdates([currentRoot.listId])

            let parentFirstIds = Self.parentFirstItemIds(
                [id] + allItemDescendantIds(of: id),
                in: items
            )
            // Dependents disappear first. If a file operation fails, the
            // requested root remains in Recently Deleted as the retry anchor.
            for targetId in parentFirstIds.reversed() {
                guard let target = item(targetId) else { continue }
                try await deleteItemAndRetainedSource(target)
                items.removeAll { $0.id == targetId }
                await scheduler.cancel(targetId)
            }
        }
    }

    /// Soft delete: marks an item with `deletedAt = now` and persists. Item
    /// stays on disk so it can be restored from Recently Deleted within 30 days.
    public func softDelete(_ id: UUID) async throws {
        try await withMutationScope { [self] in
            try await softDeleteUngated(id)
        }
    }

    private func softDeleteUngated(_ id: UUID) async throws {
        guard !isBootstrapping,
              loadIssues.isEmpty,
              !hasPendingRestoreRecovery,
              pendingRestoreCleanup == nil else {
            throw DataSafetyError.unresolvedRecoveryIssues
        }
        guard let requestedRoot = item(id) else { return }
        let affectedItemIds = Set([id] + allItemDescendantIds(of: id))
        let deletionRoots = Set(affectedItemIds.flatMap {
            itemDeletionRoots(containing: $0)
        })
        guard deletionRoots.allSatisfy({ $0 == id }) else {
            throw MutationConflictError.ancestorDeletionInProgress
        }
        if requestedRoot.deletedAt == nil {
            guard lists.contains(where: {
                $0.id == requestedRoot.listId && $0.deletedAt == nil
            }) else {
                throw MutationConflictError.inactiveDestinationList
            }
        } else if !deletionRoots.contains(id) {
            return
        }
        guard !conflictsWithListDeletion([requestedRoot.listId]) else {
            throw MutationConflictError.listDeletionInProgress
        }
        reversedItemDeletionRoots.remove(id)
        guard itemDeletionRootsInFlight.insert(id).inserted else { return }
        defer { itemDeletionRootsInFlight.remove(id) }
        let context = "soft-delete item subtree \(id)"
        do {
            try await enqueueWrite(
                context,
                reconcilesPreviousFailure: true
            ) { [self] in
            guard let root = self.item(id) else { return }
            try await reconcileRetainedItemUpdates([root.listId])
            guard try await store.pendingRestore() == nil else {
                throw RestoreError.pendingRestoreMustFinish
            }
            let currentIds = Set([id] + allItemDescendantIds(of: id))
            let otherDeletionRoots = Set(currentIds.flatMap {
                itemDeletionRoots(containing: $0)
            }).subtracting([id])
            guard otherDeletionRoots.isEmpty else {
                throw MutationConflictError.ancestorDeletionInProgress
            }
            guard !conflictsWithListDeletion([root.listId]) else {
                throw MutationConflictError.listDeletionInProgress
            }
            // A partially completed attempt leaves the root tombstoned. Reuse
            // its timestamp so retry finishes one restorable deletion batch.
            let deletionJournal = try await store.beginDeletion(
                FileStore.DeletionJournal(
                    kind: .item,
                    rootId: id.uuidString,
                    deletedAt: root.deletedAt ?? .now
                )
            )
            let deletedAt = deletionJournal.deletedAt
            let ids = Self.parentFirstItemIds(
                [id] + allItemDescendantIds(of: id),
                in: items
            )
            var plans: [SynchronousDeletionPlan] = []
            for targetId in ids {
                guard let original = self.item(targetId), original.deletedAt == nil else {
                    continue
                }
                var tombstone = original
                tombstone.deletedAt = deletedAt
                tombstone.modifiedAt = deletedAt
                plans.append(SynchronousDeletionPlan(
                    original: original,
                    tombstone: tombstone
                ))
            }

            var committedIds: Set<UUID> = []
            do {
                for plan in plans {
                    let persisted = try await persistItemResolvingRetainedUpdate(
                        plan.tombstone
                    )
                    committedIds.insert(plan.tombstone.id)
                    replaceItemInMemory(persisted)
                    await scheduler.cancel(plan.tombstone.id)
                }
                try await store.finishDeletion(deletionJournal)
                try await refreshPendingDeletionRecoveryState()
            } catch {
                retainSynchronousSoftDelete(
                    rootId: id,
                    deletedAt: deletedAt,
                    plans: plans,
                    committedIds: committedIds
                )
                try? await refreshPendingDeletionRecoveryState()
                throw error
            }
            }
            discardRetainedSoftDelete(rootId: id)
        } catch {
            if reversedItemDeletionRoots.contains(id) {
                clearWriteFailure(context: context)
            }
            throw error
        }
    }

    /// Synchronous UI-bridge variant of `softDelete(_:)`. Used when a transient
    /// inline-edit shell needs to vanish before UIKit tears down the editing
    /// cell; persistence and notification cancellation continue in the
    /// background like other sync bridge paths.
    public func applySoftDeleteSync(_ id: UUID) {
        guard !isBootstrapping,
              loadIssues.isEmpty,
              !hasPendingRestoreRecovery,
              pendingRestoreCleanup == nil,
              let requestedRoot = item(id),
              requestedRoot.deletedAt == nil,
              lists.contains(where: {
                  $0.id == requestedRoot.listId && $0.deletedAt == nil
              }) else { return }
        let affectedItemIds = Set([id] + allItemDescendantIds(of: id))
        guard !conflictsWithItemDeletion(affectedItemIds),
              !conflictsWithListDeletion([requestedRoot.listId]) else { return }
        reversedItemDeletionRoots.remove(id)
        guard beginSynchronousMutation(deferring: { [weak self] in
            self?.applySoftDeleteSync(id)
        }) else { return }
        defer { leaveMutationScope() }
        guard let root = item(id) else { return }
        // A durable root from a partial root-first attempt owns the deletion
        // batch timestamp. Retrying uses it so restore can always recognize
        // descendants completed by either attempt.
        let now = root.deletedAt ?? Date()
        let orderedIds = Self.parentFirstItemIds(
            [id] + allItemDescendantIds(of: id),
            in: items
        )
        var plans: [SynchronousDeletionPlan] = []
        for targetId in orderedIds {
            guard let original = item(targetId) else { continue }
            if isSameDeletionBatch(original.deletedAt, now) {
                continue
            }
            guard original.deletedAt == nil else { continue }
            var tombstone = original
            tombstone.deletedAt = now
            tombstone.modifiedAt = now
            replaceItemInMemory(tombstone)
            plans.append(SynchronousDeletionPlan(
                original: original,
                tombstone: tombstone
            ))
        }
        guard plans.isEmpty == false else { return }
        retainSynchronousSoftDelete(
            rootId: id,
            deletedAt: now,
            plans: plans
        )
    }

    /// Restore: clears `deletedAt`.
    public func restore(_ id: UUID) async throws {
        try await withMutationScope { [self] in
            try await restoreUngated(id)
        }
    }

    private func restoreUngated(_ id: UUID) async throws {
        guard !isBootstrapping,
              loadIssues.isEmpty,
              !hasPendingRestoreRecovery else {
            throw RestoreError.recoveryIssues
        }
        guard itemDeletionRoots(containing: id).allSatisfy({ $0 == id }) else {
            throw MutationConflictError.ancestorDeletionInProgress
        }
        try await performRestore(id)
    }

    /// Bootstrap/reload resumes a validated journal through this path while
    /// public restores remain closed across their MainActor reentrancy window.
    private func performRestore(_ id: UUID) async throws {
        let canceledDeletionRoots = itemDeletionRoots(containing: id)
            .union([id])
        reversedItemDeletionRoots.formUnion(canceledDeletionRoots)
        for rootId in canceledDeletionRoots {
            discardRetainedSoftDelete(rootId: rootId)
        }
        try await enqueueWrite(
            "restore item subtree \(id)",
            reconcilesPreviousFailure: true
        ) { [self] in
            try await store.cancelDeletion(kind: .item, rootId: id.uuidString)
            try await refreshPendingDeletionRecoveryState()
            guard let original = self.item(id) else { return }
            guard let deletedAt = original.deletedAt else {
                if let journal = try await store.pendingRestore(),
                   journal.kind == .item,
                   journal.rootId == id.uuidString {
                    try await finishRestore(journal, cleanup: .item(id))
                }
                return
            }
            let restoredAt = Date.now
            let descendantIds = allItemDescendantIds(of: id)
            let restoreIds = [id] + descendantIds.filter { descendantId in
                isSameDeletionBatch(self.item(descendantId)?.deletedAt, deletedAt)
            }

            var workingItems = items
            var planned: [(oldListId: String, item: Item)] = []
            for targetId in restoreIds {
                guard let idx = workingItems.firstIndex(where: { $0.id == targetId }) else {
                    continue
                }
                var restored = workingItems[idx]
                let oldListId = restored.listId
                restored.deletedAt = nil

                if targetId == id,
                   !lists.contains(where: { $0.id == restored.listId && $0.deletedAt == nil }) {
                    guard let fallbackListId = fallbackListIdForRestoredItem() else {
                        throw RestoreError.noAvailableList
                    }
                    restored.listId = fallbackListId
                    restored.parentId = nil
                    restored.section = nil
                } else if let parentId = restored.parentId,
                          let parent = workingItems.first(where: { $0.id == parentId }),
                          parent.deletedAt == nil {
                    restored.listId = parent.listId
                    restored.section = parent.section
                } else if !lists.contains(where: {
                    $0.id == restored.listId && $0.deletedAt == nil
                }) {
                    guard let fallbackListId = fallbackListIdForRestoredItem() else {
                        throw RestoreError.noAvailableList
                    }
                    restored.listId = fallbackListId
                    restored.parentId = nil
                    restored.section = nil
                }

                restored = Self.normalizedForStorage(
                    restored,
                    items: workingItems,
                    lists: lists
                )
                restored.modifiedAt = restoredAt
                workingItems[idx] = restored
                planned.append((oldListId: oldListId, item: restored))
            }

            let journal = try await store.beginRestore(
                FileStore.RestoreJournal(
                    kind: .item,
                    rootId: id.uuidString,
                    deletedAt: deletedAt,
                    expectedItemIds: planned.map { $0.item.id.uuidString }
                )
            )
            // Descendants first keeps the requested tombstone visible as a
            // retry anchor until every dependent file has succeeded.
            let ordered = Array(planned.dropFirst().reversed()) + Array(planned.prefix(1))
            for plan in ordered {
                let persisted = try await persistItemResolvingRetainedUpdate(
                    plan.item,
                    from: plan.oldListId
                )
                if let idx = items.firstIndex(where: { $0.id == persisted.id }) {
                    items[idx] = persisted
                }
                await scheduler.schedule(persisted)
            }
            try await finishRestore(journal, cleanup: .item(id))
            for memberId in [id] + allItemDescendantIds(of: id) {
                guard let member = item(memberId), member.deletedAt == nil else { continue }
                await scheduler.schedule(member)
            }
        }
    }

    // MARK: - Lists

    public func addList(_ list: ItemList) async throws {
        try await withMutationScope { [self] in
            try await addListUngated(list)
        }
    }

    private func addListUngated(_ list: ItemList) async throws {
        var list = list
        list.parentId = normalizedParentId(for: list)
        if let parentId = list.parentId {
            guard lists.contains(where: {
                $0.id == parentId && $0.deletedAt == nil
            }) else {
                throw MutationConflictError.inactiveDestinationList
            }
            if conflictsWithListDeletion([parentId]) {
                throw MutationConflictError.listDeletionInProgress
            }
        }
        guard !lists.contains(where: { $0.id == list.id }),
              creatingListIds.insert(list.id).inserted else {
            throw CreationError.duplicateListID(list.id)
        }
        defer { creatingListIds.remove(list.id) }

        list.modifiedAt = .now
        try await writeListOrdered(list)
        lists.append(list)
    }

    public func updateList(_ list: ItemList) async throws {
        try await withMutationScope { [self] in
            try await updateListUngated(list)
        }
    }

    private func updateListUngated(_ list: ItemList) async throws {
        guard let baseline = lists.first(where: { $0.id == list.id }) else { return }
        let oldItems = items
        let oldLists = lists
        let oldDocumentFileNames = documentFileNamesById
        if baseline.deletedAt != nil, list.deletedAt == nil {
            throw MutationConflictError.deletedListRequiresRestore
        }
        var updated = list
        updated.parentId = normalizedParentId(for: updated)
        if updated.deletedAt == nil,
           let parentId = updated.parentId,
           !lists.contains(where: {
               $0.id == parentId && $0.deletedAt == nil
           }) {
            throw MutationConflictError.inactiveDestinationList
        }
        var affectedIds: Set<String> = [updated.id]
        if let parentId = updated.parentId { affectedIds.insert(parentId) }
        guard !conflictsWithListDeletion(affectedIds) else {
            throw MutationConflictError.listDeletionInProgress
        }
        updated.modifiedAt = .now
        let fields = Self.changedListFields(from: baseline, to: updated)
        let intentGeneration = acceptListIntent(
            for: updated.id,
            fields: fields
        )
        try await enqueueWrite(
            "update list \(updated.id)",
            reconcilesPreviousFailure: true
        ) { [self] in
            _ = try await persistAndCommitList(
                updated,
                baseline: baseline,
                fields: fields,
                intentGeneration: intentGeneration
            )
            if baseline.name != updated.name || baseline.parentId != updated.parentId {
                try await persistPortableLinkRewrites(
                    oldItems: oldItems,
                    oldLists: oldLists,
                    oldDocumentFileNames: oldDocumentFileNames
                )
            }
        }
    }

    private func fallbackListIdForRestoredItem() -> String? {
        if lists.contains(where: { $0.id == ItemList.inboxId && $0.deletedAt == nil }) {
            return ItemList.inboxId
        }
        return lists
            .filter { $0.deletedAt == nil }
            .sorted {
                if $0.position != $1.position { return $0.position < $1.position }
                if $0.name != $1.name { return $0.name < $1.name }
                return $0.id < $1.id
            }
            .first?.id
    }

    /// Hard delete: removes the list folder + all items inside.
    public func deleteList(_ id: String) async throws {
        try await withMutationScope { [self] in
            try await deleteListUngated(id)
        }
    }

    private func deleteListUngated(_ id: String) async throws {
        guard !isBootstrapping,
              !hasPendingRestoreRecovery,
              loadIssues.isEmpty else {
            throw DataSafetyError.unresolvedRecoveryIssues
        }
        guard listDeletionRoots(containing: id).allSatisfy({ $0 == id }) else {
            throw MutationConflictError.ancestorDeletionInProgress
        }
        try await hardDeleteList(id)
    }

    private func hardDeleteList(_ id: String) async throws {
        guard let requestedRoot = lists.first(where: { $0.id == id }) else { return }
        let canceledDeletionRoots = listDeletionRoots(containing: id).union([id])
        reversedListDeletionRoots.formUnion(canceledDeletionRoots)
        for rootId in canceledDeletionRoots {
            discardRetainedListSoftDelete(rootId: rootId)
        }
        let ownsDeletionFence = listDeletionRootsInFlight.insert(id).inserted
        defer {
            if ownsDeletionFence { listDeletionRootsInFlight.remove(id) }
        }
        let expectedDeletedAt = requestedRoot.deletedAt

        try await enqueueWrite(
            "delete list subtree \(id)",
            reconcilesPreviousFailure: true
        ) { [self] in
            guard try await store.pendingRestore() == nil else {
                throw RestoreError.pendingRestoreMustFinish
            }
            try await store.cancelDeletion(kind: .list, rootId: id)
            try await refreshPendingDeletionRecoveryState()
            try await reconcileRetainedListUpdates()
            guard let list = lists.first(where: { $0.id == id }),
                  list.deletedAt == expectedDeletedAt else {
                return
            }

            let ids = Set([id] + allDescendantIds(of: id))
            try await reconcileRetainedItemUpdates(ids)
            let removedItemIds = items
                .filter { ids.contains($0.listId) }
                .map(\.id)
            discardRetainedSoftDeletes(removing: Set(removedItemIds))
            // A failed optimistic move can leave its durable source outside
            // the list subtree being removed. Delete that recorded source
            // before the folder so permanent deletion cannot resurrect it.
            for itemId in removedItemIds {
                guard let item = item(itemId),
                      let sourceListId = retainedSourceListId(for: itemId),
                      !ids.contains(sourceListId) else { continue }
                var sourceCopy = item
                sourceCopy.listId = sourceListId
                try await store.deleteItem(sourceCopy)
            }
            try await store.deleteList(list)
            discardRetainedListSoftDelete(rootId: id)
            for itemId in removedItemIds {
                discardRetainedItemUpdate(for: itemId)
            }
            lists.removeAll { ids.contains($0.id) }
            items.removeAll { ids.contains($0.listId) }
            for itemId in removedItemIds {
                durableItemListIds[itemId] = nil
                latestItemFieldIntent[itemId] = nil
                await scheduler.cancel(itemId)
            }
            for listId in ids {
                latestListFieldIntent[listId] = nil
            }
        }
    }

    /// Soft delete a list: stays on disk, hidden from active views, can be
    /// restored from Recently Deleted. Cascades to descendants — every nested
    /// sub-list also gets `deletedAt = now` so the entire subtree disappears
    /// together and shows up in Recently Deleted as separate restorable rows.
    /// Live items in those lists get the same tombstone so the recovery screen
    /// matches the destructive alert and they can be restored with their list.
    public func softDeleteList(_ id: String) async throws {
        try await withMutationScope { [self] in
            try await softDeleteListUngated(id)
        }
    }

    private func softDeleteListUngated(_ id: String) async throws {
        guard !isBootstrapping,
              loadIssues.isEmpty,
              !hasPendingRestoreRecovery,
              pendingRestoreCleanup == nil else {
            throw DataSafetyError.unresolvedRecoveryIssues
        }
        guard let root = lists.first(where: { $0.id == id }) else { return }
        let affectedListIds = Set([id] + allDescendantIds(of: id))
        let deletionRoots = Set(affectedListIds.flatMap {
            listDeletionRoots(containing: $0)
        })
        guard deletionRoots.allSatisfy({ $0 == id }) else {
            throw MutationConflictError.ancestorDeletionInProgress
        }
        if root.deletedAt != nil, !deletionRoots.contains(id) { return }
        let affectedItemIds = Set(items.lazy.filter {
            affectedListIds.contains($0.listId)
        }.map(\.id))
        let itemDeletionRoots = Set(affectedItemIds.flatMap {
            itemDeletionRoots(containing: $0)
        })
        guard itemDeletionRoots.isEmpty else {
            throw MutationConflictError.itemDeletionInProgress
        }
        reversedListDeletionRoots.remove(id)
        guard listDeletionRootsInFlight.insert(id).inserted else { return }
        defer { listDeletionRootsInFlight.remove(id) }
        let deletedAt = retainedListSoftDeleteTimestamp(for: id)
            ?? root.deletedAt
            ?? .now
        do {
            try await enqueueWrite(
                "soft-delete list subtree \(id)",
                reconcilesPreviousFailure: true
            ) { [self] in
                try await persistListSoftDelete(
                    rootId: id,
                    deletedAt: deletedAt
                )
            }
            discardRetainedListSoftDelete(rootId: id)
        } catch {
            retainListSoftDelete(rootId: id, deletedAt: deletedAt)
            try? await refreshPendingDeletionRecoveryState()
            throw error
        }
    }

    /// Idempotent root-first list deletion. Every durable prefix remains a
    /// coherent recoverable batch, while the retained plan replays only the
    /// still-live suffix after storage becomes writable again.
    private func persistListSoftDelete(
        rootId: String,
        deletedAt requestedDeletedAt: Date
    ) async throws {
        let ownsDeletionFence = listDeletionRootsInFlight.insert(rootId).inserted
        defer {
            if ownsDeletionFence { listDeletionRootsInFlight.remove(rootId) }
        }
        guard try await store.pendingRestore() == nil else {
            throw RestoreError.pendingRestoreMustFinish
        }
        try await reconcileRetainedListUpdates()
        guard let root = lists.first(where: { $0.id == rootId }) else { return }
        if let rootDeletedAt = root.deletedAt,
           !isSameDeletionBatch(rootDeletedAt, requestedDeletedAt) {
            return
        }

        // Include already-tombstoned descendants so replay traverses through
        // a durable prefix to any live suffix left by an interrupted attempt.
        let ids = [rootId] + allDescendantIds(of: rootId)
        let idSet = Set(ids)
        let otherListDeletionRoots = Set(ids.flatMap {
            listDeletionRoots(containing: $0)
        }).subtracting([rootId])
        guard otherListDeletionRoots.isEmpty else {
            throw MutationConflictError.ancestorDeletionInProgress
        }
        let affectedItemIds = Set(items.lazy.filter {
            idSet.contains($0.listId)
        }.map(\.id))
        let itemDeletionRoots = Set(affectedItemIds.flatMap {
            itemDeletionRoots(containing: $0)
        })
        guard itemDeletionRoots.isEmpty else {
            throw MutationConflictError.itemDeletionInProgress
        }
        try await reconcileRetainedItemUpdates(idSet)

        guard !reversedListDeletionRoots.contains(rootId),
              try await store.pendingRestore() == nil else { return }

        let deletionJournal = try await store.beginDeletion(
            FileStore.DeletionJournal(
                kind: .list,
                rootId: rootId,
                deletedAt: requestedDeletedAt
            )
        )
        let deletedAt = deletionJournal.deletedAt

        for targetId in ids {
            guard var list = lists.first(where: { $0.id == targetId }) else { continue }
            if let existingDeletedAt = list.deletedAt {
                if isSameDeletionBatch(existingDeletedAt, deletedAt) { continue }
                // A list that was already deleted independently does not join
                // this batch and must not later be restored with its parent.
                continue
            }
            list.deletedAt = deletedAt
            list.modifiedAt = deletedAt
            list.lamport += 1
            try await store.writeList(list)
            if let index = lists.firstIndex(where: { $0.id == targetId }),
               lists[index].deletedAt == nil {
                lists[index] = list
            }
        }

        let itemIds = items
            .filter { idSet.contains($0.listId) && $0.deletedAt == nil }
            .map(\.id)
        for itemId in itemIds {
            guard var item = self.item(itemId), item.deletedAt == nil else { continue }
            item.deletedAt = deletedAt
            item.modifiedAt = deletedAt
            let persisted = try await persistItemResolvingRetainedUpdate(item)
            if let index = items.firstIndex(where: { $0.id == itemId }),
               items[index].deletedAt == nil {
                items[index] = persisted
            }
            await scheduler.cancel(itemId)
        }
        try await store.finishDeletion(deletionJournal)
        try await refreshPendingDeletionRecoveryState()
    }

    /// Restore: clears `deletedAt` for the selected list plus any descendant
    /// lists deleted by the same operation. If the restored subtree's parent
    /// is still deleted, the restored root detaches to the sidebar root. Items
    /// deleted by the same list-delete operation are restored with the list;
    /// items and sublists that were already in Recently Deleted stay there.
    public func restoreList(_ id: String) async throws {
        try await withMutationScope { [self] in
            try await restoreListUngated(id)
        }
    }

    private func restoreListUngated(_ id: String) async throws {
        guard !isBootstrapping,
              loadIssues.isEmpty,
              !hasPendingRestoreRecovery else {
            throw RestoreError.recoveryIssues
        }
        guard listDeletionRoots(containing: id).allSatisfy({ $0 == id }) else {
            throw MutationConflictError.ancestorDeletionInProgress
        }
        // Restore is the user's explicit reversal of any interrupted delete.
        // Retire its replay before restoring the durable prefix so a queued
        // retry cannot tombstone the live suffix afterward.
        let canceledDeletionRoots = listDeletionRoots(containing: id).union([id])
        reversedListDeletionRoots.formUnion(canceledDeletionRoots)
        for rootId in canceledDeletionRoots {
            discardRetainedListSoftDelete(rootId: rootId)
        }
        try await performRestoreList(id)
    }

    private func performRestoreList(_ id: String) async throws {
        try await enqueueWrite(
            "restore list subtree \(id)",
            reconcilesPreviousFailure: true
        ) { [self] in
            try await store.cancelDeletion(kind: .list, rootId: id)
            try await refreshPendingDeletionRecoveryState()
            guard let original = lists.first(where: { $0.id == id }) else { return }
            guard let deletedAt = original.deletedAt else {
                if let journal = try await store.pendingRestore(),
                   journal.kind == .list,
                   journal.rootId == id {
                    try await finishRestore(journal, cleanup: .list(id))
                }
                return
            }
            let restoredAt = Date.now
            let descendantIds = allDescendantIds(of: id)
            let restoreIds = [id] + descendantIds.filter { childId in
                guard let list = lists.first(where: { $0.id == childId }) else { return false }
                // An active descendant can be the successful prefix of an
                // earlier root-last restore attempt. Keep it in scope so its
                // still-tombstoned items and descendants can finish.
                return list.deletedAt == nil || isSameDeletionBatch(list.deletedAt, deletedAt)
            }
            let restoreIdSet = Set(restoreIds)

            var workingLists = lists
            var listPlans: [ItemList] = []
            for targetId in restoreIds {
                guard let idx = workingLists.firstIndex(where: { $0.id == targetId }),
                      isSameDeletionBatch(workingLists[idx].deletedAt, deletedAt) else {
                    continue
                }
                var restored = workingLists[idx]
                restored.deletedAt = nil
                restored.modifiedAt = restoredAt
                restored.lamport += 1
                if let parentId = restored.parentId,
                   !restoreIdSet.contains(parentId),
                   let parent = workingLists.first(where: { $0.id == parentId }),
                   parent.deletedAt != nil {
                    restored.parentId = nil
                }
                workingLists[idx] = restored
                listPlans.append(restored)
            }

            let itemIds = items
                .filter {
                    restoreIdSet.contains($0.listId)
                        && isSameDeletionBatch($0.deletedAt, deletedAt)
                }
                .map(\.id)
            let orderedItemIds = Self.parentFirstItemIds(itemIds, in: items)
            var workingItems = items
            var itemPlans: [(oldListId: String, item: Item)] = []
            for itemId in orderedItemIds {
                guard let idx = workingItems.firstIndex(where: { $0.id == itemId }) else {
                    continue
                }
                var restored = workingItems[idx]
                let oldListId = restored.listId
                restored.deletedAt = nil
                if let parentId = restored.parentId,
                   let parent = workingItems.first(where: { $0.id == parentId }),
                   parent.deletedAt == nil {
                    restored.listId = parent.listId
                    restored.section = parent.section
                }
                restored = Self.normalizedForStorage(
                    restored,
                    items: workingItems,
                    lists: workingLists
                )
                restored.modifiedAt = restoredAt
                workingItems[idx] = restored
                itemPlans.append((oldListId: oldListId, item: restored))
            }

            let journal = try await store.beginRestore(
                FileStore.RestoreJournal(
                    kind: .list,
                    rootId: id,
                    deletedAt: deletedAt,
                    expectedItemIds: itemIds.map(\.uuidString),
                    expectedListIds: restoreIds
                )
            )
            // Restore dependent item files and descendant list headers first.
            // The requested root stays tombstoned and visible for retry until
            // the entire selected batch is durable.
            for plan in itemPlans.reversed() {
                let persisted = try await persistItemResolvingRetainedUpdate(
                    plan.item,
                    from: plan.oldListId
                )
                if let idx = items.firstIndex(where: { $0.id == persisted.id }) {
                    items[idx] = persisted
                }
                await scheduler.schedule(persisted)
            }

            let orderedListPlans = Array(listPlans.dropFirst().reversed())
                + Array(listPlans.prefix(1))
            for restored in orderedListPlans {
                try await store.writeList(restored)
                if let idx = lists.firstIndex(where: { $0.id == restored.id }) {
                    lists[idx] = restored
                }
            }
            try await finishRestore(journal, cleanup: .list(id))
            let activeRestoredListIds = Set(restoreIds.filter { listId in
                lists.first { $0.id == listId }?.deletedAt == nil
            })
            for member in items where member.deletedAt == nil
                && activeRestoredListIds.contains(member.listId) {
                await scheduler.schedule(member)
            }
        }
    }

    private func isSameDeletionBatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return false }
        return abs(lhs.timeIntervalSince(rhs)) < 0.001
    }

    /// Move a list under a new parent (or to root if `newParentId` is nil).
    /// Rejects cycles — the new parent must not be the list itself or one of
    /// its descendants. The on-disk folder is physically moved by
    /// `FileStore.writeList`.
    public func moveList(_ id: String, toParent newParentId: String?) async throws {
        try await withMutationScope { [self] in
            try await moveListUngated(id, toParent: newParentId)
        }
    }

    private func moveListUngated(_ id: String, toParent newParentId: String?) async throws {
        guard let baseline = lists.first(where: { $0.id == id }) else { return }
        var list = baseline
        if let newParentId {
            if newParentId == id { return }
            guard let parent = lists.first(where: { $0.id == newParentId }),
                  parent.deletedAt == nil else { return }
            let descendants = Set(descendantIds(of: id))
            if descendants.contains(newParentId) { return }
        }
        var affectedIds: Set<String> = [id]
        if let newParentId { affectedIds.insert(newParentId) }
        guard !conflictsWithListDeletion(affectedIds) else {
            throw MutationConflictError.listDeletionInProgress
        }
        list.parentId = newParentId
        list.modifiedAt = .now
        list.lamport += 1
        let fields = Self.changedListFields(from: baseline, to: list)
        let intentGeneration = acceptListIntent(for: list.id, fields: fields)
        try await enqueueWrite(
            "move list \(list.id)",
            reconcilesPreviousFailure: true
        ) { [self] in
            _ = try await persistAndCommitList(
                list,
                baseline: baseline,
                fields: fields,
                intentGeneration: intentGeneration
            )
        }
    }

    /// Store-level guard for list hierarchy writes. UI pickers prevent bad
    /// choices, but local-first data still treats the store as the authority.
    private func normalizedParentId(for list: ItemList) -> String? {
        ListHierarchy.normalizedParentId(for: list, in: lists)
    }

    /// Commit a sidebar list drag in one shot. Reparents `movedId` under
    /// `newParentId` (nil = root, same cycle guard as `moveList`), then
    /// renumbers every visible group's `position` densely from
    /// `flatOrderedIds` (the post-drag render order). Mutates the in-memory
    /// snapshot first — so the diffable data source reflects the new state
    /// *before* `UICollectionViewDropCoordinator.drop(_:toItemAt:)` animates,
    /// otherwise the move snaps back — then a single fire-and-forget write
    /// pass over only the lists that actually changed. The moved list is
    /// written first so `FileStore.writeList` relocates its folder (and
    /// refreshes descendant paths) before any descendant position write.
    /// Returns false (no mutation) if the move would create a cycle.
    @discardableResult
    public func applyListReorderSync(
        movedId: String,
        toParent newParentId: String?,
        flatOrderedIds: [String]
    ) -> Bool {
        var affectedIds = Set(flatOrderedIds)
        affectedIds.insert(movedId)
        if let newParentId { affectedIds.insert(newParentId) }
        guard !conflictsWithListDeletion(affectedIds) else { return false }
        guard beginSynchronousMutation(deferring: { [weak self] in
            _ = self?.applyListReorderSync(
                movedId: movedId,
                toParent: newParentId,
                flatOrderedIds: flatOrderedIds
            )
        }) else { return true }
        defer { leaveMutationScope() }
        guard lists.contains(where: { $0.id == movedId && $0.deletedAt == nil }) else { return false }

        // Parent/cycle guard — mirror moveList.
        if let newParentId {
            if newParentId == movedId { return false }
            guard let parent = lists.first(where: { $0.id == newParentId }),
                  parent.deletedAt == nil else { return false }
            if Set(descendantIds(of: movedId)).contains(newParentId) { return false }
        }

        let baselineById = Dictionary(
            uniqueKeysWithValues: lists.map { ($0.id, $0) }
        )
        var dirty: Set<String> = []

        // 1. Reparent the moved list in memory.
        if let idx = lists.firstIndex(where: { $0.id == movedId }),
           lists[idx].parentId != newParentId {
            lists[idx].parentId = newParentId
            dirty.insert(movedId)
        }

        // 2. Renumber positions densely per parent group, in render order.
        //    Collapsed (non-visible) groups keep their existing positions —
        //    they aren't in `flatOrderedIds`, so their counters never run.
        var perGroup: [String?: Double] = [:]
        for id in flatOrderedIds {
            guard let idx = lists.firstIndex(where: { $0.id == id }) else { continue }
            let parent = lists[idx].parentId
            let next = (perGroup[parent] ?? 0) + 1
            perGroup[parent] = next
            if lists[idx].position != next {
                lists[idx].position = next
                dirty.insert(id)
            }
        }

        let persistenceContext = "sidebar reorder"
        guard !dirty.isEmpty else {
            // Repeating the visible drag is also an explicit retry when its
            // first persistence attempt failed after memory already changed.
            retainSynchronousListUpdates([], context: persistenceContext)
            return true
        }

        // 3. Stamp + persist once each, moved list first.
        let now = Date()
        let ordered = (dirty.contains(movedId) ? [movedId] : [])
            + dirty.subtracting([movedId]).sorted()
        for id in ordered {
            guard let idx = lists.firstIndex(where: { $0.id == id }) else { continue }
            lists[idx].modifiedAt = now
            lists[idx].lamport += 1
            if let baseline = baselineById[id] {
                let fields = Self.changedListFields(from: baseline, to: lists[idx])
                _ = acceptListIntent(for: id, fields: fields, optimistic: true)
            }
        }
        retainSynchronousListUpdates(dirty, context: persistenceContext)
        return true
    }

    // MARK: - Sections

    /// Append a new section to the list. Returns the created `ListSection` so
    /// callers can highlight it after creation.
    @discardableResult
    public func addSection(in listId: String, name: String) async throws -> ListSection? {
        try await withMutationScope { [self] in
            try await addSectionUngated(in: listId, name: name)
        }
    }

    private func addSectionUngated(in listId: String, name: String) async throws -> ListSection? {
        guard var list = lists.first(where: { $0.id == listId }) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nextPos = (list.sections.map(\.position).max() ?? 0) + 1000
        let section = ListSection(name: trimmed, position: nextPos)
        list.sections.append(section)
        try await updateList(list)
        return section
    }

    /// Promote the synthetic "Others" bucket into a real named section: create
    /// a new `ListSection` with the given name and reassign every loose item
    /// (`section == nil`) in the list to its id. Any future loose items will
    /// once again surface under a fresh "Others" bucket.
    public func promoteOthersToSection(in listId: String, name: String) async throws {
        try await withMutationScope { [self] in
            try await promoteOthersToSectionUngated(in: listId, name: name)
        }
    }

    private func promoteOthersToSectionUngated(in listId: String, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var list = lists.first(where: { $0.id == listId }) else { return }
        let looseIds = items
            .filter { $0.listId == listId && $0.section == nil && $0.deletedAt == nil }
            .map(\.id)
        guard !looseIds.isEmpty else { return }
        let nextPos = (list.sections.map(\.position).max() ?? 0) + 1000
        let section = ListSection(name: trimmed, position: nextPos)
        list.sections.append(section)
        try await updateList(list)
        let sidStr = section.id.uuidString
        for id in looseIds {
            guard var it = items.first(where: { $0.id == id }) else { continue }
            it.section = sidStr
            try await update(it)
        }
    }

    /// Rename a section in-place. Items keep their `section` id reference, so
    /// no item rewrites are needed.
    public func renameSection(_ sectionId: UUID, in listId: String, to newName: String) async throws {
        try await withMutationScope { [self] in
            try await renameSectionUngated(sectionId, in: listId, to: newName)
        }
    }

    private func renameSectionUngated(
        _ sectionId: UUID,
        in listId: String,
        to newName: String
    ) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var list = lists.first(where: { $0.id == listId }),
              let idx = list.sections.firstIndex(where: { $0.id == sectionId }) else { return }
        if list.sections[idx].name == trimmed { return }
        list.sections[idx].name = trimmed
        try await updateList(list)
    }

    /// Apply a new ordering of section ids. Missing ids are dropped; unknown
    /// ids are ignored. `position` is renumbered densely so the on-disk order
    /// matches the new sequence.
    public func reorderSections(in listId: String, orderedIds: [UUID]) async throws {
        try await withMutationScope { [self] in
            try await reorderSectionsUngated(in: listId, orderedIds: orderedIds)
        }
    }

    private func reorderSectionsUngated(in listId: String, orderedIds: [UUID]) async throws {
        guard var list = lists.first(where: { $0.id == listId }) else { return }
        let bySectionId = Dictionary(uniqueKeysWithValues: list.sections.map { ($0.id, $0) })
        var rebuilt: [ListSection] = []
        var pos: Double = 1000
        for id in orderedIds {
            guard var s = bySectionId[id] else { continue }
            s.position = pos
            rebuilt.append(s)
            pos += 1000
        }
        if rebuilt.count != list.sections.count { return }
        list.sections = rebuilt
        try await updateList(list)
    }

    /// Synchronous UI-bridge variant of `reorderSections` — same rationale as
    /// `applyReorderItemsSync`. Disk write is queued in the background.
    public func applyReorderSectionsSync(in listId: String, orderedIds: [UUID]) {
        guard !conflictsWithListDeletion([listId]) else { return }
        guard beginSynchronousMutation(deferring: { [weak self] in
            self?.applyReorderSectionsSync(in: listId, orderedIds: orderedIds)
        }) else { return }
        defer { leaveMutationScope() }
        guard var list = lists.first(where: { $0.id == listId }) else { return }
        let baseline = list
        let bySectionId = Dictionary(uniqueKeysWithValues: list.sections.map { ($0.id, $0) })
        var rebuilt: [ListSection] = []
        var pos: Double = 1000
        for id in orderedIds {
            guard var s = bySectionId[id] else { continue }
            s.position = pos
            rebuilt.append(s)
            pos += 1000
        }
        if rebuilt.count != list.sections.count { return }
        list.sections = rebuilt
        list.modifiedAt = .now
        if let idx = lists.firstIndex(where: { $0.id == list.id }) {
            lists[idx] = list
        }
        let fields = Self.changedListFields(from: baseline, to: list)
        _ = acceptListIntent(for: list.id, fields: fields, optimistic: true)
        retainSynchronousListUpdates(
            [list.id],
            context: "section reorder in \(list.id)"
        )
    }

    /// Delete a section. When `cascadingItems` is true (the default — matches
    /// the Delete-List pattern), every item assigned to that section is soft-
    /// deleted alongside it. When false, items are detached (their `section`
    /// becomes `nil`) and live on as ungrouped items in the list.
    public func deleteSection(
        _ sectionId: UUID,
        in listId: String,
        cascadingItems: Bool = true
    ) async throws {
        try await withMutationScope { [self] in
            try await deleteSectionUngated(
                sectionId,
                in: listId,
                cascadingItems: cascadingItems
            )
        }
    }

    private func deleteSectionUngated(
        _ sectionId: UUID,
        in listId: String,
        cascadingItems: Bool
    ) async throws {
        try await enqueueWrite(
            "prepare section deletion in \(listId)",
            reconcilesPreviousFailure: true
        ) { [self] in
            try await reconcileRetainedItemUpdates([listId])
        }
        guard var list = lists.first(where: { $0.id == listId }) else { return }
        let sidStr = sectionId.uuidString
        let affectedIds = items
            .filter { $0.listId == listId && $0.section == sidStr && $0.deletedAt == nil }
            .map(\.id)

        if cascadingItems {
            for id in affectedIds {
                try await softDelete(id)
            }
        } else {
            for id in affectedIds {
                guard var it = items.first(where: { $0.id == id }) else { continue }
                it.section = nil
                try await update(it)
            }
        }

        list.sections.removeAll { $0.id == sectionId }
        try await updateList(list)
    }

    /// Retryable commit from the Edit Sections sheet. `kept` is the post-edit
    /// list of sections (renames + reorder applied); `deleted` is the ids that
    /// were removed. Items in deleted sections are soft-deleted first, so a
    /// retry can safely finish a partially completed operation.
    public func commitSectionEdits(
        in listId: String,
        kept: [ListSection],
        deleted: [UUID]
    ) async throws {
        try await withMutationScope { [self] in
            try await commitSectionEditsUngated(in: listId, kept: kept, deleted: deleted)
        }
    }

    private func commitSectionEditsUngated(
        in listId: String,
        kept: [ListSection],
        deleted: [UUID]
    ) async throws {
        if !deleted.isEmpty {
            try await enqueueWrite(
                "prepare section edits in \(listId)",
                reconcilesPreviousFailure: true
            ) { [self] in
                try await reconcileRetainedItemUpdates([listId])
            }
        }
        for sid in deleted {
            let sidStr = sid.uuidString
            let affected = items
                .filter { $0.listId == listId && $0.section == sidStr && $0.deletedAt == nil }
                .map(\.id)
            for id in affected {
                try await softDelete(id)
            }
        }
        guard var list = lists.first(where: { $0.id == listId }) else { return }
        // Renumber position densely in the order provided.
        var pos: Double = 1000
        list.sections = kept.map { s in
            var copy = s
            copy.position = pos
            pos += 1000
            return copy
        }
        try await updateList(list)
    }

    /// Resumable migration for legacy free-form `Item.section` names. Existing
    /// section names are reused after an interrupted attempt, missing names are
    /// appended once, and remaining item references are rewritten to UUIDs.
    public func migrateLegacySectionsIfNeeded(listId: String) async throws {
        try await withMutationScope { [self] in
            try await migrateLegacySectionsIfNeededUngated(listId: listId)
        }
    }

    private func migrateLegacySectionsIfNeededUngated(listId: String) async throws {
        guard var list = lists.first(where: { $0.id == listId }) else { return }
        let listItems = items.filter { $0.listId == listId && $0.deletedAt == nil }
        let legacyItems = listItems.compactMap { item -> (item: Item, name: String)? in
            guard let name = item.section,
                  !name.isEmpty,
                  UUID(uuidString: name) == nil else { return nil }
            return (item, name)
        }
        guard !legacyItems.isEmpty else { return }

        var nameToId: [String: UUID] = [:]
        for section in list.sections where nameToId[section.name] == nil {
            nameToId[section.name] = section.id
        }

        var nextPosition = (list.sections.map(\.position).max() ?? 0) + 1000
        var addedSection = false
        for (_, name) in legacyItems where nameToId[name] == nil {
            let section = ListSection(name: name, position: nextPosition)
            list.sections.append(section)
            nameToId[name] = section.id
            nextPosition += 1000
            addedSection = true
        }
        if addedSection {
            // Persist every destination UUID before rewriting any item. A
            // stopped item loop can then resume against these same identities.
            try await updateList(list)
        }

        for (item, name) in legacyItems {
            guard let newId = nameToId[name] else { continue }
            // Re-fetch the live value inside the loop so an edit made during an
            // earlier iteration's await isn't overwritten by this pre-loop
            // snapshot.
            guard var copy = items.first(where: { $0.id == item.id }),
                  copy.section == name else { continue }
            copy.section = newId.uuidString
            try await update(copy)
        }
    }

    // MARK: - Hierarchy helpers

    /// Direct children of `parentId` (non-deleted), sorted by position.
    public func children(of parentId: String?) -> [ItemList] {
        ListHierarchy.children(of: parentId, in: lists)
    }

    /// All descendants of `id` (children, grandchildren, …) — non-deleted.
    /// Used by cascade delete and the cycle guard.
    public func descendantIds(of id: String) -> [String] {
        ListHierarchy.descendantIds(of: id, in: lists)
    }

    /// All descendants of `id`, including deleted lists. Hard-delete and purge
    /// use this because the folder removal is recursive regardless of tombstone
    /// state, so the in-memory snapshot must drop hidden descendants too.
    private func allDescendantIds(of id: String) -> [String] {
        ListHierarchy.descendantIds(of: id, in: lists, includingDeleted: true)
    }

    /// Auto-purge tombstones older than 30 days. Called from bootstrap.
    private func purgeExpiredTombstones() async throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        let expiredItems = items.filter { ($0.deletedAt ?? .distantFuture) < cutoff }
        for expired in expiredItems {
            do {
                try await deleteItemOrdered(expired)
                items.removeAll { $0.id == expired.id }
                await scheduler.cancel(expired.id)
            } catch {
                // Keep the tombstone in memory when its file remains. Removing
                // it here would make the item appear gone until it resurrected
                // from that failed file on the next launch.
            }
        }

        let expiredListIds = lists
            .filter { ($0.deletedAt ?? .distantFuture) < cutoff }
            .map(\.id)
        for id in expiredListIds where lists.contains(where: { $0.id == id }) {
            try? await hardDeleteList(id)
        }
    }

    /// Return items matching a smart list, sorted oldest-due-first (overdue at top).
    /// `lingering` is a set of ids that should remain visible regardless of the
    /// smart-list filter — used by views to keep a just-completed item on screen
    /// for the linger window before it fades out. `showCompleted` extends the
    /// match to include done items that would otherwise be filtered out (no-op
    /// for the `.completed` smart list, which already shows done items).
    public func items(
        for query: SmartList,
        showCompleted: Bool = false,
        showPastEvents: Bool = false,
        lingering: Set<UUID> = [],
        now: Date = .now
    ) -> [Item] {
        items
            .filter { item in
                if item.deletedAt != nil { return false }
                if lingering.contains(item.id) { return true }
                if item.isRolledOffPastEvent(now: now) && !showPastEvents { return false }
                return query.matches(item, now: now, includeCompleted: showCompleted)
            }
            .sorted(by: Self.byDue)
    }

    private static func byDue(_ lhs: Item, _ rhs: Item) -> Bool {
        let l = lhs.due ?? .distantFuture
        let r = rhs.due ?? .distantFuture
        if l != r { return l < r }
        return lhs.title < rhs.title
    }
}
