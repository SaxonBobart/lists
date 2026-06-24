import Foundation
import Testing
@testable import Lists

@MainActor
struct HabitTypeConversionTests {
    @Test func savingConvertedHabitDropsNotesAndNormalizesCadence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HabitTypeConversion-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        var item = Item(
            type: .habit,
            title: "Stretch",
            body: "Legacy notes should not survive habit conversion",
            listId: ItemList.inboxId,
            frequency: .hourly,
            goalPerCycle: 0
        )
        try await store.add(item)

        item = try #require(store.item(item.id))
        #expect(item.body == "")
        #expect(item.frequency == .daily)
        #expect(item.goalPerCycle == 1)
    }
}
