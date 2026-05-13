import SwiftUI

/// Modal sheet for viewing AND editing an existing item. Mirrors
/// `QuickCaptureSheet`'s row structure (Date and Time, Repeat and Early
/// Reminder, Details) so opening an item feels like the inverse of
/// creating one. Differences from QuickCapture:
/// - Tree-view pill above the title (parent breadcrumb when this is a
///   sub-item; "Tree View" link when this item has its own children)
/// - Notes field for the item body
/// - Type picker is task / note only (habits don't convert)
/// - Trailing Save (checkmark) writes via `store.update`; Delete row at
///   the bottom soft-deletes
struct ItemDetailSheet: View {
    let originalItem: Item
    let store: ItemStore

    init(item: Item, store: ItemStore) {
        self.originalItem = item
        self.store = store
    }

    var body: some View {
        NavigationStack {
            ItemDetailContent(item: originalItem, store: store)
                .navigationDestination(for: ThreadDestination.self) { dest in
                    if let root = store.items.first(where: { $0.id == dest.rootId }) {
                        ThreadView(root: root, store: store)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Inner content

/// The form view used both by the root sheet and any pushed parent
/// destination. Owns its own draft state so navigating up the tree and
/// editing a parent doesn't corrupt the sub-item's pending edits.
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
    @State private var isShowingMarkdownEditor = false
    @State private var showDiscardConfirm = false

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
        form
            .safeAreaInset(edge: .top, spacing: 0) {
                topGlassStrip
            }
            .navigationTitle(typeTitle)
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
                    save()
                } label: {
                    Image(systemName: "checkmark")
                        .accessibilityLabel("Save")
                }
                .disabled(!isDirty)
            }
        }
        .alert("Delete this item?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\"\(title)\" will move to Recently Deleted.")
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: $showDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) { }
        }
        .fullScreenCover(isPresented: $isShowingMarkdownEditor) {
            MarkdownEditorView(text: $notes, title: title) {
                isShowingMarkdownEditor = false
            }
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
            if newValue == .never { endRepeatOn = false }
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
    }

    // MARK: - Subviews

    /// Pill + type picker float on top of the form via `.safeAreaInset`.
    /// No strip background — each element is its own glass capsule and
    /// the form scrolls visibly behind them through the glass. The pill
    /// is offset further up than the picker so they sit independently.
    @ViewBuilder
    private var topGlassStrip: some View {
        VStack(spacing: 6) {
            treePill
                .offset(y: -10)
            if originalItem.type != .habit {
                typePicker
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity)
    }

    /// Liquid-glass capsule above the title. Two states (no pill at all
    /// when the item is standalone with no parent and no children):
    /// - sub-item → label = parent title; tap opens the Tree View of the
    ///   root ancestor so the user sees the whole hierarchy in context
    /// - parent  → label = "Tree View"; tap opens the Tree View rooted at
    ///   this item
    @ViewBuilder
    private var treePill: some View {
        if let parent = parentItem {
            NavigationLink(value: ThreadDestination(rootId: rootAncestorId)) {
                pillContent(label: "Tree View / \(parent.title)")
            }
            .buttonStyle(.plain)
        } else if hasChildren {
            NavigationLink(value: ThreadDestination(rootId: originalItem.id)) {
                pillContent(label: "Tree View")
            }
            .buttonStyle(.plain)
        }
    }

    private func pillContent(label: String) -> some View {
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

    private var typePicker: some View {
        Picker("Type", selection: $selectedType) {
            Text("Task").tag(Item.ItemType.task)
            Text("Note").tag(Item.ItemType.note)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .glassEffect(.regular, in: Capsule())
    }

    private var form: some View {
        Form {
            titleAndTagsSection
            dateAndTimeSection
            repeatAndEarlySection
            detailsSection
            deleteSection
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
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
                    TagInputView(tags: $tags)
                    inlineNotesRow
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Inline notes input — sits directly below tags inside the title
    /// section so the title / tags / notes read as one connected block.
    /// Plain `TextField` styling (no live formatting) keeps the form
    /// lightweight; the trailing expand button hands off to the
    /// `MarkdownEditorView` for the actual Bear-style editing.
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
            Toggle(isOn: dateBinding) {
                rowLabel(
                    title: "Date",
                    subtitle: hasDate ? dateSubtitle : nil,
                    systemImage: "calendar"
                )
            }
            .tint(.green)

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

            Toggle(isOn: timeBinding) {
                rowLabel(
                    title: "Time",
                    subtitle: hasTime ? timeSubtitle : nil,
                    systemImage: "clock"
                )
            }
            .tint(.green)

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
                    .frame(maxWidth: .infinity, alignment: .center)
            }
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
        }
    }

    private var leadingDecorationIcon: String {
        switch selectedType {
        case .task:  return "circle"
        case .note:  return "text.document.fill"
        case .habit: return "arrow.triangle.2.circlepath"
        }
    }

    private var activeLists: [ItemList] {
        store.lists.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }

    private var selectedList: ItemList? {
        store.lists.first { $0.id == listId }
    }

    private var availableRepeatPresets: [RepeatPreset] {
        originalItem.type == .habit ? RepeatPreset.habitOptions : RepeatPreset.taskOptions
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

    private var parentItem: Item? {
        guard let pid = originalItem.parentId else { return nil }
        return store.items.first { $0.id == pid && $0.deletedAt == nil }
    }

    private var hasChildren: Bool {
        store.items.contains { $0.parentId == originalItem.id && $0.deletedAt == nil }
    }

    /// Walk up the parent chain from this item until we reach the
    /// top-level ancestor. Used by the tree-view pill so a deeply nested
    /// sub-item still opens the full tree, not just its immediate parent.
    private var rootAncestorId: UUID {
        var current = originalItem
        while let pid = current.parentId,
              let parent = store.items.first(where: { $0.id == pid && $0.deletedAt == nil }) {
            current = parent
        }
        return current.id
    }

    private func displayName(for p: Item.Priority) -> String {
        switch p {
        case .none:   return "None"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
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
        case .task, .note:
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
        item.done = (finalType == .task) ? done : false
        item.completedAt = (finalType == .task && done) ? (originalItem.completedAt ?? .now) : nil
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
