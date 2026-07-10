import Foundation
import Testing
@testable import Lists

@MainActor
struct HabitTypeConversionTests {
    @Test func savingConvertedHabitPreservesDormantDataAndNormalizesCadence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HabitTypeConversion-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let completion = HabitCompletion(at: Date(timeIntervalSince1970: 1_800_000_000))

        var item = Item(
            type: .habit,
            title: "Stretch",
            body: "Dormant notes",
            listId: ItemList.inboxId,
            frequency: .hourly,
            goalPerCycle: 0,
            completions: [completion]
        )
        try await store.add(item)

        item = try #require(store.item(item.id))
        #expect(item.body == "Dormant notes")
        #expect(item.completions == [completion])
        #expect(item.frequency == .daily)
        #expect(item.goalPerCycle == 1)
    }

    @Test func taskHabitTaskRoundTripPreservesBodyAndCompletionHistory() {
        let completion = HabitCompletion(at: Date(timeIntervalSince1970: 1_800_000_000))
        var item = Item(
            type: .task,
            title: "Stretch",
            body: "Bring this back when it is a task again",
            listId: ItemList.inboxId,
            completions: [completion]
        )

        ItemTypeTransition.apply(.habit, to: &item)
        #expect(item.type == .habit)
        #expect(item.body == "Bring this back when it is a task again")
        #expect(item.completions == [completion])

        ItemTypeTransition.apply(.task, to: &item)
        #expect(item.type == .task)
        #expect(item.body == "Bring this back when it is a task again")
        #expect(item.completions == [completion])
    }
}
