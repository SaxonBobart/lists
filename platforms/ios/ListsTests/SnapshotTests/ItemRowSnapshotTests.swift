import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lists

final class ItemRowSnapshotTests: XCTestCase {
    @MainActor
    func testCompactSublistNavigation_Narrow() {
        let child = ItemList(id: "project", name: "Project workspace", icon: "folder", color: .blue,
                             createdAt: .now, modifiedAt: .now, position: 0)
        let view = VStack(spacing: 0) {
            CVSubListsHeaderRow(expanded: true, onToggle: {})
            CVSubListChildRow(child: child, openItemCount: 2, onOpen: {})
        }
        .background(Color(.systemBackground))
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 320, height: 100),
            traits: SnapshotEnvironment.fixedDarkTraits))
    }

    @MainActor
    func testCompactSublistNavigation_LargerText() {
        let child = ItemList(id: "research", name: "Research and references", icon: "folder", color: .blue,
                             createdAt: .now, modifiedAt: .now, position: 0)
        let view = VStack(spacing: 0) {
            CVSubListsHeaderRow(expanded: true, onToggle: {})
            CVSubListChildRow(child: child, openItemCount: 12, onOpen: {})
        }
        .dynamicTypeSize(.accessibility2)
        .background(Color(.systemBackground))
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 320, height: 200),
            traits: SnapshotEnvironment.fixedDarkTraits))
    }

    @MainActor
    func testInlineDocumentProperties_Dark() async throws {
        let store = try await TestStore.seeded()
        let note = Item(type: .note, title: "Project notes", body: "Brief, drawings, and next steps.", listId: "inbox")
        try await store.add(note)
        let controller = UIHostingController(rootView: ItemDetailSheet(item: note, store: store))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.layoutIfNeeded()
        // Let the UIKit-backed Markdown editor finish its initial measurement.
        try await Task.sleep(for: .milliseconds(300))
        controller.view.layoutIfNeeded()
        // Native glass toolbar blur varies slightly between render passes;
        // retain pixel checks for the property layout with a small tolerance.
        assertSnapshot(of: controller, as: .image(drawHierarchyInKeyWindow: true, precision: 0.995,
            size: CGSize(width: 393, height: 852), traits: SnapshotEnvironment.fixedDarkTraits))
    }

    @MainActor
    func testTrailingAttachmentControlsAndChild_Dark() async throws {
        let store = try await TestStore.seeded()
        let note = Item(type: .note, title: "Project notes", body: "Brief, drawings, and next steps.\n[Brief](Attachments/brief.pdf)", listId: "inbox")
        let child = Item(type: .note, title: "Meeting notes", body: "Decisions and follow-up ideas.", listId: "inbox", parentId: note.id)
        let reference = Item(type: .note, title: "Reference note", body: "[Drawing](Attachments/drawing.png)", listId: "inbox")
        try await store.add(note)
        try await store.add(child)
        try await store.add(reference)
        let view = VStack(alignment: .leading, spacing: 0) {
            ItemRow(item: note, isOverdue: false, store: store, onToggle: {}, showCollapseControl: true)
            ItemRow(item: child, isOverdue: false, store: store, onToggle: {}, indent: 1)
            ItemRow(item: reference, isOverdue: false, store: store, onToggle: {}, showCollapseControl: true)
        }
        .background(Color(.systemBackground))
        assertSnapshot(of: view, as: .image(drawHierarchyInKeyWindow: true,
            layout: .fixed(width: 393, height: 300), traits: SnapshotEnvironment.fixedDarkTraits))
    }

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

    @MainActor
    func testReminderAndAlarmCountAsFacts() {
        let reminderOnly = Item(
            type: .task,
            title: "Take the bins out",
            listId: "home",
            reminder: Reminder(enabled: true)
        )
        let alarmOnly = Item(
            type: .task,
            title: "Call back",
            listId: "work",
            triggers: Triggers(alarm: TriggerToggle(enabled: true))
        )

        XCTAssertTrue(ItemFactChips.hasFacts(for: reminderOnly))
        XCTAssertTrue(ItemFactChips.hasFacts(for: alarmOnly))
    }
}
