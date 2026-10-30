import EventKit
import Foundation
import Observation

struct CalendarConnectionSource: Identifiable {
    let id: String
    let title: String
    let account: String
}
struct CalendarConnectionEvent {
    let key: String
    let localIdentifier: String
    let values: CalendarImport.Values
}
@MainActor protocol CalendarEventSource {
    var authorized: Bool { get }
    func requestAccess() async throws -> Bool
    func calendars() -> [CalendarConnectionSource]
    func events(calendarID: String, start: Date, end: Date) throws -> [CalendarConnectionEvent]
}
@MainActor private final class AppleCalendarEventSource: CalendarEventSource {
    private let store = EKEventStore()
    var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    func requestAccess() async throws -> Bool { try await store.requestFullAccessToEvents() }
    func calendars() -> [CalendarConnectionSource] {
        store.calendars(for: .event).map { .init(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func events(calendarID: String, start: Date, end: Date) throws -> [CalendarConnectionEvent] {
        guard let calendar = store.calendar(withIdentifier: calendarID) else {
            throw NSError(domain: "CalendarConnection", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "This calendar is unavailable. Its imported items have been kept."])
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        return store.events(matching: predicate).compactMap { event in
            guard let start = event.startDate, let end = event.endDate else { return nil }
            let occurrence = (event.hasRecurrenceRules || event.isDetached)
                ? event.occurrenceDate.map { "|\($0.timeIntervalSince1970)" } ?? "" : ""
            let key = (event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier) + occurrence
            let raw = [event.notes, event.location.map { "Location: \($0)" }, event.url?.absoluteString]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            let body = raw.isEmpty || raw.hasSuffix("\n") ? raw : raw + "\n"
            return .init(key: key, localIdentifier: event.calendarItemIdentifier,
                values: .init(title: event.title ?? "Untitled Event", body: body, start: start, end: end,
                              allDay: event.isAllDay, timeZone: event.timeZone?.identifier))
        }
    }
}

@MainActor @Observable
final class CalendarConnections {
    static let shared = CalendarConnections()
    struct Connection: Codable, Identifiable {
        var id = UUID()
        var calendarID: String
        var name: String
        var listID: String
        var enabled = true
        var start: Date
        var end: Date
        var lastRefresh: Date?
        var imported: [String: UUID] = [:]
    }
    private(set) var connections: [Connection] = []
    private(set) var calendars: [CalendarConnectionSource] = []
    private(set) var connectionErrors: [UUID: String] = [:]
    private(set) var authorized = false
    private(set) var busy = false
    var error: String?
    private let source: any CalendarEventSource
    private var loadFailed = false
    private let file: URL

    init(source: (any CalendarEventSource)? = nil, file: URL? = nil) {
        self.source = source ?? AppleCalendarEventSource()
        self.authorized = self.source.authorized
        self.file = file ?? URL.applicationSupportDirectory.appendingPathComponent("Lists/calendar-connections.json")
        do {
            if FileManager.default.fileExists(atPath: self.file.path) {
                connections = try JSONDecoder().decode([Connection].self, from: Data(contentsOf: self.file))
            }
        } catch { self.error = error.localizedDescription; loadFailed = true }
    }

    private func save() throws {
        guard !loadFailed else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(connections).write(to: file, options: .atomic)
    }

    func requestAccess() async {
        do {
            let granted = try await source.requestAccess()
            authorized = granted
            guard granted else { error = "Allow full calendar access in Settings to read your calendars. Lists never writes changes to Apple Calendar."; return }
            calendars = source.calendars()
            if !loadFailed { error = nil }
        } catch { self.error = error.localizedDescription }
    }

    func connect(calendar: CalendarConnectionSource, listID: String, start: Date, end: Date, store: ItemStore) async {
        guard !busy else { return }
        guard !loadFailed else { error = "Calendar connection settings need recovery. Your imported items are unchanged."; return }
        guard start < end, end.timeIntervalSince(start) <= 3 * 366 * 86400 else {
            error = "Choose a date range of up to three years."; return
        }
        let previous = connections
        if let index = connections.firstIndex(where: { $0.calendarID == calendar.id }) {
            connections[index].name = calendar.title
            connections[index].listID = listID
            connections[index].start = start
            connections[index].end = end
            connections[index].enabled = true
        } else {
            connections.append(Connection(calendarID: calendar.id, name: calendar.title,
                                          listID: listID, start: start, end: end))
        }
        do { try save() } catch { connections = previous; self.error = error.localizedDescription; return }
        await refresh(store: store)
    }

    func disconnect(_ id: UUID) {
        guard !busy, let index = connections.firstIndex(where: { $0.id == id }) else { return }
        let previous = connections
        connections[index].enabled = false
        do { try save(); error = nil } catch { connections = previous; self.error = error.localizedDescription }
    }

    func refresh(store: ItemStore) async {
        guard !busy, !loadFailed, connections.contains(where: \.enabled) else { return }
        authorized = source.authorized
        guard authorized else {
            error = "Calendar access is unavailable. Existing imported items are unchanged."; return
        }
        busy = true
        defer { busy = false }
        error = nil
        for index in connections.indices where connections[index].enabled {
            let connection = connections[index]
            do {
                guard store.lists.contains(where: { $0.id == connection.listID && $0.deletedAt == nil }) else {
                    throw NSError(domain: "CalendarConnection", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Choose an available destination list for \(connection.name)."])
                }
                let sourceEvents = try source.events(calendarID: connection.calendarID, start: connection.start, end: connection.end)
                var seen = Set<String>()
                for event in sourceEvents {
                    let key = event.key
                    guard seen.insert(key).inserted else { continue }
                    let incoming = event.values
                    // Search metadata too: a crash after item creation but before ledger save is safe.
                    let linked = store.items.first { item in
                        guard let origin = item.calendarImport, origin.connectionID == connection.id else { return false }
                        return origin.sourceKey == key || (!key.contains("|")
                            && origin.localIdentifier == event.localIdentifier)
                    }
                    if let item = linked {
                        connections[index].imported[key] = item.id
                        if item.deletedAt == nil, item.calendarImport?.detached != true {
                            var merged = CalendarImport.merge(incoming, into: item, now: .now)
                            merged.calendarImport?.sourceKey = key
                            merged.calendarImport?.localIdentifier = event.localIdentifier
                            if merged != item { try await store.update(merged) }
                        }
                    } else if connections[index].imported[key] == nil {
                        var item = Item(type: .event, title: incoming.title, listId: connection.listID,
                                        due: incoming.start, dueAllDay: incoming.allDay, dueTimeZone: incoming.timeZone, end: incoming.end)
                        item.body = incoming.body
                        item.calendarImport = CalendarImport(connectionID: connection.id, sourceKey: key,
                            localIdentifier: event.localIdentifier, calendarName: connection.name,
                            baseline: incoming, checkedAt: .now)
                        try await store.add(item)
                        connections[index].imported[key] = item.id
                        try save()
                    }
                }
                // Never infer deletion from a missing event: it may have moved outside the range.
                for item in store.items where item.calendarImport?.connectionID == connection.id && item.deletedAt == nil {
                    guard let origin = item.calendarImport, !origin.detached,
                          origin.baseline.start < connection.end, origin.baseline.end > connection.start,
                          !seen.contains(origin.sourceKey), !origin.sourceUnavailable else { continue }
                    var updated = item
                    updated.calendarImport?.sourceUnavailable = true
                    try await store.update(updated)
                }
                connections[index].lastRefresh = .now
                try save()
                connectionErrors[connection.id] = nil
            } catch { connectionErrors[connection.id] = error.localizedDescription }
        }
    }
}
