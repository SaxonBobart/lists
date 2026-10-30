import Foundation
import Testing
@testable import Lists

struct SampleDataTests {
    private struct NoopNotificationScheduler: NotificationScheduling {
        func schedule(_ item: Item) async {}
        func cancel(_ id: UUID) async {}
    }

    @Test func samplesContainOnlySupportedItemTypes() {
        let items = SampleData.seedItems(
            inboxId: ItemList.inboxId,
            now: ISO8601.date(from: "2026-06-23T10:00:00.000Z")!
        )

        #expect(!items.isEmpty)
        #expect(items.allSatisfy { [.task, .note, .event].contains($0.type) })
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
        let parent = try #require(store.items.first { $0.listId == "attachment-samples" && $0.title == "Project notes" })
        let references = MarkdownMediaReference.distinctReferences(in: parent.body)
        #expect(references.count == 2)
        #expect(store.items.filter { $0.parentId == parent.id }.map(\.type).contains(.note))
        #expect(store.items.filter { $0.parentId == parent.id }.map(\.type).contains(.task))
        for reference in references {
            let url = try await store.attachmentURL(for: reference.path)
            let bytes = try Data(contentsOf: url)
            #expect(!bytes.isEmpty)
            if url.pathExtension == "pdf" { #expect(bytes.starts(with: Data("%PDF".utf8))) }
            if url.pathExtension == "png" { #expect(bytes.starts(with: Data([137, 80, 78, 71]))) }
        }
        let standalone = try #require(store.standaloneFiles.first { $0.listID == "attachment-samples" })
        #expect(standalone.fileName == "Unlinked budget.pdf")
        let reference = try #require(store.items.first { $0.listId == "attachment-samples" && $0.title == "Reference note" })
        #expect(!store.items.contains { $0.parentId == reference.id })
        #expect(MarkdownMediaReference.distinctReferences(in: reference.body).count == 1)
        let order = store.collectionEntries(in: "attachment-samples")
        #expect(order.first == .item(parent.id))
        #expect(order.dropFirst().first == .file(standalone.id))
        let movedDrawing = try #require(store.standaloneFiles.first { $0.listID == "attachment-file-moves" })
        #expect(movedDrawing.fileName == "Moved drawing.png")
        let drawingURL = try await store.standaloneFileURL(movedDrawing)
        #expect(try Data(contentsOf: drawingURL).starts(with: Data([137, 80, 78, 71])))
        #expect(!store.items.contains { $0.title == standalone.fileName })
        let standaloneURL = try await store.standaloneFileURL(standalone)
        #expect(try Data(contentsOf: standaloneURL).starts(with: Data("%PDF".utf8)))

        let reloaded = ItemStore(store: FileStore(root: root), scheduler: NoopNotificationScheduler())
        try await reloaded.bootstrap()
        #expect(!reloaded.items.contains { $0.id == custom.id })
        #expect(reloaded.lists.map(\.id).contains(SampleData.calendarDemoId))
        #expect(reloaded.standaloneFiles == store.standaloneFiles)
        #expect(MarkdownMediaReference.distinctReferences(in: try #require(reloaded.item(parent.id)).body).count == 2)

        try await store.replaceWithSampleData()
        #expect(store.lists.filter { $0.id == "attachment-samples" }.count == 1)
        #expect(store.items.filter { $0.listId == "attachment-samples" }.count == 5)
        #expect(store.standaloneFiles.filter { $0.listID == "attachment-samples" }.count == 1)
    }
}
