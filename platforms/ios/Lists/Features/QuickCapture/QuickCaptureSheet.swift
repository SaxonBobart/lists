import SwiftUI

/// Bottom sheet for adding a new item. Tasks, notes, and events share the
/// Date/Time + Repeat/Early Reminder + Details layout.
struct QuickCaptureSheet: View {
    let store: ItemStore
    let defaultListId: String
    let defaultSection: String?
    let defaultNewItemType: Item.ItemType
    let initialSchedule: CalendarCaptureSchedule?
    var onOpenCreatedItem: (Item) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var titleFocused: Bool

    private let pasteOnOpen: Bool
    @State private var didPasteOnOpen = false
    @State private var clipboardPayload: ItemClipboardPayload?
    @State private var clipboardBody = ""
    @State private var pastedScheduleState: (hasDate: Bool, hasTime: Bool, hasReminder: Bool)?
    @State private var selectedType: Item.ItemType
    @State private var descriptionSession = ItemDescriptionSession()
    @State private var descriptionSeed: Item?
    @State private var lastDescriptionDraft: Item?
    @State private var descriptionLocks: Set<ItemDescriptionField> = []
    @State private var inferredTitle: String?
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
    // Event-only fields (start + end + completable)
    @State private var endDate: Date = Self.defaultDue().addingTimeInterval(3600)
    @State private var completable: Bool = false
    /// All-day event toggle. Mirrors the editor: when on, the Starts/Ends pills
    /// drop their time component (`displayedComponents` becomes `[.date]`).
    @State private var allDay: Bool = false

    // Sub-sheet presentation
    @State private var showRepeatCustom = false
    @State private var showEarlyCustom = false
    @State private var showTimeZonePicker = false
    @State private var showSectionPicker = false
    @State private var showDiscardConfirm = false
    @State private var isSaving = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    /// Set to true just before calling `dismiss()` from the Discard button so
    /// the `SheetDismissInterceptor` allows the dismissal to go through even
    /// while the form is still dirty.
    @State private var pendingDismiss = false

    init(
        store: ItemStore,
        defaultListId: String = ItemList.inboxId,
        defaultSection: String? = nil,
        defaultNewItemType: Item.ItemType = .task,
        initialSchedule: CalendarCaptureSchedule? = nil,
        pasteOnOpen: Bool = false,
        onOpenCreatedItem: @escaping (Item) -> Void = { _ in }
    ) {
        self.store = store
        self.defaultListId = defaultListId
        self.defaultSection = defaultSection
        self.defaultNewItemType = defaultNewItemType
        self.initialSchedule = initialSchedule
        self.pasteOnOpen = pasteOnOpen
        self.onOpenCreatedItem = onOpenCreatedItem
        _listId = State(initialValue: defaultListId)
        let initialType = ItemTypePolicy().effectiveDefaultType(defaultNewItemType)
        _selectedType = State(initialValue: initialType)
        _repeatPreset = State(initialValue: .never)
        _section = State(initialValue: defaultSection)
        if let schedule = initialSchedule {
            _due = State(initialValue: schedule.start)
            _hasDate = State(initialValue: true)
            _hasTime = State(initialValue: !schedule.isAllDay)
            _allDay = State(initialValue: schedule.isAllDay)
            _endDate = State(
                initialValue: schedule.end
                    ?? EventDefaults.defaultEnd(
                        for: schedule.start,
                        allDay: schedule.isAllDay
                    )
            )
            _dueTimeZone = State(initialValue: TimeZone.current.identifier)
        }
    }

    var body: some View {
        NavigationStack {
            form
                .disabled(isSaving)
                .safeAreaInset(edge: .top, spacing: 0) {
                    pickerInset.disabled(isSaving)
                }
                .background {
                    // While the discard popover is open we drop the modal
                    // flag so the popover's natural tap-outside dismiss
                    // works — otherwise the sheet's `isModalInPresentation`
                    // bleeds into the popover and traps the user.
                    SheetDismissInterceptor(
                        preventDismiss: isSaving
                            || (isDirty && !showDiscardConfirm && !pendingDismiss),
                        onAttempt: {
                            if !isSaving { showDiscardConfirm = true }
                        }
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
                    .disabled(isSaving)
                    .accessibilityIdentifier("quickcapture.cancel")
                    .popover(isPresented: $showDiscardConfirm) {
                        QuickCaptureDiscardPopover(
                            title: "Are you sure you want to discard this new item?",
                            onDiscard: discardChanges
                        )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if ItemClipboard.shared.canPaste {
                        Button("Paste", systemImage: "doc.on.clipboard", action: pasteIntoDraft)
                            .accessibilityIdentifier("quickcapture.paste")
                            .disabled(isSaving)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        add(openCreatedItem: true)
                    } label: {
                        Image(systemName: openCreatedItemIcon)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .accessibilityLabel(openCreatedItemLabel)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(ListsTokens.documentAccent)
                    .disabled(trimmedTitle.isEmpty || isSaving)
                    .accessibilityIdentifier("quickcapture.save.and.open.notes")
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
                    .disabled(trimmedTitle.isEmpty || isSaving)
                    .accessibilityIdentifier("quickcapture.save")
                }
            }
            .defaultFocus($titleFocused, true)
            .task {
                // Request keyboard focus after the presented field joins the hierarchy.
                // defaultFocus alone does not activate the keyboard on iPhone.
                await Task.yield()
                guard !Task.isCancelled else { return }
                titleFocused = true
            }
            .onDisappear { descriptionSession.cancel() }
            .onChange(of: title) { _, _ in interpretDescription() }
            .onAppear {
                if descriptionSeed == nil {
                    descriptionSeed = draft.makeItem()
                    lastDescriptionDraft = draft.makeItem()
                }
                if pasteOnOpen && !didPasteOnOpen { didPasteOnOpen = true; pasteIntoDraft() }
            }
            .onChange(of: selectedType) { _, newValue in
                descriptionSession.cancel()
                inferredTitle = nil
                descriptionSeed = nil

                // Events always carry a start + end (like the editor). Seed a
                // sensible end if the carried-over value isn't after the start.
                if newValue == .event, endDate <= due {
                    endDate = due.addingTimeInterval(3600)
                }
                lastDescriptionDraft = draft.makeItem()
                interpretDescription()
            }
            .onChange(of: hasDate) { oldValue, newValue in
                if pastedScheduleState?.hasDate == newValue { return }
                pastedScheduleState = nil
                withFormAnimation {
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
                if pastedScheduleState?.hasTime == newValue { return }
                pastedScheduleState = nil
                withFormAnimation {
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
                if pastedScheduleState?.hasReminder == newValue { return }
                pastedScheduleState = nil
                withFormAnimation {
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
                CustomRepeatSheet(initialRRule: customRRule, startDate: hasScheduledDate ? due : .now) { rrule in
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
        .alert("Couldn’t Add Item", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {
                saveErrorMessage = ""
            }
            .accessibilityIdentifier("quickcapture.persistence.error.dismiss")
        } message: {
            Text(saveErrorMessage)
        }
    }

    // MARK: - Animated bindings (so picker insertion/collapse animates)

    private var dateBinding: Binding<Bool> {
        Binding(
            get: { hasDate },
            set: { newValue in
                withFormAnimation { hasDate = newValue }
            }
        )
    }

    private var timeBinding: Binding<Bool> {
        Binding(
            get: { hasTime },
            set: { newValue in withFormAnimation { hasTime = newValue } }
        )
    }

    /// Turning Alarm on implies "alarm at this time" — auto-enable Reminder
    /// and Time (the cascades in `onChange(of: hasReminder)` /
    /// `onChange(of: hasTime)` flip Date on and expand the time wheel).
    private var alarmBinding: Binding<Bool> {
        Binding(
            get: { hasAlarm },
            set: { newValue in
                withFormAnimation {
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
                withFormAnimation { endRepeatOn = newValue }
            }
        )
    }

    // MARK: - Subviews

    @ViewBuilder
    private var pickerInset: some View {
        QuickCaptureTypePicker(
            selection: $selectedType,
            habitsPluginEnabled: false
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
            if clipboardPayload == nil, inferredTitle != nil || descriptionSession.isAnalyzing || descriptionSession.statusMessage != nil {
                Section {
                    if inferredTitle != nil {
                        TextField("Title", text: Binding(
                            get: { inferredTitle ?? title },
                            set: { inferredTitle = $0; descriptionLocks.insert(.title) }
                        ))
                        .accessibilityIdentifier("quickcapture.inferred.title")
                    }
                    if !clipboardBody.isEmpty {
                        TextField("Notes", text: Binding(
                            get: { clipboardBody },
                            set: { clipboardBody = $0; descriptionLocks.insert(.body) }
                        ), axis: .vertical)
                        .accessibilityIdentifier("quickcapture.inferred.body")
                    }
                } footer: {
                    if descriptionSession.isAnalyzing {
                        HStack { ProgressView(); Text("Finding details…") }
                    } else if let message = descriptionSession.statusMessage {
                        Text(message)
                    } else if inferredTitle != nil {
                        Text("Details filled from your description. You can edit them before saving.")
                    }
                }
            }

                QuickCaptureDateAndTimeSection(
                    selectedType: selectedType,
                    due: $due,
                    endDate: $endDate,
                    allDay: $allDay,
                    completable: $completable,
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
                        withFormAnimation {
                            expandedPicker = expandedPicker == .date ? .none : .date
                        }
                    },
                    onToggleTimePicker: {
                        withFormAnimation {
                            expandedPicker = expandedPicker == .time ? .none : .time
                        }
                    },
                    onShowTimeZonePicker: { showTimeZonePicker = true }
                )
                if hasScheduledDate {
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
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        // Explicit grouped backdrop so the section cards contrast against the
        // sheet in light mode.
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Helpers

    private var trimmedTitle: String {
        (inferredTitle ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Events always have a start date even though they do not use the task
    /// Date toggle. Their recurrence and early-reminder controls therefore
    /// remain available when `hasDate` is false.
    private var hasScheduledDate: Bool {
        selectedType == .event || hasDate
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
        selectedType.descriptionPlaceholder
    }

    private var openCreatedItemIcon: String {
        "text.document"
    }

    private var openCreatedItemLabel: String {
        "Add and Open Notes"
    }

    private var availableRepeatPresets: [RepeatPreset] {
        RepeatPreset.taskOptions
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
        guard !isSaving else { return }
        showDiscardConfirm = false
        pendingDismiss = true
        DispatchQueue.main.async { dismiss() }
    }

    private func withFormAnimation(_ updates: () -> Void) {
        withAnimation(reduceMotion ? nil : .smooth, updates)
    }

    private static func defaultDue() -> Date {
        ReminderPreferences.defaultTime()
    }

    private static func defaultEndRepeat() -> Date {
        ScheduleFormatting.defaultEndRepeat()
    }

    private var draft: QuickCaptureDraft {
        QuickCaptureDraft(
            selectedType: selectedType,
            title: inferredTitle ?? title,
            tags: tags,
            notes: clipboardBody,
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
            endDate: endDate,
            completable: completable,
            allDay: allDay
        )
    }

    private func interpretDescription() {
        guard clipboardPayload == nil, !isSaving else { return }
        let current = draft.makeItem()
        if let previous = lastDescriptionDraft {
            var changes = ItemDescriptionMerge.detectingChangedFields(current: current, previous: previous)
            changes.remove(.title)
            descriptionLocks.formUnion(changes)
        }
        var seed = descriptionSeed ?? current
        seed = ItemDescriptionMerge.applying(
            .init(item: current, fields: descriptionLocks), to: seed,
            lockedFields: Set(ItemDescriptionField.allCases).subtracting(descriptionLocks)
        )
        seed.title = title
        descriptionSeed = seed
        applyDescriptionItem(ItemDescriptionMerge.applying(
            .init(item: seed, fields: []), to: current, lockedFields: descriptionLocks
        ))
        if !descriptionLocks.contains(.title) { inferredTitle = nil }
        lastDescriptionDraft = draft.makeItem()
        let request = ItemDescriptionRequest(
            description: title, seed: seed,
            destinations: activeLists.map { list in
                .init(id: list.id, name: list.name, sections: list.sections.map {
                    .init(id: $0.id.uuidString, name: $0.name)
                })
            }, referenceDate: .now, localeIdentifier: Locale.current.identifier,
            timeZoneIdentifier: TimeZone.current.identifier
        )
        descriptionSession.schedule(request) { extraction in
            let latest = draft.makeItem()
            if let previous = lastDescriptionDraft {
                var changes = ItemDescriptionMerge.detectingChangedFields(current: latest, previous: previous)
                changes.remove(.title)
                descriptionLocks.formUnion(changes)
            }
            let item = ItemDescriptionMerge.applying(extraction, to: latest, lockedFields: descriptionLocks)
            applyDescriptionItem(item)
        }
    }

    private func applyDescriptionItem(_ item: Item) {
        pastedScheduleState = (item.due != nil, item.due != nil && !item.dueAllDay, item.reminder?.enabled == true)
        inferredTitle = item.title
        clipboardBody = item.body
        tags = item.tags
        hasDate = item.due != nil
        due = item.due ?? Self.defaultDue()
        dueTimeZone = item.dueTimeZone
        hasTime = item.due != nil && !item.dueAllDay
        allDay = item.dueAllDay
        endDate = item.end ?? due.addingTimeInterval(3600)
        flagged = item.flagged
        priority = item.priority
        section = item.section
        listId = item.listId
        completable = item.completable
        hasReminder = item.reminder?.enabled == true
        hasAlarm = item.triggers?.alarm?.enabled == true
        customEarly = item.reminder?.early
        earlyPreset = customEarly == nil ? .none : .custom
        customRRule = item.recurrence?.rrule
        repeatPreset = customRRule == nil ? .never : .custom
        endRepeatOn = false
        lastDescriptionDraft = draft.makeItem()
    }

    private func pasteIntoDraft() {
        descriptionSession.cancel()
        inferredTitle = nil
        do {
            let payload = try ItemClipboard.shared.read()
            let originals = try payload.items()
            let copies = ItemClipboard.copies(originals, destination: .init(listId: listId, section: section, schedule: initialSchedule))
            guard let item = copies.first else { return }
            pastedScheduleState = (item.due != nil, item.due != nil && !item.dueAllDay, item.reminder?.enabled == true)
            clipboardPayload = payload
            clipboardBody = item.body
            selectedType = item.type
            title = item.title
            tags = item.tags
            hasDate = item.due != nil
            due = item.due ?? Self.defaultDue()
            dueTimeZone = item.dueTimeZone
            hasTime = item.due != nil && !item.dueAllDay
            allDay = item.dueAllDay
            endDate = item.end ?? due.addingTimeInterval(3600)
            flagged = item.flagged
            priority = item.priority
            completable = item.completable
            hasReminder = item.reminder?.enabled == true
            hasAlarm = item.triggers?.alarm?.enabled == true
            customEarly = item.reminder?.early
            earlyPreset = customEarly == nil ? .none : .custom
            customRRule = item.recurrence?.rrule
            repeatPreset = customRRule == nil ? .never : .custom
            endRepeatOn = false
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }

    private func add(openCreatedItem: Bool) {
        guard !isSaving, !trimmedTitle.isEmpty else { return }
        descriptionSession.cancel()
        let item = draft.makeItem()
        isSaving = true
        showSaveError = false

        Task {
            do {
                var savedItem = item
                if let clipboardPayload {
                    savedItem = try await ItemClipboard.shared.paste(clipboardPayload,
                        into: .init(listId: item.listId, section: item.section), store: store, editedRoot: item)
                } else { try await store.add(item) }
                pendingDismiss = true
                isSaving = false
                dismiss()

                if openCreatedItem {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onOpenCreatedItem(savedItem)
                    }
                }
            } catch {
                saveErrorMessage = error.localizedDescription
                isSaving = false
                showSaveError = true
            }
        }
    }
}
