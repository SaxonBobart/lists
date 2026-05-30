import XCTest
import SwiftUI
@testable import Lists

/// Render smoke test for the redesigned detail screen. The Overview's stats are
/// anchored to "now" (consistency, streak, heatmap), so a committed image
/// snapshot would drift daily — instead this just forces SwiftUI to evaluate the
/// view body in a window and asserts it builds without crashing. The numbers
/// themselves are covered by HabitStatsTests; the editing flows by
/// HabitCompletionStoreTests.
@MainActor
final class HabitDetailViewRenderTests: XCTestCase {

    /// Forces SwiftUI to evaluate the view body and lay it out (rasterizing it),
    /// which surfaces any crash in the cards, stats, heatmap, or log grouping.
    private func host(_ view: some View) {
        let renderer = ImageRenderer(content: view.frame(width: 393, height: 852))
        renderer.scale = 2
        XCTAssertNotNil(renderer.uiImage, "the detail view body must render without crashing")
    }

    func testHabitDetailRendersWithHistory() async throws {
        let store = try await TestStore.seeded()
        var habit = Item(type: .habit, title: "Drink water", listId: ItemList.inboxId,
                         frequency: .daily, goalPerCycle: 3)
        habit.completions = (0..<10).flatMap { dayOffset in
            (0..<2).map { _ in HabitCompletion(at: Date().addingTimeInterval(Double(-dayOffset) * 86_400)) }
        }
        try await store.add(habit)

        host(HabitDetailView(item: habit, store: store))
    }

    func testFlexibleWeeklyHabitDetailRenders() async throws {
        let store = try await TestStore.seeded()
        var habit = Item(type: .habit, title: "Gym", listId: ItemList.inboxId,
                         frequency: .weekly, goalPerCycle: 3)
        habit.flexibleGoal = true
        habit.completions = [HabitCompletion(at: .now)]
        try await store.add(habit)

        host(HabitDetailView(item: habit, store: store))
    }

    func testMonthlyHabitDetailRendersMonthGrid() async throws {
        let store = try await TestStore.seeded()
        var habit = Item(type: .habit, title: "Pay rent", listId: ItemList.inboxId,
                         frequency: .monthly, goalPerCycle: 1)
        habit.completions = (0..<6).map { HabitCompletion(at: Date().addingTimeInterval(Double(-$0) * 30 * 86_400)) }
        try await store.add(habit)

        host(HabitDetailView(item: habit, store: store))
    }

    func testEmptyHabitDetailRenders() async throws {
        let store = try await TestStore.seeded()
        let habit = Item(type: .habit, title: "Meditate", listId: ItemList.inboxId,
                         frequency: .daily, goalPerCycle: 1)
        try await store.add(habit)

        host(HabitDetailView(item: habit, store: store))
    }
}
