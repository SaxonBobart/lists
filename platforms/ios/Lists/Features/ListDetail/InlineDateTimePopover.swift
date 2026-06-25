import SwiftUI

/// Compact date / time / repeat / early-reminder editor opened from the
/// inline-edit keyboard toolbar's `calendar.badge.clock` button. Seeds from
/// the item, and on Done recomposes the date-related fields and writes them
/// back through `ItemStore.applyUpdateSync`. Reuses the same sub-sheets and
/// preset enums as document details and Quick Capture (`CustomRepeatSheet`,
/// `EarlyReminderCustomSheet`, `TimeZonePickerSheet`, `RepeatPreset`,
/// `EarlyReminderPreset`).
struct InlineDateTimePopover: View {
    let itemId: UUID
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss

    @State private var hasDate: Bool
    @State private var due: Date
    @State private var hasTime: Bool
    @State private var hasReminder: Bool
    @State private var hasAlarm: Bool
    @State private var dueTimeZone: String?

    // Event scheduling (used when `itemType == .event`): Starts / Ends / All Day.
    @State private var eventEnd: Date
    @State private var allDay: Bool

    @State private var expandedPicker: InlineDateTimeExpandedPicker = .none

    @State private var repeatPreset: RepeatPreset
    @State private var customRRule: String?
    @State private var endRepeatOn: Bool
    @State private var endRepeatDate: Date
    @State private var earlyPreset: EarlyReminderPreset
    @State private var customEarly: EarlyReminder?

    @State private var showRepeatCustom = false
    @State private var showEarlyCustom = false
    @State private var showTimeZonePicker = false

    private let itemType: Item.ItemType

    init(item: Item, store: ItemStore) {
        self.itemId = item.id
        self.store = store
        self.itemType = item.type

        let resolvedDue = item.due ?? Self.defaultDue()
        _hasDate = State(initialValue: item.due != nil)
        _due = State(initialValue: resolvedDue)
        _hasTime = State(initialValue: item.due != nil && !item.dueAllDay)
        _hasReminder = State(initialValue: item.reminder?.enabled ?? false)
        _hasAlarm = State(initialValue: item.triggers?.alarm?.enabled ?? false)
        _dueTimeZone = State(initialValue: item.dueTimeZone)
        _eventEnd = State(initialValue: item.end ?? resolvedDue.addingTimeInterval(3600))
        _allDay = State(initialValue: item.dueAllDay)

        let parsed = Self.parseRecurrence(item.recurrence?.rrule, type: item.type)
        _repeatPreset = State(initialValue: parsed.preset)
        _customRRule = State(initialValue: parsed.customRRule)
        _endRepeatOn = State(initialValue: parsed.endDate != nil)
        _endRepeatDate = State(initialValue: parsed.endDate ?? Self.defaultEndRepeat())

        let parsedEarly = Self.parseEarly(item.reminder?.early)
        _earlyPreset = State(initialValue: parsedEarly.preset)
        _customEarly = State(initialValue: parsedEarly.custom)
    }

    var body: some View {
        NavigationStack {
            formWithCascades
                .navigationTitle("Date & Time")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
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
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").accessibilityLabel("Cancel")
            }
            .tint(.primary)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { apply() } label: {
                Image(systemName: "checkmark").fontWeight(.semibold).accessibilityLabel("Done")
            }
            .tint(.primary)
            .accessibilityIdentifier("inline.datetime.done")
        }
    }

    private var formWithCascades: some View {
        Form {
            if itemType == .event {
                eventDateSection
            } else {
                dateAndTimeSection
            }
            if hasDate {
                repeatAndEarlySection
            }
        }
        .listSectionSpacing(.compact)
        // Hide the form's default scroll background and re-establish a proper
        // grouped backdrop so the section cards read crisply in both light and
        // dark mode.
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onChange(of: hasDate) { oldValue, newValue in
                withAnimation(.smooth) {
                    if newValue && !oldValue {
                        if !hasReminder { hasReminder = true }
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
                        if hasTime { expandedPicker = .time }
                    } else {
                        earlyPreset = .none
                        customEarly = nil
                        hasAlarm = false
                    }
                }
            }
            .onChange(of: repeatPreset) { _, newValue in
                if newValue == .never { endRepeatOn = false }
            }
    }

    // MARK: - Sections

    private var dateAndTimeSection: some View {
        InlineDateAndTimeSection(
            hasDate: $hasDate,
            due: $due,
            hasTime: $hasTime,
            hasReminder: $hasReminder,
            hasAlarm: $hasAlarm,
            dueTimeZone: $dueTimeZone,
            expandedPicker: $expandedPicker,
            dateSubtitle: dateSubtitle,
            timeSubtitle: timeSubtitle,
            onShowTimeZonePicker: { showTimeZonePicker = true }
        )
    }

    /// Event variant of the date section — Apple Calendar-style Starts / Ends /
    /// All Day (shared `EventDateRows`) plus the same Reminder / Alarm toggles.
    private var eventDateSection: some View {
        InlineEventDateSection(
            due: $due,
            eventEnd: $eventEnd,
            allDay: $allDay,
            hasTime: $hasTime,
            hasReminder: $hasReminder,
            hasAlarm: $hasAlarm
        )
    }

    private var repeatAndEarlySection: some View {
        InlineRepeatAndEarlySection(
            availableRepeatPresets: availableRepeatPresets,
            currentRepeatDisplay: currentRepeatDisplay,
            currentEarlyDisplay: currentEarlyDisplay,
            endRepeatSubtitle: endRepeatSubtitle,
            hasReminder: hasReminder,
            repeatPreset: $repeatPreset,
            endRepeatOn: $endRepeatOn,
            endRepeatDate: $endRepeatDate,
            earlyPreset: $earlyPreset,
            showRepeatCustom: $showRepeatCustom,
            showEarlyCustom: $showEarlyCustom
        )
    }

    // MARK: - Computed

    private var availableRepeatPresets: [RepeatPreset] {
        itemType == .habit ? RepeatPreset.habitOptions : RepeatPreset.taskOptions
    }

    private var currentRepeatDisplay: String {
        if repeatPreset == .custom {
            return customRRule.flatMap { RecurrenceRule.parse($0)?.shortLabel } ?? "Custom"
        }
        return repeatPreset.displayName
    }

    private var currentEarlyDisplay: String {
        if earlyPreset == .custom { return CustomEarlyReminder.displayName(for: customEarly) }
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

    // MARK: - Apply

    private func apply() {
        guard var item = store.item(itemId) else { dismiss(); return }
        if itemType == .event {
            item.due = due
            item.end = eventEnd
            item.dueAllDay = allDay
        } else {
            item.due = hasDate ? due : nil
            item.dueAllDay = hasDate && !hasTime
        }
        item.dueTimeZone = dueTimeZone

        let resolvedEarly: EarlyReminder? = (earlyPreset == .custom) ? customEarly : earlyPreset.value
        item.reminder = hasReminder ? Reminder(enabled: true, early: resolvedEarly) : nil
        item.triggers = hasAlarm ? Triggers(alarm: TriggerToggle(enabled: true)) : nil
        item.recurrence = composeRRule().map { Recurrence(rrule: $0) }

        store.applyUpdateSync(item)
        dismiss()
    }

    private func composeRRule() -> String? {
        let base = (repeatPreset == .custom) ? customRRule : repeatPreset.rrule
        guard let base else { return nil }
        if endRepeatOn {
            return "\(base);UNTIL=\(ScheduleFormatting.formatUntil(endRepeatDate))"
        }
        return base
    }

    // MARK: - Static helpers

    private static func defaultDue() -> Date {
        ReminderPreferences.defaultTime()
    }

    private static func defaultEndRepeat() -> Date {
        ScheduleFormatting.defaultEndRepeat()
    }

    private static func parseRecurrence(_ rrule: String?, type: Item.ItemType)
        -> (preset: RepeatPreset, customRRule: String?, endDate: Date?) {
        guard let rrule, !rrule.isEmpty else { return (.never, nil, nil) }
        let parts = RRuleParts.splitUntil(from: rrule)
        let base = parts.base
        let endDate = parts.until.flatMap { ScheduleFormatting.parseUntil($0) }
        let candidates: [RepeatPreset] = type == .habit ? RepeatPreset.habitOptions : RepeatPreset.taskOptions
        for preset in candidates where preset != .custom && preset != .never {
            if preset.rrule == base { return (preset, nil, endDate) }
        }
        return (.custom, base, endDate)
    }

    private static func parseEarly(_ early: EarlyReminder?) -> (preset: EarlyReminderPreset, custom: EarlyReminder?) {
        guard let early else { return (.none, nil) }
        for preset in EarlyReminderPreset.allCases where preset != .none && preset != .custom {
            if let v = preset.value, v.value == early.value && v.unit == early.unit {
                return (preset, nil)
            }
        }
        return (.custom, early)
    }
}
