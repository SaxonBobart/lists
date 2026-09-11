import Foundation

/// Portable source metadata travels with an item, independently of its current list.
public struct CalendarImport: Codable, Equatable, Sendable {
    public struct Values: Codable, Equatable, Sendable {
        var title: String
        var body: String
        var start: Date
        var end: Date
        var allDay: Bool
        var timeZone: String?
    }
    public enum Field: String, Codable, CaseIterable, Sendable {
        case title, body, schedule
        var label: String { rawValue.capitalized }
    }
    var connectionID: UUID
    var sourceKey: String
    var localIdentifier: String
    var calendarName: String
    var baseline: Values
    var conflicts: [Field] = []
    var detached = false
    var sourceUnavailable = false
    var checkedAt: Date

    static func merge(_ incoming: Values, into item: Item, now: Date) -> Item {
        guard var origin = item.calendarImport, !origin.detached else { return item }
        var result = item
        let old = origin.baseline
        func mergeField<T: Equatable>(_ field: Field, _ previous: T, _ next: T,
                                     _ local: T, apply: () -> Void) {
            guard next != previous else { return }
            if local == previous || local == next {
                apply()
                origin.conflicts.removeAll { $0 == field }
            } else if !origin.conflicts.contains(field) {
                origin.conflicts.append(field)
            }
        }
        mergeField(.title, old.title, incoming.title, item.title) { result.title = incoming.title }
        mergeField(.body, old.body, incoming.body, item.body) { result.body = incoming.body }
        let changedSchedule = old.start != incoming.start || old.end != incoming.end
            || old.allDay != incoming.allDay || old.timeZone != incoming.timeZone
        if changedSchedule {
            let unchanged = item.due == old.start && item.dueAllDay == old.allDay
                && item.dueTimeZone == old.timeZone && (item.type != .event || item.end == old.end)
            if unchanged {
                applySchedule(incoming, to: &result)
                origin.conflicts.removeAll { $0 == .schedule }
            } else if !origin.conflicts.contains(.schedule) { origin.conflicts.append(.schedule) }
        }
        origin.baseline = incoming
        origin.checkedAt = now
        origin.sourceUnavailable = false
        result.calendarImport = origin
        return result
    }

    static func applySchedule(_ values: Values, to item: inout Item) {
        item.due = values.start
        item.dueAllDay = values.allDay
        item.dueTimeZone = values.timeZone
        // Converting an event into a task or note is always a local choice.
        if item.type == .event { item.end = values.end }
    }

    static func resolve(_ field: Field, useSource: Bool, item: Item) -> Item {
        guard var origin = item.calendarImport else { return item }
        var result = item
        if useSource {
            switch field {
            case .title: result.title = origin.baseline.title
            case .body: result.body = origin.baseline.body
            case .schedule: applySchedule(origin.baseline, to: &result)
            }
        }
        origin.conflicts.removeAll { $0 == field }
        result.calendarImport = origin
        return result
    }
}
