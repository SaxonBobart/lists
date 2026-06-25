import SwiftUI

/// Bottom sheet for adding a new item. Tasks, notes, and events share the
/// Date/Time + Repeat/Early Reminder + Details layout.
/// Habits use a dedicated layout that mirrors `HabitDetailView` — a single
/// **Habit** section (Frequency, Goal per cycle, Reminder + time, Show
/// streak) plus the standard Details section.
struct QuickCaptureSheet: View {
    let store: ItemStore
    let defaultListId: String
    let defaultSection: String?
    let defaultNewItemType: Item.ItemType
    var onOpenCreatedItem: (Item) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    @AppStorage(BuiltInModulePreferences.habitsEnabledKey) private var habitsPluginEnabled = true

    @State private var selectedType: Item.ItemType
    @State private var title: String = ""
    @State private var tags: [String] = []

    // Date and Time
    @State private var hasDate: Bool = false
    @State private var due: Date = Self.defaultDue()
    @State private var hasTime: Bool = false
    @State private var hasReminder: Bool = false
    @State private var hasAlarm: Bool = false
    @State private var dueTimeZone: String? = nil

    /// Which inline picker is currently visible. Separated from `hasDate` /
    /// `hasTime` so the user can collapse the picker without disabling the
    /// row — tapping the row label flips this; the switch flips enable state.
    private enum ExpandedPicker { case none, date, time }
    @State private var expandedPicker: ExpandedPicker = .none

    // Repeat + Early Reminder
    @State private var repeatPreset: RepeatPreset = .never
    @State private var customRRule: String? = nil
    @State private var endRepeatOn: Bool = false
    @State private var endRepeatDate: Date = Self.defaultEndRepeat()
    @State private var earlyPreset: EarlyReminderPreset = .none
    @State private var customEarly: EarlyReminder? = nil

    // Details
    @State private var flagged: Bool = false
    @State private var priority: Item.Priority = .none
    @State private var section: String? = nil
    @State private var listId: String
    @State private var goalPerCycle: Int = 1
    @State private var habitFlexibleGoal: Bool = false
    @State private var showStreak: Bool = true

    // Event-only fields (start + end + completable)
    @State private var endDate: Date = Self.defaultDue().addingTimeInterval(3600)
    @State private var completable: Bool = false
    /// All-day event toggle. Mirrors the editor: when on, the Starts/Ends pills
    /// drop their time component (`displayedComponents` becomes `[.date]`).
    @State private var allDay: Bool = false

    // Habit-only fields (mirror HabitDetailView's Details tab)
    @State private var habitFrequency: HabitFrequency = .daily
    @State private var hasHabitReminderTime: Bool = false
    @State private var habitReminderTime: Date = Self.defaultHabitReminderTime()

    // Sub-sheet presentation
    @State private var showRepeatCustom = false
    @State private var showEarlyCustom = false
    @State private var showTimeZonePicker = false
    @State private var showSectionPicker = false
    @State private var showDiscardConfirm = false
    /// Set to true just before calling `dismiss()` from the Discard button so
    /// the `SheetDismissInterceptor` allows the dismissal to go through even
    /// while the form is still dirty.
    @State private var pendingDismiss = false

    init(
        store: ItemStore,
        defaultListId: String = ItemList.inboxId,
        defaultSection: String? = nil,
        defaultNewItemType: Item.ItemType = .task,
        onOpenCreatedItem: @escaping (Item) -> Void = { _ in }
    ) {
        self.store = store
        self.defaultListId = defaultListId
        self.defaultSection = defaultSection
        self.defaultNewItemType = defaultNewItemType
        self.onOpenCreatedItem = onOpenCreatedItem
        _listId = State(initialValue: defaultListId)
        let initialType = BuiltInModulePreferences.effectiveItemType(
            defaultNewItemType,
            habitsEnabled: BuiltInModulePreferences.isEnabled(.habits)
        )
        _selectedType = State(initialValue: initialType)
        _repeatPreset = State(initialValue: initialType == .habit ? .daily : .never)
        _section = State(initialValue: defaultSection)
    }

    var body: some View {
        NavigationStack {
            form
                .safeAreaInset(edge: .top, spacing: 0) { pickerInset }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .background {
                    // While the discard popover is open we drop the modal
                    // flag so the popover's natural tap-outside dismiss
                    // works — otherwise the sheet's `isModalInPresentation`
                    // bleeds into the popover and traps the user.
                    SheetDismissInterceptor(
                        preventDismiss: isDirty && !showDiscardConfirm && !pendingDismiss,
                        onAttempt: { showDiscardConfirm = true }
                    )
                }
                .navigationTitle("New Item")
                .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if isDirty {
                            showDiscardConfirm = true
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel("Cancel")
                    }
                    .tint(Color.primary)
                    .accessibilityIdentifier("quickcapture.cancel")
                    .popover(isPresented: $showDiscardConfirm) {
                        QuickCaptureDiscardPopover(
                            title: "Are you sure you want to discard this new item?",
                            onDiscard: discardChanges
                        )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        add(openCreatedItem: true)
                    } label: {
                        Image(systemName: "text.document")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .accessibilityLabel("Add and Open Notes")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(ListsTokens.documentAccent)
                    .disabled(trimmedTitle.isEmpty)
                    .accessibilityIdentifier("quickcapture.saveAndOpenNotes")
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        add(openCreatedItem: false)
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .accessibilityLabel("Add")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(ListsTokens.accent)
                    .disabled(trimmedTitle.isEmpty)
                    .accessibilityIdentifier("quickcapture.save")
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    titleFocused = true
                }
            }
            .onChange(of: selectedType) { oldValue, newValue in
                snapRepeatPreset(oldValue: oldValue, newValue: newValue)
                // Events always carry a start + end (like the editor). Seed a
                // sensible end if the carried-over value isn't after the start.
                if newValue == .event, endDate <= due {
                    endDate = due.addingTimeInterval(3600)
                }
            }
            .onChange(of: habitsPluginEnabled) { _, enabled in
                if !enabled, selectedType == .habit {
                    selectedType = .task
                }
            }
            .onChange(of: hasDate) { oldValue, newValue in
                withAnimation(.smooth) {
                    if newValue && !oldValue {
                        if !hasReminder { hasReminder = true }
                        // Only auto-expand the calendar when Time isn't also
                        // being turned on — otherwise the Time cascade wants
                        // the time wheel and we'd clobber it here.
                        if !hasTime { expandedPicker = .date }
                    } else if oldValue && !newValue {
                        hasTime = false
                        hasReminder = false
                        earlyPreset = .none
                        customEarly = nil
                        hasAlarm = false
                        expandedPicker = .none
                    }
                }
            }
            .onChange(of: hasTime) { oldValue, newValue in
                withAnimation(.smooth) {
                    if newValue && !oldValue {
                        if !hasDate { hasDate = true }
                        if !hasReminder { hasReminder = true }
                        expandedPicker = .time
                    } else if oldValue && !newValue {
                        hasAlarm = false
                        expandedPicker = .none
                    }
                }
            }
            .onChange(of: hasReminder) { _, newValue in
                withAnimation(.smooth) {
                    if newValue {
                        if !hasDate { hasDate = true }
                        // Reminder does NOT auto-enable Time — date-only
                        // reminders are valid (fire at start of day). Only
                        // expand the time wheel if the user already turned
                        // Time on themselves.
                        if hasTime { expandedPicker = .time }
                    } else {
                        earlyPreset = .none
                        customEarly = nil
                        hasAlarm = false
                    }
                }
            }
            .onChange(of: repeatPreset) { _, newValue in
                if newValue == .never {
                    endRepeatOn = false
                }
            }
            .sheet(isPresented: $showRepeatCustom) {
                CustomRepeatSheet(initialRRule: customRRule, startDate: hasDate ? due : .now) { rrule in
                    customRRule = rrule
                }
            }
            .sheet(isPresented: $showEarlyCustom) {
                EarlyReminderCustomSheet(
                    initialValue: customEarly?.value ?? 5,
                    initialUnit: customEarly?.unit ?? .minute
                ) { value, unit in
                    customEarly = EarlyReminder(value: value, unit: unit)
                }
            }
            .sheet(isPresented: $showTimeZonePicker) {
                TimeZonePickerSheet(identifier: $dueTimeZone)
            }
            .sheet(isPresented: $showSectionPicker) {
                SectionPickerSheet(
                    store: store,
                    listId: listId,
                    section: $section
                )
                .tint(.primary)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Animated bindings (so picker insertion/collapse animates)

    private var dateBinding: Binding<Bool> {
        Binding(
            get: { hasDate },
            set: { newValue in
                withAnimation(.smooth) { hasDate = newValue }
            }
        )
    }

    private var timeBinding: Binding<Bool> {
        Binding(
            get: { hasTime },
            set: { newValue in withAnimation(.smooth) { hasTime = newValue } }
        )
    }

    /// Turning Alarm on implies "alarm at this time" — auto-enable Reminder
    /// and Time (the cascades in `onChange(of: hasReminder)` /
    /// `onChange(of: hasTime)` flip Date on and expand the time wheel).
    private var alarmBinding: Binding<Bool> {
        Binding(
            get: { hasAlarm },
            set: { newValue in
                withAnimation(.smooth) {
                    hasAlarm = newValue
                    if newValue {
                        if !hasReminder { hasReminder = true }
                        if !hasTime { hasTime = true }
                    }
                }
            }
        )
    }

    private var endRepeatBinding: Binding<Bool> {
        Binding(
            get: { endRepeatOn },
            set: { newValue in
                withAnimation(.smooth) { endRepeatOn = newValue }
            }
        )
    }

    // MARK: - Subviews

    @ViewBuilder
    private var pickerInset: some View {
        QuickCaptureTypePicker(
            selection: $selectedType,
            habitsPluginEnabled: habitsPluginEnabled
        )
            .glassEffect()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    private var form: some View {
        Form {
            QuickCaptureTitleSection(
                leadingDecorationIcon: leadingDecorationIcon,
                placeholder: titlePlaceholder,
                title: $title,
                titleFocused: $titleFocused
            )
            if selectedType == .habit {
                QuickCaptureHabitSection(
                    frequency: $habitFrequency,
                    goalPerCycle: $goalPerCycle,
                    flexibleGoal: $habitFlexibleGoal,
                    hasReminderTime: $hasHabitReminderTime,
                    reminderTime: $habitReminderTime,
                    showStreak: $showStreak
                )
                QuickCaptureDetailsSection(
                    showsCompletable: false,
                    completable: $completable,
                    flagged: $flagged,
                    priority: $priority,
                    tags: $tags,
                    section: $section,
                    listId: $listId,
                    activeLists: activeLists,
                    selectedList: selectedList,
                    sectionDisplayName: sectionDisplayName,
                    onShowSectionPicker: { showSectionPicker = true }
                )
            } else {
                QuickCaptureDateAndTimeSection(
                    selectedType: selectedType,
                    due: $due,
                    endDate: $endDate,
                    allDay: $allDay,
                    hasDate: dateBinding,
                    hasTime: timeBinding,
                    hasReminder: $hasReminder,
                    hasAlarm: alarmBinding,
                    datePickerExpanded: expandedPicker == .date,
                    timePickerExpanded: expandedPicker == .time,
                    dateSubtitle: dateSubtitle,
                    timeSubtitle: timeSubtitle,
                    timeZoneLabel: TimeZoneLabel.display(for: dueTimeZone),
                    onToggleDatePicker: {
                        withAnimation(.smooth) {
                            expandedPicker = expandedPicker == .date ? .none : .date
                        }
                    },
                    onToggleTimePicker: {
                        withAnimation(.smooth) {
                            expandedPicker = expandedPicker == .time ? .none : .time
                        }
                    },
                    onShowTimeZonePicker: { showTimeZonePicker = true }
                )
                if hasDate {
                    QuickCaptureRepeatAndEarlySection(
                        repeatPresets: availableRepeatPresets,
                        repeatPreset: $repeatPreset,
                        repeatDisplay: currentRepeatDisplay,
                        endRepeatOn: endRepeatBinding,
                        endRepeatDate: $endRepeatDate,
                        endRepeatSubtitle: endRepeatSubtitle,
                        hasReminder: hasReminder,
                        earlyPreset: $earlyPreset,
                        earlyDisplay: currentEarlyDisplay,
                        onShowRepeatCustom: { showRepeatCustom = true },
                        onShowEarlyCustom: { showEarlyCustom = true }
                    )
                }
                QuickCaptureDetailsSection(
                    showsCompletable: selectedType == .event,
                    completable: $completable,
                    flagged: $flagged,
                    priority: $priority,
                    tags: $tags,
                    section: $section,
                    listId: $listId,
                    activeLists: activeLists,
                    selectedList: selectedList,
                    sectionDisplayName: sectionDisplayName,
                    onShowSectionPicker: { showSectionPicker = true }
                )
            }
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        // Explicit grouped backdrop so the section cards contrast against the
        // sheet in light mode.
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Helpers

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when any field has been touched beyond its initial defaults.
    /// Drives the discard-confirmation dialog on the cancel button.
    private var isDirty: Bool {
        draft.isDirty(
            defaultListId: defaultListId,
            defaultSection: defaultSection,
            defaultNewItemType: defaultNewItemType
        )
    }

    private var activeLists: [ItemList] {
        store.lists.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }

    private var selectedList: ItemList? {
        store.lists.first { $0.id == listId }
    }

    private var leadingDecorationIcon: String {
        switch selectedType {
        case .task:  return "circle"
        case .note:  return "text.document.fill"
        case .habit: return "checkmark.arrow.trianglehead.clockwise"
        case .event: return "calendar"
        }
    }

    private var titlePlaceholder: String {
        selectedType.titlePlaceholder
    }

    private var availableRepeatPresets: [RepeatPreset] {
        selectedType == .habit ? RepeatPreset.habitOptions : RepeatPreset.taskOptions
    }

    /// Resolves an `Item.section` UUID-string to the section's user-visible
    /// name. Returns nil when no current list match exists (the section was
    /// deleted out from under us, or the value is a stale legacy free-form
    /// string from a list that hasn't been opened in the new build yet — in
    /// the latter case we just show the raw value as a fallback).
    private func sectionDisplayName(_ value: String) -> String? {
        guard let list = store.lists.first(where: { $0.id == listId }) else { return nil }
        if let match = list.sections.first(where: { $0.id.uuidString == value }) {
            return match.name
        }
        // Legacy fallback: treat as a free-form name if it's not a UUID.
        return UUID(uuidString: value) == nil ? value : nil
    }

    private var currentRepeatDisplay: String {
        if repeatPreset == .custom {
            return customRRule.flatMap { RecurrenceRule.parse($0)?.shortLabel } ?? "Custom"
        }
        return repeatPreset.displayName
    }

    private var currentEarlyDisplay: String {
        if earlyPreset == .custom {
            return CustomEarlyReminder.displayName(for: customEarly)
        }
        return earlyPreset.displayName
    }

    private var dateSubtitle: String {
        ScheduleFormatting.relativeDateSubtitle(for: due)
    }

    private var timeSubtitle: String {
        ScheduleFormatting.timeSubtitle(for: due)
    }

    private var endRepeatSubtitle: String {
        ScheduleFormatting.longDate(endRepeatDate)
    }

    private func discardChanges() {
        showDiscardConfirm = false
        pendingDismiss = true
        DispatchQueue.main.async { dismiss() }
    }

    private func snapRepeatPreset(oldValue: Item.ItemType, newValue: Item.ItemType) {
        if newValue == .habit, !RepeatPreset.habitOptions.contains(repeatPreset) {
            repeatPreset = .daily
        } else if oldValue == .habit, newValue != .habit, !RepeatPreset.taskOptions.contains(repeatPreset) {
            repeatPreset = .never
        }
    }

    private static func defaultDue() -> Date {
        ReminderPreferences.defaultTime()
    }

    private static func defaultEndRepeat() -> Date {
        ScheduleFormatting.defaultEndRepeat()
    }

    private static func defaultHabitReminderTime() -> Date {
        ReminderPreferences.defaultTime()
    }

    private var draft: QuickCaptureDraft {
        QuickCaptureDraft(
            selectedType: selectedType,
            title: title,
            tags: tags,
            notes: "",
            hasDate: hasDate,
            due: due,
            hasTime: hasTime,
            hasReminder: hasReminder,
            hasAlarm: hasAlarm,
            dueTimeZone: dueTimeZone,
            repeatPreset: repeatPreset,
            customRRule: customRRule,
            endRepeatOn: endRepeatOn,
            endRepeatDate: endRepeatDate,
            earlyPreset: earlyPreset,
            customEarly: customEarly,
            flagged: flagged,
            priority: priority,
            section: section,
            listId: listId,
            goalPerCycle: goalPerCycle,
            flexibleGoal: habitFlexibleGoal,
            showStreak: showStreak,
            endDate: endDate,
            completable: completable,
            allDay: allDay,
            habitFrequency: habitFrequency,
            hasHabitReminderTime: hasHabitReminderTime,
            habitReminderTime: habitReminderTime
        )
    }

    private func add(openCreatedItem: Bool) {
        let item = draft.makeItem()
        Task {
            try? await store.add(item)
            dismiss()
            if openCreatedItem {
                await MainActor.run {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onOpenCreatedItem(item)
                    }
                }
            }
        }
    }
}
