import SwiftUI

/// Modal sheet for viewing AND editing an existing item. Routes by type:
/// tasks, notes, and events open as a document-style page
/// (`ItemDocumentView` — title, fact strip, inline markdown body, live-apply,
/// full controls in a Details pop-up); habits keep this classic draft + Save
/// form (`ItemDetailContent`), since their detail surface is the dedicated
/// Overview/Log screen (`HabitDetailView`).
struct ItemDetailSheet: View {
    let originalItem: Item
    let store: ItemStore

    @State private var path = NavigationPath()

    init(item: Item, store: ItemStore) {
        self.originalItem = item
        self.store = store
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if originalItem.type == .habit {
                    ItemDetailContent(item: originalItem, store: store)
                } else {
                    ItemDocumentView(item: originalItem, store: store, path: $path)
                }
            }
            .navigationDestination(for: ThreadDestination.self) { dest in
                if let root = store.items.first(where: { $0.id == dest.rootId }) {
                    ThreadView(root: root, store: store)
                }
            }
            // Single registration at the stack root so breadcrumb jumps work
            // from any depth (a per-page destination would collide by type).
            .navigationDestination(for: BreadcrumbDestination.self) { dest in
                if let item = store.items.first(where: { $0.id == dest.id && $0.deletedAt == nil }) {
                    ItemDocumentView(item: item, store: store, path: $path)
                }
            }
        }
    }
}

// MARK: - Inner content

/// The classic draft + Save form — reached only for habits now (other types
/// route to `ItemDocumentView`). No notes field: habits deliberately have no
/// markdown body (the existing body, if any, is preserved untouched on save).
struct ItemDetailContent: View {
    let originalItem: Item
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss

    // Editable item fields
    @State private var selectedType: Item.ItemType
    @State private var title: String
    @State private var notes: String
    @State private var tags: [String]
    @State private var done: Bool
    @State private var listId: String
    @State private var section: String?
    @State private var priority: Item.Priority
    @State private var flagged: Bool

    // Date / time
    @State private var hasDate: Bool
    @State private var due: Date
    @State private var hasTime: Bool
    @State private var hasReminder: Bool
    @State private var isUrgent: Bool
    @State private var dueTimeZone: String?

    /// Which inline picker is currently visible. Separated from `hasDate` /
    /// `hasTime` so the user can collapse the picker without disabling the
    /// row — tapping the row label flips this; the switch flips enable state.
    private enum ExpandedPicker { case none, date, time }
    @State private var expandedPicker: ExpandedPicker = .none

    // Repeat + Early Reminder
    @State private var repeatPreset: RepeatPreset
    @State private var customRRule: String?
    @State private var endRepeatOn: Bool
    @State private var endRepeatDate: Date
    @State private var earlyPreset: EarlyReminderPreset
    @State private var customEarly: EarlyReminder?

    // Habit-specific
    @State private var goalPerCycle: Int
    @State private var showStreak: Bool

    // Sub-sheet presentation
    @State private var showRepeatCustom = false
    @State private var showEarlyCustom = false
    @State private var showTimeZonePicker = false
    @State private var showSectionPicker = false
    @State private var showingDeleteConfirm = false
    @State private var showDiscardConfirm = false
    /// Set to true just before calling `dismiss()` from the Discard button so
    /// the `SheetDismissInterceptor` allows the dismissal to go through even
    /// while the form is still dirty.
    @State private var pendingDismiss = false

    init(item: Item, store: ItemStore) {
        self.originalItem = item
        self.store = store

        _selectedType = State(initialValue: item.type)
        _title = State(initialValue: item.title)
        _notes = State(initialValue: item.body)
        _tags = State(initialValue: item.tags)
        _done = State(initialValue: item.done)
        _listId = State(initialValue: item.listId)
        _section = State(initialValue: item.section)
        _priority = State(initialValue: item.priority)
        _flagged = State(initialValue: item.flagged)

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

        _goalPerCycle = State(initialValue: item.goalPerCycle)
        _showStreak = State(initialValue: item.showStreak)
    }

    var body: some View {
        formChrome
            .background {
                // While the discard popover is open we drop the modal flag
                // so the popover's natural tap-outside dismiss works —
                // otherwise the sheet's `isModalInPresentation` bleeds into
                // the popover and traps the user.
                SheetDismissInterceptor(
                    preventDismiss: isDirty && !showDiscardConfirm && !pendingDismiss,
                    onAttempt: { showDiscardConfirm = true }
                )
            }
            .alert("Delete this item?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\"\(title)\" will move to Recently Deleted.")
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
            if newValue == .never { endRepeatOn = false }
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

    // MARK: - Subviews

    /// Form + pinned picker bar + nav toolbar. Pulled out of `body` so the
    /// chained `.alert` / `.sheet` / `.onChange` modifiers stay below
    /// Swift's complex-expression type-checking limit.
    private var formChrome: some View {
        form
            .safeAreaInset(edge: .top, spacing: 0) { pickerInset }
            .scrollEdgeEffectStyle(.soft, for: .top)
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
                    .accessibilityIdentifier("itemdetail.cancel")
                    .popover(isPresented: $showDiscardConfirm) {
                        discardPopover(
                            title: "Are you sure you want to discard your changes?"
                        )
                    }
                }
                ToolbarItem(placement: .principal) {
                    treePill
                        .accessibilityIdentifier("itemdetail.parent")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                            .accessibilityLabel("Save")
                    }
                    .tint(Color.primary)
                    .disabled(!isDirty)
                    .accessibilityIdentifier("itemdetail.save")
                }
            }
    }

    @ViewBuilder
    private var pickerInset: some View {
        if originalItem.type != .habit {
            typePicker
                .glassEffect()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
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

    /// Tree-view pill (sub-item / parent) or, when standalone, a plain
    /// "Edit Item" title. See `DetailSheetHeaderTitle`.
    private var treePill: some View {
        DetailSheetHeaderTitle(item: originalItem, store: store, standaloneLabel: "Edit Item")
    }

    private var typePicker: some View {
        Picker("Type", selection: $selectedType) {
            Text("Task").tag(Item.ItemType.task)
            Text("Note").tag(Item.ItemType.note)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var form: some View {
        Form {
            titleAndTagsSection
            dateAndTimeSection
            if hasDate {
                repeatAndEarlySection
            }
            tagsSection
            detailsSection
            deleteSection
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        // Backdrop the form with the grouped-page color so the section cards
        // (.secondarySystemGroupedBackground — white in light mode, dark gray
        // in dark) read as cards. Without this, light-mode cards vanish into
        // the sheet's default white background.
        .background(Color(.systemGroupedBackground))
    }

    private var titleAndTagsSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                if selectedType == .task {
                    Button {
                        done.toggle()
                    } label: {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(done ? Color.accentColor : Color(.tertiaryLabel))
                            .frame(width: 28, alignment: .center)
                            .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: leadingDecorationIcon)
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, alignment: .center)
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Title", text: $title, axis: .vertical)
                        .font(.title3)
                        .lineLimit(1...6)
                        .strikethrough(done && selectedType == .task,
                                       color: Color(.tertiaryLabel))
                        .foregroundStyle(done && selectedType == .task ? Color.secondary : Color.primary)
                        .accessibilityIdentifier("itemdetail.title")
                }
            }
            .padding(.vertical, 2)
        }
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
            .accessibilityIdentifier("itemdetail.due")

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
                title: "Time",
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

    private var tagsSection: some View {
        Section {
            TagInputView(tags: $tags)
                .accessibilityIdentifier("itemdetail.tags")
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            Toggle(isOn: $flagged) {
                rowLabel(title: "Flag", subtitle: nil, systemImage: "flag")
            }
            .tint(.green)
            .accessibilityIdentifier("itemdetail.flag")

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
            .accessibilityIdentifier("itemdetail.priority")

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
                    if let sectionName = resolvedSectionName, !sectionName.isEmpty {
                        Text(sectionName)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                        .font(.footnote)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("itemdetail.section")

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
            .accessibilityIdentifier("itemdetail.list")

            placeholderRow(label: "Attachments", systemImage: "paperclip")

            if originalItem.type == .habit {
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

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete Item", systemImage: "trash")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .tint(.red)
            .accessibilityIdentifier("itemdetail.delete")
        }
    }

    // MARK: - Animated bindings

    private var dateBinding: Binding<Bool> {
        Binding(
            get: { hasDate },
            set: { newValue in withAnimation(.smooth) { hasDate = newValue } }
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
            set: { newValue in withAnimation(.smooth) { endRepeatOn = newValue } }
        )
    }

    // MARK: - Row label helpers (mirror QuickCaptureSheet)

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

    // MARK: - Computed

    private var typeTitle: String {
        switch originalItem.type {
        case .task:  return "Task"
        case .habit: return "Habit"
        case .note:  return "Note"
        case .event: return "Event"
        }
    }

    private var leadingDecorationIcon: String {
        switch selectedType {
        case .task:  return "circle"
        case .note:  return "text.document.fill"
        case .habit: return "checkmark.arrow.trianglehead.clockwise"
        case .event: return "calendar"
        }
    }

    private var activeLists: [ItemList] {
        store.lists.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }

    private var selectedList: ItemList? {
        store.lists.first { $0.id == listId }
    }

    /// Human-readable label for the currently-bound `section` UUID, looked up
    /// against the selected list's named sections. Returns nil for nil/empty
    /// (uncategorized) or when the UUID no longer matches any section
    /// (orphan — leave the field showing no value).
    private var resolvedSectionName: String? {
        guard let s = section, !s.isEmpty else { return nil }
        return selectedList?.sections.first { $0.id.uuidString == s }?.name
    }

    private var availableRepeatPresets: [RepeatPreset] {
        originalItem.type == .habit ? RepeatPreset.habitOptions : RepeatPreset.taskOptions
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

    // MARK: - Save / Delete

    /// True when any field has diverged from the originalItem.
    private var isDirty: Bool {
        composedItem() != originalItem
    }

    /// Build an `Item` from the current draft state, preserving identity
    /// fields from the original.
    private func composedItem() -> Item {
        let (cleanedTitle, parsedTags) = Tag.extractInline(from: title)
        let mergedTags = mergeTags(parsedTags, with: tags)

        let resolvedDue: Date? = hasDate ? due : nil
        let resolvedDueAllDay = hasDate && !hasTime

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

        let composedRRule = composeRRule()
        let resolvedRecurrence: Recurrence?
        switch originalItem.type {
        case .task, .note, .event:
            resolvedRecurrence = composedRRule.map { Recurrence(rrule: $0) }
        case .habit:
            if repeatPreset == .custom, customRRule != nil {
                resolvedRecurrence = composedRRule.map { Recurrence(rrule: $0) }
            } else {
                resolvedRecurrence = endRepeatOn ? composedRRule.map { Recurrence(rrule: $0) } : nil
            }
        }

        let finalType: Item.ItemType = originalItem.type == .habit ? .habit : selectedType
        let finalTitle = cleanedTitle.isEmpty ? title.trimmingCharacters(in: .whitespacesAndNewlines) : cleanedTitle

        var item = originalItem
        item.type = finalType
        item.title = finalTitle
        item.body = notes
        item.listId = listId
        item.section = section?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.tags = mergedTags
        // Type-flip rule: converting a task into an event keeps its checkbox —
        // `completable` flips on, so a done-state never silently disappears.
        if finalType == .event && originalItem.type == .task {
            item.completable = true
        }
        let keepsDone = finalType == .task || (finalType == .event && item.completable)
        item.done = keepsDone ? done : false
        item.completedAt = (keepsDone && done) ? (originalItem.completedAt ?? .now) : nil
        item.due = resolvedDue
        item.dueAllDay = resolvedDueAllDay
        item.dueTimeZone = dueTimeZone
        item.priority = priority
        item.flagged = flagged
        item.reminder = resolvedReminder
        item.recurrence = resolvedRecurrence
        item.triggers = resolvedTriggers
        item.goalPerCycle = goalPerCycle
        item.showStreak = showStreak
        return item
    }

    private func composeRRule() -> String? {
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

    private func mergeTags(_ inlineTags: [String], with manualTags: [String]) -> [String] {
        var result = manualTags
        for tag in inlineTags {
            result = Tag.appending(tag, to: result)
        }
        return result
    }

    private func save() {
        let toSave = composedItem()
        Task {
            try? await store.update(toSave)
            dismiss()
        }
    }

    private func delete() {
        Task {
            try? await store.softDelete(originalItem.id)
            dismiss()
        }
    }

    // MARK: - Static helpers

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

    /// Detect whether an existing RRULE matches one of the named presets,
    /// and split out the UNTIL= end date if present. Falls back to
    /// `.custom` with the raw RRULE when no preset matches.
    private static func parseRecurrence(_ rrule: String?, type: Item.ItemType) -> (preset: RepeatPreset, customRRule: String?, endDate: Date?) {
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
        let candidates: [RepeatPreset] = type == .habit
            ? RepeatPreset.habitOptions
            : RepeatPreset.taskOptions
        for preset in candidates where preset != .custom && preset != .never {
            if preset.rrule == base {
                return (preset, nil, endDate)
            }
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

// MARK: - Empty-string helper (mirrors QuickCaptureSheet)

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Detail sheet header title

/// Principal toolbar title for a detail sheet, reflecting where the item sits
/// in the hierarchy:
/// - sub-item → "{parent title}" pill; tap opens MoveToParentPicker
/// - parent   → "Move to…" pill; tap opens MoveToParentPicker
/// - standalone (no parent, no children) → plain `standaloneLabel` text, no pill
struct DetailSheetHeaderTitle: View {
    let item: Item
    let store: ItemStore
    let standaloneLabel: String

    @State private var showParentPicker = false

    var body: some View {
        if item.parentId != nil || hasChildren {
            Button {
                showParentPicker = true
            } label: {
                pill(label: pillLabel)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showParentPicker) {
                MoveToParentPicker(item: item, store: store)
            }
        } else {
            Text(standaloneLabel)
                .font(ListsTypography.headline)
                .foregroundStyle(ListsTokens.Foreground.primary)
        }
    }

    private var pillLabel: String {
        if let parent = parentItem {
            return parent.title.isEmpty ? "Untitled" : parent.title
        }
        return "Move to…"
    }

    private func pill(label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.indent")
                .imageScale(.small)
            Text(label)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: Capsule())
    }

    private var parentItem: Item? {
        guard let pid = item.parentId else { return nil }
        return store.items.first { $0.id == pid && $0.deletedAt == nil }
    }

    private var hasChildren: Bool {
        store.items.contains { $0.parentId == item.id && $0.deletedAt == nil }
    }

}
