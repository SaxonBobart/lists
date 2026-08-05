import SwiftUI

/// Smart-list screen for query surfaces other than Today. Today adds its day
/// header and Today/Overdue sectioning on top of the same row grammar as the
/// other query surfaces.
///
/// `.scheduled` is special-cased to group items by their due date (Today
/// / Tomorrow / weekday / short date) and its menu offers visibility toggles
/// instead of sorting, since date grouping is the order. `.all` groups by list
/// and section; the remaining smart lists render as one flat section.
struct SmartListScreen: View {
    let store: ItemStore
    let smartList: SmartList
    let defaultNewItemType: Item.ItemType
    let moveSession: ItemMoveSession
    let documentLinkSession: DocumentLinkSession
    let habitsPluginEnabled: Bool

    @State private var captureTarget: CaptureTarget?
    @State private var fabIsInteracting = false
    @State private var lingeringIds: Set<UUID> = []
    @State private var prefs = ListViewPreferences()
    @State private var detailItem: Item?
    @State private var rowMutationError: String?

    private var prefsKey: String { "smart:\(smartList.rawValue)" }
    private var tint: Color { ListsTokens.smartColor(smartList) }
    private var hasMenu: Bool { true }
    private var bottomContentInset: CGFloat {
        isDestinationModeActive ? 0 : 96
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
                Color(.systemBackground).ignoresSafeArea()

                if effectiveViewMode == .calendar {
                    CalendarPlannerView(
                        store: store,
                        items: calendarItems,
                        surfaceKey: prefsKey,
                        tint: tint,
                        defaultListId: store.defaultCaptureListId,
                        defaultSection: nil,
                        defaultNewItemType: defaultNewItemType,
                        appliesGlobalListVisibility: smartList == .calendar,
                        moveSession: moveSession,
                        documentLinkSession: documentLinkSession
                    )
                } else if isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: smartList.iconName,
                        description: Text(emptyDescription)
                    )
                } else {
                    SmartListCollectionView(
                        store: store,
                        moveSession: moveSession,
                        documentLinkSession: documentLinkSession,
                        prefs: prefs,
                        groups: snapshotGroups,
                        onToggleItem: { toggleAndLinger($0) },
                        onIncrementHabit: { incrementHabitAndLinger($0) },
                        onSoftDeleteItem: { id in
                            Task {
                                do {
                                    try await store.softDelete(id)
                                } catch {
                                    rowMutationError = error.localizedDescription
                                }
                            }
                        },
                        onMutationFailure: { rowMutationError = $0 },
                        onShowItemDetail: openOrLink,
                        bottomContentInset: bottomContentInset
                    )
                    // Full-bleed so rows scroll under the glass nav bar; the
                    // controller is auto-tracked for large-title collapse.
                    .ignoresSafeArea()
                }

                if !isDestinationModeActive && effectiveViewMode != .calendar {
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
                    .padding(.bottom, 16)
                }
            }
        .navigationTitle(smartList.displayName)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarTitleColor(tint)
        .tint(tint)
        .toolbar {
            if hasMenu && !isDestinationModeActive {
                ToolbarItem(placement: .topBarTrailing) {
                    SmartListToolbarMenu(smartList: smartList, prefs: prefs)
                }
            }
        }
        .sheet(item: $captureTarget) { target in
            QuickCaptureSheet(
                store: store,
                defaultListId: target.listId,
                defaultSection: target.section,
                defaultNewItemType: defaultNewItemType,
                onOpenCreatedItem: { detailItem = $0 }
            )
        }
        .itemDetailCover(
            item: $detailItem,
            store: store,
            onBeginMove: beginMove,
            onBeginDocumentLink: beginDocumentLink
        )
        .itemMutationErrorAlert($rowMutationError)
    }

    // MARK: - Snapshot builder

    /// Convert the smart list's data structures into the row-level model
    /// `SmartListCollectionView` consumes.
    private var snapshotGroups: [SmartListGroup] {
        switch smartList {
        case .completed:
            return [SmartListGroup(
                id: "completed",
                rows: completedEntries.map(\.row)
            )]
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

    /// Flat list used by non-scheduled, non-All smart lists.
    private var flatItems: [Item] {
        let showPastEvents = prefs.showPastEvents(for: prefsKey)
        let raw = store.items(
            for: smartList,
            showCompleted: prefs.showCompleted(for: prefsKey),
            showPastEvents: showPastEvents,
            lingering: lingeringIds
        )
        return raw
            .filter { $0.isAvailable(in: itemTypePolicy) }
            .sortedBy(prefs.sort(for: prefsKey), direction: prefs.sortDirection(for: prefsKey))
    }

    private var effectiveViewMode: ListViewPreferences.ViewMode {
        let defaultMode: ListViewPreferences.ViewMode =
            smartList == .calendar ? .calendar : .list
        let requested = prefs.viewMode(for: prefsKey, default: defaultMode)
        return requested == .columns ? .list : requested
    }

    /// Query calendars retain the smart list's semantic filter while changing
    /// only its presentation. The dedicated Calendar tile is the global
    /// projection and therefore includes every active date-producing item.
    private var calendarItems: [Item] {
        let available = store.items.filter {
            $0.deletedAt == nil && $0.isAvailable(in: itemTypePolicy)
        }
        return available.filter {
            smartList.matches($0, includeCompleted: true)
        }
    }

    private var isEmpty: Bool {
        switch smartList {
        case .completed: return completedEntries.isEmpty
        case .scheduled: return scheduledGroups.isEmpty
        case .all:       return allViewLists.isEmpty
        default:         return flatItems.isEmpty
        }
    }

    // MARK: - All view (per-list grouping with sections)

    private var allViewLists: [AllSmartListSections.Entry] {
        AllSmartListSections.entries(
            lists: store.lists,
            items: availableItems,
            showCompleted: prefs.showCompleted(for: prefsKey),
            showPastEvents: prefs.showPastEvents(for: prefsKey),
            lingering: lingeringIds,
            sortMode: prefs.sort(for: prefsKey),
            sortDirection: prefs.sortDirection(for: prefsKey),
            now: .now,
            calendar: .current
        )
    }

    private func flattenForAll(_ parents: [Item]) -> [(item: Item, indent: Int)] {
        let showCompleted = prefs.showCompleted(for: prefsKey)
        let showPastEvents = prefs.showPastEvents(for: prefsKey)
        let now = Date.now
        let calendar = Calendar.current
        return ItemHierarchy.flattenForAll(
            parents: parents,
            allItems: availableItems,
            showCompleted: showCompleted,
            showPastEvents: showPastEvents,
            lingering: lingeringIds,
            now: now,
            calendar: calendar
        )
    }

    /// Date-grouped sections for the `.scheduled` smart list. When
    /// "Show Overdue" is on, unfinished actionable past items appear in a
    /// leading "Overdue" section. Past calendar events and completed items stay
    /// in date buckets when their visibility toggles are enabled.
    private var scheduledGroups: [(label: String, items: [Item], isOverdue: Bool)] {
        let now = Date.now
        let calendar = Calendar.current
        return ScheduledSmartListSections.split(
            availableItems,
            showCompleted: prefs.showCompleted(for: prefsKey),
            showOverdue: prefs.showOverdue(for: prefsKey),
            showPastEvents: prefs.showPastEvents(for: prefsKey),
            lingering: lingeringIds,
            now: now,
            calendar: calendar
        ).map { group in
            switch group.kind {
            case .overdue:
                return (label: "Overdue", items: group.items, isOverdue: true)
            case .day(let day):
                return (
                    label: Self.sectionLabel(for: day, now: now, calendar: calendar),
                    items: group.items,
                    isOverdue: false
                )
            }
        }
    }

    private var availableItems: [Item] {
        store.items.filter { $0.isAvailable(in: itemTypePolicy) }
    }

    private struct CompletedEntry {
        let row: SmartListRow
        let completedAt: Date
        let title: String
    }

    /// Completed is occurrence-aware for recurring documents. Each genuine
    /// completion is a row; missed occurrences never enter this projection.
    /// Non-recurring items retain their familiar one-item row.
    private var completedEntries: [CompletedEntry] {
        var entries: [CompletedEntry] = []
        for item in availableItems where item.deletedAt == nil {
            let completedOccurrences = item.recurrenceOccurrences.filter {
                $0.status == .completed && $0.completedAt != nil
            }
            if completedOccurrences.isEmpty {
                if item.isComplete(at: .now), let completedAt = item.completedAt {
                    entries.append(CompletedEntry(
                        row: .item(id: item.id, indent: 0),
                        completedAt: completedAt,
                        title: item.title
                    ))
                }
            } else {
                entries.append(contentsOf: completedOccurrences.compactMap { occurrence in
                    guard let completedAt = occurrence.completedAt else { return nil }
                    return CompletedEntry(
                        row: .recurrenceOccurrence(
                            itemId: item.id,
                            occurrenceId: occurrence.id
                        ),
                        completedAt: completedAt,
                        title: item.title
                    )
                })
            }
        }
        return entries.sorted {
            if $0.completedAt != $1.completedAt {
                return $0.completedAt > $1.completedAt
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var itemTypePolicy: ItemTypePolicy {
        ItemTypePolicy(habitsEnabled: habitsPluginEnabled)
    }

    private var isDestinationModeActive: Bool {
        moveSession.isActive || documentLinkSession.isActive
    }

    private func openOrLink(_ item: Item) {
        if documentLinkSession.isActive {
            documentLinkSession.commit(to: item, store: store)
        } else {
            detailItem = item
        }
    }

    private func beginMove(_ item: Item) {
        documentLinkSession.cancel()
        moveSession.begin(item: item)
    }

    private func beginDocumentLink(_ source: DocumentLinkSource) {
        moveSession.cancel()
        documentLinkSession.begin(source: source)
    }

    private static func sectionLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        if day == today { return "Today" }
        if day == calendar.date(byAdding: .day, value: 1, to: today) { return "Tomorrow" }
        if day == calendar.date(byAdding: .day, value: -1, to: today) { return "Yesterday" }
        let days = calendar.dateComponents(
            [.day],
            from: today,
            to: day
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

    private func toggleAndLinger(_ item: Item) {
        ItemCompletionLinger.toggle(
            item,
            store: store,
            showCompleted: keepsCompletedRowsVisible,
            lingeringIds: $lingeringIds,
            startLinger: startLinger,
            onFailure: { rowMutationError = $0 }
        )
    }

    private func incrementHabitAndLinger(_ item: Item) {
        ItemCompletionLinger.incrementHabit(
            item,
            store: store,
            showCompleted: keepsCompletedRowsVisible,
            lingeringIds: $lingeringIds,
            startLinger: startLinger,
            onFailure: { rowMutationError = $0 }
        )
    }

    private var keepsCompletedRowsVisible: Bool {
        smartList == .completed || prefs.showCompleted(for: prefsKey)
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
        case .calendar:  return "Nothing scheduled"
        case .scheduled: return "Nothing scheduled"
        case .flagged:   return "No flagged items"
        case .alarms:    return "No alarms"
        case .completed: return "Nothing completed yet"
        case .all:       return "Nothing here"
        case .tags:      return "No tags"
        }
    }

    private var emptyDescription: String {
        switch smartList {
        case .today:     return "Items due today appear here."
        case .calendar:  return "Dated items from your lists appear here."
        case .scheduled: return "Items with a future date appear here."
        case .flagged:   return "Flag an item to keep it nearby."
        case .alarms:    return "Items with Alarm turned on appear here."
        case .completed: return "Items you finish appear here, sorted by completion time."
        case .all:       return "Add an item to a list to see it here."
        case .tags:      return "Tag an item to see it here."
        }
    }
}
