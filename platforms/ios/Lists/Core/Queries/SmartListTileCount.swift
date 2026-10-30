import Foundation

enum SmartListTileCount {
    static func count(
        for smartList: SmartList,
        lists: [ItemList],
        items: [Item],
        showCompleted: Bool = false,
        showOverdue: Bool = true,
        showPastEvents: Bool = false,
        sortMode: ListViewPreferences.SortMode = .manual,
        sortDirection: ListViewPreferences.SortDirection = .ascending,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {

        switch smartList {
        case .today:
            let sections = TodaySmartListSections.split(
                smartListItems(
                    for: .today,
                    in: items,
                    showCompleted: showCompleted,
                    showPastEvents: false,
                    now: now,
                    calendar: calendar
                ),
                now: now,
                calendar: calendar
            )
            return sections.today.count + (showOverdue ? sections.overdue.count : 0)

        case .scheduled:
            return ScheduledSmartListSections.split(
                items,
                showCompleted: showCompleted,
                showOverdue: showOverdue,
                showPastEvents: showPastEvents,
                now: now,
                calendar: calendar
            )
            .reduce(0) { $0 + $1.items.count }

        case .all:
            let entries = AllSmartListSections.entries(
                lists: lists,
                items: items,
                showCompleted: showCompleted,
                showPastEvents: showPastEvents,
                sortMode: sortMode,
                sortDirection: sortDirection,
                now: now,
                calendar: calendar
            )
            return entries.reduce(0) { total, entry in
                total + entry.buckets.reduce(0) { bucketTotal, bucket in
                    bucketTotal + ItemHierarchy.flattenForAll(
                        parents: bucket.parents,
                        allItems: items,
                        showCompleted: showCompleted,
                        showPastEvents: showPastEvents,
                        now: now,
                        calendar: calendar
                    ).count
                }
            }

        case .tags:
            return Tag.activeTagNames(
                in: items,
                now: now,
                calendar: calendar
            ).count

        case .completed:
            return items.reduce(into: 0) { count, item in
                let recurrenceCompletions = item.recurrenceOccurrences.lazy.filter {
                    $0.status == .completed && $0.completedAt != nil
                }.count
                if recurrenceCompletions > 0 {
                    count += recurrenceCompletions
                } else if item.isComplete(at: now) {
                    count += 1
                }
            }

        case .flagged, .alarms, .reminders:
            return smartListItems(
                for: smartList,
                in: items,
                showCompleted: showCompleted,
                showPastEvents: showPastEvents,
                now: now,
                calendar: calendar
            ).count
        }
    }

    private static func smartListItems(
        for smartList: SmartList,
        in items: [Item],
        showCompleted: Bool,
        showPastEvents: Bool,
        now: Date,
        calendar: Calendar
    ) -> [Item] {
        items.filter { item in
            if item.deletedAt != nil { return false }
            if item.isRolledOffPastEvent(now: now, calendar: calendar) && !showPastEvents {
                return false
            }
            return smartList.matches(
                item,
                now: now,
                includeCompleted: showCompleted,
                calendar: calendar
            )
        }
    }
}
