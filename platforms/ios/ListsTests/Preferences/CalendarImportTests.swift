import Foundation
import Testing
@testable import Lists

struct CalendarImportTests {
    private func source() -> CalendarImport.Values {
        .init(title: "Wash the Dog", body: "Original notes", start: Date(timeIntervalSince1970: 1000),
              end: Date(timeIntervalSince1970: 4600), allDay: false, timeZone: "UTC")
    }
    private func imported() -> Item {
        let values = source()
        var item = Item(type: .event, title: values.title, listId: "personal", due: values.start,
                        dueTimeZone: values.timeZone, end: values.end)
        item.body = values.body
        item.calendarImport = CalendarImport(connectionID: UUID(), sourceKey: "stable", localIdentifier: "local",
                                              calendarName: "Personal", baseline: values, checkedAt: .now)
        return item
    }
    @Test func untouchedFieldsUpdateWithoutChangingIdentityOrDestination() {
        var item = imported(); item.listId = "home"
        var source = source(); source.title = "Wash Penny"; source.start += 3600; source.end += 3600
        let result = CalendarImport.merge(source, into: item, now: .now)
        #expect(result.id == item.id)
        #expect(result.listId == "home")
        #expect(result.title == source.title)
        #expect(result.due == source.start)
        #expect(result.calendarImport?.conflicts.isEmpty == true)
    }
    @Test func localTitleAndTypeSurviveSourceChangesAndAcknowledgement() {
        var item = imported(); item.title = "Wash the Dog Penny"; item.type = .task; item.end = nil
        var source = source(); source.title = "Wash the Dog Saturday"; source.start += 3600; source.end += 3600
        let result = CalendarImport.merge(source, into: item, now: .now)
        #expect(result.title == item.title)
        #expect(result.type == .task)
        #expect(result.end == nil)
        #expect(result.due == source.start)
        #expect(result.calendarImport?.conflicts == [.title])
        let kept = CalendarImport.resolve(.title, useSource: false, item: result)
        #expect(CalendarImport.merge(source, into: kept, now: .now).calendarImport?.conflicts.isEmpty == true)
        let accepted = CalendarImport.resolve(.title, useSource: true, item: result)
        #expect(accepted.title == source.title)
    }
    @Test func localScheduleConflictsAndDetachedItemsDoNotChange() {
        var item = imported(); item.due = Date(timeIntervalSince1970: 9999)
        var source = source(); source.start += 100; source.end += 100
        let result = CalendarImport.merge(source, into: item, now: .now)
        #expect(result.due == item.due)
        #expect(result.calendarImport?.conflicts == [.schedule])
        item.calendarImport?.detached = true
        #expect(CalendarImport.merge(source, into: item, now: .now) == item)
    }
    @Test func metadataRoundTrips() throws {
        let item = imported()
        let decoded = try JSONDecoder().decode(Item.self, from: JSONEncoder().encode(item))
        #expect(decoded.calendarImport == item.calendarImport)
        let markdown = try FrontmatterCodec.encode(item)
        let reopened = try FrontmatterCodec.decode(markdown)
        #expect(reopened.calendarImport?.sourceKey == item.calendarImport?.sourceKey)
        #expect(reopened.calendarImport?.baseline == item.calendarImport?.baseline)
    }
}


@MainActor private final class FixtureCalendarSource: CalendarEventSource {
    var authorized = true
    var values: [CalendarConnectionEvent] = []
    func requestAccess() async throws -> Bool { authorized }
    func calendars() -> [CalendarConnectionSource] { [.init(id: "good", title: "Work", account: "Fixture")] }
    func events(calendarID: String, start: Date, end: Date) throws -> [CalendarConnectionEvent] {
        guard calendarID != "missing" else { throw CocoaError(.fileNoSuchFile) }
        return values
    }
}
@MainActor struct CalendarConnectionsTests {
    @Test func failingSourceDoesNotBlockHealthySourceAndRefreshPreservesLocalEditsAndDeletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CalendarConnections-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = FileStore(root: root.appendingPathComponent("Lists"))
        try await files.ensureRoot(); try await files.writeList(.makeInbox())
        let store = ItemStore(store: files); try await store.bootstrap()
        let file = root.appendingPathComponent("connections.json")
        let bad = CalendarConnections.Connection(calendarID: "missing", name: "Missing", listID: ItemList.inboxId, start: .distantPast, end: .distantFuture)
        let good = CalendarConnections.Connection(calendarID: "good", name: "Work", listID: ItemList.inboxId, start: .distantPast, end: .distantFuture)
        try JSONEncoder().encode([bad, good]).write(to: file)
        let source = FixtureCalendarSource()
        let start = Date.now
        source.values = [.init(key: "event", localIdentifier: "local", values: .init(title: "Source", body: "", start: start, end: start.addingTimeInterval(3600), allDay: false, timeZone: nil))]
        let service = CalendarConnections(source: source, file: file)
        await service.refresh(store: store)
        #expect(service.connectionErrors[bad.id] != nil)
        #expect(service.connectionErrors[good.id] == nil)
        #expect(service.connections.first(where: { $0.id == good.id })?.lastRefresh != nil)
        var imported = try #require(store.items.first(where: { $0.calendarImport?.connectionID == good.id }))
        imported.title = "My title"; try await store.update(imported)
        source.values = [.init(key: "event", localIdentifier: "local", values: .init(title: "Changed source", body: "New notes", start: start, end: start.addingTimeInterval(3600), allDay: false, timeZone: nil))]
        await service.refresh(store: store)
        #expect(store.item(imported.id)?.title == "My title")
        #expect(store.item(imported.id)?.body == "New notes")
        #expect(store.item(imported.id)?.calendarImport?.conflicts.contains(.title) == true)
        #expect(store.items.filter { $0.calendarImport?.connectionID == good.id }.count == 1)
        try await store.softDelete(imported.id)
        await service.refresh(store: store)
        #expect(store.item(imported.id)?.deletedAt != nil)
        #expect(store.items.filter { $0.calendarImport?.connectionID == good.id }.count == 1)
        let restored = CalendarConnections(source: source, file: file)
        #expect(restored.connections.first(where: { $0.id == good.id })?.imported["event"] == imported.id)
    }
}
