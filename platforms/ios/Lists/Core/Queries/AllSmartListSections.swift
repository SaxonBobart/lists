import Foundation

enum AllSmartListSections {
    struct Entry: Equatable {
        let list: ItemList
        let buckets: [Bucket]
    }

    struct Bucket: Equatable {
        let sectionKey: String?
        let name: String?
        let parents: [Item]
    }

    static func entries(
        lists: [ItemList],
        items: [Item],
        showCompleted: Bool = false,
        showPastEvents: Bool = false,
        lingering: Set<UUID> = [],
        sortMode: ListViewPreferences.SortMode,
        sortDirection: ListViewPreferences.SortDirection,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Entry] {
        let orderedLists = lists
            .filter { $0.deletedAt == nil }
            .sorted { $0.position < $1.position }

        var entries: [Entry] = []
        for list in orderedLists {
            let parents = items.filter { item in
                item.listId == list.id
                    && item.deletedAt == nil
                    && item.parentId == nil
                    && item.type != .habit
                    && (showCompleted || !item.isComplete(at: now) || lingering.contains(item.id))
                    && (showPastEvents || !item.isRolledOffPastEvent(now: now, calendar: calendar))
            }
            .sortedBy(sortMode, direction: sortDirection)

            guard parents.isEmpty == false else { continue }

            let namedKeys = Set(list.sections.map { $0.id.uuidString })
            var buckets: [Bucket] = []
            let uncategorized = parents.filter { item in
                guard let section = item.section else { return true }
                return namedKeys.contains(section) == false
            }
            if uncategorized.isEmpty == false {
                buckets.append(Bucket(sectionKey: nil, name: nil, parents: uncategorized))
            }

            for section in list.sections.sorted(by: { $0.position < $1.position }) {
                let key = section.id.uuidString
                let group = parents.filter { $0.section == key }
                if group.isEmpty == false {
                    buckets.append(Bucket(sectionKey: key, name: section.name, parents: group))
                }
            }

            if buckets.isEmpty == false {
                entries.append(Entry(list: list, buckets: buckets))
            }
        }
        return entries
    }
}
