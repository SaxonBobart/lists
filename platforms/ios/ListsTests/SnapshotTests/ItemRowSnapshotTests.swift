import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lists

final class ItemRowSnapshotTests: XCTestCase {

    private struct Fixtures {
        let store: ItemStore
        let baseTask: Item
        let doneTask: Item
        let habit: Item
        let note: Item
        let flaggedTask: Item
        let highPriorityTask: Item
        let dueTask: Item
        let taggedTask: Item
    }

    @MainActor
    private func makeFixtures() async throws -> Fixtures {
        let store = try await TestStore.seeded()
        let listId = "work"

        let baseTask = Item(
            type: .task,
            title: "Email Sarah about onboarding",
            listId: listId
        )

        let doneTask = Item(
            type: .task,
            title: "Submit timesheet",
            listId: listId,
            done: true,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let habit = Item(
            type: .habit,
            title: "Read 30 minutes",
            listId: "personal",
            frequency: .daily,
            goalPerCycle: 3,
            completions: [HabitCompletion(at: .now)]
        )

        let note = Item(
            type: .note,
            title: "Roadmap ideas",
            body: "Rough sketch of upcoming projects.",
            listId: "projects"
        )

        let flaggedTask = Item(
            type: .task,
            title: "Pay phone bill",
            listId: listId,
            flagged: true
        )

        let highPriorityTask = Item(
            type: .task,
            title: "Submit production hotfix",
            listId: listId,
            priority: .high
        )

        let dueTask = Item(
            type: .task,
            title: "Call Mum",
            listId: "personal",
            due: Date(timeIntervalSince1970: 1_700_000_000),
            dueAllDay: false
        )

        let taggedTask = Item(
            type: .task,
            title: "Renew passport",
            listId: "personal",
            tags: ["admin", "health"]
        )

        return Fixtures(
            store: store,
            baseTask: baseTask,
            doneTask: doneTask,
            habit: habit,
            note: note,
            flaggedTask: flaggedTask,
            highPriorityTask: highPriorityTask,
            dueTask: dueTask,
            taggedTask: taggedTask
        )
    }

    @MainActor
    private func host(_ item: Item, store: ItemStore, isOverdue: Bool = false) -> UIHostingController<some View> {
        let view = ItemRow(item: item, isOverdue: isOverdue, store: store, onToggle: {})
            .background(Color(.systemBackground))
        let vc = UIHostingController(rootView: view)
        vc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 120)
        return vc
    }

    @MainActor
    func testTaskOpen_iPhone16_Light() async throws {
        let f = try await makeFixtures()
        assertSnapshot(of: host(f.baseTask, store: f.store), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testTaskOpen_iPhone16_Dark() async throws {
        let f = try await makeFixtures()
        assertSnapshot(
            of: host(f.baseTask, store: f.store),
            as: .image(on: SnapshotEnvironment.iPhone16Light, traits: SnapshotEnvironment.darkTraits)
        )
    }

    @MainActor
    func testTaskOpen_iPhone16_A11yLarge() async throws {
        let f = try await makeFixtures()
        assertSnapshot(
            of: host(f.baseTask, store: f.store),
            as: .image(on: SnapshotEnvironment.iPhone16Light, traits: SnapshotEnvironment.a11yLargeTraits)
        )
    }

    @MainActor
    func testTaskDone_iPhone16_Light() async throws {
        let f = try await makeFixtures()
        assertSnapshot(of: host(f.doneTask, store: f.store), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testHabit_iPhone16_Light() async throws {
        let f = try await makeFixtures()
        assertSnapshot(of: host(f.habit, store: f.store), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testNote_iPhone16_Light() async throws {
        let f = try await makeFixtures()
        assertSnapshot(of: host(f.note, store: f.store), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testFlagged_iPhone16_Light() async throws {
        let f = try await makeFixtures()
        assertSnapshot(of: host(f.flaggedTask, store: f.store), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testHighPriority_iPhone16_Light() async throws {
        let f = try await makeFixtures()
        assertSnapshot(of: host(f.highPriorityTask, store: f.store), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testWithDueDate_iPhone16_Light() async throws {
        let f = try await makeFixtures()
        assertSnapshot(of: host(f.dueTask, store: f.store), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testWithTags_iPhone16_Light() async throws {
        let f = try await makeFixtures()
        assertSnapshot(of: host(f.taggedTask, store: f.store), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }
}
