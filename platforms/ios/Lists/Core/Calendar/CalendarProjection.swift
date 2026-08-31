import Foundation

struct CalendarEntry: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        enum Source: String, Hashable, Sendable {
            case current
            case projected
            case history
            case habit
        }

        let itemId: UUID
        let source: Source
        let scheduledAt: Date
        let occurrenceId: UUID?
    }

    enum Status: Equatable, Sendable {
        case open
        case completed
        case missed
    }

    let id: ID
    let itemId: UUID
    let title: String
    let type: Item.ItemType
    let listId: String
    let section: String?
    let start: Date
    let end: Date
    let isAllDay: Bool
    let status: Status
    let isCompletable: Bool
    let priority: Item.Priority
    let flagged: Bool
    let hasRecurrence: Bool

    var isProjected: Bool {
        id.source == .projected || id.source == .habit
    }

    var isEditableOccurrence: Bool {
        id.source == .current
    }

    func overlaps(_ interval: DateInterval) -> Bool {
        start < interval.end && end > interval.start
    }
}

enum CalendarProjection {
    private static let maximumGeneratedOccurrences = 5_000

    static func entries(
        items: [Item],
        in interval: DateInterval,
        preferences: CalendarProjectionPreferences,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [CalendarEntry] {
        var result: [CalendarEntry] = []

        for item in items where item.deletedAt == nil {
            guard preferences.includes(item.type),
                  !preferences.hiddenListIds.contains(item.listId) else {
                continue
            }
            if item.type == .habit {
                result.append(contentsOf: habitEntries(
                    for: item,
                    in: interval,
                    preferences: preferences,
                    now: now,
                    calendar: calendar
                ))
            } else {
                result.append(contentsOf: scheduledEntries(
                    for: item,
                    in: interval,
                    preferences: preferences,
                    now: now,
                    calendar: calendar
                ))
            }
        }

        return result.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            if $0.title != $1.title {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.id.itemId.uuidString < $1.id.itemId.uuidString
        }
    }

    /// Returns the next display date for one habit without expanding it into
    /// an unbounded list of future rows. Scheduled's List presentation uses
    /// this to show each habit exactly once.
    static func nextHabitOccurrence(
        for item: Item,
        onOrAfter threshold: Date = .now,
        includeCompleted: Bool,
        calendar: Calendar = .current
    ) -> Date? {
        guard item.type == .habit else { return nil }
        return nextHabitOccurrenceDate(
            for: item,
            frequency: (item.frequency ?? .daily).normalizedForHabit,
            anchor: item.due ?? item.createdAt,
            onOrAfter: threshold,
            includeCompleted: includeCompleted,
            calendar: calendar
        )
    }

    static func currentEntry(
        for item: Item,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CalendarEntry? {
        guard item.type != .habit, let due = item.due else { return nil }
        return makeEntry(
            item: item,
            source: .current,
            start: due,
            duration: displayDuration(for: item, start: due, calendar: calendar),
            status: item.isComplete(at: now) ? .completed : .open,
            occurrenceId: nil,
            calendar: calendar
        )
    }

    private static func scheduledEntries(
        for item: Item,
        in interval: DateInterval,
        preferences: CalendarProjectionPreferences,
        now: Date,
        calendar: Calendar
    ) -> [CalendarEntry] {
        guard let due = item.due else { return [] }
        let completed = item.isComplete(at: now)
        if completed && !preferences.showCompletedItems {
            return historyEntries(
                for: item,
                in: interval,
                preferences: preferences,
                calendar: calendar
            )
        }

        var entries: [CalendarEntry] = []
        let duration = displayDuration(for: item, start: due, calendar: calendar)
        let current = makeEntry(
            item: item,
            source: .current,
            start: due,
            duration: duration,
            status: completed ? .completed : .open,
            occurrenceId: nil,
            calendar: calendar
        )
        if current.overlaps(interval) {
            entries.append(current)
        }

        if preferences.recurrenceVisibility == .visibleRange,
           !completed,
           let rule = item.recurrence?.rrule {
            let recurrenceCalendar = RecurrenceEngine.calendar(forTimeZone: item.dueTimeZone)
            var cursor = due
            var generated = 0
            while let next = RecurrenceEngine.nextOccurrence(
                after: cursor,
                rrule: rule,
                calendar: recurrenceCalendar
            ), next < interval.end, generated < maximumGeneratedOccurrences {
                cursor = next
                generated += 1
                guard next >= interval.start.addingTimeInterval(-duration) else {
                    continue
                }
                let projected = makeEntry(
                    item: item,
                    source: .projected,
                    start: next,
                    duration: duration,
                    status: .open,
                    occurrenceId: nil,
                    calendar: recurrenceCalendar
                )
                if projected.overlaps(interval) {
                    entries.append(projected)
                }
            }
        }

        entries.append(contentsOf: historyEntries(
            for: item,
            in: interval,
            preferences: preferences,
            calendar: calendar
        ))
        return deDuplicated(entries)
    }

    private static func historyEntries(
        for item: Item,
        in interval: DateInterval,
        preferences: CalendarProjectionPreferences,
        calendar: Calendar
    ) -> [CalendarEntry] {
        guard preferences.showCompletedHistory || preferences.showMissedHistory else {
            return []
        }
        let duration = displayDuration(
            for: item,
            start: item.due ?? interval.start,
            calendar: calendar
        )
        return item.recurrenceOccurrences.compactMap { occurrence in
            let status: CalendarEntry.Status
            switch occurrence.status {
            case .open:
                return nil
            case .completed where preferences.showCompletedHistory:
                status = .completed
            case .missed where preferences.showMissedHistory:
                status = .missed
            default:
                return nil
            }
            let entry = makeEntry(
                item: item,
                source: .history,
                start: occurrence.scheduledAt,
                duration: duration,
                status: status,
                occurrenceId: occurrence.id,
                calendar: calendar
            )
            return entry.overlaps(interval) ? entry : nil
        }
    }

    private static func habitEntries(
        for item: Item,
        in interval: DateInterval,
        preferences: CalendarProjectionPreferences,
        now: Date,
        calendar: Calendar
    ) -> [CalendarEntry] {
        let frequency = (item.frequency ?? .daily).normalizedForHabit
        let anchor = item.due ?? item.createdAt
        let allDay = item.due == nil

        let dates: [Date]
        switch preferences.recurrenceVisibility {
        case .nextOccurrence:
            guard let next = nextHabitOccurrenceDate(
                for: item,
                frequency: frequency,
                anchor: anchor,
                onOrAfter: now,
                includeCompleted: preferences.showCompletedItems,
                calendar: calendar
            ) else {
                return []
            }
            dates = [next]
        case .visibleRange:
            dates = habitOccurrences(
                frequency: frequency,
                anchor: anchor,
                in: interval,
                calendar: calendar
            )
        }

        return dates.compactMap { date in
            let completed = habitIsComplete(item, on: date, calendar: calendar)
            guard preferences.showCompletedItems || !completed else { return nil }
            let duration: TimeInterval = allDay ? allDayDuration(from: date, calendar: calendar) : 30 * 60
            let entry = CalendarEntry(
                id: .init(
                    itemId: item.id,
                    source: .habit,
                    scheduledAt: date,
                    occurrenceId: nil
                ),
                itemId: item.id,
                title: item.title,
                type: item.type,
                listId: item.listId,
                section: item.section,
                start: date,
                end: date.addingTimeInterval(duration),
                isAllDay: allDay,
                status: completed ? .completed : .open,
                isCompletable: true,
                priority: item.priority,
                flagged: item.flagged,
                hasRecurrence: true
            )
            return entry.overlaps(interval) ? entry : nil
        }
    }

    private static func nextHabitOccurrenceDate(
        for item: Item,
        frequency: HabitFrequency,
        anchor: Date,
        onOrAfter threshold: Date,
        includeCompleted: Bool,
        calendar: Calendar
    ) -> Date? {
        let search = DateInterval(
            start: calendar.startOfDay(for: threshold),
            end: calendar.date(byAdding: .year, value: 5, to: threshold)
                ?? threshold.addingTimeInterval(5 * 366 * 86_400)
        )
        return habitOccurrences(
            frequency: frequency,
            anchor: anchor,
            in: search,
            calendar: calendar
        ).first {
            includeCompleted || !habitIsComplete(item, on: $0, calendar: calendar)
        }
    }

    private static func habitOccurrences(
        frequency: HabitFrequency,
        anchor: Date,
        in interval: DateInterval,
        calendar: Calendar
    ) -> [Date] {
        var result: [Date] = []
        var cursor = firstHabitOccurrence(
            frequency: frequency,
            anchor: anchor,
            onOrAfter: interval.start,
            calendar: calendar
        )
        var generated = 0
        while let date = cursor,
              date < interval.end,
              generated < maximumGeneratedOccurrences {
            result.append(date)
            cursor = nextHabitDate(
                after: date,
                frequency: frequency,
                anchor: anchor,
                calendar: calendar
            )
            generated += 1
        }
        return result
    }

    private static func firstHabitOccurrence(
        frequency: HabitFrequency,
        anchor: Date,
        onOrAfter threshold: Date,
        calendar: Calendar
    ) -> Date? {
        if anchor >= threshold { return anchor }
        var cursor = anchor
        var generated = 0
        while let next = nextHabitDate(
            after: cursor,
            frequency: frequency,
            anchor: anchor,
            calendar: calendar
        ), generated < maximumGeneratedOccurrences {
            if next >= threshold { return next }
            cursor = next
            generated += 1
        }
        return nil
    }

    private static func nextHabitDate(
        after date: Date,
        frequency: HabitFrequency,
        anchor: Date,
        calendar: Calendar
    ) -> Date? {
        switch frequency.normalizedForHabit {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            let anchorComponents = calendar.dateComponents(
                [.day, .hour, .minute, .second],
                from: anchor
            )
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: date),
                  let range = calendar.range(of: .day, in: .month, for: nextMonth) else {
                return nil
            }
            var components = calendar.dateComponents([.year, .month], from: nextMonth)
            components.day = min(anchorComponents.day ?? 1, range.count)
            components.hour = anchorComponents.hour
            components.minute = anchorComponents.minute
            components.second = anchorComponents.second
            return calendar.date(from: components)
        default:
            return nil
        }
    }

    private static func habitIsComplete(
        _ item: Item,
        on date: Date,
        calendar: Calendar
    ) -> Bool {
        guard let frequency = item.frequency?.normalizedForHabit else { return false }
        let key = HabitCycle.key(for: frequency, on: date)
        return (item.completionLog[key] ?? 0) >= max(1, item.goalPerCycle)
    }

    private static func makeEntry(
        item: Item,
        source: CalendarEntry.ID.Source,
        start: Date,
        duration: TimeInterval,
        status: CalendarEntry.Status,
        occurrenceId: UUID?,
        calendar: Calendar
    ) -> CalendarEntry {
        CalendarEntry(
            id: .init(
                itemId: item.id,
                source: source,
                scheduledAt: start,
                occurrenceId: occurrenceId
            ),
            itemId: item.id,
            title: item.title,
            type: item.type,
            listId: item.listId,
            section: item.section,
            start: start,
            end: start.addingTimeInterval(max(1, duration)),
            isAllDay: item.dueAllDay,
            status: status,
            isCompletable: item.type == .task
                || item.type == .habit
                || (item.type == .event && item.completable),
            priority: item.priority,
            flagged: item.flagged,
            hasRecurrence: item.recurrence != nil
        )
    }

    private static func displayDuration(
        for item: Item,
        start: Date,
        calendar: Calendar
    ) -> TimeInterval {
        if item.dueAllDay {
            if item.type == .event,
               let end = item.end,
               end > start {
                return end.timeIntervalSince(start)
            }
            return allDayDuration(from: start, calendar: calendar)
        }
        if item.type == .event,
           let end = item.end,
           end > start {
            return end.timeIntervalSince(start)
        }
        return 30 * 60
    }

    private static func allDayDuration(from start: Date, calendar: Calendar) -> TimeInterval {
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        return nextDay.timeIntervalSince(start)
    }

    private static func deDuplicated(_ entries: [CalendarEntry]) -> [CalendarEntry] {
        var seen: Set<String> = []
        return entries.filter { entry in
            let dayKey = "\(entry.itemId.uuidString)|\(entry.start.timeIntervalSinceReferenceDate)"
            return seen.insert(dayKey).inserted
        }
    }
}
