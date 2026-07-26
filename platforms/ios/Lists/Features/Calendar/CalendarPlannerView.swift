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

struct CalendarPlannerView: View {
    private struct PendingRecurringChange: Identifiable {
        let id = UUID()
        let entry: CalendarEntry
        let start: Date
        let end: Date
    }

    private enum RecurringChangeScope {
        case onlyThis
        case thisAndFuture
        case entireSeries
    }

    let store: ItemStore
    let items: [Item]
    let surfaceKey: String
    let tint: Color
    let defaultListId: String?
    let defaultSection: String?
    let defaultNewItemType: Item.ItemType
    var defaultViewKind: CalendarViewKind = .month
    var appliesGlobalListVisibility = false
    var moveSession: ItemMoveSession?
    var documentLinkSession: DocumentLinkSession?

    @State private var preferences = CalendarPreferences()
    @State private var anchor = Date.now
    @State private var selectedDate = Date.now
    @State private var captureRequest: CalendarCaptureRequest?
    @State private var detailItem: Item?
    @State private var datePickerPresented = false
    @State private var mutationError: String?
    @State private var pendingRecurringChange: PendingRecurringChange?
    @State private var fabIsInteracting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var calendar: Calendar { .current }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                rangeBar
                Divider()
                calendarContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if defaultListId != nil && !isDestinationModeActive {
                FloatingAddButton(
                    tint: tint,
                    action: { presentCapture(at: selectedDate, asEvent: false, allDay: true) },
                    onLongPress: {
                        presentCapture(at: selectedDate, asEvent: true, allDay: false)
                    },
                    isInteracting: $fabIsInteracting
                )
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .accessibilityIdentifier("calendar.add")
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
            Button("Entire Series") {
                applyPendingRecurringChange(.entireSeries)
            }
            Button("Cancel", role: .cancel) {
                pendingRecurringChange = nil
            }
        } message: {
            Text("Choose which occurrences should use the new date or time.")
        }
        .tint(tint)
    }

    private var rangeBar: some View {
        HStack(spacing: 8) {
            Button {
                shift(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous \(viewKind.label)")
            .accessibilityIdentifier("calendar.previous")

            Button {
                datePickerPresented = true
            } label: {
                Text(CalendarDateMath.title(for: viewKind, anchor: anchor, calendar: calendar))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $datePickerPresented) {
                DatePicker(
                    "Date",
                    selection: anchorBinding,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()
                .presentationCompactAdaptation(.popover)
            }
            .accessibilityIdentifier("calendar.range")

            Button {
                shift(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next \(viewKind.label)")
            .accessibilityIdentifier("calendar.next")

            Spacer(minLength: 4)

            Button("Today") {
                withPlannerAnimation {
                    anchor = .now
                    selectedDate = .now
                }
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier("calendar.today")

            viewMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var viewMenu: some View {
        Menu {
            Picker("Calendar View", selection: viewKindBinding) {
                ForEach(CalendarViewKind.allCases) { kind in
                    Label(kind.label, systemImage: kind.systemImage)
                        .tag(kind)
                }
            }

            if viewKind == .month {
                Divider()
                Picker("Month Layout", selection: monthDensityBinding) {
                    ForEach(CalendarMonthDensity.allCases) { density in
                        Text(density.label).tag(density)
                    }
                }
            }

            Divider()
            Toggle("Show Weekends", isOn: $preferences.showWeekends)
            Toggle("Week Numbers", isOn: $preferences.showWeekNumbers)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 30, height: 30)
        }
        .accessibilityLabel("Calendar View Options")
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
                onDuplicate: duplicate
            )
        case .day, .threeDay, .week:
            CalendarTimelineView(
                days: timelineDays,
                index: entryIndex,
                calendar: calendar,
                tint: tint,
                colorForEntry: colorForEntry,
                onOpen: open,
                onReschedule: reschedule,
                onDuplicate: duplicate,
                onCreateAt: { presentCapture(at: $0, asEvent: true, allDay: false) }
            )
        case .month:
            CalendarMonthView(
                anchor: anchor,
                selectedDate: $selectedDate,
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
        preferences.viewKind(for: surfaceKey, default: defaultViewKind)
    }

    private var monthDensity: CalendarMonthDensity {
        preferences.monthDensity(for: surfaceKey)
    }

    private var visibleInterval: DateInterval {
        CalendarDateMath.interval(for: viewKind, anchor: anchor, calendar: calendar)
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

    private var isDestinationModeActive: Bool {
        moveSession?.isActive == true || documentLinkSession?.isActive == true
    }

    private var viewKindBinding: Binding<CalendarViewKind> {
        Binding(
            get: { viewKind },
            set: { kind in
                withPlannerAnimation {
                    preferences.setViewKind(kind, for: surfaceKey)
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

    private var anchorBinding: Binding<Date> {
        Binding(
            get: { anchor },
            set: { value in
                withPlannerAnimation {
                    anchor = value
                    selectedDate = value
                    datePickerPresented = false
                }
            }
        )
    }

    private func shift(_ direction: Int) {
        withPlannerAnimation {
            let shifted = CalendarDateMath.shifted(
                anchor,
                kind: viewKind,
                direction: direction,
                calendar: calendar
            )
            anchor = shifted
            selectedDate = shifted
        }
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
        detailItem = store.item(entry.itemId)
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
        case .thisAndFuture, .entireSeries:
            // Lists stores one durable Markdown document for a series. Past
            // ledger entries are immutable, so changing the current document
            // naturally affects this occurrence and every future occurrence;
            // "Entire Series" additionally means the same thing because past
            // history is never rewritten.
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
                try await store.update(source)
                try await store.add(detached)
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
        let type = asEvent ? Item.ItemType.event : defaultNewItemType
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

    private func withPlannerAnimation(_ updates: () -> Void) {
        withAnimation(reduceMotion ? nil : .smooth, updates)
    }
}
