import Foundation

struct ScheduledSmartListGroup: Equatable {
    enum Kind: Equatable {
        case overdue
        case day(Date)
    }

    var kind: Kind
    var items: [Item]

    var isOverdue: Bool {
        kind == .overdue
    }
}

enum ScheduledSmartListSections {
    static func split(
        _ items: [Item],
        showCompleted: Bool = false,
        showOverdue: Bool = false,
        showPastEvents: Bool = false,
        showHabits: Bool = false,
        lingering: Set<UUID> = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ScheduledSmartListGroup] {
        var overdue: [Item] = []
        var dated: [Date: [Item]] = [:]
        var displayDates: [UUID: Date] = [:]

        for item in items {
            guard item.deletedAt == nil else { continue }
            if item.type == .habit {
                guard showHabits,
                      let occurrence = CalendarProjection.nextHabitOccurrence(
                        for: item,
                        onOrAfter: now,
                        includeCompleted: showCompleted,
                        calendar: calendar
                      ) else { continue }
                let day = calendar.startOfDay(for: occurrence)
                displayDates[item.id] = occurrence
                dated[day, default: []].append(item)
                continue
            }
            guard let due = item.due else { continue }
            displayDates[item.id] = due

            let isLingering = lingering.contains(item.id)
            let completed = item.isComplete(at: now)
            if completed && !showCompleted && !isLingering { continue }
            if item.isRolledOffPastEvent(now: now, calendar: calendar)
                && !showPastEvents
                && !isLingering { continue }

            if item.isOverdue(now: now, calendar: calendar) {
                if showOverdue || isLingering {
                    overdue.append(item)
                }
                continue
            }

            let day = calendar.startOfDay(for: due)
            dated[day, default: []].append(item)
        }

        let timeSort: (Item, Item) -> Bool = { lhs, rhs in
            (displayDates[lhs.id] ?? .distantFuture) < (displayDates[rhs.id] ?? .distantFuture)
        }

        var groups: [ScheduledSmartListGroup] = []
        if !overdue.isEmpty {
            groups.append(ScheduledSmartListGroup(kind: .overdue, items: overdue.sorted(by: timeSort)))
        }
        for day in dated.keys.sorted() {
            groups.append(ScheduledSmartListGroup(
                kind: .day(day),
                items: (dated[day] ?? []).sorted(by: timeSort)
            ))
        }
        return groups
    }
}
