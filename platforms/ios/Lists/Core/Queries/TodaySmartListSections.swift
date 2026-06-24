import Foundation

struct TodaySmartListSections: Equatable {
    var overdue: [Item]
    var today: [Item]

    static func split(
        _ items: [Item],
        lingering: Set<UUID> = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TodaySmartListSections {
        let startOfToday = calendar.startOfDay(for: now)
        var overdue: [Item] = []
        var today: [Item] = []

        for item in items {
            guard let due = item.due else { continue }
            let isLingering = lingering.contains(item.id)

            if item.type == .event && !item.completable {
                if calendar.isDate(due, inSameDayAs: now)
                    || (due < startOfToday && (item.end.map { $0 > startOfToday } ?? false)) {
                    today.append(item)
                }
                continue
            }

            if due < startOfToday {
                if item.isOverdue(now: now, calendar: calendar) || isLingering {
                    overdue.append(item)
                }
            } else if calendar.isDate(due, inSameDayAs: now) {
                today.append(item)
            }
        }

        return TodaySmartListSections(overdue: overdue, today: today)
    }
}
