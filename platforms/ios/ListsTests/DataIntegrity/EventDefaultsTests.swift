import Foundation
import Testing
@testable import Lists

struct EventDefaultsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @MainActor
    private func emptyStore() async throws -> ItemStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsEventDefaults-\(UUID().uuidString)")
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(ItemList(
            id: ItemList.inboxId,
            name: "Inbox",
            icon: "tray",
            color: .blue,
            createdAt: .now,
            modifiedAt: .now,
            position: 0
        ))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        return store
    }

    @Test func defaultStartUsesNextTopOfHour() {
        let now = ISO8601.date(from: "2026-06-23T09:42:00.000Z")!

        let start = EventDefaults.defaultStart(now: now, calendar: calendar)

        #expect(hourMinuteString(from: start) == "2026-06-23T10:00")
    }

    @Test func normalizeTimedEventSeedsStartAndOneHourEnd() throws {
        var event = Item(type: .event, title: "Call", listId: "inbox")
        let now = ISO8601.date(from: "2026-06-23T09:42:00.000Z")!

        EventDefaults.normalize(&event, now: now, calendar: calendar)

        let due = try #require(event.due)
        let end = try #require(event.end)
        #expect(hourMinuteString(from: due) == "2026-06-23T10:00")
        #expect(abs(end.timeIntervalSince(due) - 3_600) <= 1)
        #expect(!event.dueAllDay)
    }

    @Test func normalizeMovesEndAfterStart() throws {
        let start = ISO8601.date(from: "2026-06-23T09:00:00.000Z")!
        var event = Item(
            type: .event,
            title: "Call",
            listId: "inbox",
            due: start,
            end: start.addingTimeInterval(-600)
        )

        EventDefaults.normalize(&event, calendar: calendar)

        let end = try #require(event.end)
        #expect(abs(end.timeIntervalSince(start) - 3_600) <= 1)
    }

    @Test func normalizeAllDayEventWithStartSeedsOneDayEnd() throws {
        let start = ISO8601.date(from: "2026-06-23T00:00:00.000Z")!
        var event = Item(type: .event, title: "Conference", listId: "inbox", due: start)
        event.dueAllDay = true

        EventDefaults.normalize(&event, calendar: calendar)

        let end = try #require(event.end)
        #expect(ISO8601.dayString(from: end) == "2026-06-24")
    }

    @Test func normalizeIgnoresNonEvents() {
        var task = Item(type: .task, title: "Task", listId: "inbox")

        EventDefaults.normalize(&task, calendar: calendar)

        #expect(task.due == nil)
        #expect(task.end == nil)
    }

    @MainActor
    @Test func storeAddNormalizesEventWithoutDates() async throws {
        let store = try await emptyStore()
        let event = Item(type: .event, title: "Planning", listId: ItemList.inboxId)

        try await store.add(event)

        let live = try #require(store.item(event.id))
        let due = try #require(live.due)
        let end = try #require(live.end)
        #expect(end > due)
        #expect(!live.completable)
    }

    @MainActor
    @Test func storeAddClearsEventOnlyFieldsFromNonEvents() async throws {
        let store = try await emptyStore()
        let start = ISO8601.date(from: "2026-06-23T09:00:00.000Z")!
        let task = Item(
            type: .task,
            title: "Was event",
            listId: ItemList.inboxId,
            due: start,
            end: start.addingTimeInterval(3_600),
            completable: true
        )

        try await store.add(task)

        let live = try #require(store.item(task.id))
        #expect(live.end == nil)
        #expect(!live.completable)
    }

    private func hourMinuteString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.string(from: date)
    }
}
