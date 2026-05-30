import SwiftUI

/// Compact date / time / repeat / early-reminder editor opened from the
/// inline-edit keyboard toolbar's `calendar.badge.clock` button. Seeds from
/// the item, and on Done recomposes the date-related fields and writes them
/// back through `ItemStore.applyUpdateSync`. Reuses the same sub-sheets and
/// preset enums as `ItemDetailSheet` (`CustomRepeatSheet`,
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
    @State private var isUrgent: Bool
    @State private var dueTimeZone: String?

    private enum ExpandedPicker { case none, date, time }
    @State private var expandedPicker: ExpandedPicker = .none

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
        _isUrgent = State(initialValue: item.triggers?.urgent?.enabled ?? false)
        _dueTimeZone = State(initialValue: item.dueTimeZone)

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
            dateAndTimeSection
            if hasDate {
                repeatAndEarlySection
            }
        }
        .listSectionSpacing(.compact)
        // Mirror ItemDetailSheet: hide the form's default scroll background
        // (which was rendering as a milky-gray overlay over the sheet) and
        // re-establish a proper grouped backdrop so the section cards read
        // crisply in both light and dark mode.
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
                        isUrgent = false
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
                        isUrgent = false
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
                        isUrgent = false
                    }
                }
            }
            .onChange(of: repeatPreset) { _, newValue in
                if newValue == .never { endRepeatOn = false }
            }
    }

    // MARK: - Sections (mirror ItemDetailSheet)

    private var dateAndTimeSection: some View {
        Section {
            splitToggleRow(
                title: "Date",
                subtitle: hasDate ? dateSubtitle : nil,
                systemImage: "calendar",
                isOn: dateBinding,
                tapTarget: hasDate
                    ? { withAnimation(.smooth) { expandedPicker = expandedPicker == .date ? .none : .date } }
                    : nil
            )

            if hasDate && expandedPicker == .date {
                DatePicker("Date", selection: $due, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(.blue)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
            }

            splitToggleRow(
                title: "Time",
                subtitle: hasTime ? timeSubtitle : nil,
                systemImage: "clock",
                isOn: timeBinding,
                tapTarget: hasTime
                    ? { withAnimation(.smooth) { expandedPicker = expandedPicker == .time ? .none : .time } }
                    : nil
            )

            if hasTime && expandedPicker == .time {
                DatePicker("Time", selection: $due, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .tint(.blue)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))

                Button { showTimeZonePicker = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .center)
                        Text("Time Zone").foregroundStyle(.primary)
                        Spacer()
                        Text(TimeZoneLabel.display(for: dueTimeZone)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .imageScale(.small).foregroundStyle(.tertiary).font(.footnote)
                    }
                }
                .buttonStyle(.plain)
            }

            Toggle(isOn: $hasReminder) {
                rowLabel(title: "Reminder", subtitle: nil, systemImage: "bell")
            }
            .tint(.green)

            Toggle(isOn: urgentBinding) {
                rowLabel(title: "Urgent", subtitle: nil, systemImage: "alarm.fill")
            }
            .tint(.green)
        } header: {
            Text("Date and Time")
        }
    }

    private var repeatAndEarlySection: some View {
        Section {
            Menu {
                ForEach(availableRepeatPresets, id: \.self) { preset in
                    Button {
                        repeatPreset = preset
                        if preset == .custom { showRepeatCustom = true }
                    } label: {
                        if preset == repeatPreset {
                            Label(preset.displayName, systemImage: "checkmark")
                        } else {
                            Text(preset.displayName)
                        }
                    }
                }
            } label: {
                pickerRowLabel(
                    title: "Repeat",
                    value: currentRepeatDisplay,
                    systemImage: repeatPreset == .never ? "repeat.badge.xmark" : "repeat"
                )
            }
            .buttonStyle(.plain)

            if repeatPreset != .never {
                Toggle(isOn: endRepeatBinding) {
                    rowLabel(
                        title: "End Repeat",
                        subtitle: endRepeatOn ? endRepeatSubtitle : nil,
                        systemImage: "calendar.badge.minus"
                    )
                }
                .tint(.green)

                if endRepeatOn {
                    DatePicker("", selection: $endRepeatDate, in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(.blue)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                }
            }

            if hasReminder {
                Menu {
                    ForEach(EarlyReminderPreset.allCases, id: \.self) { preset in
                        Button {
                            earlyPreset = preset
                            if preset == .custom { showEarlyCustom = true }
                        } label: {
                            if preset == earlyPreset {
                                Label(preset.displayName, systemImage: "checkmark")
                            } else {
                                Text(preset.displayName)
                            }
                        }
                    }
                } label: {
                    pickerRowLabel(
                        title: "Early Reminder",
                        value: currentEarlyDisplay,
                        systemImage: "clock.arrow.circlepath"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Bindings

    private var dateBinding: Binding<Bool> {
        Binding(get: { hasDate }, set: { v in withAnimation(.smooth) { hasDate = v } })
    }
    private var timeBinding: Binding<Bool> {
        Binding(get: { hasTime }, set: { v in withAnimation(.smooth) { hasTime = v } })
    }
    private var urgentBinding: Binding<Bool> {
        Binding(get: { isUrgent }, set: { v in
            withAnimation(.smooth) {
                isUrgent = v
                if v {
                    if !hasReminder { hasReminder = true }
                    if !hasTime { hasTime = true }
                }
            }
        })
    }
    private var endRepeatBinding: Binding<Bool> {
        Binding(get: { endRepeatOn }, set: { v in withAnimation(.smooth) { endRepeatOn = v } })
    }

    // MARK: - Row helpers (mirror ItemDetailSheet)

    private func splitToggleRow(
        title: String, subtitle: String?, systemImage: String,
        isOn: Binding<Bool>, tapTarget: (() -> Void)?
    ) -> some View {
        HStack(spacing: 0) {
            if let tapTarget {
                Button(action: tapTarget) {
                    rowLabel(title: title, subtitle: subtitle, systemImage: systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary)
            } else {
                rowLabel(title: title, subtitle: subtitle, systemImage: systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { }
            }
            Toggle("", isOn: isOn).labelsHidden().tint(.green)
        }
    }

    private func rowLabel(title: String, subtitle: String?, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .imageScale(.small).foregroundStyle(.secondary).frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.blue)
                }
            }
        }
    }

    private func pickerRowLabel(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .imageScale(.small).foregroundStyle(.secondary).frame(width: 24, alignment: .center)
            Text(title).foregroundStyle(.primary)
            Spacer()
            Text(value).foregroundStyle(.secondary)
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small).foregroundStyle(.tertiary).font(.footnote)
        }
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
        let cal = Calendar.current
        if cal.isDateInToday(due) { return "Today" }
        if cal.isDateInTomorrow(due) { return "Tomorrow" }
        let df = DateFormatter()
        df.dateFormat = "EEEE, d MMMM yyyy"
        return df.string(from: due)
    }

    private var timeSubtitle: String {
        let df = DateFormatter()
        df.timeStyle = .short
        return df.string(from: due)
    }

    private var endRepeatSubtitle: String {
        let df = DateFormatter()
        df.dateFormat = "EEEE, d MMMM yyyy"
        return df.string(from: endRepeatDate)
    }

    // MARK: - Apply

    private func apply() {
        guard var item = store.item(itemId) else { dismiss(); return }
        item.due = hasDate ? due : nil
        item.dueAllDay = hasDate && !hasTime
        item.dueTimeZone = dueTimeZone

        let resolvedEarly: EarlyReminder? = (earlyPreset == .custom) ? customEarly : earlyPreset.value
        item.reminder = hasReminder ? Reminder(enabled: true, early: resolvedEarly) : nil
        item.triggers = isUrgent ? Triggers(urgent: TriggerToggle(enabled: true)) : nil
        item.recurrence = composeRRule().map { Recurrence(rrule: $0) }

        store.applyUpdateSync(item)
        dismiss()
    }

    private func composeRRule() -> String? {
        let base = (repeatPreset == .custom) ? customRRule : repeatPreset.rrule
        guard let base else { return nil }
        if endRepeatOn {
            return "\(base);UNTIL=\(Self.formatUntil(endRepeatDate))"
        }
        return base
    }

    // MARK: - Static helpers (mirror ItemDetailSheet)

    private static func defaultDue() -> Date {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        return cal.date(byAdding: .hour, value: 9, to: startOfToday) ?? .now
    }

    private static func defaultEndRepeat() -> Date {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        return cal.date(byAdding: .month, value: 6, to: startOfToday) ?? .now
    }

    private static func formatUntil(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    private static func parseRecurrence(_ rrule: String?, type: Item.ItemType)
        -> (preset: RepeatPreset, customRRule: String?, endDate: Date?) {
        guard let rrule, !rrule.isEmpty else { return (.never, nil, nil) }
        var base = rrule
        var endDate: Date? = nil
        if let untilRange = rrule.range(of: ";UNTIL=") {
            let untilStr = String(rrule[untilRange.upperBound...])
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            f.timeZone = TimeZone(identifier: "UTC")
            endDate = f.date(from: untilStr)
            base = String(rrule[rrule.startIndex..<untilRange.lowerBound])
        }
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
