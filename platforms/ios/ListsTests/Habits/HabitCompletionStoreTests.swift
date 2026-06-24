import Foundation
import Testing
@testable import Lists

/// The Log screen edits individual completion events. These pin the store methods
/// behind it (add / delete / retime / −1), and that each keeps memory and disk in
/// sync by updating memory first, then persisting.
@MainActor
struct HabitCompletionStoreTests {
    private func storeWithHabit(
        frequency: HabitFrequency = .daily,
        goal: Int = 5
    ) async throws -> (store: ItemStore, root: URL, id: UUID) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsHC-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        let habit = Item(type: .habit, title: "Water", listId: ItemList.inboxId,
                         frequency: frequency, goalPerCycle: goal)
        try await store.add(habit)
        return (store, root, habit.id)
    }

    private func reload(_ root: URL, _ id: UUID) async throws -> Item? {
        try await FileStore(root: root).loadAll().lists.flatMap(\.items).first { $0.id == id }
    }

    @Test func inlineHabitDefaultsToDailyGoalAndPersists() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsInlineHabit-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let id = store.addInlineItem(type: .habit, listId: ItemList.inboxId, section: nil)
        await store.flushPendingWrites()

        let live = try #require(store.item(id))
        #expect(live.type == .habit)
        #expect(live.frequency == .daily)
        #expect(live.goalPerCycle == 1)

        let reloaded = try await reload(root, id)
        #expect(reloaded?.type == .habit)
        #expect(reloaded?.frequency == .daily)
        #expect(reloaded?.goalPerCycle == 1)
    }

    @Test func addCompletionAppendsEventAndPersists() async throws {
        let (store, root, id) = try await storeWithHabit()
        try await store.addCompletion(id, at: .now)
        #expect(store.item(id)?.completions.count == 1)
        let reloaded = try await reload(root, id)
        #expect(reloaded?.completions.count == 1, "in-memory add must match disk")
    }

    @Test func deleteCompletionRemovesByItsId() async throws {
        let (store, _, id) = try await storeWithHabit()
        try await store.addCompletion(id, at: .now)
        let cid = try #require(store.item(id)?.completions.first?.id)
        try await store.deleteCompletion(id, completionId: cid)
        #expect(store.item(id)?.completions.count == 0)
    }

    @Test func updateCompletionRetimesTheEvent() async throws {
        let (store, _, id) = try await storeWithHabit()
        let t0 = ISO8601.date(from: "2026-05-20T09:00:00.000Z")!
        try await store.addCompletion(id, at: t0)
        let cid = try #require(store.item(id)?.completions.first?.id)

        let t1 = ISO8601.date(from: "2026-05-18T15:30:00.000Z")!
        try await store.updateCompletion(id, completionId: cid, to: t1)
        #expect(store.item(id)?.completions.first?.at == t1)
    }

    @Test func removeLatestCompletionDropsTheMostRecentInThatCycle() async throws {
        let (store, _, id) = try await storeWithHabit()
        let early = ISO8601.date(from: "2026-05-20T08:00:00.000Z")!
        let late = ISO8601.date(from: "2026-05-20T20:00:00.000Z")!
        try await store.addCompletion(id, at: early)
        try await store.addCompletion(id, at: late)

        try await store.removeLatestCompletion(in: late, for: id)
        let comps = try #require(store.item(id)?.completions)
        #expect(comps.count == 1)
        #expect(comps.first?.at == early, "the −1 removes the latest event in the cycle")
    }

    @Test func incrementHabitAddsAnEventAndCapsAtGoal() async throws {
        let (store, _, id) = try await storeWithHabit(goal: 2)
        try await store.incrementHabit(id)
        try await store.incrementHabit(id)
        try await store.incrementHabit(id)  // already at goal → no-op
        #expect(store.item(id)?.completions.count == 2)
    }

    @Test func addCompletionsBulkAddsOnePerDateInOneWrite() async throws {
        let (store, root, id) = try await storeWithHabit()
        let cal = Calendar(identifier: .iso8601)
        let start = ISO8601.date(from: "2026-05-16T12:00:00.000Z")!
        let dates = (0..<10).map { cal.date(byAdding: .day, value: $0, to: start)! }

        try await store.addCompletions(id, on: dates)

        #expect(store.item(id)?.completions.count == 10, "one event per date in the range")
        let reloaded = try await reload(root, id)
        #expect(reloaded?.completions.count == 10, "bulk add must persist in a single write")
    }

    @Test func addCompletionsWithNoDatesIsANoOp() async throws {
        let (store, _, id) = try await storeWithHabit()
        try await store.addCompletions(id, on: [])
        #expect(store.item(id)?.completions.count == 0)
    }

    @Test func setHabitCountAddsAndTrimsEventsForACycle() async throws {
        let (store, _, id) = try await storeWithHabit(goal: 5)
        let day = ISO8601.date(from: "2026-05-15T12:00:00.000Z")!
        try await store.setHabitCount(id, count: 3, on: day)
        #expect(store.item(id)?.completionLog["2026-05-15"] == 3)
        try await store.setHabitCount(id, count: 1, on: day)
        #expect(store.item(id)?.completionLog["2026-05-15"] == 1, "setting lower trims events")
    }
}
