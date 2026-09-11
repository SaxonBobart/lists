import Foundation

enum CalendarDateMath {
    static let agendaWindowMonthSpan = 6

    static func weekStripDays(selected: Date, visible: [Date], calendar: Calendar) -> [Date] {
        var start = startOfWeek(containing: selected, calendar: calendar)
        if let last = visible.max(),
           let end = calendar.date(byAdding: .day, value: 6, to: start), last > end {
            // Keep both compact columns visible when their range crosses the week boundary.
            start = calendar.date(byAdding: .day, value: -6, to: last) ?? start
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    struct WeekStripMotion {
        let selected: Double
        let first: Double
        let last: Double
        let viewport: Double
        let selectionStart: Double
        let selectionEnd: Double
        let selectionFraction: Double
    }

    static func weekStripMotion(selected: Date, visible: [Date], progress: Double,
                                showWeekends: Bool, calendar: Calendar) -> WeekStripMotion {
        let base = weekStripDays(selected: selected, visible: visible, calendar: calendar)[0]
        let whole = Int(floor(progress))
        let fraction = progress - Double(whole)
        let transition = min(1, max(0, (fraction - 0.35) / 0.30))
        let selectionFraction = transition * transition * (3 - 2 * transition)
        func advance(_ date: Date, by count: Int) -> Date {
            var result = date
            for _ in 0..<abs(count) {
                repeat { result = calendar.date(byAdding: .day, value: count < 0 ? -1 : 1, to: result)! }
                while !showWeekends && calendar.isDateInWeekend(result)
            }
            return result
        }
        func index(_ date: Date) -> Double { Double(calendar.dateComponents([.day], from: base, to: date).day ?? 0) }
        func position(_ date: Date) -> Double {
            let from = index(advance(date, by: whole))
            return from + (index(advance(date, by: whole + 1)) - from) * selectionFraction
        }
        func viewport(_ offset: Int) -> Double {
            index(weekStripDays(selected: advance(selected, by: offset),
                visible: visible.map { advance($0, by: offset) }, calendar: calendar)[0])
        }
        return WeekStripMotion(selected: position(selected), first: position(visible.min() ?? selected),
            last: position(visible.max() ?? selected),
            viewport: viewport(whole) + (viewport(whole + 1) - viewport(whole)) * fraction,
            selectionStart: index(advance(selected, by: whole)),
            selectionEnd: index(advance(selected, by: whole + 1)), selectionFraction: selectionFraction)
    }

    static func agendaScrollDay(target: Date, availableDays: [Date], calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: target)
        let sorted = availableDays.sorted()
        return sorted.first(where: { $0 >= day }) ?? sorted.last
    }

    static func startOfWeek(
        containing date: Date,
        calendar: Calendar
    ) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    static func monthInterval(
        containing date: Date,
        calendar: Calendar
    ) -> DateInterval {
        calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(
                start: calendar.startOfDay(for: date),
                duration: 31 * 86_400
            )
    }

    static func monthGridInterval(
        containing date: Date,
        calendar: Calendar
    ) -> DateInterval {
        let month = monthInterval(containing: date, calendar: calendar)
        let start = startOfWeek(containing: month.start, calendar: calendar)
        let finalDay = calendar.date(byAdding: .day, value: -1, to: month.end)
            ?? month.end
        let finalWeekStart = startOfWeek(containing: finalDay, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: finalWeekStart)
            ?? month.end
        return DateInterval(start: start, end: end)
    }

    static func yearInterval(
        containing date: Date,
        calendar: Calendar
    ) -> DateInterval {
        calendar.dateInterval(of: .year, for: date)
            ?? DateInterval(
                start: calendar.startOfDay(for: date),
                duration: 366 * 86_400
            )
    }

    static func agendaWindow(
        centeredOn date: Date,
        calendar: Calendar
    ) -> DateInterval {
        let center = calendar.startOfDay(for: date)
        let start = calendar.date(
            byAdding: .month,
            value: -agendaWindowMonthSpan,
            to: center
        ) ?? center.addingTimeInterval(-183 * 86_400)
        let end = calendar.date(
            byAdding: .month,
            value: agendaWindowMonthSpan,
            to: center
        ) ?? center.addingTimeInterval(183 * 86_400)
        return DateInterval(start: calendar.startOfDay(for: start), end: calendar.startOfDay(for: end))
    }

    static func expandingAgendaWindow(
        _ interval: DateInterval,
        towardPast: Bool,
        calendar: Calendar
    ) -> DateInterval {
        if towardPast {
            let start = calendar.date(
                byAdding: .month,
                value: -agendaWindowMonthSpan,
                to: interval.start
            ) ?? interval.start.addingTimeInterval(-183 * 86_400)
            return DateInterval(start: calendar.startOfDay(for: start), end: interval.end)
        }
        let end = calendar.date(
            byAdding: .month,
            value: agendaWindowMonthSpan,
            to: interval.end
        ) ?? interval.end.addingTimeInterval(183 * 86_400)
        return DateInterval(start: interval.start, end: calendar.startOfDay(for: end))
    }

    static func days(
        in interval: DateInterval,
        calendar: Calendar
    ) -> [Date] {
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: interval.start)
        while cursor < interval.end {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor),
                  next > cursor else {
                break
            }
            cursor = next
        }
        return result
    }

    static func visibleWeekdays(
        from weekStart: Date,
        showWeekends: Bool,
        calendar: Calendar
    ) -> [Date] {
        (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                return nil
            }
            return showWeekends || !calendar.isDateInWeekend(date) ? date : nil
        }
    }

    static func interval(
        for kind: CalendarViewKind,
        anchor: Date,
        calendar: Calendar
    ) -> DateInterval {
        switch kind {
        case .list:
            return monthInterval(containing: anchor, calendar: calendar)
        case .month:
            return monthGridInterval(containing: anchor, calendar: calendar)
        case .day:
            let start = calendar.startOfDay(for: anchor)
            return DateInterval(
                start: start,
                end: calendar.date(byAdding: .day, value: 1, to: start)
                    ?? start.addingTimeInterval(86_400)
            )
        case .twoDay:
            let start = calendar.startOfDay(for: anchor)
            return DateInterval(
                start: start,
                end: calendar.date(byAdding: .day, value: 2, to: start)
                    ?? start.addingTimeInterval(2 * 86_400)
            )
        case .week:
            let start = startOfWeek(containing: anchor, calendar: calendar)
            return DateInterval(
                start: start,
                end: calendar.date(byAdding: .day, value: 7, to: start)
                    ?? start.addingTimeInterval(7 * 86_400)
            )
        case .year:
            return yearInterval(containing: anchor, calendar: calendar)
        }
    }

    static func shifted(
        _ anchor: Date,
        kind: CalendarViewKind,
        direction: Int,
        calendar: Calendar
    ) -> Date {
        let component: Calendar.Component
        let value: Int
        switch kind {
        case .list, .month:
            component = .month
            value = direction
        case .day:
            component = .day
            value = direction
        case .twoDay:
            component = .day
            value = direction * 2
        case .week:
            component = .weekOfYear
            value = direction
        case .year:
            component = .year
            value = direction
        }
        return calendar.date(byAdding: component, value: value, to: anchor) ?? anchor
    }

    static func title(
        for kind: CalendarViewKind,
        anchor: Date,
        calendar: Calendar
    ) -> String {
        switch kind {
        case .list, .month:
            return anchor.formatted(.dateTime.month(.wide).year())
        case .day:
            return anchor.formatted(.dateTime.weekday(.wide).month(.wide).day())
        case .twoDay:
            let end = calendar.date(byAdding: .day, value: 1, to: anchor) ?? anchor
            if calendar.component(.month, from: anchor) == calendar.component(.month, from: end) {
                return "\(anchor.formatted(.dateTime.day()))–\(end.formatted(.dateTime.day().month(.wide)))"
            }
            return "\(anchor.formatted(.dateTime.month(.abbreviated).day()))–\(end.formatted(.dateTime.month(.abbreviated).day()))"
        case .week:
            let week = interval(for: .week, anchor: anchor, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: -1, to: week.end) ?? week.end
            if calendar.component(.month, from: week.start) == calendar.component(.month, from: end) {
                return "\(week.start.formatted(.dateTime.day()))–\(end.formatted(.dateTime.day().month(.wide).year()))"
            }
            return "\(week.start.formatted(.dateTime.month(.abbreviated).day()))–\(end.formatted(.dateTime.month(.abbreviated).day().year()))"
        case .year:
            return anchor.formatted(.dateTime.year())
        }
    }

    static func dayIdentifier(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }
}
