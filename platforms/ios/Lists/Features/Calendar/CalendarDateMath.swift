import Foundation

enum CalendarDateMath {
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
        case .threeDay:
            let start = calendar.startOfDay(for: anchor)
            return DateInterval(
                start: start,
                end: calendar.date(byAdding: .day, value: 3, to: start)
                    ?? start.addingTimeInterval(3 * 86_400)
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
        case .threeDay:
            component = .day
            value = direction * 3
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
        case .threeDay:
            let end = calendar.date(byAdding: .day, value: 2, to: anchor) ?? anchor
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
