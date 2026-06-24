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
        lingering: Set<UUID> = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ScheduledSmartListGroup] {
        var overdue: [Item] = []
        var dated: [Date: [Item]] = [:]

        for item in items {
            guard item.deletedAt == nil else { continue }
            guard item.type != .habit else { continue }
            guard let due = item.due else { continue }

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
            (lhs.due ?? .distantFuture) < (rhs.due ?? .distantFuture)
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
