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
                List {
                    if smartList == .scheduled {
                        ForEach(scheduledGroups, id: \.label) { group in
                            sectionView(label: group.label, items: group.items, isOverdueSection: group.isOverdue)
                        }
                    } else {
                        Section {
                            flatRows(flatItems)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(fabIsInteracting)
                .animation(.easeInOut(duration: 0.4), value: lingeringIds)
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
    }

    // MARK: - Rows + sections

    @ViewBuilder
    private func flatRows(_ items: [Item]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
            ItemRow(
                item: item,
                isOverdue: isOverdue(item),
                store: store,
                onToggle: { toggleAndLinger(item) },
                onIncrementHabit: { incrementHabitAndLinger(item) },
                previousSiblingId: previousIdInSameList(at: idx, in: items)
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func sectionView(label: String, items: [Item], isOverdueSection: Bool) -> some View {
        Section {
            flatRows(items)
        } header: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOverdueSection ? .red : .secondary)
                .textCase(nil)
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
        return raw.sortedBy(prefs.sort(for: prefsKey))
    }

    private var isEmpty: Bool {
        smartList == .scheduled ? scheduledGroups.isEmpty : flatItems.isEmpty
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

    private func isOverdue(_ item: Item) -> Bool {
        guard let due = item.due else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    private func previousIdInSameList(at idx: Int, in items: [Item]) -> UUID? {
        guard idx > 0 else { return nil }
        let prev = items[idx - 1]
        return prev.listId == items[idx].listId ? prev.id : nil
    }

    // MARK: - Menu + bindings

    @ViewBuilder
    private func smartListMenu() -> some View {
        Menu {
            if smartList != .scheduled {
                Picker(selection: sortBinding) {
                    ForEach(ListViewPreferences.SortMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode)
                    }
                } label: {
                    Label("Sort By", systemImage: "arrow.up.arrow.down")
                }
                .pickerStyle(.menu)
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
