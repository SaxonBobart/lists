import EventKit
import Foundation
import Observation

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
    private(set) var calendars: [EKCalendar] = []
    private(set) var busy = false
    var error: String?
    private let events = EKEventStore()
    private var loadFailed = false
    private let file: URL

    init() {
        file = URL.applicationSupportDirectory.appendingPathComponent("Lists/calendar-connections.json")
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                connections = try JSONDecoder().decode([Connection].self, from: Data(contentsOf: file))
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
            let granted = try await events.requestFullAccessToEvents()
            guard granted else { error = "Allow full calendar access in Settings to read your calendars. Lists never writes changes to Apple Calendar."; return }
            calendars = events.calendars(for: .event).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        } catch { self.error = error.localizedDescription }
    }

    func connect(calendar: EKCalendar, listID: String, start: Date, end: Date, store: ItemStore) async {
        guard !busy, !loadFailed, start < end, end.timeIntervalSince(start) <= 3 * 366 * 86400 else {
            error = "Choose a date range of up to three years."; return
        }
        let previous = connections
        if let index = connections.firstIndex(where: { $0.calendarID == calendar.calendarIdentifier }) {
            connections[index].listID = listID
            connections[index].start = start
            connections[index].end = end
            connections[index].enabled = true
        } else {
            connections.append(Connection(calendarID: calendar.calendarIdentifier, name: calendar.title,
                                          listID: listID, start: start, end: end))
        }
        do { try save() } catch { connections = previous; self.error = error.localizedDescription; return }
        await refresh(store: store)
    }

    func disconnect(_ id: UUID) {
        guard !busy, let index = connections.firstIndex(where: { $0.id == id }) else { return }
        let previous = connections
        connections[index].enabled = false
        do { try save() } catch { connections = previous; self.error = error.localizedDescription }
    }

    func refresh(store: ItemStore) async {
        guard !busy, !loadFailed, connections.contains(where: \.enabled) else { return }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            error = "Calendar access is unavailable. Existing imported items are unchanged."; return
        }
        busy = true
        defer { busy = false }
        do {
            for index in connections.indices where connections[index].enabled {
                let connection = connections[index]
                guard store.lists.contains(where: { $0.id == connection.listID && $0.deletedAt == nil }) else {
                    throw NSError(domain: "CalendarConnection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose an available destination list for \(connection.name)."])
                }
                guard let calendar = events.calendar(withIdentifier: connection.calendarID) else {
                    throw NSError(domain: "CalendarConnection", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(connection.name) is unavailable. Its imported items have been kept."])
                }
                let predicate = events.predicateForEvents(withStart: connection.start, end: connection.end, calendars: [calendar])
                let sourceEvents = events.events(matching: predicate)
                var seen = Set<String>()
                for event in sourceEvents {
                    let external = event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier
                    let occurrence = (event.hasRecurrenceRules || event.isDetached)
                        ? event.occurrenceDate.map { "|\($0.timeIntervalSince1970)" } ?? "" : ""
                    let key = external + occurrence
                    guard seen.insert(key).inserted, let start = event.startDate, let end = event.endDate else { continue }
                    let rawBody = [event.notes, event.location.map { "Location: \($0)" }, event.url?.absoluteString]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
                    let body = rawBody.isEmpty || rawBody.hasSuffix("\n") ? rawBody : rawBody + "\n"
                    let incoming = CalendarImport.Values(title: event.title ?? "Untitled Event", body: body,
                                                         start: start, end: end, allDay: event.isAllDay,
                                                         timeZone: event.timeZone?.identifier)
                    // Search metadata too: a crash after item creation but before ledger save is safe.
                    let linked = store.items.first { item in
                        guard let origin = item.calendarImport, origin.connectionID == connection.id else { return false }
                        return origin.sourceKey == key || (occurrence.isEmpty
                            && origin.localIdentifier == event.calendarItemIdentifier)
                    }
                    if let item = linked {
                        connections[index].imported[key] = item.id
                        if item.deletedAt == nil, item.calendarImport?.detached != true {
                            var merged = CalendarImport.merge(incoming, into: item, now: .now)
                            merged.calendarImport?.sourceKey = key
                            merged.calendarImport?.localIdentifier = event.calendarItemIdentifier
                            if merged != item { try await store.update(merged) }
                        }
                    } else if connections[index].imported[key] == nil {
                        var item = Item(type: .event, title: incoming.title, listId: connection.listID,
                                        due: start, dueAllDay: incoming.allDay, dueTimeZone: incoming.timeZone, end: end)
                        item.body = body
                        item.calendarImport = CalendarImport(connectionID: connection.id, sourceKey: key,
                            localIdentifier: event.calendarItemIdentifier, calendarName: calendar.title,
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
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
