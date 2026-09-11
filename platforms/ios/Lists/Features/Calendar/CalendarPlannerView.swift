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
    @State private var monthReturnView: CalendarViewKind?
    @State private var mutationError: String?
    @State private var pendingRecurringChange: PendingRecurringChange?
    @State private var occurrenceDetail: CalendarEntry?
    @State private var pendingOriginalItemID: UUID?
    @State private var timelineScrollRequestID = 0
    @State private var overdueExpanded = false
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
                if !overdueEntries.isEmpty {
                    overdueSection
                    Divider()
                }
                rangeBar
                if isTimeline {
                    CalendarWeekStrip(selectedDate: selectedDate, visibleDates: visibleTimelineDates, paging: timelinePaging,
                                      calendar: calendar, tint: tint, showWeekends: preferences.showWeekends, onSelect: navigate)
                    Divider().accessibilityIdentifier("calendar.week.divider")
                }
                calendarContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if defaultListId != nil && !isDestinationModeActive {
                Button {
                    presentCapture(at: defaultTimedCaptureDate(on: selectedDate), asEvent: true, allDay: false)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular.tint(tint).interactive(), in: Circle())
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .accessibilityLabel("Add event")
                .accessibilityIdentifier("calendar.add")
            }
        }
        .onGeometryChange(for: Int.self) { CalendarTimelineGeometry.adaptiveColumns(width: $0.size.width) } action: { adaptiveTimelineColumns = $0 }
        .overlay(alignment: .bottomLeading) {
            if !isDestinationModeActive {
                Button("Today") { navigate(to: .now) }
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .padding(16)
                    .accessibilityIdentifier("calendar.today")
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
        .navigationBarTitleDisplayMode(.inline)
        .tint(tint)
    }

    private var overdueSection: some View {
        VStack(spacing: 0) {
            Button {
                withPlannerAnimation {
                    overdueExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text("\(overdueEntries.count) Overdue")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: overdueExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(overdueEntries.count) overdue items")
            .accessibilityValue(overdueExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("calendar.overdue.toggle")

            if overdueExpanded {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(overdueEntries) { entry in
                            CalendarAgendaEntryRow(
                                entry: entry,
                                color: colorForEntry(entry),
                                canToggle: canToggle(entry),
                                onToggle: { toggle(entry) },
                                onOpen: { open(entry) },
                                onDuplicate: { duplicate(entry) },
                                instanceIdentifier: "calendar.overdue.entry.\(entry.itemId.uuidString)"
                            )
                            if entry.id != overdueEntries.last?.id {
                                Divider()
                                    .padding(.leading, entry.isCompletable ? 52 : 16)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(maxHeight: 220)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .accessibilityIdentifier("calendar.overdue.list")
            }
        }
        .background(.bar)
    }

    private var overdueEntries: [CalendarEntry] {
        overdueItems.compactMap {
            CalendarProjection.currentEntry(for: $0, calendar: calendar)
        }
        .sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private var rangeBar: some View {
        HStack(spacing: 12) {
            if isTimeline {
                Button {
                    monthReturnView = viewKind
                    anchor = selectedDate
                    preferences.setViewKind(.month, for: surfaceKey)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.medium))
                        Text(anchor, format: .dateTime.month(.wide))
                    }
                    .font(.body)
                    .lineLimit(1)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(.primary)
                .accessibilityLabel("Choose date, \(anchor.formatted(.dateTime.month(.wide).year()))")
                .accessibilityIdentifier("calendar.range")
            } else {
                // This is context, not a disabled date-picker button.
                Group {
                    if viewKind == .year { Text(anchor, format: .dateTime.year()) }
                    else { Text(anchor, format: .dateTime.month(.wide).year()) }
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("calendar.range")
            }
            if !isTimeline {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 40) }
                    .accessibilityLabel("Previous \(viewKind.label)")
                    .accessibilityIdentifier("calendar.previous")
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 40) }
                    .accessibilityLabel("Next \(viewKind.label)")
                    .accessibilityIdentifier("calendar.next")
            }
            Spacer(minLength: 0)
            viewMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var viewMenu: some View {
        Menu {
            Picker("Calendar View", selection: viewKindBinding) {
                ForEach(availableViewKinds) { kind in
                    Label(kind.label, systemImage: kind.systemImage)
                        .tag(kind)
                        .accessibilityIdentifier("calendar.view.kind.\(kind.rawValue)")
                }
            }

            if viewKind == .month {
                Divider()
                Picker("Month Layout", selection: monthDensityBinding) {
                    ForEach(CalendarMonthDensity.allCases) { density in
                        Text(density.label)
                            .tag(density)
                            .accessibilityIdentifier("calendar.month.layout.\(density.rawValue)")
                    }
                }
            }

            Divider()
            Toggle("Show Weekends", isOn: $preferences.showWeekends)
                .accessibilityIdentifier("calendar.view.show.weekends")
            Toggle("Week Numbers", isOn: $preferences.showWeekNumbers)
                .accessibilityIdentifier("calendar.view.show.week.numbers")
        } label: {
            Image(systemName: viewKind.systemImage)
                .font(.system(size: 22))
                .frame(width: 24, height: 22)
                .padding(.vertical, 5)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .tint(.primary)
        .accessibilityLabel("Calendar view, \(viewKind.label)")
        .accessibilityIdentifier("calendar.view.menu")
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
                paging: timelinePaging
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
                onMoveToDay: moveToDay
            )
        case .year:
            CalendarYearView(
                anchor: anchor,
                calendar: calendar,
                index: entryIndex,
                showWeekends: preferences.showWeekends,
                showWeekNumbers: preferences.showWeekNumbers,
                tint: tint,
                colorForEntry: colorForEntry,
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

    private var availableViewKinds: [CalendarViewKind] {
        [.list, .day, .twoDay, .month, .year]
    }

    private var monthDensity: CalendarMonthDensity {
        preferences.monthDensity(for: surfaceKey)
    }

    private var visibleInterval: DateInterval {
        if viewKind == .list { return agendaInterval }
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

    private var isDestinationModeActive: Bool {
        moveSession?.isActive == true || documentLinkSession?.isActive == true
    }

    private var viewKindBinding: Binding<CalendarViewKind> {
        Binding(
            get: { viewKind },
            set: { kind in
                withPlannerAnimation {
                    monthReturnView = nil
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

    private var monthDensityBinding: Binding<CalendarMonthDensity> {
        Binding(
            get: { monthDensity },
            set: { preferences.setMonthDensity($0, for: surfaceKey) }
        )
    }

    private var isTimeline: Bool { [.day, .twoDay, .week].contains(viewKind) }

    private var visibleTimelineDates: [Date] {
        let start = calendar.startOfDay(for: selectedDate)
        return timelineDays.filter { $0 >= start }.prefix(timelineColumnCount).map { $0 }
    }

    private var monthSelection: Binding<Date> {
        Binding(get: { selectedDate }, set: { date in
            if let previous = monthReturnView {
                monthReturnView = nil
                preferences.setViewKind(previous, for: surfaceKey)
            }
            navigate(to: date)
        })
    }

    private func shift(_ direction: Int) {
        let shifted = CalendarDateMath.shifted(
            anchor,
            kind: viewKind,
            direction: direction,
            calendar: calendar
        )
        navigate(to: shifted)
    }

    private func navigate(to date: Date) {
        withPlannerAnimation {
            anchor = date
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
            && (entry.type == .habit || entry.id.source == .current)
    }

    private func toggle(_ entry: CalendarEntry) {
        guard canToggle(entry) else { return }
        Task {
            do {
                if entry.type == .habit {
                    if entry.status == .completed {
                        try await store.removeLatestCompletion(in: entry.start, for: entry.itemId)
                    } else {
                        try await store.incrementHabit(entry.itemId, now: entry.start)
                    }
                } else {
                    try await store.toggleDone(entry.itemId)
                }
            } catch {
                mutationError = error.localizedDescription
            }
        }
    }

    private func open(_ entry: CalendarEntry) {
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

    private func duplicate(_ entry: CalendarEntry) {
        guard var copy = store.item(entry.itemId) else { return }
        copy.id = UUID()
        copy.createdAt = .now
        copy.modifiedAt = copy.createdAt
        copy.due = entry.start
        copy.end = copy.type == .event ? entry.end : nil
        copy.recurrence = nil
        copy.recurrenceOccurrences = []
        copy.recurrenceSourceId = nil
        copy.recurrenceSuccessorId = nil
        copy.done = false
        copy.completedAt = nil
        copy.completions = []
        Task {
            do {
                try await store.add(copy)
            } catch {
                mutationError = error.localizedDescription
            }
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
                                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selected)
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
        }
        .frame(height: rowHeight)
        .clipped()

    }
}
