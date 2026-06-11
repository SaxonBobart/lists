import SwiftUI

/// Bottom sheet for adding a new item (task, note, or habit). Tasks and
/// notes share the full Date/Time + Repeat/Early Reminder + Details layout.
/// Habits use a dedicated layout that mirrors `HabitDetailView` — a single
/// **Habit** section (Frequency, Goal per cycle, Reminder + time, Show
/// streak) plus the standard Details section.
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
    @State private var hasReminder: Bool = false
    @State private var isUrgent: Bool = false
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
    @State private var showStreak: Bool = true

    // Event-only fields (start + optional end + completable)
    @State private var hasEnd: Bool = false
    @State private var endDate: Date = Self.defaultDue().addingTimeInterval(3600)
    @State private var completable: Bool = false

    // Habit-only fields (mirror HabitDetailView's Details tab)
    @State private var habitFrequency: HabitFrequency = .daily
    @State private var hasHabitReminderTime: Bool = false
    @State private var habitReminderTime: Date = Self.defaultHabitReminderTime()

    // Sub-sheet presentation
    @State private var showRepeatCustom = false
    @State private var showEarlyCustom = false
    @State private var showTimeZonePicker = false
    @State private var showSectionPicker = false
    @State private var isShowingMarkdownEditor = false
    @State private var showDiscardConfirm = false
    /// Set to true just before calling `dismiss()` from the Discard button so
    /// the `SheetDismissInterceptor` allows the dismissal to go through even
    /// while the form is still dirty.
    @State private var pendingDismiss = false

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
                        discardPopover(
                            title: "Are you sure you want to discard this new item?"
                        )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        add()
                    } label: {
                        Image(systemName: "checkmark")
                            .accessibilityLabel("Add")
                    }
                    .tint(Color.primary)
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
                        // Reminder does NOT auto-enable Time — date-only
                        // reminders are valid (fire at start of day). Only
                        // expand the time wheel if the user already turned
                        // Time on themselves.
                        if hasTime { expandedPicker = .time }
                    } else {
                        earlyPreset = .none
                        customEarly = nil
                        isUrgent = false
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
            .fullScreenCover(isPresented: $isShowingMarkdownEditor) {
                MarkdownEditorView(text: $notes, title: title) {
                    isShowingMarkdownEditor = false
                }
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

    /// Turning Urgent on implies "alarm at this time" — auto-enable Reminder
    /// and Time (the cascades in `onChange(of: hasReminder)` /
    /// `onChange(of: hasTime)` flip Date on and expand the time wheel).
    private var urgentBinding: Binding<Bool> {
        Binding(
            get: { isUrgent },
            set: { newValue in
                withAnimation(.smooth) {
                    isUrgent = newValue
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

    /// Event "Ends" toggle — seeds a sensible span when switched on (+1 hour
    /// for a timed event, next day for an all-day one).
    private var endBinding: Binding<Bool> {
        Binding(
            get: { hasEnd },
            set: { newValue in
                withAnimation(.smooth) {
                    hasEnd = newValue
                    if newValue {
                        endDate = hasTime
                            ? due.addingTimeInterval(3600)
                            : (Calendar.current.date(byAdding: .day, value: 1, to: due) ?? due)
                    }
                }
            }
        )
    }

    // MARK: - Subviews

    private var typePicker: some View {
        Picker("Type", selection: $selectedType) {
            Text("Task").tag(Item.ItemType.task).accessibilityIdentifier("quickcapture.type.task")
            Text("Note").tag(Item.ItemType.note).accessibilityIdentifier("quickcapture.type.note")
            Text("Habit").tag(Item.ItemType.habit).accessibilityIdentifier("quickcapture.type.habit")
            Text("Event").tag(Item.ItemType.event).accessibilityIdentifier("quickcapture.type.event")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var pickerInset: some View {
        typePicker
            .glassEffect()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    /// Apple Reminders-style discard popover: title prompt and a single
    /// centered destructive pill button. Tap-outside dismisses naturally
    /// because `SheetDismissInterceptor` releases `isModalInPresentation`
    /// while this popover is open.
    private func discardPopover(title: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showDiscardConfirm = false
                pendingDismiss = true
                DispatchQueue.main.async { dismiss() }
            } label: {
                Text("Discard Changes")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 260)
        .presentationCompactAdaptation(.popover)
    }

    private var form: some View {
        Form {
            titleAndTagsSection
            if selectedType == .habit {
                habitSection
                habitDetailsSection
            } else {
                dateAndTimeSection
                if hasDate {
                    repeatAndEarlySection
                }
                detailsSection
            }
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        // Explicit grouped backdrop so the section cards contrast against the
        // sheet in light mode (see ItemDetailSheet for the same fix).
        .background(Color(.systemGroupedBackground))
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
                        .accessibilityIdentifier("quickcapture.title")
                    TagInputView(tags: $tags)
                        .accessibilityIdentifier("quickcapture.tags")
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
                .accessibilityIdentifier("quickcapture.body")
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
            splitToggleRow(
                title: "Date",
                subtitle: hasDate ? dateSubtitle : nil,
                systemImage: "calendar",
                isOn: dateBinding,
                tapTarget: hasDate
                    ? { withAnimation(.smooth) { expandedPicker = expandedPicker == .date ? .none : .date } }
                    : nil
            )
            .accessibilityIdentifier("quickcapture.due")

            if hasDate && expandedPicker == .date {
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

            splitToggleRow(
                title: selectedType == .event ? "Starts" : "Time",
                subtitle: hasTime ? timeSubtitle : nil,
                systemImage: "clock",
                isOn: timeBinding,
                tapTarget: hasTime
                    ? { withAnimation(.smooth) { expandedPicker = expandedPicker == .time ? .none : .time } }
                    : nil
            )

            if hasTime && expandedPicker == .time {
                DatePicker(
                    "Time",
                    selection: $due,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .tint(.blue)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))

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

            if selectedType == .event && hasDate {
                splitToggleRow(
                    title: "Ends",
                    subtitle: nil,
                    systemImage: "calendar.badge.clock",
                    isOn: endBinding,
                    tapTarget: nil
                )
                .accessibilityIdentifier("quickcapture.ends")

                if hasEnd {
                    DatePicker(
                        "End",
                        selection: $endDate,
                        in: due...,
                        displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date]
                    )
                    .labelsHidden()
                    .tint(.blue)
                }
            }

            Toggle(isOn: $hasReminder) {
                rowLabel(title: "Reminder", subtitle: nil, systemImage: "bell")
            }
            .tint(.green)

            Toggle(isOn: urgentBinding) {
                rowLabel(title: "Urgent", subtitle: nil, systemImage: "alarm.fill")
            }
            .tint(.green)

            placeholderRow(label: "Location", systemImage: "location")
        } header: {
            Text("Date and Time")
        } footer: {
            Text("Mark this reminder as urgent to set an alarm.")
        }
    }

    /// Row with a label area on the left and a `Toggle` switch on the right
    /// (drives `isOn`). Used for Date and Time so tapping the label
    /// expands/collapses the inline picker while the switch still controls
    /// enable/disable. Pass `nil` for `tapTarget` to make the label inert:
    /// no `Button` is rendered (so no press feedback), and an empty
    /// `onTapGesture` absorbs taps so SwiftUI's Form row-level "tap anywhere
    /// flips the Toggle" behavior can't fire. The switch is then the only
    /// way to flip `isOn`.
    private func splitToggleRow(
        title: String,
        subtitle: String?,
        systemImage: String,
        isOn: Binding<Bool>,
        tapTarget: (() -> Void)?
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

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.green)
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
                    systemImage: repeatPreset == .never ? "repeat.badge.xmark" : "repeat"
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
            if selectedType == .event {
                Toggle(isOn: $completable) {
                    rowLabel(title: "Checkbox",
                             subtitle: completable ? "Behaves like a task — can go overdue" : nil,
                             systemImage: "checkmark.circle")
                }
                .tint(.green)
                .accessibilityIdentifier("quickcapture.completable")
            }

            Toggle(isOn: $flagged) {
                rowLabel(title: "Flag", subtitle: nil, systemImage: "flag")
            }
            .tint(.green)
            .accessibilityIdentifier("quickcapture.flag")

            Picker(selection: $priority) {
                ForEach(Item.Priority.allCases, id: \.self) { p in
                    Text(displayName(for: p)).tag(p)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: priorityGlyph(for: priority))
                        .imageScale(.small)
                        .foregroundStyle(priorityIconColor(for: priority))
                        .frame(width: 24, alignment: .center)
                    Text("Priority")
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .accessibilityIdentifier("quickcapture.priority")

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
                    if let section, !section.isEmpty,
                       let name = sectionDisplayName(section) {
                        Text(name)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                        .font(.footnote)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quickcapture.section")

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
            .tint(.primary)
            .accessibilityIdentifier("quickcapture.list")

            placeholderRow(label: "Attachments", systemImage: "paperclip")
        }
    }

    // MARK: - Habit-specific sections

    /// Mirrors `HabitDetailView.detailsContent` — single Habit section with
    /// Frequency (full HabitFrequency, not the task-shaped 4-option preset),
    /// Goal per cycle, Reminder toggle + Time picker, Show streak.
    private var habitSection: some View {
        Section("Habit") {
            Picker(selection: $habitFrequency) {
                ForEach(HabitFrequency.habitCadences, id: \.self) { f in
                    Text(displayName(for: f)).tag(f)
                }
            } label: {
                Label("Frequency", systemImage: "repeat")
                    .labelStyle(GlyphLabelStyle())
            }

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

            Toggle(isOn: habitReminderBinding) {
                rowLabel(title: "Reminder", subtitle: nil, systemImage: "bell")
            }
            .tint(.green)

            if hasHabitReminderTime {
                DatePicker(
                    selection: $habitReminderTime,
                    displayedComponents: .hourAndMinute
                ) {
                    Label("Time", systemImage: "clock")
                        .labelStyle(GlyphLabelStyle())
                }
            }

            Toggle(isOn: $showStreak) {
                rowLabel(title: "Show streak", subtitle: nil, systemImage: "flame")
            }
            .tint(.green)
        }
    }

    private var habitDetailsSection: some View {
        Section("Details") {
            Toggle(isOn: $flagged) {
                rowLabel(title: "Flag", subtitle: nil, systemImage: "flag")
            }
            .tint(.green)
            .accessibilityIdentifier("quickcapture.flag")

            Picker(selection: $priority) {
                ForEach(Item.Priority.allCases, id: \.self) { p in
                    Text(displayName(for: p)).tag(p)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: priorityGlyph(for: priority))
                        .imageScale(.small)
                        .foregroundStyle(priorityIconColor(for: priority))
                        .frame(width: 24, alignment: .center)
                    Text("Priority")
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .accessibilityIdentifier("quickcapture.priority")

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
                    if let section, !section.isEmpty,
                       let name = sectionDisplayName(section) {
                        Text(name)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                        .font(.footnote)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quickcapture.section")

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
            .tint(.primary)
            .accessibilityIdentifier("quickcapture.list")
        }
    }

    private var habitReminderBinding: Binding<Bool> {
        Binding(
            get: { hasHabitReminderTime },
            set: { newValue in
                withAnimation(.smooth) { hasHabitReminderTime = newValue }
            }
        )
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

        let commonDirty = !trimmedTitle.isEmpty
            || !tags.isEmpty
            || !notes.isEmpty
            || selectedType != typeDefault
            || flagged
            || priority != .none
            || section != defaultSection
            || listId != defaultListId

        if selectedType == .habit {
            return commonDirty
                || habitFrequency != .daily
                || hasHabitReminderTime
                || goalPerCycle != 1
                || !showStreak
        }

        let initialRepeat: RepeatPreset = typeDefault == .habit ? .daily : .never
        return commonDirty
            || hasDate
            || hasTime
            || hasReminder
            || isUrgent
            || repeatPreset != initialRepeat
            || endRepeatOn
            || earlyPreset != .none
            || customRRule != nil
            || customEarly != nil
            || hasEnd
            || completable
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

    private func priorityGlyph(for p: Item.Priority) -> String {
        switch p {
        case .none:   return "exclamationmark.circle"
        case .low:    return "exclamationmark"
        case .medium: return "exclamationmark.2"
        case .high:   return "exclamationmark.3"
        }
    }

    private func priorityIconColor(for p: Item.Priority) -> Color {
        switch p {
        case .none:   return Color.secondary
        case .low:    return .yellow
        case .medium: return .orange
        case .high:   return .red
        }
    }

    private func displayName(for f: HabitFrequency) -> String {
        switch f {
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
        case .custom:            return "Custom"
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

    private static func defaultHabitReminderTime() -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
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

        let resolvedDue: Date?
        let resolvedDueAllDay: Bool
        let resolvedReminder: Reminder?
        let resolvedTriggers: Triggers?
        let resolvedRecurrence: Recurrence?
        let resolvedFrequency: HabitFrequency?
        let resolvedTimeZone: String?

        switch selectedType {
        case .task, .note, .event:
            resolvedDue = hasDate ? due : nil
            resolvedDueAllDay = hasDate && !hasTime
            let resolvedEarly: EarlyReminder?
            if earlyPreset == .custom {
                resolvedEarly = customEarly
            } else {
                resolvedEarly = earlyPreset.value
            }
            resolvedReminder = hasReminder
                ? Reminder(enabled: true, early: resolvedEarly)
                : nil
            resolvedTriggers = isUrgent
                ? Triggers(urgent: TriggerToggle(enabled: true))
                : nil
            resolvedRecurrence = composedRRule().map { Recurrence(rrule: $0) }
            resolvedFrequency = nil
            resolvedTimeZone = dueTimeZone

        case .habit:
            // Habits use the simpler Habit-section fields; no Date/Time
            // toggles, no urgency, no early reminder, no end-repeat. Mirror
            // HabitDetailView's save shape.
            resolvedDue = hasHabitReminderTime ? habitReminderTime : nil
            resolvedDueAllDay = false
            resolvedReminder = hasHabitReminderTime
                ? Reminder(enabled: true, early: nil)
                : nil
            resolvedTriggers = nil
            resolvedRecurrence = nil
            resolvedFrequency = habitFrequency
            resolvedTimeZone = nil
        }

        var item = Item(
            type: selectedType,
            title: cleanedTitle.isEmpty ? trimmedTitle : cleanedTitle,
            listId: listId,
            section: section?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            tags: mergedTags,
            due: resolvedDue,
            dueAllDay: resolvedDueAllDay,
            dueTimeZone: resolvedTimeZone,
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
        if selectedType == .event {
            item.end = (hasDate && hasEnd) ? endDate : nil
            item.completable = completable
        }
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

    /// Concise human label for an existing task RRULE: the matching preset's
    /// name when it maps to one ("Daily", "Every 6 months"), otherwise the
    /// custom summary ("Every 6 weeks"). Used by the row recurrence indicator.
    static func summary(forRRule rrule: String) -> String {
        if let preset = taskOptions.first(where: { $0.rrule == rrule }) {
            return preset.displayName
        }
        return RecurrenceRule.parse(rrule)?.shortLabel ?? "Custom"
    }

    static let taskOptions: [RepeatPreset] = [
        .never, .hourly, .daily, .weekdays, .weekends, .weekly,
        .fortnightly, .monthly, .everyThreeMonths, .everySixMonths, .yearly, .custom
    ]

    static let habitOptions: [RepeatPreset] = [.daily, .weekly, .monthly]
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
