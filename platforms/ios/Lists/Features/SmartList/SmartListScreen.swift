import SwiftUI

/// Generic smart-list screen for non-Today smart lists. Today specifically
/// has its own `TodayView` with day-of-week header + Overdue/Today
/// sectioning.
///
/// `.scheduled` is special-cased to group items by their due date (Today
/// / Tomorrow / weekday / short date) — and its menu offers Show
/// Completed + Show Overdue toggles (no sort, since the date grouping
/// IS the order). Other smart lists render as a single flat section
/// with Sort By + Show Completed in the menu. `.completed` is
/// unfiltered.
struct SmartListScreen: View {
    let store: ItemStore
    let smartList: SmartList

    @State private var captureTarget: CaptureTarget?
    @State private var fabIsInteracting = false
    @State private var lingeringIds: Set<UUID> = []
    @State private var prefs = ListViewPreferences()
    @State private var detailItem: Item?

    private var prefsKey: String { "smart:\(smartList.rawValue)" }
    private var tint: Color { ListsTokens.smartColor(smartList) }
    private var hasMenu: Bool { smartList != .completed }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(.systemBackground).ignoresSafeArea()

            if isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: smartList.iconName,
                    description: Text(emptyDescription)
                )
            } else {
                SmartListCollectionView(
                    store: store,
                    prefs: prefs,
                    groups: snapshotGroups,
                    onToggleItem: { toggleAndLinger($0) },
                    onIncrementHabit: { incrementHabitAndLinger($0) },
                    onSoftDeleteItem: { id in
                        Task { try? await store.softDelete(id) }
                    },
                    onShowItemDetail: { detailItem = $0 }
                )
                .ignoresSafeArea(edges: .bottom)
            }

            FloatingAddButton(
                tint: tint,
                action: {
                    if let id = store.defaultCaptureListId {
                        captureTarget = CaptureTarget(listId: id, section: nil)
                    }
                },
                isInteracting: $fabIsInteracting
            )
            .opacity(store.defaultCaptureListId == nil ? 0.4 : 1)
            .allowsHitTesting(store.defaultCaptureListId != nil)
            .padding(.trailing, 16)
            .padding(.bottom, 0)
        }
        .navigationTitle(smartList.displayName)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarTitleColor(tint)
        .tint(tint)
        .toolbar {
            if hasMenu {
                ToolbarItem(placement: .topBarTrailing) {
                    smartListMenu()
                }
            }
        }
        .sheet(item: $captureTarget) { target in
            QuickCaptureSheet(store: store, defaultListId: target.listId, defaultSection: target.section)
        }
        .sheet(item: $detailItem) { item in
            ItemDetailSheet(item: item, store: store)
        }
    }

    // MARK: - Snapshot builder

    /// Convert the smart list's data structures into the row-level model
    /// `SmartListCollectionView` consumes.
    private var snapshotGroups: [SmartListGroup] {
        switch smartList {
        case .scheduled:
            return scheduledGroups.map { g in
                var rows: [SmartListRow] = [
                    .sectionTitle(id: "title.\(g.label)", text: g.label, isOverdue: g.isOverdue)
                ]
                rows.append(contentsOf: g.items.map { .item(id: $0.id, indent: 0) })
                return SmartListGroup(id: "scheduled.\(g.label)", rows: rows)
            }
        case .all:
            return allViewLists.map { entry in
                var rows: [SmartListRow] = [
                    .listHeader(listId: entry.list.id, name: entry.list.name, color: entry.list.color)
                ]
                for (offset, bucket) in entry.buckets.enumerated() {
                    if let name = bucket.name {
                        rows.append(.sectionTitle(
                            id: "all.\(entry.list.id).bucket.\(offset)",
                            text: name,
                            isOverdue: false
                        ))
                    }
                    let flat = flattenForAll(bucket.parents)
                    rows.append(contentsOf: flat.map { .item(id: $0.item.id, indent: $0.indent) })
                }
                return SmartListGroup(id: "all.\(entry.list.id)", rows: rows)
            }
        default:
            return [SmartListGroup(
                id: "flat",
                rows: flatItems.map { .item(id: $0.id, indent: 0) }
            )]
        }
    }

    // MARK: - Data

    /// Flat list used by non-scheduled smart lists (Flagged / Urgent /
    /// All / Completed).
    private var flatItems: [Item] {
        let raw = store.items(
            for: smartList,
            showCompleted: prefs.showCompleted(for: prefsKey),
            lingering: lingeringIds
        )
        return raw.sortedBy(prefs.sort(for: prefsKey), direction: prefs.sortDirection(for: prefsKey))
    }

    private var isEmpty: Bool {
        switch smartList {
        case .scheduled: return scheduledGroups.isEmpty
        case .all:       return allViewLists.isEmpty
        default:         return flatItems.isEmpty
        }
    }

    // MARK: - All view (per-list grouping with sections)

    /// One entry per non-empty user list, in sidebar order. Each entry carries
    /// the section buckets to render under that list's header.
    private struct AllViewEntry {
        let list: ItemList
        /// Buckets to render. `name == nil` means uncategorized — render
        /// items without a section header.
        let buckets: [(sectionKey: String?, name: String?, parents: [Item])]
    }

    private var allViewLists: [AllViewEntry] {
        let showCompleted = prefs.showCompleted(for: prefsKey)
        let orderedLists = store.lists
            .filter { $0.deletedAt == nil }
            .sorted { $0.position < $1.position }

        var entries: [AllViewEntry] = []
        for list in orderedLists {
            let parents = store.items.filter { item in
                item.listId == list.id
                    && item.deletedAt == nil
                    && item.parentId == nil
                    && item.type != .habit
                    && (showCompleted || !item.isComplete || lingeringIds.contains(item.id))
            }
            .sortedBy(prefs.sort(for: prefsKey), direction: prefs.sortDirection(for: prefsKey))

            if parents.isEmpty { continue }

            var buckets: [(String?, String?, [Item])] = []
            let uncategorized = parents.filter { $0.section == nil }
            if !uncategorized.isEmpty {
                buckets.append((nil, nil, uncategorized))
            }
            for section in list.sections.sorted(by: { $0.position < $1.position }) {
                let key = section.id.uuidString
                let group = parents.filter { $0.section == key }
                if !group.isEmpty {
                    buckets.append((key, section.name, group))
                }
            }
            if !buckets.isEmpty {
                entries.append(AllViewEntry(list: list, buckets: buckets))
            }
        }
        return entries
    }

    private func flattenForAll(_ parents: [Item]) -> [(item: Item, indent: Int)] {
        let showCompleted = prefs.showCompleted(for: prefsKey)
        var out: [(Item, Int)] = []
        for parent in parents {
            out.append((parent, 0))
            let kids = store.items
                .filter { item in
                    item.parentId == parent.id
                        && item.deletedAt == nil
                        && (showCompleted || !item.isComplete || lingeringIds.contains(item.id))
                }
                .sortedBy(prefs.sort(for: prefsKey), direction: prefs.sortDirection(for: prefsKey))
            for child in kids {
                out.append((child, 1))
                let g = store.items
                    .filter { item in
                        item.parentId == child.id
                            && item.deletedAt == nil
                            && (showCompleted || !item.isComplete || lingeringIds.contains(item.id))
                    }
                    .sortedBy(prefs.sort(for: prefsKey), direction: prefs.sortDirection(for: prefsKey))
                for grand in g {
                    out.append((grand, 2))
                }
            }
        }
        return out
    }

    /// Date-grouped sections for the `.scheduled` smart list. When
    /// "Show Overdue" is on, overdue items appear in a leading "Overdue"
    /// section; otherwise they're hidden.
    private var scheduledGroups: [(label: String, items: [Item], isOverdue: Bool)] {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        let showCompleted = prefs.showCompleted(for: prefsKey)
        let showOverdueItems = prefs.showOverdue(for: prefsKey)

        let raw = store.items.filter { item in
            if item.deletedAt != nil { return false }
            if lingeringIds.contains(item.id) { return true }
            if item.type == .habit { return false }
            guard let due = item.due else { return false }
            if item.done && !showCompleted { return false }
            if due >= startOfToday { return true }
            return showOverdueItems
        }

        var overdue: [Item] = []
        var future: [Item] = []
        for item in raw {
            guard let due = item.due else { continue }
            if due < startOfToday {
                overdue.append(item)
            } else {
                future.append(item)
            }
        }

        let timeSort: (Item, Item) -> Bool = { lhs, rhs in
            (lhs.due ?? .distantFuture) < (rhs.due ?? .distantFuture)
        }

        var groups: [(label: String, items: [Item], isOverdue: Bool)] = []
        if !overdue.isEmpty {
            groups.append((label: "Overdue", items: overdue.sorted(by: timeSort), isOverdue: true))
        }
        let buckets = Dictionary(grouping: future) { item -> Date in
            cal.startOfDay(for: item.due ?? .distantFuture)
        }
        for day in buckets.keys.sorted() {
            let sorted = (buckets[day] ?? []).sorted(by: timeSort)
            groups.append((label: Self.sectionLabel(for: day), items: sorted, isOverdue: false))
        }
        return groups
    }

    private static func sectionLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInTomorrow(date)  { return "Tomorrow" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: .now),
            to: cal.startOfDay(for: date)
        ).day ?? 0
        let f = DateFormatter()
        f.locale = Locale.current
        if (-6...6).contains(days) {
            f.dateFormat = "EEEE"      // full weekday name
        } else {
            f.dateStyle = .long
            f.timeStyle = .none
        }
        return f.string(from: date)
    }

    // MARK: - Menu + bindings

    @ViewBuilder
    private func smartListMenu() -> some View {
        Menu {
            if smartList != .scheduled {
                let currentMode = prefs.sort(for: prefsKey)
                Menu {
                    Picker(selection: sortBinding) {
                        ForEach(ListViewPreferences.SortMode.allCases, id: \.self) { mode in
                            Label(mode.label, systemImage: mode.systemImage).tag(mode)
                        }
                    } label: { EmptyView() }
                    .pickerStyle(.inline)

                    if currentMode != .manual {
                        Picker(selection: sortDirectionBinding) {
                            ForEach(ListViewPreferences.SortDirection.allCases, id: \.self) { dir in
                                Text(currentMode.directionLabel(dir)).tag(dir)
                            }
                        } label: { EmptyView() }
                        .pickerStyle(.inline)
                    }
                } label: {
                    Label {
                        Text("Sort By")
                        Text(currentMode.label)
                    } icon: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }

            Toggle(isOn: showCompletedBinding) {
                Label("Show Completed", systemImage: "checkmark.circle")
            }

            if smartList == .scheduled {
                Toggle(isOn: showOverdueBinding) {
                    Label("Show Overdue", systemImage: "exclamationmark.triangle")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .accessibilityLabel("View Options")
        }
    }

    private var sortBinding: Binding<ListViewPreferences.SortMode> {
        Binding(
            get: { prefs.sort(for: prefsKey) },
            set: { prefs.setSort($0, for: prefsKey) }
        )
    }

    private var sortDirectionBinding: Binding<ListViewPreferences.SortDirection> {
        Binding(
            get: { prefs.sortDirection(for: prefsKey) },
            set: { prefs.setSortDirection($0, for: prefsKey) }
        )
    }

    private var showCompletedBinding: Binding<Bool> {
        Binding(
            get: { prefs.showCompleted(for: prefsKey) },
            set: { prefs.setShowCompleted($0, for: prefsKey) }
        )
    }

    private var showOverdueBinding: Binding<Bool> {
        Binding(
            get: { prefs.showOverdue(for: prefsKey) },
            set: { prefs.setShowOverdue($0, for: prefsKey) }
        )
    }

    /// Mirror of `ListDetailView.toggleAndLinger` — keeps a just-completed
    /// item visible for 1.5s so it fades out instead of vanishing. For the
    /// Completed smart list this is a no-op (linger isn't needed; items
    /// stay visible by definition).
    private func toggleAndLinger(_ item: Item) {
        let willComplete = !item.done
        Task { try? await store.toggleDone(item.id) }
        let showCompleted = prefs.showCompleted(for: prefsKey)
        guard willComplete, !showCompleted, smartList != .completed else {
            lingeringIds.remove(item.id)
            return
        }
        startLinger(for: item.id)
    }

    private func incrementHabitAndLinger(_ item: Item) {
        let key = HabitCycle.key(for: item.frequency ?? .daily, on: .now)
        let current = item.completionLog[key] ?? 0
        let willComplete = current + 1 >= item.goalPerCycle
        Task { try? await store.incrementHabit(item.id) }
        let showCompleted = prefs.showCompleted(for: prefsKey)
        guard willComplete, !showCompleted, smartList != .completed else { return }
        startLinger(for: item.id)
    }

    private func startLinger(for id: UUID) {
        lingeringIds.insert(id)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.4)) {
                _ = lingeringIds.remove(id)
            }
        }
    }

    private var emptyTitle: String {
        switch smartList {
        case .today:     return "Nothing today"
        case .scheduled: return "Nothing scheduled"
        case .flagged:   return "No flagged items"
        case .urgent:    return "No urgent items"
        case .completed: return "Nothing completed yet"
        case .all:       return "Nothing here"
        }
    }

    private var emptyDescription: String {
        switch smartList {
        case .today:     return "Items due today appear here."
        case .scheduled: return "Items with a future date appear here."
        case .flagged:   return "Flag an item to keep it nearby."
        case .urgent:    return "Items with the urgent trigger active appear here."
        case .completed: return "Items you finish appear here, sorted by completion time."
        case .all:       return "Add an item to a list to see it here."
        }
    }
}
