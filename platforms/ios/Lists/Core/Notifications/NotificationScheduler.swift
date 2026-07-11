import Foundation
@preconcurrency import UserNotifications
import os

protocol UserNotificationRequestCenter: Sendable {
    func pendingRequests() async -> [UNNotificationRequest]
    func deliveredIdentifiers() async -> [String]
    func add(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String]) async
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async
}

private struct SystemUserNotificationRequestCenter: UserNotificationRequestCenter, @unchecked Sendable {
    let center: UNUserNotificationCenter

    func pendingRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func deliveredIdentifiers() async -> [String] {
        await center.deliveredNotifications().map(\.request.identifier)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

protocol NotificationScheduling: Sendable {
    func schedule(_ item: Item) async
    func cancel(_ id: UUID) async
    func reconcile(_ items: [Item]) async
}

extension NotificationScheduling {
    func reconcile(_ items: [Item]) async {
        for item in items {
            await schedule(item)
        }
    }
}

/// Wraps `UNUserNotificationCenter`. Schedules / cancels standard local
/// notifications keyed by item id.
///
/// Timezone convention: reminder *triggers* fire at the user's local wall-clock
/// (`Calendar.current`) — a 9am reminder means 9am wherever you are.
/// Habit cycle *keys* are pinned to UTC (`HabitCycle.key`). The two only
/// diverge around timezone changes near a cycle boundary, and the trigger side
/// is deliberately local because that's what a reminder time means to a person.
public actor NotificationScheduler {

    public static let shared = NotificationScheduler()

    /// iOS keeps only the soonest ~64 pending notifications per app and
    /// silently discards the rest. The cap can't be raised; what we can do is
    /// keep our usage small (one trigger per habit, see `habitTriggers`) and
    /// log loudly when the queue reaches the limit so a reminder that will
    /// never fire is at least diagnosable.
    public static let pendingLimit = 64

    private static let log = Logger(
        subsystem: "io.github.saxonbobart.lists", category: "notifications")
    private static let durableRevisionKey = "lists.durable-item-revision"
    private static let removalFenceDefaultsKey = "notification-identifiers-pending-removal"

    private let center: any UserNotificationRequestCenter
    private let authorizationCenter: UNUserNotificationCenter
    private var operationChain: Task<Void, Never>?
    private var operationGeneration: UInt64 = 0
    private struct FailedScheduleIntent: Sendable {
        var item: Item
        var clearsDeliveredBase: Bool
        var attempt: Int
    }
    private var failedScheduleIntents: [UUID: FailedScheduleIntent] = [:]
    private var failedScheduleRetryTasks: [UUID: Task<Void, Never>] = [:]
    /// Latest durable reminder state seen this process. When notificationd
    /// admits a nearer 65th request by evicting a farther one, this lets us
    /// retain the displaced item for a later retry instead of forgetting it.
    private var knownDesiredItems: [UUID: Item] = [:]
    /// `removePendingNotificationRequests` has no completion callback. Never
    /// reuse an identifier whose removal this actor has requested: a later
    /// system-side removal could otherwise erase a newly scheduled request.
    private var identifiersPendingRemoval: Set<String>
    private let persistsRemovalFences: Bool
    private var safelyReusableIdentifiers: Set<String> = []
    private var cancellationCleanupIdentifiers: [UUID: Set<String>] = [:]
    private var cancellationCleanupPreservedDeliveredIdentifiers: [UUID: Set<String>] = [:]
    private var cancellationCleanupTasks: [UUID: Task<Void, Never>] = [:]

    public init() {
        let center = UNUserNotificationCenter.current()
        self.center = SystemUserNotificationRequestCenter(center: center)
        self.authorizationCenter = center
        self.identifiersPendingRemoval = Set(
            UserDefaults.standard.stringArray(
                forKey: Self.removalFenceDefaultsKey
            ) ?? []
        )
        self.persistsRemovalFences = true
    }

    init(center: any UserNotificationRequestCenter) {
        self.center = center
        self.authorizationCenter = .current()
        self.identifiersPendingRemoval = []
        self.persistsRemovalFences = false
    }

    // MARK: - Authorization

    /// Returns true if the user granted permission, false if denied/error.
    @discardableResult
    public func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await authorizationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await authorizationCenter.requestAuthorization(
                    options: [.alert, .sound, .badge]
                )
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await authorizationCenter.notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Schedule / cancel

    /// Schedule notification(s) for the item. No-op if the reminder is disabled
    /// or the item is deleted. Tasks fire once at their due date; habits fire on a
    /// *repeating* schedule keyed to their frequency.
    public func schedule(_ item: Item) async {
        finishFailedSchedule(for: item.id)
        if Self.shouldSchedule(item) {
            knownDesiredItems[item.id] = item
        } else {
            knownDesiredItems[item.id] = nil
        }
        let previous = operationChain
        operationGeneration &+= 1
        let generation = operationGeneration
        let operation = Task { [self] in
            await previous?.value
            await performSchedule(
                item,
                clearsDeliveredBase: item.type != .habit
            )
        }
        operationChain = operation
        await operation.value
        if operationGeneration == generation {
            operationChain = nil
            await retryExhaustedScheduleIfCapacityMayHaveChanged()
        }
    }

    private func performSchedule(
        _ item: Item,
        clearsDeliveredBase: Bool = true,
        checksBudget: Bool = true,
        existingPendingRequests: [UNNotificationRequest]? = nil,
        existingDeliveredIdentifiers: [String]? = nil
    ) async {
        guard item.deletedAt == nil,
              let reminder = item.reminder, reminder.enabled
        else {
            await performCancel(
                item.id,
                existingPendingIdentifiers: existingPendingRequests?.map(\.identifier),
                existingDeliveredIdentifiers: existingDeliveredIdentifiers
            )
            return
        }

        let pendingRequests: [UNNotificationRequest]
        if let existingPendingRequests {
            pendingRequests = existingPendingRequests
        } else {
            pendingRequests = await center.pendingRequests().filter {
                Self.itemId(from: $0.identifier) == item.id
            }
        }
        let pendingIdentifiers = pendingRequests.map(\.identifier)
        let deliveredIdentifiers: [String]
        if let existingDeliveredIdentifiers {
            deliveredIdentifiers = existingDeliveredIdentifiers
        } else {
            deliveredIdentifiers = await identifiersInDeliveredNotifications(for: item.id)
        }
        var desiredTriggers: [(suffix: String, trigger: UNNotificationTrigger)] = []
        if item.type == .habit {
            // Repeating, frequency-keyed reminders. No `fireDate > now` guard —
            // a repeating trigger has no single fire date, and a completed
            // current cycle should not cancel future habit reminders.
            let triggers = Self.habitTriggers(for: item)
            guard !triggers.isEmpty else {
                await performCancel(
                    item.id,
                    clearsDelivered: true,
                    existingPendingIdentifiers: pendingIdentifiers,
                    existingDeliveredIdentifiers: deliveredIdentifiers
                )
                return
            }
            desiredTriggers = triggers.map { ($0.suffix, $0.trigger) }
        } else {
            // Dated non-habit items: a single reminder at the (early-adjusted)
            // due date. Revalidate immediately before touching delivered state
            // so launch at the fire boundary cannot erase a just-fired alert.
            guard let fireDate = Self.singleReminderFireDate(for: item) else {
                await performCancel(
                    item.id,
                    clearsDelivered: !Self.shouldPreserveDelivered(item),
                    existingPendingIdentifiers: pendingIdentifiers,
                    existingDeliveredIdentifiers: deliveredIdentifiers
                )
                return
            }

            let cal = Calendar.current
            let comps = cal.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
            desiredTriggers = [(
                "",
                UNCalendarNotificationTrigger(
                    dateMatching: comps,
                    repeats: false
                )
            )]
        }

        // Replacing a pending request with the same identifier is atomic and
        // does not consume a second slot. Only allocate a fresh revision after
        // a cancellation (whose asynchronous removal may still be in flight)
        // or when this item has no pending request yet.
        let durableRevision = Self.durableRevisionToken(for: item)
        let requestsByIdentifier = Dictionary(
            pendingRequests.map { ($0.identifier, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var reusableIdentifiers = pendingIdentifiers
            .filter { identifier in
                guard !identifiersPendingRemoval.contains(identifier) else { return false }
                // If delivered history already owns this identifier, use a
                // fresh pending identifier. Otherwise clearing the stale
                // delivered entry could also erase a just-fired replacement.
                if clearsDeliveredBase,
                   deliveredIdentifiers.contains(identifier) { return false }
                if safelyReusableIdentifiers.contains(identifier) { return true }
                return requestsByIdentifier[identifier]?
                    .content.userInfo[Self.durableRevisionKey] as? String == durableRevision
            }
            .sorted()
        var requests: [UNNotificationRequest] = []
        for desired in desiredTriggers {
            let identifier: String
            if !reusableIdentifiers.isEmpty {
                identifier = reusableIdentifiers.removeFirst()
            } else {
                let suffix = desired.suffix.isEmpty ? "" : ".\(desired.suffix)"
                identifier = "\(item.id.uuidString).r.\(UUID().uuidString)\(suffix)"
            }
            requests.append(UNNotificationRequest(
                identifier: identifier,
                content: makeContent(for: item),
                trigger: desired.trigger
            ))
        }

        let pendingSet = Set(pendingIdentifiers)
        var newIdentifiers = requests.map(\.identifier).filter { !pendingSet.contains($0) }
        var globalPendingBeforeAddition: [UNNotificationRequest] = []
        if !newIdentifiers.isEmpty {
            globalPendingBeforeAddition = await center.pendingRequests()
            let currentPendingCount = globalPendingBeforeAddition.count
            if currentPendingCount + newIdentifiers.count > Self.pendingLimit,
               requests.count == 1,
               let fallbackIdentifier = pendingIdentifiers.first(where: {
                   !identifiersPendingRemoval.contains($0)
                       && (!clearsDeliveredBase || !deliveredIdentifiers.contains($0))
               }) {
                // At the system cap there is no spare slot for a revisioned
                // migration. A durable cross-process cancellation fence makes
                // an unfenced predecessor safe to replace atomically in place.
                requests[0] = UNNotificationRequest(
                    identifier: fallbackIdentifier,
                    content: requests[0].content,
                    trigger: requests[0].trigger
                )
                newIdentifiers = []
            } else if currentPendingCount + newIdentifiers.count > Self.pendingLimit {
                // Submit the request and let notificationd keep the soonest 64.
                // Rejecting it here made queue occupancy, rather than fire date,
                // decide which reminder survived. Post-add verification below
                // retains a later request for retry when the system omits it.
                Self.log.notice("""
                    Submitting reminder for item \
                    \(item.id.uuidString, privacy: .public) at the pending limit
                    """)
            }
        }

        var addedIdentifiers: [String] = []
        do {
            for request in requests {
                try await center.add(request)
                addedIdentifiers.append(request.identifier)
            }
        } catch {
            // Keep the previously registered request until its replacement is
            // known to exist. Revisioned identifiers make cleanup exact: a
            // delayed removal can never target a later replacement.
            let addedNewIdentifiers = addedIdentifiers.filter { !pendingSet.contains($0) }
            if !addedNewIdentifiers.isEmpty {
                markIdentifiersPendingRemoval(addedNewIdentifiers)
                safelyReusableIdentifiers.subtract(addedNewIdentifiers)
                await center.removePendingRequests(withIdentifiers: addedNewIdentifiers)
            }
            retainFailedSchedule(
                item,
                clearsDeliveredBase: clearsDeliveredBase
            )
            Self.log.error("""
                Failed to schedule reminder for item \
                \(item.id.uuidString, privacy: .public): \
                \(String(describing: error), privacy: .private)
                """)
            return
        }

        // Some OS versions enforce the pending cap without surfacing an add
        // error. Do not delete a known-good predecessor unless every intended
        // request is observable in the queue.
        let observedIdentifiers = Set(await center.pendingRequests().map(\.identifier))
        let missingIdentifiers = Set(requests.map(\.identifier))
            .subtracting(observedIdentifiers)
        let vanishedUnrelatedIdentifiers = Set(
            globalPendingBeforeAddition.map(\.identifier)
        ).subtracting(observedIdentifiers).filter { identifier in
            Self.itemId(from: identifier) != item.id
                && !identifiersPendingRemoval.contains(identifier)
        }
        let deliveredAfterAdd = missingIdentifiers.isEmpty
            && vanishedUnrelatedIdentifiers.isEmpty
            ? Set<String>()
            : Set(await center.deliveredIdentifiers())
        let missingRequestsAlreadyFired = item.type != .habit
            && missingIdentifiers.isSubset(of: deliveredAfterAdd)
        if !missingIdentifiers.isEmpty && !missingRequestsAlreadyFired {
            if !newIdentifiers.isEmpty {
                markIdentifiersPendingRemoval(newIdentifiers)
                safelyReusableIdentifiers.subtract(newIdentifiers)
                await center.removePendingRequests(withIdentifiers: newIdentifiers)
            }
            retainFailedSchedule(item, clearsDeliveredBase: clearsDeliveredBase)
            Self.log.error("""
                Notification center did not retain the replacement for item \
                \(item.id.uuidString, privacy: .public)
                """)
            return
        }

        let displacedItemIds = Set(vanishedUnrelatedIdentifiers.compactMap { identifier in
            deliveredAfterAdd.contains(identifier) ? nil : Self.itemId(from: identifier)
        })
        for displacedId in displacedItemIds {
            guard let displaced = knownDesiredItems[displacedId] else { continue }
            retainFailedSchedule(
                displaced,
                clearsDeliveredBase: displaced.type != .habit
            )
        }

        finishFailedSchedule(for: item.id)
        safelyReusableIdentifiers.formUnion(addedIdentifiers)
        let added = Set(addedIdentifiers)
        let obsoletePending = pendingIdentifiers.filter {
            !added.contains($0) && !identifiersPendingRemoval.contains($0)
        }
        if !obsoletePending.isEmpty {
            markIdentifiersPendingRemoval(obsoletePending)
            safelyReusableIdentifiers.subtract(obsoletePending)
            await center.removePendingRequests(withIdentifiers: obsoletePending)
        }
        if clearsDeliveredBase {
            let latestDelivered = await identifiersInDeliveredNotifications(for: item.id)
            // Any predecessor that was pending (but not delivered) in the
            // initial snapshot may cross its fire boundary while asynchronous
            // removal settles. If delivery wins that race, preserve the alert.
            let potentiallyFiringPredecessors = Set(obsoletePending)
                .subtracting(deliveredIdentifiers)
            if !obsoletePending.isEmpty {
                retainCancellationCleanup(
                    for: item.id,
                    identifiers: Set(obsoletePending),
                    preservingDelivered: potentiallyFiringPredecessors
                )
            }
            let protectedReplacementIdentifiers = Set(addedIdentifiers)
                .union(potentiallyFiringPredecessors)
            let staleLatestDelivered = latestDelivered.filter {
                !protectedReplacementIdentifiers.contains($0)
            }
            let identifiers = Array(
                Set(deliveredIdentifiers).union(staleLatestDelivered)
            )
            guard !identifiers.isEmpty else {
                if checksBudget { await warnIfOverBudget() }
                return
            }
            await center.removeDeliveredNotifications(
                withIdentifiers: identifiers
            )
        }
        if checksBudget { await warnIfOverBudget() }
    }

    /// Hitting the iOS pending-notification cap is silent by design (the system
    /// just keeps the 64 soonest). Make it observable.
    private func warnIfOverBudget() async {
        let pending = await center.pendingRequests().count
        if pending >= Self.pendingLimit {
            Self.log.warning("""
                \(pending) pending notifications — iOS keeps only the soonest \
                \(Self.pendingLimit); later reminders will be silently dropped
                """)
        }
    }

    public func cancel(_ id: UUID) async {
        finishFailedSchedule(for: id)
        knownDesiredItems[id] = nil
        let previous = operationChain
        operationGeneration &+= 1
        let generation = operationGeneration
        let operation = Task { [self] in
            await previous?.value
            await performCancel(id)
        }
        operationChain = operation
        await operation.value
        if operationGeneration == generation {
            operationChain = nil
            await retryExhaustedScheduleIfCapacityMayHaveChanged()
        }
    }

    /// Rebuild the notification queue from durable item state after launch or
    /// a library reload. Existing requests are replaced atomically when their
    /// durable revision matches; stale/canceled identifiers are never reused.
    public func reconcile(_ items: [Item]) async {
        let previous = operationChain
        operationGeneration &+= 1
        let generation = operationGeneration
        let operation = Task { [self] in
            await previous?.value
            await performReconciliation(items)
        }
        operationChain = operation
        await operation.value
        if operationGeneration == generation {
            operationChain = nil
            await retryExhaustedScheduleIfCapacityMayHaveChanged()
        }
    }

    private func performReconciliation(_ items: [Item]) async {
        for id in Array(failedScheduleIntents.keys) {
            finishFailedSchedule(for: id)
        }
        let desiredItems = Dictionary(
            items.filter(Self.shouldSchedule).map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        knownDesiredItems = desiredItems
        let activeReminderIds = Set(items.filter(Self.shouldPreserveDelivered).map(\.id))

        let pendingRequests = await center.pendingRequests()
        let pending = pendingRequests.map(\.identifier)
        let settledRemovalFences = identifiersPendingRemoval.subtracting(pending)
        if !settledRemovalFences.isEmpty {
            clearRemovalFences(settledRemovalFences)
        }
        let fencedPendingIdentifiers = pending.filter {
            identifiersPendingRemoval.contains($0)
        }
        if !fencedPendingIdentifiers.isEmpty {
            // The app may have terminated before notificationd applied an
            // earlier asynchronous removal. Reissue it on every launch while
            // continuing to fence the identifier from reuse.
            await center.removePendingRequests(
                withIdentifiers: fencedPendingIdentifiers
            )
            let fencedByItem = Dictionary(
                grouping: fencedPendingIdentifiers,
                by: { Self.itemId(from: $0) }
            )
            for (id, identifiers) in fencedByItem {
                guard let id else { continue }
                let clearsDelivered = desiredItems[id].map { $0.type != .habit }
                    ?? !activeReminderIds.contains(id)
                if clearsDelivered {
                    retainCancellationCleanup(
                        for: id,
                        identifiers: Set(identifiers)
                    )
                }
            }
        }
        let delivered = await center.deliveredIdentifiers()
        let desiredIds = Set(desiredItems.keys)
        let stalePendingIdentifiers = pending.filter { identifier in
            guard let id = Self.itemId(from: identifier) else { return false }
            return !desiredIds.contains(id)
                && !identifiersPendingRemoval.contains(identifier)
        }
        if !stalePendingIdentifiers.isEmpty {
            markIdentifiersPendingRemoval(stalePendingIdentifiers)
            safelyReusableIdentifiers.subtract(stalePendingIdentifiers)
            await center.removePendingRequests(
                withIdentifiers: stalePendingIdentifiers
            )
            let cleanupByItem = Dictionary(
                grouping: stalePendingIdentifiers,
                by: Self.itemId(from:)
            )
            for (id, identifiers) in cleanupByItem {
                guard let id, !activeReminderIds.contains(id) else { continue }
                retainCancellationCleanup(
                    for: id,
                    identifiers: Set(identifiers)
                )
            }
        }
        let staleDeliveredIdentifiers = delivered.filter { identifier in
            guard let id = Self.itemId(from: identifier) else { return false }
            return !activeReminderIds.contains(id)
        }
        if !staleDeliveredIdentifiers.isEmpty {
            await center.removeDeliveredNotifications(
                withIdentifiers: staleDeliveredIdentifiers
            )
        }
        for item in desiredItems.values.sorted(by: {
            let lhsDate = Self.schedulingPriorityDate(for: $0)
            let rhsDate = Self.schedulingPriorityDate(for: $1)
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return $0.id.uuidString < $1.id.uuidString
        }) {
            let itemPending = pendingRequests.filter {
                Self.itemId(from: $0.identifier) == item.id
            }
            let itemDelivered = delivered.filter { Self.itemId(from: $0) == item.id }
            await performSchedule(
                item,
                clearsDeliveredBase: item.type != .habit,
                checksBudget: false,
                existingPendingRequests: itemPending,
                existingDeliveredIdentifiers: itemDelivered
            )
        }
        await warnIfOverBudget()
    }

    private func performCancel(
        _ id: UUID,
        clearsDelivered: Bool = true,
        existingPendingIdentifiers: [String]? = nil,
        existingDeliveredIdentifiers: [String]? = nil
    ) async {
        finishFailedSchedule(for: id)
        let pendingIdentifiers: [String]
        if let existingPendingIdentifiers {
            pendingIdentifiers = existingPendingIdentifiers
        } else {
            pendingIdentifiers = await identifiersInPendingRequests(for: id)
        }
        if !pendingIdentifiers.isEmpty {
            markIdentifiersPendingRemoval(pendingIdentifiers)
            safelyReusableIdentifiers.subtract(pendingIdentifiers)
            await center.removePendingRequests(withIdentifiers: pendingIdentifiers)
        }
        if clearsDelivered {
            let priorDeliveredIdentifiers: [String]
            if let existingDeliveredIdentifiers {
                priorDeliveredIdentifiers = existingDeliveredIdentifiers
            } else {
                priorDeliveredIdentifiers = []
            }
            let latestDeliveredIdentifiers = await identifiersInDeliveredNotifications(for: id)
            let deliveredIdentifiers = Array(
                Set(priorDeliveredIdentifiers).union(latestDeliveredIdentifiers)
            )
            if !deliveredIdentifiers.isEmpty {
                await center.removeDeliveredNotifications(
                    withIdentifiers: deliveredIdentifiers
                )
            }
            if !pendingIdentifiers.isEmpty {
                retainCancellationCleanup(
                    for: id,
                    identifiers: Set(pendingIdentifiers)
                )
            }
        }
    }

    /// Pending-request removal is fire-and-forget. Keep clearing the exact old
    /// delivered identifiers until those pending requests have actually left
    /// the queue. Because canceled identifiers are never reused, this cannot
    /// erase an alert from a later re-enabled reminder.
    private func retainCancellationCleanup(
        for id: UUID,
        identifiers: Set<String>,
        preservingDelivered preservedIdentifiers: Set<String> = []
    ) {
        cancellationCleanupIdentifiers[id, default: []].formUnion(identifiers)
        cancellationCleanupPreservedDeliveredIdentifiers[id, default: []]
            .formUnion(preservedIdentifiers)
        guard cancellationCleanupTasks[id] == nil else { return }
        cancellationCleanupTasks[id] = Task { @Sendable [weak self] in
            await self?.runCancellationCleanup(for: id)
        }
    }

    private func runCancellationCleanup(for id: UUID) async {
        defer {
            cancellationCleanupTasks[id] = nil
            cancellationCleanupIdentifiers[id] = nil
            cancellationCleanupPreservedDeliveredIdentifiers[id] = nil
        }
        while !Task.isCancelled {
            guard let identifiers = cancellationCleanupIdentifiers[id],
                  !identifiers.isEmpty else { return }
            let pending = Set(await center.pendingRequests().map(\.identifier))
            let preservedDelivered = cancellationCleanupPreservedDeliveredIdentifiers[id] ?? []
            let delivered = Set(await center.deliveredIdentifiers())
                .intersection(identifiers)
                .subtracting(preservedDelivered)
            if !delivered.isEmpty {
                await center.removeDeliveredNotifications(
                    withIdentifiers: Array(delivered)
                )
            }
            guard !pending.isDisjoint(with: identifiers) else {
                // The absence may be the notification naturally firing rather
                // than removal settling. Query delivered state once more after
                // observing absence so that transition is covered too.
                let finalDelivered = Set(await center.deliveredIdentifiers())
                    .intersection(identifiers)
                    .subtracting(preservedDelivered)
                if !finalDelivered.isEmpty {
                    await center.removeDeliveredNotifications(
                        withIdentifiers: Array(finalDelivered)
                    )
                }
                guard cancellationCleanupIdentifiers[id] == identifiers else {
                    continue
                }
                clearRemovalFences(identifiers)
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
        }
    }

    private func identifiersInPendingRequests(for id: UUID) async -> [String] {
        await center.pendingRequests().map(\.identifier).filter {
            Self.itemId(from: $0) == id
        }
    }

    private func identifiersInDeliveredNotifications(for id: UUID) async -> [String] {
        await center.deliveredIdentifiers().filter {
            Self.itemId(from: $0) == id
        }
    }

    private func markIdentifiersPendingRemoval<S: Sequence>(_ identifiers: S)
    where S.Element == String {
        identifiersPendingRemoval.formUnion(identifiers)
        persistRemovalFences()
    }

    private func clearRemovalFences<S: Sequence>(_ identifiers: S)
    where S.Element == String {
        identifiersPendingRemoval.subtract(identifiers)
        persistRemovalFences()
    }

    private func persistRemovalFences() {
        guard persistsRemovalFences else { return }
        UserDefaults.standard.set(
            identifiersPendingRemoval.sorted(),
            forKey: Self.removalFenceDefaultsKey
        )
    }

    private func retainFailedSchedule(
        _ item: Item,
        clearsDeliveredBase: Bool
    ) {
        let attempt = (failedScheduleIntents[item.id]?.attempt ?? 0) + 1
        failedScheduleIntents[item.id] = FailedScheduleIntent(
            item: item,
            clearsDeliveredBase: clearsDeliveredBase,
            attempt: attempt
        )
        failedScheduleRetryTasks[item.id]?.cancel()
        guard attempt <= 5 else { return }
        let delays = [500, 1_000, 2_000, 4_000, 8_000]
        let delay = delays[attempt - 1]
        failedScheduleRetryTasks[item.id] = Task { @Sendable [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(delay))
            } catch {
                return
            }
            await self?.retryFailedSchedule(for: item.id)
        }
    }

    private func retryFailedSchedule(for id: UUID) async {
        failedScheduleRetryTasks[id] = nil
        guard let intent = failedScheduleIntents[id] else { return }

        let previous = operationChain
        operationGeneration &+= 1
        let generation = operationGeneration
        let operation = Task { [self] in
            await previous?.value
            await performSchedule(
                intent.item,
                clearsDeliveredBase: intent.clearsDeliveredBase
            )
        }
        operationChain = operation
        await operation.value
        if operationGeneration == generation {
            operationChain = nil
        }
    }

    /// Failed intents remain durable in this actor after timed retries are
    /// exhausted. Any later queue-changing operation gives the most urgent one
    /// a fresh retry window, so a reminder does not remain stranded after a
    /// different item is canceled.
    private func retryExhaustedScheduleIfCapacityMayHaveChanged() async {
        guard operationChain == nil else { return }
        let exhausted = failedScheduleIntents
            .filter { id, intent in
                intent.attempt > 5 && failedScheduleRetryTasks[id] == nil
            }
            .min { lhs, rhs in
                let lhsDate = Self.schedulingPriorityDate(for: lhs.value.item)
                let rhsDate = Self.schedulingPriorityDate(for: rhs.value.item)
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.key.uuidString < rhs.key.uuidString
            }
        guard let (id, retained) = exhausted else { return }
        var refreshed = retained
        refreshed.attempt = 0
        failedScheduleIntents[id] = refreshed
        await retryFailedSchedule(for: id)
    }

    private func finishFailedSchedule(for id: UUID) {
        failedScheduleIntents.removeValue(forKey: id)
        failedScheduleRetryTasks.removeValue(forKey: id)?.cancel()
    }

    private nonisolated static func itemId(from identifier: String) -> UUID? {
        guard identifier.count >= 36 else { return nil }
        return UUID(uuidString: String(identifier.prefix(36)))
    }

    private nonisolated static func shouldSchedule(_ item: Item) -> Bool {
        guard item.deletedAt == nil,
              item.reminder?.enabled == true else { return false }
        if item.type == .habit {
            return !habitTriggers(for: item).isEmpty
        }
        return singleReminderFireDate(for: item) != nil
    }

    private nonisolated static func shouldPreserveDelivered(_ item: Item) -> Bool {
        guard item.deletedAt == nil,
              item.reminder?.enabled == true else { return false }
        if item.type == .habit {
            return !habitTriggers(for: item).isEmpty
        }
        guard effectiveFireDate(for: item) != nil else { return false }
        return !item.isComplete(at: .now)
    }

    private nonisolated static func schedulingPriorityDate(for item: Item) -> Date {
        if item.type == .habit {
            return habitTriggers(for: item)
                .compactMap { $0.trigger.nextTriggerDate() }
                .min() ?? .distantFuture
        }
        return singleReminderFireDate(for: item) ?? .distantFuture
    }

    private func makeContent(for item: Item) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = item.title
        let body = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { content.body = body }
        content.sound = .default
        content.threadIdentifier = item.listId
        content.userInfo[Self.durableRevisionKey] = Self.durableRevisionToken(for: item)
        return content
    }

    private nonisolated static func durableRevisionToken(for item: Item) -> String {
        String(Int64((item.modifiedAt.timeIntervalSince1970 * 1_000).rounded()))
    }

    /// Repeating calendar triggers for a habit, using the time-of-day from
    /// `item.due`. Gentle by design — no urgency, no guilt.
    ///
    /// The schedule is built from the habit's *normalized* cadence (daily /
    /// weekly / monthly) — the only cadences the habit UI offers, and the same
    /// basis `HabitCycle`/`HabitStats` bucket on. A legacy raw value (`hourly`,
    /// `weekdays`, `custom`, …) must never drive a reminder cadence the user
    /// can no longer see or edit. One trigger per habit also keeps the app far
    /// away from the 64-notification cap.
    nonisolated public static func habitTriggers(
        for item: Item
    ) -> [(suffix: String, trigger: UNCalendarNotificationTrigger)] {
        guard item.type == .habit, let raw = item.frequency, let due = item.due else { return [] }
        let frequency = raw.normalizedForHabit
        let cal = Calendar.current
        let time = cal.dateComponents([.hour, .minute], from: due)
        let hour = time.hour ?? 9
        let minute = time.minute ?? 0

        func trigger(_ build: (inout DateComponents) -> Void) -> UNCalendarNotificationTrigger {
            var dc = DateComponents()
            build(&dc)
            return UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        }

        switch frequency {
        case .daily:
            return [("", trigger { $0.hour = hour; $0.minute = minute })]
        case .weekly:
            let weekday = cal.component(.weekday, from: due)
            return [("", trigger { $0.weekday = weekday; $0.hour = hour; $0.minute = minute })]
        case .monthly:
            let day = cal.component(.day, from: due)
            return [("", trigger { $0.day = day; $0.hour = hour; $0.minute = minute })]
        default:
            return []  // unreachable: normalizedForHabit only yields the three cadences
        }
    }

    // MARK: - Helpers

    nonisolated static func singleReminderFireDate(for item: Item, now: Date = .now) -> Date? {
        guard item.type != .habit,
              item.deletedAt == nil,
              item.reminder?.enabled == true,
              !item.isComplete(at: now),
              let fireDate = effectiveFireDate(for: item),
              fireDate > now else {
            return nil
        }
        return fireDate
    }

    /// Computes the actual fire date taking `reminder.early` offset into
    /// account.
    private nonisolated static func effectiveFireDate(for item: Item) -> Date? {
        guard let due = item.due else { return nil }
        guard let early = item.reminder?.early else { return due }
        let cal = Calendar.current
        let component: Calendar.Component
        switch early.unit {
        case .minute: component = .minute
        case .hour:   component = .hour
        case .day:    component = .day
        case .week:   component = .weekOfYear
        case .month:  component = .month
        }
        return cal.date(byAdding: component, value: -early.value, to: due) ?? due
    }
}

extension NotificationScheduler: NotificationScheduling {}
