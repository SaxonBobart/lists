import SwiftUI

struct CalendarCaptureSchedule: Equatable, Sendable {
    let start: Date
    let end: Date?
    let isAllDay: Bool

    init(start: Date, end: Date? = nil, isAllDay: Bool) {
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }
}

private struct CalendarCaptureRequest: Identifiable {
    let id = UUID()
    let listId: String
    let section: String?
    let type: Item.ItemType
    let schedule: CalendarCaptureSchedule
}

private struct CalendarOccurrenceDetail: View {
    let entry: CalendarEntry
    let onOpenSource: () -> Void
    let onDuplicate: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(entry.title)
                        .font(.headline)
                    Text(entry.start, format: .dateTime.weekday().day().month().year())
                    if !entry.isAllDay {
                        Text(entry.start, format: .dateTime.hour().minute())
                    }
                    if entry.type == .event {
                        LabeledContent("Ends") {
                            Text(entry.end, format: .dateTime.day().month().hour().minute())
                        }
                    }
                }
                Section {
                    Text(entry.id.source == .projected
                         ? "This is a future occurrence. Open the repeating item to edit its current and future schedule."
                         : "This is a recorded occurrence. Opening the original item does not edit this historical date.")
                    Button("Open Original Item", action: onOpenSource)
                        .accessibilityIdentifier("calendar.occurrence.open.original")
                    Button("Duplicate as One-Off", action: onDuplicate)
                        .accessibilityIdentifier("calendar.occurrence.duplicate")
                }
            }
            .navigationTitle(entry.id.source == .projected ? "Future Occurrence" : "Past Occurrence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("calendar.occurrence.done")
                }
            }
        }
    }
}

struct CalendarPlannerView: View {
    @State private var timelinePaging = CalendarPagingState()
    private struct PendingRecurringChange: Identifiable {
        let id = UUID()
        let entry: CalendarEntry
        let start: Date
        let end: Date
    }

    private enum RecurringChangeScope {
        case onlyThis
        case thisAndFuture
    }

    let store: ItemStore
    let items: [Item]
    @Bindable var preferences: CalendarPreferences
    var overdueItems: [Item] = []
    let surfaceKey: String
    let tint: Color
    let defaultListId: String?
    let defaultSection: String?
    let defaultNewItemType: Item.ItemType
    var defaultViewKind: CalendarViewKind = .month
    var appliesGlobalListVisibility = false
    var moveSession: ItemMoveSession?
    var documentLinkSession: DocumentLinkSession?

    @State private var anchor = Date.now
    @State private var selectedDate = Date.now
    @State private var captureRequest: CalendarCaptureRequest?
    @State private var detailItem: Item?
    @State private var mutationError: String?
    @State private var pendingRecurringChange: PendingRecurringChange?
    @State private var pendingRecurringCut: CalendarEntry?
    @Environment(\.undoManager) private var undoManager
    @State private var pendingRecurringDeletion: CalendarEntry?
    @State private var occurrenceDetail: CalendarEntry?
    @State private var pendingOriginalItemID: UUID?
    @State private var timelineScrollRequestID = 0
    @State private var showsOverdue = false
    @Environment(\.moveShelfHeight) private var moveShelfHeight
    @State private var inboxTab = 0
    @State private var overdueItemToOpen: CalendarEntry?
    @State private var appliedOpeningView = false
    @State private var monthDisplayDate: Date?
    @State private var agendaInterval = CalendarDateMath.agendaWindow(
        centeredOn: .now,
        calendar: .current
    )
    @State private var agendaScrollTarget: Date?
    @State private var agendaScrollRequestID = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var adaptiveTimelineColumns = 2

    private var calendar: Calendar { .current }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                if isTimeline {
                    CalendarWeekStrip(selectedDate: selectedDate, visibleDates: visibleTimelineDates, paging: timelinePaging,
                                      calendar: calendar, tint: tint, showWeekends: preferences.showWeekends, onSelect: selectDestinationDate)
                    Divider().accessibilityIdentifier("calendar.week.divider")
                }
                calendarContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

        }
        .preference(key: CalendarMenuPreferenceKey.self, value: CalendarMenuContext(
            preferences: preferences, surfaceKey: surfaceKey, viewKind: viewKind,
            parentLabel: viewKind == .month ? (monthDisplayDate ?? anchor).formatted(.dateTime.year())
                : selectedDate.formatted(.dateTime.month(.wide))))
        .onAppear {
            guard !appliedOpeningView else { return }
            appliedOpeningView = true
            preferences.applyOpeningView(for: surfaceKey)
        }
        .onChange(of: viewKind) { _, kind in
            if kind == .month || kind == .year {
                anchor = selectedDate
                monthDisplayDate = nil
            }
        }
        .sheet(isPresented: $showsOverdue, onDismiss: {
            if let entry = overdueItemToOpen { overdueItemToOpen = nil; open(entry) }
        }) {
            NavigationStack {
                TabView(selection: $inboxTab) {
                    Tab("Overdue", systemImage: "clock.badge.exclamationmark", value: 0) {
                        if overdueEntries.isEmpty {
                            ContentUnavailableView("Nothing overdue", systemImage: "checkmark.circle")
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(overdueEntries) { entry in
                                        CalendarAgendaEntryRow(entry: entry, color: colorForEntry(entry),
                                            canToggle: canToggle(entry), onToggle: { toggle(entry) },
                                            onOpen: { overdueItemToOpen = entry; showsOverdue = false },
                                            onDuplicate: { duplicate(entry) }, actions: actionsForEntry(entry),
                                            instanceIdentifier: "calendar.overdue.entry.\(entry.itemId.uuidString)")
                                    }
                                }.padding(.horizontal, 16)
                            }
                        }
                    }
                    Tab("Invitations", systemImage: "envelope", value: 1) {
                        ContentUnavailableView("No invitations", systemImage: "envelope",
                            description: Text("Calendar invitations will appear here when calendar sync is available."))
                            .accessibilityIdentifier("calendar.invitations.empty")
                    }
                }
                .accessibilityIdentifier("calendar.inbox.tabs")
                .navigationTitle(inboxTab == 0 ? "Overdue" : "Invitations")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsOverdue = false }
                            .accessibilityIdentifier("calendar.overdue.done")
                    }
                }
            }.accessibilityIdentifier("calendar.overdue.sheet")
        }
        .onGeometryChange(for: Int.self) { CalendarTimelineGeometry.adaptiveColumns(width: $0.size.width) } action: { adaptiveTimelineColumns = $0 }
        .overlay(alignment: .bottom) {
            if documentLinkSession?.isActive != true {
                CalendarBottomControls(viewKind: viewKindBinding, yearLabel: Date.now.formatted(.dateTime.year()),
                    tint: tint, overdueCount: overdueEntries.count,
                    onToday: { navigate(to: .now) }, onOverdue: { showsOverdue = true },
                    onAdd: defaultListId == nil || moveSession?.isActive == true ? nil : {
                        presentCapture(at: defaultTimedCaptureDate(on: selectedDate), asEvent: true, allDay: false)
                    })
                    .padding(.bottom, moveSession?.isActive == true ? moveShelfHeight + 12 : 0)
            }
        }
        .sheet(item: $captureRequest) { request in
            QuickCaptureSheet(
                store: store,
                defaultListId: request.listId,
                defaultSection: request.section,
                defaultNewItemType: request.type,
                initialSchedule: request.schedule,
                onOpenCreatedItem: { detailItem = $0 }
            )
        }
        .sheet(item: $occurrenceDetail, onDismiss: {
            if let id = pendingOriginalItemID {
                pendingOriginalItemID = nil
                detailItem = store.item(id)
            }
        }) { entry in
            CalendarOccurrenceDetail(
                entry: entry,
                onOpenSource: {
                    pendingOriginalItemID = entry.itemId
                    occurrenceDetail = nil
                },
                onDuplicate: {
                    occurrenceDetail = nil
                    duplicate(entry)
                }
            )
        }
        .itemDetailCover(
            item: $detailItem,
            store: store,
            onBeginMove: { item in
                moveSession?.begin(item: item)
            },
            onBeginDocumentLink: { source in
                documentLinkSession?.begin(source: source)
            }
        )
        .itemMutationErrorAlert($mutationError)
        .confirmationDialog(
            "Change recurring item",
            isPresented: Binding(
                get: { pendingRecurringChange != nil },
                set: { if !$0 { pendingRecurringChange = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Only This") {
                applyPendingRecurringChange(.onlyThis)
            }
            Button("This and Future") {
                applyPendingRecurringChange(.thisAndFuture)
            }
            Button("Cancel", role: .cancel) {
                pendingRecurringChange = nil
            }
        } message: {
            Text("Choose which occurrences should use the new date or time.")
        }
        .confirmationDialog("Cut repeating item", isPresented: Binding(
            get: { pendingRecurringCut != nil }, set: { if !$0 { pendingRecurringCut = nil } }
        ), titleVisibility: .visible) {
            if let entry = pendingRecurringCut {
                Button("This Occurrence", role: .destructive) { cut(entry, onlyThis: true) }
                    .accessibilityIdentifier("calendar.cut.occurrence")
                Button("Entire Series", role: .destructive) { cut(entry, onlyThis: false) }
                    .accessibilityIdentifier("calendar.cut.series")
                Button("Cancel", role: .cancel) { pendingRecurringCut = nil }
            }
        }
        .alert("Delete repeating item?", isPresented: Binding(
            get: { pendingRecurringDeletion != nil },
            set: { if !$0 { pendingRecurringDeletion = nil } }
        )) {
            Button("Delete This Occurrence Only", role: .destructive) {
                applyRecurringDeletion(onlyThis: true)
            }
            .accessibilityIdentifier("calendar.delete.occurrence")
            Button("Delete All Future Occurrences", role: .destructive) {
                applyRecurringDeletion(onlyThis: false)
            }
            .accessibilityIdentifier("calendar.delete.future")
            Button("Cancel", role: .cancel) { pendingRecurringDeletion = nil }
                .accessibilityIdentifier("calendar.delete.cancel")
        } message: {
            Text("This item repeats. Do you want to delete just this occurrence or this and all future occurrences?")
        }
        .navigationBarTitleDisplayMode(.inline)
        .tint(tint)
    }

    private var overdueEntries: [CalendarEntry] {
        let candidates = Dictionary((items + overdueItems).map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest }).values.filter {
            preferences.includes($0.type) && (!appliesGlobalListVisibility || !preferences.hiddenListIds.contains($0.listId))
        }
        let overdue = ScheduledSmartListSections.split(Array(candidates), showCompleted: false,
            showOverdue: true, showPastEvents: false, showHabits: false, now: .now, calendar: calendar)
            .first(where: { $0.isOverdue })?.items ?? []
        return overdue.compactMap {
            CalendarProjection.currentEntry(for: $0, calendar: calendar)
        }
        .sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private var rangeBar: some View {
        Text(monthDisplayDate ?? anchor, format: .dateTime.month(.wide))
            .font(.largeTitle.bold())
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: monthDisplayDate)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityIdentifier("calendar.range")
    }

    @ViewBuilder
    private var calendarContent: some View {
        switch viewKind {
        case .list:
            CalendarAgendaView(
                days: displayDays,
                index: entryIndex,
                colorForEntry: colorForEntry,
                canToggle: canToggle,
                onToggle: toggle,
                onOpen: open,
                onDuplicate: duplicate,
                actionsForEntry: actionsForEntry,
                scrollTarget: agendaScrollTarget ?? selectedDate,
                scrollRequestID: agendaScrollRequestID,
                onExpandPast: expandAgendaPast,
                onExpandFuture: expandAgendaFuture
            )
        case .day, .twoDay, .week:
            CalendarTimelineView(
                days: timelineDays,
                selectedDate: $selectedDate,
                index: entryIndex,
                calendar: calendar,
                tint: tint,
                colorForEntry: colorForEntry,
                onOpen: open,
                onReschedule: reschedule,
                onDuplicate: duplicate,
                onCreateAt: { presentCapture(at: $0, asEvent: true, allDay: false) },
                visibleColumnCount: timelineColumnCount,
                scrollRequestID: timelineScrollRequestID,
                onVisibleRangeChange: updateTimelineAnchor,
                paging: timelinePaging,
                onDelete: deleteEvent, actionsForEntry: actionsForEntry
            )
        case .month:
            CalendarMonthView(
                anchor: anchor,
                selectedDate: monthSelection,
                density: monthDensity,
                showWeekends: preferences.showWeekends,
                showWeekNumbers: preferences.showWeekNumbers,
                calendar: calendar,
                tint: tint,
                index: entryIndex,
                colorForEntry: colorForEntry,
                canToggle: canToggle,
                onToggle: toggle,
                onOpen: open,
                onDuplicate: duplicate,
                actionsForEntry: actionsForEntry,
                onMoveToDay: moveToDay,
                onOpenDay: openDay,
                onPageMonth: { direction in
                    // The pager has already animated into place. Rebase without a second crossfade.
                    let date = CalendarDateMath.monthPage(selectedDate, offset: direction, calendar: calendar)
                    anchor = date
                    selectedDate = date
                    monthDisplayDate = nil
                },
                onDominantMonth: { monthDisplayDate = $0 },
                navigationHeader: AnyView(rangeBar)
            )
        case .year:
            CalendarYearView(
                anchor: anchor,
                calendar: calendar,
                showWeekends: preferences.showWeekends,
                showWeekNumbers: preferences.showWeekNumbers,
                tint: tint,
                onSelectMonth: { month in
                    withPlannerAnimation {
                        anchor = month
                        selectedDate = month
                        preferences.setViewKind(.month, for: surfaceKey)
                    }
                }
            )
        }
    }

    private var viewKind: CalendarViewKind {
        let stored = preferences.viewKind(for: surfaceKey, default: defaultViewKind)
        return stored.adaptiveValue
    }

    private var monthDensity: CalendarMonthDensity {
        preferences.monthDensity(for: surfaceKey)
    }

    private var visibleInterval: DateInterval {
        if viewKind == .list { return agendaInterval }
        if viewKind == .month {
            let previous = CalendarDateMath.monthPage(anchor, offset: -1, calendar: calendar)
            let next = CalendarDateMath.monthPage(anchor, offset: 1, calendar: calendar)
            return DateInterval(start: CalendarDateMath.monthGridInterval(containing: previous, calendar: calendar).start,
                end: CalendarDateMath.monthGridInterval(containing: next, calendar: calendar).end)
        }
        if viewKind == .day || viewKind == .twoDay || viewKind == .week {
            let start = calendar.date(byAdding: .day, value: -42, to: anchor)
                ?? anchor.addingTimeInterval(-42 * 86_400)
            let end = calendar.date(byAdding: .day, value: 43, to: anchor)
                ?? anchor.addingTimeInterval(43 * 86_400)
            return DateInterval(
                start: calendar.startOfDay(for: start),
                end: calendar.startOfDay(for: end)
            )
        }
        return CalendarDateMath.interval(for: viewKind, anchor: anchor, calendar: calendar)
    }

    private var projectedEntries: [CalendarEntry] {
        var snapshot = preferences.snapshot
        if !appliesGlobalListVisibility {
            snapshot = CalendarProjectionPreferences(
                recurrenceVisibility: snapshot.recurrenceVisibility,
                showTasks: snapshot.showTasks,
                showEvents: snapshot.showEvents,
                showHabits: snapshot.showHabits,
                showNotes: snapshot.showNotes,
                showCompletedItems: snapshot.showCompletedItems,
                showCompletedHistory: snapshot.showCompletedHistory,
                showMissedHistory: snapshot.showMissedHistory,
                hiddenListIds: []
            )
        }
        return CalendarProjection.entries(
            items: items,
            in: visibleInterval,
            preferences: snapshot,
            calendar: calendar
        )
    }

    private var entryIndex: CalendarEntryIndex {
        CalendarEntryIndex(
            entries: projectedEntries,
            interval: visibleInterval,
            calendar: calendar
        )
    }

    private var displayDays: [Date] {
        CalendarDateMath.days(in: visibleInterval, calendar: calendar)
    }

    private var timelineDays: [Date] {
        displayDays.filter {
            preferences.showWeekends || !calendar.isDateInWeekend($0)
        }
    }

    private var timelineColumnCount: Int {
        switch viewKind {
        case .day: return 1
        case .twoDay: return min(preferences.showWeekends ? 7 : 5, adaptiveTimelineColumns)
        case .week: return preferences.showWeekends ? 7 : 5
        default: return 1
        }
    }

    private var moveDestinationList: String? {
        scopedDestinationListId ?? moveSession?.movingItem(in: store)?.listId ?? defaultListId
    }

    private func commitCalendarMove(on date: Date, preserveTime: Bool, allDay: Bool? = nil) {
        guard let listId = moveDestinationList else { return }
        moveSession?.commit(toList: listId, date: date, preserveTime: preserveTime, allDay: allDay, store: store, calendar: calendar)
    }

    private var viewKindBinding: Binding<CalendarViewKind> {
        Binding(
            get: { viewKind },
            set: { kind in
                withPlannerAnimation {
                    anchor = selectedDate
                    preferences.setViewKind(kind, for: surfaceKey)
                    if kind == .list {
                        ensureAgendaContains(anchor)
                        agendaScrollTarget = anchor
                        agendaScrollRequestID += 1
                    }
                }
            }
        )
    }

    private var isTimeline: Bool { [.day, .twoDay, .week].contains(viewKind) }

    private var visibleTimelineDates: [Date] {
        let start = calendar.startOfDay(for: selectedDate)
        return timelineDays.filter { $0 >= start }.prefix(timelineColumnCount).map { $0 }
    }

    private var monthSelection: Binding<Date> {
        Binding(get: { selectedDate }, set: selectDestinationDate)
    }

    private func selectDestinationDate(_ date: Date) {
        if moveSession?.isActive == true { commitCalendarMove(on: date, preserveTime: true) }
        navigate(to: date)
    }

    private func openDay(_ date: Date) {
        preferences.setViewKind(preferences.dayLayout(for: surfaceKey), for: surfaceKey)
        navigate(to: date)
    }

    private func navigate(to date: Date) {
        withPlannerAnimation {
            anchor = date
            monthDisplayDate = nil
            selectedDate = date
            timelineScrollRequestID += 1
            if viewKind == .list {
                ensureAgendaContains(date)
                agendaScrollTarget = date
                agendaScrollRequestID += 1
            }
        }
    }

    private func ensureAgendaContains(_ date: Date) {
        guard !agendaInterval.contains(date) else { return }
        agendaInterval = CalendarDateMath.agendaWindow(centeredOn: date, calendar: calendar)
    }

    private func expandAgendaPast() {
        agendaInterval = CalendarDateMath.expandingAgendaWindow(
            agendaInterval,
            towardPast: true,
            calendar: calendar
        )
    }

    private func expandAgendaFuture() {
        agendaInterval = CalendarDateMath.expandingAgendaWindow(
            agendaInterval,
            towardPast: false,
            calendar: calendar
        )
    }

    private func updateTimelineAnchor(_ date: Date) {
        anchor = date
        selectedDate = date
    }

    private func colorForEntry(_ entry: CalendarEntry) -> Color {
        guard let list = store.lists.first(where: { $0.id == entry.listId }) else {
            return tint
        }
        return ListsTokens.listColor(list.color)
    }

    private func canToggle(_ entry: CalendarEntry) -> Bool {
        entry.isCompletable
            && entry.status != .missed
            && entry.id.source == .current
    }

    private func toggle(_ entry: CalendarEntry) {
        guard canToggle(entry) else { return }
        Task {
            do {

                    try await store.toggleDone(entry.itemId)

            } catch {
                mutationError = error.localizedDescription
            }
        }
    }

    private func open(_ entry: CalendarEntry) {
        if moveSession?.isActive == true {
            selectDestinationDate(entry.start)
            return
        }
        if documentLinkSession?.isActive == true,
           let item = store.item(entry.itemId) {
            documentLinkSession?.commit(to: item, store: store)
            return
        }
        if entry.id.source == .projected || entry.id.source == .history {
            occurrenceDetail = entry
        } else {
            detailItem = store.item(entry.itemId)
        }
    }

    private func reschedule(_ entry: CalendarEntry, start: Date, end: Date) {
        guard entry.isEditableOccurrence, let item = store.item(entry.itemId) else { return }
        if item.recurrence != nil {
            pendingRecurringChange = PendingRecurringChange(
                entry: entry,
                start: start,
                end: end
            )
            return
        }
        updateSchedule(item, start: start, end: end)
    }

    private func updateSchedule(_ original: Item, start: Date, end: Date) {
        var item = original
        let originalStart = item.due ?? start
        let originalDuration = (item.end ?? end).timeIntervalSince(originalStart)
        item.due = start
        if item.type == .event {
            item.end = end > start ? end : start.addingTimeInterval(max(60, originalDuration))
        }
        item.modifiedAt = .now
        Task {
            do {
                try await store.update(item)
            } catch {
                mutationError = error.localizedDescription
            }
        }
    }

    private func applyPendingRecurringChange(_ scope: RecurringChangeScope) {
        guard let change = pendingRecurringChange,
              let item = store.item(change.entry.itemId) else {
            pendingRecurringChange = nil
            return
        }
        pendingRecurringChange = nil

        switch scope {
        case .onlyThis:
            detachCurrentOccurrence(
                from: item,
                entry: change.entry,
                start: change.start,
                end: change.end
            )
        case .thisAndFuture:
            // Lists stores one durable Markdown document for a series while
            // past ledger entries remain immutable. Moving that document is
            // therefore explicitly a current-and-future operation.
            updateSchedule(item, start: change.start, end: change.end)
        }
    }

    private func detachCurrentOccurrence(
        from sourceItem: Item,
        entry: CalendarEntry,
        start: Date,
        end: Date
    ) {
        guard let rule = sourceItem.recurrence?.rrule,
              let currentDue = sourceItem.due else {
            updateSchedule(sourceItem, start: start, end: end)
            return
        }
        let recurrenceCalendar = RecurrenceEngine.calendar(
            forTimeZone: sourceItem.dueTimeZone
        )
        guard let next = RecurrenceEngine.nextOccurrence(
            after: currentDue,
            rrule: rule,
            calendar: recurrenceCalendar
        ) else {
            updateSchedule(sourceItem, start: start, end: end)
            return
        }

        var detached = sourceItem
        detached.id = UUID()
        detached.createdAt = .now
        detached.modifiedAt = detached.createdAt
        detached.due = start
        detached.end = detached.type == .event ? end : nil
        detached.recurrence = nil
        detached.recurrenceOccurrences = []
        detached.recurrenceSourceId = nil
        detached.recurrenceSuccessorId = nil
        detached.done = false
        detached.completedAt = nil

        var source = sourceItem
        let duration = (sourceItem.end ?? entry.end).timeIntervalSince(currentDue)
        source.due = next
        if source.type == .event {
            source.end = next.addingTimeInterval(max(60, duration))
        }
        if let openIndex = source.recurrenceOccurrences.firstIndex(where: {
            $0.status == .open
        }) {
            source.recurrenceOccurrences[openIndex].scheduledAt = next
        }
        source.modifiedAt = .now

        Task {
            do {
                try await store.add(detached)
                do {
                    try await store.update(source)
                } catch {
                    // Keep the durable series authoritative if its advance
                    // fails after the detached document was created.
                    try? await store.softDelete(detached.id)
                    throw error
                }
            } catch {
                mutationError = error.localizedDescription
            }
        }
    }

    private func deleteEvent(_ entry: CalendarEntry) {
        if entry.hasRecurrence {
            pendingRecurringDeletion = entry
        } else {
            removeCalendarItem(entry.itemId)
        }
    }

    private func applyRecurringDeletion(onlyThis: Bool) {
        guard let entry = pendingRecurringDeletion,
              let item = store.item(entry.itemId) else { return }
        pendingRecurringDeletion = nil
        if onlyThis, !entry.isEditableOccurrence {
            var updated = item
            if entry.id.source == .history {
                updated.recurrenceOccurrences.removeAll { $0.id == entry.id.occurrenceId }
            } else { updated.recurrence?.excludedDates.append(ISO8601.string(from: entry.start)) }
            Task {
                do { try await store.update(updated) }
                catch { mutationError = error.localizedDescription }
            }
        } else if onlyThis, let advanced = CalendarTimelinePolicy.deletingCurrentOccurrence(from: item) {
            Task {
                do { try await store.update(advanced) }
                catch { mutationError = error.localizedDescription }
            }
        } else {
            removeCalendarItem(entry.itemId)
        }
    }

    private func removeCalendarItem(_ id: UUID) {
        Task {
            do { try await store.softDelete(id) }
            catch { mutationError = error.localizedDescription }
        }
    }

    private var scopedDestinationListId: String? {
        surfaceKey.hasPrefix("list:") ? defaultListId : nil
    }

    private func clipboardDestination(_ entry: CalendarEntry) -> ItemPasteDestination {
        .init(listId: scopedDestinationListId, section: defaultSection)
    }

    private func actionsForEntry(_ entry: CalendarEntry) -> ItemActions? {
        guard let item = store.item(entry.itemId) else { return nil }
        return ItemActions(item: item, store: store, onOpen: { open(entry) },
            onDelete: { deleteEvent(entry) }, onError: { mutationError = $0 },
            onSchedule: { detailItem = item }, onMove: moveSession.map { session in { session.begin(item: item) } },
            undoManager: undoManager, destination: clipboardDestination(entry),
            onCut: {
                if entry.hasRecurrence { pendingRecurringCut = entry }
                else { cut(entry, onlyThis: false) }
            }, onCopy: { copy(entry) }, onDuplicate: { duplicate(entry) }, onToggle: { toggle(entry) }, allowsCompletion: canToggle(entry))
    }

    private func copy(_ entry: CalendarEntry) {
        guard var item = store.item(entry.itemId) else { return }
        item.due = entry.start
        item.end = item.type == .event ? entry.end : nil
        Task {
            do { try await ItemClipboard.shared.copy(item, store: store) }
            catch { mutationError = error.localizedDescription }
        }
    }

    private func cut(_ entry: CalendarEntry, onlyThis: Bool) {
        pendingRecurringCut = nil
        guard var item = store.item(entry.itemId) else { return }
        Task {
            do {
                if onlyThis && entry.hasRecurrence {
                    let original = item
                    item.due = entry.start
                    item.end = item.type == .event ? entry.end : nil
                    item.recurrence = nil
                    item.recurrenceOccurrences = []
                    item.recurrenceSourceId = nil
                    item.recurrenceSuccessorId = nil
                    let payload = try await ItemClipboard.shared.prepare(item, store: store)
                    try ItemClipboard.shared.write(payload)
                    if !entry.isEditableOccurrence {
                        var updated = original
                        if entry.id.source == .history {
                            updated.recurrenceOccurrences.removeAll { $0.id == entry.id.occurrenceId }
                        } else { updated.recurrence?.excludedDates.append(ISO8601.string(from: entry.start)) }
                        try await store.update(updated)
                    } else if let advanced = CalendarTimelinePolicy.deletingCurrentOccurrence(from: original) {
                        try await store.update(advanced)
                    } else { try await store.softDelete(original.id) }
                    ItemClipboard.shared.registerUndoCut {
                        if store.item(original.id)?.deletedAt != nil { try await store.restore(original.id) }
                        try await store.update(original)
                    }
                    undoManager?.registerUndo(withTarget: store) { target in
                        Task { @MainActor in
                            do {
                                if target.item(original.id)?.deletedAt != nil { try await target.restore(original.id) }
                                try await target.update(original)
                            } catch { target.reportClipboardFailure(error) }
                        }
                    }
                    undoManager?.setActionName("Cut Occurrence")
                } else { try await ItemClipboard.shared.cut(item, store: store, undoManager: undoManager) }
            } catch { mutationError = error.localizedDescription }
        }
    }

    private func duplicate(_ entry: CalendarEntry) {
        guard var item = store.item(entry.itemId) else { return }
        item.due = entry.start
        item.end = item.type == .event ? entry.end : nil
        Task {
            do {
                let payload = try await ItemClipboard.shared.prepare(item, store: store)
                try await ItemClipboard.shared.paste(payload, into: clipboardDestination(entry), store: store)
            } catch { mutationError = error.localizedDescription }
        }
    }

    private func moveToDay(_ itemId: UUID, _ originalStart: Date, _ day: Date) -> Bool {
        guard let entry = projectedEntries.first(where: {
            $0.itemId == itemId
                && abs($0.start.timeIntervalSince(originalStart)) < 1
                && $0.isEditableOccurrence
        }) else {
            return false
        }
        let targetDay = calendar.startOfDay(for: day)
        let newStart: Date
        if entry.isAllDay {
            newStart = targetDay
        } else {
            let time = calendar.dateComponents([.hour, .minute, .second], from: entry.start)
            newStart = calendar.date(
                bySettingHour: time.hour ?? 0,
                minute: time.minute ?? 0,
                second: time.second ?? 0,
                of: targetDay
            ) ?? targetDay
        }
        let duration = max(1, entry.end.timeIntervalSince(entry.start))
        reschedule(entry, start: newStart, end: newStart.addingTimeInterval(duration))
        return true
    }

    private func presentCapture(
        at date: Date,
        asEvent: Bool,
        allDay: Bool
    ) {
        if moveSession?.isActive == true {
            commitCalendarMove(on: date, preserveTime: false, allDay: allDay)
            return
        }
        guard let listId = defaultListId else { return }
        let start: Date
        if allDay {
            start = calendar.startOfDay(for: date)
        } else {
            start = date
        }
        let type = asEvent ? Item.ItemType.event : .task
        let end = type == .event
            ? EventDefaults.defaultEnd(for: start, allDay: allDay, calendar: calendar)
            : nil
        captureRequest = CalendarCaptureRequest(
            listId: listId,
            section: defaultSection,
            type: type,
            schedule: CalendarCaptureSchedule(start: start, end: end, isAllDay: allDay)
        )
    }

    private func defaultTimedCaptureDate(on day: Date) -> Date {
        if calendar.isDateInToday(day) {
            return EventDefaults.defaultStart()
        }
        return calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: calendar.startOfDay(for: day)
        ) ?? day
    }

    private func withPlannerAnimation(_ updates: () -> Void) {
        withAnimation(reduceMotion ? nil : .smooth, updates)
    }
}

struct CalendarWeekStrip: View {
    @State private var bounceTowardFuture = true
    @State private var bounceTrigger: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var rowHeight = 67.0
    let selectedDate: Date
    let visibleDates: [Date]
    var pageProgress: CGFloat = 0
    var paging: CalendarPagingState? = nil
    let calendar: Calendar
    let tint: Color
    let showWeekends: Bool
    let onSelect: (Date) -> Void

    private var week: [Date] {
        CalendarDateMath.weekStripDays(selected: selectedDate, visible: visibleDates, calendar: calendar)
    }

    var body: some View {
        GeometryReader { geometry in
            let cellWidth = geometry.size.width / 7
            let motion = CalendarDateMath.weekStripMotion(selected: selectedDate, visible: visibleDates,
                progress: Double((paging?.progress ?? pageProgress).rounded()), showWeekends: showWeekends, calendar: calendar)
            let highlightedDate = calendar.date(byAdding: .day, value: Int(motion.selectionStart), to: week[0]) ?? selectedDate
            let firstIndex = Int(floor(motion.viewport)) - 7
            let dates = (firstIndex..<(firstIndex + 21)).compactMap { calendar.date(byAdding: .day, value: $0, to: week[0]) }
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(dates, id: \.self) { day in
                        Text(day, format: .dateTime.weekday(.narrow))
                            .font(.caption2)
                            .foregroundStyle(calendar.isDateInWeekend(day) ? .tertiary : .secondary)
                            .frame(width: cellWidth)
                    }
                }
                .offset(x: (Double(firstIndex) - motion.viewport) * cellWidth)
                .frame(width: geometry.size.width, alignment: .leading)
                .clipped().accessibilityHidden(true)
                ZStack(alignment: .leading) {
                    if visibleDates.count > 1 {
                        Capsule().fill(Color.primary.opacity(0.12))
                            .frame(width: max(38, (motion.last - motion.first) * cellWidth + 38), height: 38)
                            .keyframeAnimator(initialValue: CGFloat(1), trigger: bounceTrigger) { [reduceMotion, bounceTowardFuture] pill, scale in
                                pill.scaleEffect(x: reduceMotion ? 1 : scale, y: 1, anchor: bounceTowardFuture ? .leading : .trailing)
                            } keyframes: { _ in
                                SpringKeyframe(CGFloat(1.08), duration: 0.10)
                                SpringKeyframe(CGFloat(1), duration: 0.30)
                            }
                            .offset(x: (motion.first - motion.viewport) * cellWidth + (cellWidth - 38) / 2)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: motion.first - motion.viewport)
                    }
                    HStack(spacing: 0) {
                        ForEach(dates, id: \.self) { day in
                            let dayIndex = Double(calendar.dateComponents([.day], from: week[0], to: day).day ?? 0)
                            let weight = dayIndex == motion.selectionStart ? 1 - motion.selectionFraction
                                : (dayIndex == motion.selectionEnd ? motion.selectionFraction : 0)
                            let selected = weight > 0.5
                            let today = calendar.isDateInToday(day)
                            Button { onSelect(day) } label: {
                                ZStack {
                                    ZStack {
                                        if selected {
                                            Circle().fill(today ? tint : Color.primary)
                                                .transition(.asymmetric(insertion: .scale(scale: 0), removal: .identity))
                                        }
                                    }
                                    .frame(width: 36, height: 36)
                                    .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72), value: selected)
                                    Text(day, format: .dateTime.day()).font(.body)
                                        .foregroundStyle(selected ? (today ? Color.white : Color(.systemBackground))
                                            : (today ? tint : Color.primary))
                                }
                                .frame(width: cellWidth, height: 38)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .disabled(!showWeekends && calendar.isDateInWeekend(day))
                            .opacity(!showWeekends && calendar.isDateInWeekend(day) ? 0.35 : 1)
                            .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("calendar.week.day.\(CalendarDateMath.dayIdentifier(day, calendar: calendar))")
                        }
                    }
                    .offset(x: (Double(firstIndex) - motion.viewport) * cellWidth)
                    .frame(width: geometry.size.width, alignment: .leading)
                    .clipped()
                }.frame(height: 38)
            }.padding(.vertical, 4)
                .onChange(of: highlightedDate) { old, new in
                    // Update direction together with the trigger, before starting the keyframes.
                    bounceTowardFuture = new > old
                    bounceTrigger = new
                }
        }
        .frame(height: rowHeight)
        .clipped()

    }
}

struct CalendarMenuContext: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.surfaceKey == rhs.surfaceKey && lhs.preferences === rhs.preferences
            && lhs.viewKind == rhs.viewKind && lhs.parentLabel == rhs.parentLabel
    }
    let preferences: CalendarPreferences
    let surfaceKey: String
    let viewKind: CalendarViewKind
    let parentLabel: String
}

struct CalendarMenuPreferenceKey: PreferenceKey {
    static var defaultValue: CalendarMenuContext? { nil }
    static func reduce(value: inout CalendarMenuContext?, nextValue: () -> CalendarMenuContext?) {
        if let next = nextValue() { value = next }
    }
}

private struct CalendarMenuEnvironmentKey: EnvironmentKey {
    static var defaultValue: CalendarMenuContext? { nil }
}

extension EnvironmentValues {
    var calendarMenuContext: CalendarMenuContext? {
        get { self[CalendarMenuEnvironmentKey.self] }
        set { self[CalendarMenuEnvironmentKey.self] = newValue }
    }
}

struct CalendarMenuScope: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var context: CalendarMenuContext?
    func body(content: Content) -> some View {
        content.environment(\.calendarMenuContext, context)
            .navigationBarBackButtonHidden(context?.viewKind.parentViewKind != nil)
            .toolbar {
                if let context, context.viewKind.parentViewKind != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(reduceMotion ? nil : .smooth) {
                                context.preferences.goToParent(for: context.surfaceKey)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                                Text(context.parentLabel).lineLimit(1)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .tint(.primary)
                        .accessibilityLabel("Back to \(context.parentLabel)")
                        .accessibilityIdentifier("calendar.level.back")
                    }
                }
            }
            .background {
                if context?.viewKind.parentViewKind != nil { CalendarEdgeBackNavigation() }
            }
            .onPreferenceChange(CalendarMenuPreferenceKey.self) { context = $0 }
    }
}

struct CalendarOverflowActions: View {
    @Environment(\.calendarMenuContext) private var context

    var body: some View {
        ClipboardUndoButton()
        if let context {
            CalendarDisplayOptions(preferences: context.preferences, surfaceKey: context.surfaceKey)
            Divider()
        }
    }
}

private struct CalendarDisplayOptions: View {
    @Bindable var preferences: CalendarPreferences
    let surfaceKey: String
    var body: some View {
        Menu("Calendar Options", systemImage: "calendar") {
            Menu("Default Calendar View", systemImage: "calendar") {
                Picker("Default Calendar View", selection: Binding(
                    get: { preferences.openingView(for: surfaceKey) },
                    set: { preferences.setOpeningView($0, for: surfaceKey) })) {
                    ForEach(CalendarOpeningView.allCases) { choice in
                        Label(choice.label, systemImage: choice.viewKind.systemImage).tag(choice)
                            .accessibilityIdentifier("calendar.opening.\(choice.rawValue.lowercased())")
                    }
                }
                .accessibilityIdentifier("calendar.opening.view")
            }
            .accessibilityIdentifier("calendar.opening.menu")
            Divider()
            Toggle("Show Weekends", isOn: $preferences.showWeekends)
                .accessibilityIdentifier("calendar.view.show.weekends")
            Toggle("Week Numbers", isOn: $preferences.showWeekNumbers)
                .accessibilityIdentifier("calendar.view.show.week.numbers")
            Picker("Month Markers", selection: Binding(
                get: { preferences.monthDensity(for: surfaceKey) },
                set: { preferences.setMonthDensity($0, for: surfaceKey) })) {
                ForEach(CalendarMonthDensity.allCases) { density in
                    Text(density.label).tag(density)
                }
            }.accessibilityIdentifier("calendar.month.markers")
        }.accessibilityIdentifier("calendar.display.menu")
    }
}

/// Keep the navigation controller's interactive edge pop when Calendar supplies
/// its own back button. Only the button walks Calendar's internal levels.
private struct CalendarEdgeBackNavigation: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.installIfVisible() }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.restore() }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var gesture: UIGestureRecognizer?
        private weak var previousDelegate: (any UIGestureRecognizerDelegate)?
        private weak var navigationHost: UIViewController?
        private var previousEnabled = false
        private var visible = false

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            visible = true
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installIfVisible()
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            installIfVisible()
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            visible = false
            restore()
        }

        func installIfVisible() {
            guard visible, let navigation = navigationController,
                  let edge = navigation.interactivePopGestureRecognizer else { return }
            var host: UIViewController = self
            while let parent = host.parent, parent !== navigation { host = parent }
            guard navigation.topViewController === host else { return }
            if gesture !== edge {
                restore()
                gesture = edge
                previousDelegate = edge.delegate
                previousEnabled = edge.isEnabled
                navigationHost = host
            }
            edge.delegate = self
            edge.isEnabled = navigation.viewControllers.count > 1
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigation = navigationController else { return false }
            return navigation.topViewController === navigationHost
                && navigation.viewControllers.count > 1
                && navigation.transitionCoordinator == nil
        }

        func restore() {
            if let gesture, gesture.delegate === self {
                gesture.delegate = previousDelegate
                // Disabling a recognizer here would cancel a pop already in progress.
                if gesture.state != .began && gesture.state != .changed {
                    gesture.isEnabled = previousEnabled
                }
            }
            gesture = nil
            previousDelegate = nil
            navigationHost = nil
        }
    }
}

/// Shared by runtime and snapshots so all bottom controls are checked together.
struct CalendarBottomControls: View {
    @Binding var viewKind: CalendarViewKind
    let yearLabel: String
    let tint: Color
    let overdueCount: Int
    let onToday: () -> Void
    let onOverdue: () -> Void
    let onAdd: (() -> Void)?

    @State private var availableWidth: CGFloat = 393

    var body: some View {
        BottomControlRow(spacing: availableWidth < 350 ? 2 : 8, alignment: .bottom) {
            Spacer(minLength: 0)
            if viewKind.parentViewKind == .month { viewMenu }
            CalendarOverdueBadgeButton(count: overdueCount, action: onOverdue)
                .frame(width: 64, height: 64)
            Button(action: onToday) {
                Image(systemName: "1.calendar")
                    .font(.system(size: 22))
                    .frame(width: 64, height: 64)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .foregroundStyle(.primary)
            .accessibilityLabel(viewKind == .year ? "Go to \(yearLabel)" : "Today")
            .accessibilityIdentifier("calendar.today")
            if let onAdd { addButton(action: onAdd) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    private func addButton(action onAdd: @escaping () -> Void) -> some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .glassEffect(.regular.tint(tint).interactive(), in: Circle())
        }
        .accessibilityLabel("Add event")
        .accessibilityIdentifier("calendar.add")
    }

    private var viewMenu: some View {
        Menu {
            Picker("Calendar View", selection: $viewKind) {
                ForEach([CalendarViewKind.day, .twoDay, .list]) { kind in
                    Label(kind.label, systemImage: kind.systemImage)
                        .tag(kind)
                        .accessibilityIdentifier("calendar.view.kind.\(kind.rawValue)")
                }
            }

        } label: {
            Image(systemName: viewKind.systemImage)
                .font(.system(size: 22))
                .frame(width: 64, height: 64)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .tint(.primary)
        .accessibilityLabel("Calendar view, \(viewKind.label)")
        .accessibilityIdentifier("calendar.view.menu")
    }

}

/// Native toolbar-item badges are also available when the item hosts a custom button.
private struct CalendarOverdueBadgeButton: UIViewRepresentable {
    let count: Int
    let action: () -> Void

    func makeUIView(context: Context) -> Toolbar { Toolbar(action: action) }
    func updateUIView(_ toolbar: Toolbar, context: Context) {
        toolbar.action = action
        let badge: UIBarButtonItem.Badge? = count > 0 ? .count(count) : nil
        if toolbar.item.badge != badge { toolbar.item.badge = badge }
        toolbar.button.accessibilityLabel = "Inbox, \(count) overdue items"
    }

    final class Toolbar: UIToolbar {
        let button = UIButton(type: .system)
        let item: UIBarButtonItem
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
            item = UIBarButtonItem(customView: button)
            super.init(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
            let appearance = UIToolbarAppearance()
            appearance.configureWithTransparentBackground()
            standardAppearance = appearance
            scrollEdgeAppearance = appearance
            compactAppearance = appearance
            directionalLayoutMargins = .zero
            clipsToBounds = false
            var configuration = UIButton.Configuration.glass()
            configuration.image = UIImage(systemName: "tray")
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22)
            configuration.baseForegroundColor = .label
            configuration.cornerStyle = .capsule
            button.configuration = configuration
            button.accessibilityIdentifier = "calendar.overdue.open"
            button.addAction(UIAction { [weak self] _ in self?.action() }, for: .touchUpInside)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 64),
                button.heightAnchor.constraint(equalToConstant: 64)
            ])
            item.hidesSharedBackground = true
            items = [item]
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}
