import Foundation

enum EventDefaults {
    static func defaultStart(now: Date = .now, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let flooredHour = calendar.date(from: components) ?? now
        return calendar.date(byAdding: .hour, value: 1, to: flooredHour) ?? now
    }

    static func defaultEnd(for start: Date, allDay: Bool, calendar: Calendar = .current) -> Date {
        if allDay {
            return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        }
        return start.addingTimeInterval(3_600)
    }

    static func normalize(_ item: inout Item, now: Date = .now, calendar: Calendar = .current) {
        guard item.type == .event else { return }
        if item.due == nil {
            item.due = defaultStart(now: now, calendar: calendar)
            item.dueAllDay = false
        }
        if let start = item.due, item.end.map({ $0 > start }) != true {
            item.end = defaultEnd(for: start, allDay: item.dueAllDay, calendar: calendar)
        }
    }
}
