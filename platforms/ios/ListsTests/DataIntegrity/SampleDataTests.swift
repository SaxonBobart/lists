import Foundation
import Testing
@testable import Lists

struct SampleDataTests {
    private struct NoopNotificationScheduler: NotificationScheduling {
        func schedule(_ item: Item) async {}
        func cancel(_ id: UUID) async {}
    }

    @Test func seededHabitsDoNotPersistMarkdownBodies() {
        let items = SampleData.seedItems(
            inboxId: ItemList.inboxId,
            now: ISO8601.date(from: "2026-06-23T10:00:00.000Z")!
        )

        let habits = items.filter { $0.type == .habit }

        #expect(!habits.isEmpty)
        #expect(habits.allSatisfy { $0.body.isEmpty })
    }

    @Test func seededContentDoesNotAdvertiseNonCurrentProducts() {
        let items = SampleData.seedItems(
            inboxId: ItemList.inboxId,
            now: ISO8601.date(from: "2026-06-23T10:00:00.000Z")!
        )
        let lists = SampleData.seedLists(
            now: ISO8601.date(from: "2026-06-23T10:00:00.000Z")!
        )
        let visibleSnippets = items.map { "\($0.title)\n\($0.body)" } + lists.map(\.name)
        let visibleContent = visibleSnippets.joined(separator: "\n")

        for nonCurrentTerm in [
            "iCal",
            "sync",
            "shared lists",
            "web companion",
            "AlarmKit",
            "side app",
            "export flow",
            "rebuild cache",
            "sprint 1",
            "design schema",
            "build editor",
            "library rebuild"
        ] {
            #expect(
                !visibleContent.localizedCaseInsensitiveContains(nonCurrentTerm),
                "Seed data should demo current behavior, not advertise non-current product: \(nonCurrentTerm)"
            )
        }
    }

    @Test func seededContentIncludesInspectableRecurrenceHistory() {
        let items = SampleData.seedItems(
            inboxId: ItemList.inboxId,
            now: ISO8601.date(from: "2026-06-23T10:00:00.000Z")!
        )
        let recurringDemos = items.filter { !$0.recurrenceOccurrences.isEmpty }

        #expect(recurringDemos.count >= 2)
        #expect(recurringDemos.allSatisfy {
            $0.recurrence != nil
                && $0.due != nil
                && $0.recurrenceOccurrences.filter { $0.status == .open }.count == 1
        })
        #expect(recurringDemos.contains { item in
            item.recurrenceOccurrences.contains { $0.status == .completed }
                && item.recurrenceOccurrences.contains { $0.status == .missed }
        })
    }

    @MainActor
    @Test func seededLibraryIncludesEachListPresentation() {
        let defaultsName = "SampleDataTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let lists = SampleData.seedLists()
        let preferences = ListViewPreferences(defaults: defaults)
        SampleData.applyPresentationDefaults(to: preferences)

        #expect(lists.contains { $0.id == SampleData.listDemoId })
        #expect(lists.contains {
            $0.id == SampleData.columnsDemoId && !$0.sections.isEmpty
        })
        #expect(lists.contains { $0.id == SampleData.calendarDemoId })
        #expect(preferences.viewMode(for: SampleData.listDemoId) == .list)
        #expect(preferences.viewMode(for: SampleData.columnsDemoId) == .columns)
        #expect(preferences.viewMode(for: SampleData.calendarDemoId) == .calendar)
    }

    @MainActor
    @Test func onDeviceResetReplacesExistingLibraryWithSamples() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SampleReset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let fileStore = FileStore(root: root)
        let store = ItemStore(store: fileStore, scheduler: NoopNotificationScheduler())
        try await store.bootstrap()
        let custom = Item(
            type: .task,
            title: "Should be replaced",
            listId: ItemList.inboxId
        )
        try await store.add(custom)

        try await store.replaceWithSampleData(
            now: ISO8601.date(from: "2026-06-23T10:00:00.000Z")!
        )

        #expect(!store.items.contains { $0.id == custom.id })
        #expect(store.lists.contains { $0.id == SampleData.listDemoId })
        #expect(store.lists.contains { $0.id == SampleData.columnsDemoId })
        #expect(store.lists.contains { $0.id == SampleData.calendarDemoId })
        #expect(store.items.contains { $0.listId == SampleData.columnsDemoId })
        #expect(store.items.contains { $0.listId == SampleData.calendarDemoId })

        let reloaded = ItemStore(store: FileStore(root: root), scheduler: NoopNotificationScheduler())
        try await reloaded.bootstrap()
        #expect(!reloaded.items.contains { $0.id == custom.id })
        #expect(reloaded.lists.map(\.id).contains(SampleData.calendarDemoId))
    }
}
