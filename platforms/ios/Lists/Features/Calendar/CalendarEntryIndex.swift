import Foundation

struct CalendarEntryIndex {
    private let entriesByDay: [Date: [CalendarEntry]]
    private let calendar: Calendar

    init(
        entries: [CalendarEntry],
        interval: DateInterval,
        calendar: Calendar
    ) {
        self.calendar = calendar
        var buckets: [Date: [CalendarEntry]] = [:]
        for entry in entries {
            let clippedStart = max(entry.start, interval.start)
            let clippedEnd = min(entry.end, interval.end)
            guard clippedEnd > clippedStart else { continue }

            var day = calendar.startOfDay(for: clippedStart)
            let finalInstant = clippedEnd.addingTimeInterval(-0.001)
            let finalDay = calendar.startOfDay(for: finalInstant)
            var guardCount = 0
            while day <= finalDay && guardCount < 3_700 {
                buckets[day, default: []].append(entry)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day),
                      next > day else {
                    break
                }
                day = next
                guardCount += 1
            }
        }
        entriesByDay = buckets.mapValues { values in
            values.sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                if $0.start != $1.start { return $0.start < $1.start }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }

    func entries(on day: Date) -> [CalendarEntry] {
        entriesByDay[calendar.startOfDay(for: day)] ?? []
    }

    var populatedDays: [Date] {
        entriesByDay.keys.sorted()
    }
}
