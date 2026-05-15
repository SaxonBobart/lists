import SwiftUI

/// Bottom sheet for adding a new item (task, note, or habit). One layout
/// serves all three types — only the **Repeat** picker's preset list changes
/// (full list for tasks/notes; Daily/Weekly/Monthly/Custom for habits) and
/// habits gain a `Goal per cycle` stepper and a `Show streak` toggle in the
/// Details section.
struct QuickCaptureSheet: View {
    let store: ItemStore
    let defaultListId: String
    let defaultSection: String?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    @State private var selectedType: Item.ItemType
    @State private var title: String = ""
    @State private var tags: [String] = []
    @State private var notes: String = ""

    // Date and Time
    @State private var hasDate: Bool = false
    @State private var due: Date = Self.defaultDue()
    @State private var hasTime: Bool = false
    @State private var hasReminder: Bool = true
    @State private var isUrgent: Bool = false
    @State private var dueTimeZone: String? = nil

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
    @State private var showStreak: Bool = true

    // Sub-sheet presentation
    @State private var showRepeatCustom = false
    @State private var showEarlyCustom = false
    @State private var showTimeZonePicker = false
    @State private var showSectionPicker = false
    @State private var isShowingMarkdownEditor = false
    @State private var showDiscardConfirm = false

    init(store: ItemStore, defaultListId: String = ItemList.inboxId, defaultSection: String? = nil) {
        self.store = store
        self.defaultListId = defaultListId
        self.defaultSection = defaultSection
        _listId = State(initialValue: defaultListId)
        let listDefault = store.lists.first(where: { $0.id == defaultListId })?.defaultItemType ?? .task
        _selectedType = State(initialValue: listDefault)
        _repeatPreset = State(initialValue: listDefault == .habit ? .daily : .never)
        _section = State(initialValue: defaultSection)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                typePicker
                form
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
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        add()
                    } label: {
                        Image(systemName: "checkmark")
                            .accessibilityLabel("Add")
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    titleFocused = true
                }
            }
            .onChange(of: selectedType) { oldValue, newValue in
                snapRepeatPreset(oldValue: oldValue, newValue: newValue)
            }
            .onChange(of: hasDate) { oldValue, newValue in
                withAnimation(.smooth) {
                    if newValue && !oldValue {
                        hasReminder = true
                    } else if oldValue && !newValue {
                        hasTime = false
                        hasReminder = false
                        earlyPreset = .none
                        customEarly = nil
                    }
                }
            }
            .onChange(of: hasReminder) { _, newValue in
                if !newValue {
                    earlyPreset = .none
                    customEarly = nil
                }
            }
            .onChange(of: repeatPreset) { _, newValue in
                if newValue == .never {
                    endRepeatOn = false
                }
            }
            .sheet(isPresented: $showRepeatCustom) {
                let parsed = CustomRRule.parse(customRRule ?? "")
                RepeatCustomSheet(
                    initialInterval: parsed?.interval ?? 1,
                    initialUnit: parsed?.unit ?? .week
                ) { interval, unit in
                    customRRule = CustomRRule.make(interval: interval, unit: unit, end: nil)
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
                    section: $section,
                    existingSections: existingSectionsInCurrentList
                )
            }
            .confirmationDialog(
                "Discard new item?",
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            }
            .fullScreenCover(isPresented: $isShowingMarkdownEditor) {
                MarkdownEditorView(text: $notes, title: title) {
                    isShowingMarkdownEditor = false
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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

    /// Toggling Time on without a date implies "today at this time" — flip
    /// Date on too so the user doesn't need two taps.
    private var timeBinding: Binding<Bool> {
        Binding(
            get: { hasTime },
            set: { newValue in
                withAnimation(.smooth) {
                    hasTime = newValue
                    if newValue && !hasDate {
                        hasDate = true
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

    private var typePicker: some View {
        Picker("Type", selection: $selectedType) {
            Text("Task").tag(Item.ItemType.task)
            Text("Note").tag(Item.ItemType.note)
            Text("Habit").tag(Item.ItemType.habit)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var form: some View {
        Form {
            titleAndTagsSection
            dateAndTimeSection
            repeatAndEarlySection
            detailsSection
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
    }

    private var titleAndTagsSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: leadingDecorationIcon)
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .center)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("New item", text: $title, axis: .vertical)
                        .font(.title3)
                        .focused($titleFocused)
                        .lineLimit(1...6)
                    TagInputView(tags: $tags)
                    inlineNotesRow
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Inline notes — sits directly below tags so title / tags / notes
    /// read as one connected block. Plain `TextField`; the expand button
    /// hands off to `MarkdownEditorView` for live-formatted editing.
    private var inlineNotesRow: some View {
        HStack(alignment: .top, spacing: 6) {
            TextField("Notes", text: $notes, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...8)
            Button {
                isShowingMarkdownEditor = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Markdown editor")
            .accessibilityIdentifier("item.notes.expand")
        }
        .padding(.top, 2)
    }

    private var dateAndTimeSection: some View {
        Section {
            // Date toggle (multi-line label with blue subtitle when on)
            Toggle(isOn: dateBinding) {
                rowLabel(
                    title: "Date",
                    subtitle: hasDate ? dateSubtitle : nil,
                    systemImage: "calendar"
                )
            }
            .tint(.green)

            // Inline calendar — only when date is set and time is off
            if hasDate && !hasTime {
                DatePicker(
                    "Date",
                    selection: $due,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(.blue)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
            }

            // Time toggle — always visible. If user turns Time on while Date
            // is off, the Date is auto-enabled with today as the default.
            Toggle(isOn: timeBinding) {
                rowLabel(
                    title: "Time",
                    subtitle: hasTime ? timeSubtitle : nil,
                    systemImage: "clock"
                )
            }
            .tint(.green)

            // Inline wheel — only when both date and time are on
            if hasDate && hasTime {
                DatePicker(
                    "Time",
                    selection: $due,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .tint(.blue)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))

                // Time Zone row — only visible alongside the time wheel
                Button {
                    showTimeZonePicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .center)
                        Text("Time Zone")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(TimeZoneLabel.display(for: dueTimeZone))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .foregroundStyle(.tertiary)
                            .font(.footnote)
                    }
                }
                .buttonStyle(.plain)
            }

            Toggle(isOn: $hasReminder) {
                rowLabel(title: "Reminder", subtitle: nil, systemImage: "bell")
            }
            .tint(.green)
            .disabled(!hasDate)

            // Location — sub-option of Reminder. Only meaningful when there
            // is something to be reminded about.
            if hasDate && hasReminder {
                placeholderRow(label: "Location", systemImage: "location")
            }

            Toggle(isOn: $isUrgent) {
                rowLabel(title: "Urgent", subtitle: nil, systemImage: "alarm.fill")
            }
            .tint(.green)
        } header: {
            Text("Date and Time")
        } footer: {
            Text("Mark this reminder as urgent to set an alarm.")
        }
    }

    private var repeatAndEarlySection: some View {
        Section {
            // Repeat — Menu with Custom triggering sub-sheet
            Menu {
                ForEach(availableRepeatPresets, id: \.self) { preset in
                    Button {
                        repeatPreset = preset
                        if preset == .custom {
                            showRepeatCustom = true
                        }
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
                    systemImage: "repeat"
                )
            }
            .buttonStyle(.plain)

            // End Repeat — only when Repeat is set
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
                    DatePicker(
                        "",
                        selection: $endRepeatDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(.blue)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                }
            }

            // Early Reminder — only when Reminder is on
            if hasReminder {
                Menu {
                    ForEach(EarlyReminderPreset.allCases, id: \.self) { preset in
                        Button {
                            earlyPreset = preset
                            if preset == .custom {
                                showEarlyCustom = true
                            }
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

    private var detailsSection: some View {
        Section("Details") {
            Toggle(isOn: $flagged) {
                rowLabel(title: "Flag", subtitle: nil, systemImage: "flag")
            }
            .tint(.green)

            Picker(selection: $priority) {
                ForEach(Item.Priority.allCases, id: \.self) { p in
                    Text(displayName(for: p)).tag(p)
                }
            } label: {
                Label("Priority", systemImage: "exclamationmark.circle")
                    .labelStyle(GlyphLabelStyle())
            }
            .pickerStyle(.menu)

            // Section row — tappable picker
            Button {
                showSectionPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.dashed")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .center)
                    Text("Section")
                        .foregroundStyle(.primary)
                    Spacer()
                    if let section, !section.isEmpty {
                        Text(section)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                        .font(.footnote)
                }
            }
            .buttonStyle(.plain)

            // List row — leading IconBadge of selected list + chevron
            Menu {
                ForEach(activeLists, id: \.id) { list in
                    Button {
                        listId = list.id
                    } label: {
                        if list.id == listId {
                            Label(list.name, systemImage: "checkmark")
                        } else {
                            Label(list.name, systemImage: list.icon)
                        }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    if let list = selectedList {
                        IconBadge(
                            systemName: list.icon,
                            hue: ListsTokens.listColor(list.color),
                            size: 24,
                            glyphSize: 12,
                            shape: .circle
                        )
                    } else {
                        Image(systemName: "tray.fill")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .center)
                    }
                    Text("List")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(selectedList?.name ?? "")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                        .font(.footnote)
                }
            }
            .buttonStyle(.plain)

            placeholderRow(label: "Attachments", systemImage: "paperclip")

            if selectedType == .habit {
                Stepper(value: $goalPerCycle, in: 1...99) {
                    HStack(spacing: 12) {
                        Image(systemName: "target")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .center)
                        Text("Goal per cycle")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(goalPerCycle)")
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $showStreak) {
                    rowLabel(title: "Show streak", subtitle: nil, systemImage: "flame")
                }
                .tint(.green)
            }
        }
    }

    // MARK: - Row label helpers

    private func rowLabel(title: String, subtitle: String?, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.blue)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func pickerRowLabel(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
                .foregroundStyle(.tertiary)
                .font(.footnote)
        }
    }

    private func placeholderRow(label: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            Text(label)
            Spacer()
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when any field has been touched beyond its initial defaults.
    /// Drives the discard-confirmation dialog on the cancel button.
    private var isDirty: Bool {
        let typeDefault = store.lists.first(where: { $0.id == defaultListId })?.defaultItemType ?? .task
        let initialRepeat: RepeatPreset = typeDefault == .habit ? .daily : .never

        return !trimmedTitle.isEmpty
            || !tags.isEmpty
            || !notes.isEmpty
            || selectedType != typeDefault
            || hasDate
            || hasTime
            || !hasReminder         // default true; user toggling off counts as a touch
            || isUrgent
            || flagged
            || priority != .none
            || section != defaultSection
            || listId != defaultListId
            || repeatPreset != initialRepeat
            || endRepeatOn
            || earlyPreset != .none
            || customRRule != nil
            || customEarly != nil
            || goalPerCycle != 1
            || !showStreak
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
        case .habit: return "arrow.triangle.2.circlepath"
        }
    }

    private var availableRepeatPresets: [RepeatPreset] {
        selectedType == .habit ? RepeatPreset.habitOptions : RepeatPreset.taskOptions
    }

    private var existingSectionsInCurrentList: [String] {
        Set(
            store.items
                .filter { $0.listId == listId && $0.deletedAt == nil }
                .compactMap { $0.section }
        )
        .sorted()
    }

    private var currentRepeatDisplay: String {
        if repeatPreset == .custom {
            return CustomRRule.displayName(for: customRRule)
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
        let cal = Calendar.current
        if cal.isDateInToday(due)    { return "Today" }
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

    private func composedRRule() -> String? {
        let base: String?
        if repeatPreset == .custom {
            base = customRRule
        } else {
            base = repeatPreset.rrule
        }
        guard let base else { return nil }
        if endRepeatOn {
            return "\(base);UNTIL=\(Self.formatUntil(endRepeatDate))"
        }
        return base
    }

    private static func formatUntil(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    private func displayName(for p: Item.Priority) -> String {
        switch p {
        case .none:   return "None"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    private func snapRepeatPreset(oldValue: Item.ItemType, newValue: Item.ItemType) {
        if newValue == .habit, !RepeatPreset.habitOptions.contains(repeatPreset) {
            repeatPreset = .daily
        } else if oldValue == .habit, newValue != .habit, !RepeatPreset.taskOptions.contains(repeatPreset) {
            repeatPreset = .never
        }
    }

    private static func defaultDue() -> Date {
        // Start of today + 9 hours so the subtitle reads "Today" and the
        // wheel opens on a friendly time of day.
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        return cal.date(byAdding: .hour, value: 9, to: startOfToday) ?? .now
    }

    private static func defaultEndRepeat() -> Date {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        return cal.date(byAdding: .month, value: 6, to: startOfToday) ?? .now
    }

    private func mergeTags(_ inlineTags: [String], with manualTags: [String]) -> [String] {
        var result = manualTags
        for tag in inlineTags {
            result = Tag.appending(tag, to: result)
        }
        return result
    }

    private func add() {
        let (cleanedTitle, parsedTags) = Tag.extractInline(from: trimmedTitle)
        let mergedTags = mergeTags(parsedTags, with: tags)

        let resolvedDue: Date? = hasDate ? due : nil
        let resolvedDueAllDay: Bool = hasDate && !hasTime

        let resolvedEarly: EarlyReminder?
        if earlyPreset == .custom {
            resolvedEarly = customEarly
        } else {
            resolvedEarly = earlyPreset.value
        }

        let resolvedReminder: Reminder? = hasReminder
            ? Reminder(enabled: true, early: resolvedEarly)
            : nil

        let resolvedTriggers: Triggers? = isUrgent
            ? Triggers(urgent: TriggerToggle(enabled: true))
            : nil

        let composed = composedRRule()
        let resolvedRecurrence: Recurrence?
        let resolvedFrequency: HabitFrequency?
        switch selectedType {
        case .task, .note:
            resolvedRecurrence = composed.map { Recurrence(rrule: $0) }
            resolvedFrequency = nil
        case .habit:
            if repeatPreset == .custom, customRRule != nil {
                resolvedFrequency = .custom
                resolvedRecurrence = composed.map { Recurrence(rrule: $0) }
            } else {
                resolvedFrequency = repeatPreset.habitFrequency ?? .daily
                // For preset habit frequencies, only persist a recurrence when
                // the user has set an End Repeat (so we can carry the UNTIL).
                resolvedRecurrence = endRepeatOn ? composed.map { Recurrence(rrule: $0) } : nil
            }
        }

        var item = Item(
            type: selectedType,
            title: cleanedTitle.isEmpty ? trimmedTitle : cleanedTitle,
            listId: listId,
            section: section?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            tags: mergedTags,
            due: resolvedDue,
            dueAllDay: resolvedDueAllDay,
            dueTimeZone: dueTimeZone,
            priority: priority,
            flagged: flagged,
            reminder: resolvedReminder,
            recurrence: resolvedRecurrence,
            triggers: resolvedTriggers,
            frequency: resolvedFrequency,
            goalPerCycle: selectedType == .habit ? goalPerCycle : 1,
            showStreak: selectedType == .habit ? showStreak : true
        )
        item.body = notes
        Task {
            try? await store.add(item)
            dismiss()
        }
    }
}

// MARK: - Glyph label style

/// Shared row-icon styling: icon in `.secondary` foreground, `.imageScale(.small)`,
/// 24pt fixed leading column. Apply via `.labelStyle(GlyphLabelStyle())`.
struct GlyphLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            configuration.title
        }
    }
}

// MARK: - Repeat preset

/// Unified preset list for the Repeat row. Task/note get the full set;
/// habits get the trimmed `.habitOptions` since the noisy cases (hourly,
/// weekdays, fortnightly, etc.) don't fit a "cycle + goal" model. `.custom`
/// is in both so the sub-sheet can compose richer RRULEs.
enum RepeatPreset: String, CaseIterable, Hashable {
    case never
    case hourly
    case daily
    case weekdays
    case weekends
    case weekly
    case fortnightly
    case monthly
    case everyThreeMonths
    case everySixMonths
    case yearly
    case custom

    var displayName: String {
        switch self {
        case .never:             return "Never"
        case .hourly:            return "Hourly"
        case .daily:             return "Daily"
        case .weekdays:          return "Weekdays"
        case .weekends:          return "Weekends"
        case .weekly:            return "Weekly"
        case .fortnightly:       return "Every 2 weeks"
        case .monthly:           return "Monthly"
        case .everyThreeMonths:  return "Every 3 months"
        case .everySixMonths:    return "Every 6 months"
        case .yearly:            return "Yearly"
        case .custom:            return "Custom…"
        }
    }

    /// RRULE for tasks/notes. `nil` means no recurrence.
    var rrule: String? {
        switch self {
        case .never:             return nil
        case .hourly:            return "FREQ=HOURLY"
        case .daily:             return "FREQ=DAILY"
        case .weekdays:          return "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
        case .weekends:          return "FREQ=WEEKLY;BYDAY=SA,SU"
        case .weekly:            return "FREQ=WEEKLY"
        case .fortnightly:       return "FREQ=WEEKLY;INTERVAL=2"
        case .monthly:           return "FREQ=MONTHLY"
        case .everyThreeMonths:  return "FREQ=MONTHLY;INTERVAL=3"
        case .everySixMonths:    return "FREQ=MONTHLY;INTERVAL=6"
        case .yearly:            return "FREQ=YEARLY"
        case .custom:            return nil   // handled via customRRule
        }
    }

    /// Habit frequency for the four habit-supported cases.
    var habitFrequency: HabitFrequency? {
        switch self {
        case .daily:   return .daily
        case .weekly:  return .weekly
        case .monthly: return .monthly
        case .custom:  return .custom
        default:       return nil
        }
    }

    static let taskOptions: [RepeatPreset] = [
        .never, .hourly, .daily, .weekdays, .weekends, .weekly,
        .fortnightly, .monthly, .everyThreeMonths, .everySixMonths, .yearly, .custom
    ]

    static let habitOptions: [RepeatPreset] = [.daily, .weekly, .monthly, .custom]
}

// MARK: - Early reminder preset

/// Preset offsets for the Early Reminder row, matching PRODUCT-SPEC §4.1.1.
enum EarlyReminderPreset: String, CaseIterable, Hashable {
    case none
    case fiveMin
    case fifteenMin
    case thirtyMin
    case oneHour
    case twoHours
    case oneDay
    case twoDays
    case oneWeek
    case oneMonth
    case custom

    var displayName: String {
        switch self {
        case .none:       return "None"
        case .fiveMin:    return "5 minutes before"
        case .fifteenMin: return "15 minutes before"
        case .thirtyMin:  return "30 minutes before"
        case .oneHour:    return "1 hour before"
        case .twoHours:   return "2 hours before"
        case .oneDay:     return "1 day before"
        case .twoDays:    return "2 days before"
        case .oneWeek:    return "1 week before"
        case .oneMonth:   return "1 month before"
        case .custom:     return "Custom…"
        }
    }

    var value: EarlyReminder? {
        switch self {
        case .none:       return nil
        case .fiveMin:    return EarlyReminder(value: 5, unit: .minute)
        case .fifteenMin: return EarlyReminder(value: 15, unit: .minute)
        case .thirtyMin:  return EarlyReminder(value: 30, unit: .minute)
        case .oneHour:    return EarlyReminder(value: 1, unit: .hour)
        case .twoHours:   return EarlyReminder(value: 2, unit: .hour)
        case .oneDay:     return EarlyReminder(value: 1, unit: .day)
        case .twoDays:    return EarlyReminder(value: 2, unit: .day)
        case .oneWeek:    return EarlyReminder(value: 1, unit: .week)
        case .oneMonth:   return EarlyReminder(value: 1, unit: .month)
        case .custom:     return nil   // handled via customEarly
        }
    }
}

// MARK: - Small string helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
