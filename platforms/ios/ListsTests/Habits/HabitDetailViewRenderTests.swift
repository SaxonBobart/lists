import SwiftUI
import Testing
import UIKit
@testable import Lists

/// Render smoke test for the redesigned detail screen. The Overview's stats are
/// anchored to "now" (consistency, streak, heatmap), so a committed image
/// snapshot would drift daily — instead this just forces SwiftUI to evaluate the
/// view body in a window and asserts it builds without crashing. The numbers
/// themselves are covered by HabitStatsTests; the editing flows by
/// HabitCompletionStoreTests.
@MainActor
struct HabitDetailViewRenderTests {

    /// Forces SwiftUI to evaluate the view body and lay it out in a real
    /// window, which surfaces any crash in the cards, stats, heatmap, or log
    /// grouping. Hosted via `UIHostingController` rather than `ImageRenderer`:
    /// the OS 27 SwiftUI runtime hits an internal assertion tearing down an
    /// `ImageRenderer`'s view graph under XCTest (AppearanceEffect.willRemove →
    /// UpdateGroup.enqueueAction), which killed the whole suite.
    private func host(_ view: some View) {
        let frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let controller = UIHostingController(rootView: view.frame(width: 393, height: 852))
        // Attach to the test host app's window scene when one exists (the
        // scene-less fallback still evaluates the body — just without
        // appearance callbacks).
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:))
        if let window {
            window.frame = frame
            window.rootViewController = controller
            window.makeKeyAndVisible()
        }
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        #expect(controller.view != nil, "the detail view body must build and lay out without crashing")
        window?.isHidden = true
        window?.rootViewController = nil
    }

    @Test func habitDetailRendersWithHistory() async throws {
        let store = try await TestStore.seeded()
        var habit = Item(type: .habit, title: "Drink water", listId: ItemList.inboxId,
                         frequency: .daily, goalPerCycle: 3)
        habit.completions = (0..<10).flatMap { dayOffset in
            (0..<2).map { _ in HabitCompletion(at: Date().addingTimeInterval(Double(-dayOffset) * 86_400)) }
        }
        try await store.add(habit)

        host(HabitDetailView(item: habit, store: store))
    }

    @Test func flexibleWeeklyHabitDetailRenders() async throws {
        let store = try await TestStore.seeded()
        var habit = Item(type: .habit, title: "Gym", listId: ItemList.inboxId,
                         frequency: .weekly, goalPerCycle: 3)
        habit.flexibleGoal = true
        habit.completions = [HabitCompletion(at: .now)]
        try await store.add(habit)

        host(HabitDetailView(item: habit, store: store))
    }

    @Test func monthlyHabitDetailRendersMonthGrid() async throws {
        let store = try await TestStore.seeded()
        var habit = Item(type: .habit, title: "Pay rent", listId: ItemList.inboxId,
                         frequency: .monthly, goalPerCycle: 1)
        habit.completions = (0..<6).map { HabitCompletion(at: Date().addingTimeInterval(Double(-$0) * 30 * 86_400)) }
        try await store.add(habit)

        host(HabitDetailView(item: habit, store: store))
    }

    @Test func emptyHabitDetailRenders() async throws {
        let store = try await TestStore.seeded()
        let habit = Item(type: .habit, title: "Meditate", listId: ItemList.inboxId,
                         frequency: .daily, goalPerCycle: 1)
        try await store.add(habit)

        host(HabitDetailView(item: habit, store: store))
    }
}
