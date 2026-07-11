import SnapshotTesting
import SwiftUI
import XCTest
@testable import Lists

/// Visual contracts for the progress-first habit detail. These replace the old
/// `view != nil` smoke checks, which could pass while the actual screen clipped,
/// exposed the wrong hierarchy, or became unusable at large text sizes.
@MainActor
final class HabitDetailViewSnapshotTests: XCTestCase {
    private let now = ISO8601.date(from: "2026-07-11T12:00:00.000Z")!

    private func host(
        _ habit: Item,
        store: ItemStore
    ) -> UIHostingController<some View> {
        let view = HabitDetailView(
            item: habit,
            store: store,
            now: now,
            notificationStatusProvider: { .enabled },
            requestNotificationAuthorization: { true }
        )
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        return controller
    }

    private func makeDailyHabit(store: ItemStore) async throws -> Item {
        let calendar = Calendar(identifier: .iso8601)
        var habit = Item(
            type: .habit,
            title: "Drink water",
            listId: ItemList.inboxId,
            createdAt: now.addingTimeInterval(-14 * 24 * 3_600),
            due: ISO8601.date(from: "2026-07-11T09:00:00.000Z"),
            reminder: Reminder(enabled: true),
            frequency: .daily,
            goalPerCycle: 3,
            showStreak: true
        )
        habit.dueTimeZone = "Australia/Brisbane"
        habit.completions = (0..<12).flatMap { dayOffset -> [HabitCompletion] in
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else {
                return []
            }
            let count = dayOffset.isMultiple(of: 3) ? 2 : 3
            return (0..<count).map { completionOffset in
                HabitCompletion(at: day.addingTimeInterval(Double(completionOffset * 1_800)))
            }
        }
        try await store.add(habit)
        return habit
    }

    func testProgress_iPhone16_Light() async throws {
        let store = try await TestStore.seeded()
        let habit = try await makeDailyHabit(store: store)

        assertSnapshot(
            of: host(habit, store: store),
            as: .image(
                on: SnapshotEnvironment.iPhone16Light,
                drawHierarchyInKeyWindow: true
            )
        )
    }

    func testProgress_iPhone16_Dark() async throws {
        let store = try await TestStore.seeded()
        let habit = try await makeDailyHabit(store: store)

        assertSnapshot(
            of: host(habit, store: store),
            as: .image(
                on: SnapshotEnvironment.iPhone16Light,
                drawHierarchyInKeyWindow: true,
                traits: SnapshotEnvironment.darkTraits
            )
        )
    }

    func testProgress_iPhone16_A11yLarge() async throws {
        let store = try await TestStore.seeded()
        let habit = try await makeDailyHabit(store: store)

        assertSnapshot(
            of: host(habit, store: store),
            as: .image(
                on: SnapshotEnvironment.iPhone16Light,
                drawHierarchyInKeyWindow: true,
                traits: SnapshotEnvironment.a11yLargeTraits
            )
        )
    }
}
