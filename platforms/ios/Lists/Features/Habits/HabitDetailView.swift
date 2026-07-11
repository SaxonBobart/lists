import SwiftUI

/// The edit surface deliberately presents a normalized view of legacy habit
/// data. Keeping that normalized projection as the session baseline prevents a
/// nil cadence, missing source timezone, or old month-end reminder from looking
/// like an unsaved user edit merely because the form was opened.
struct HabitEditSession {
    var draft: Item
    var hasReminderTime: Bool
    var reminderTime: Date

    private var normalizedBaseline: Item

    init(source: Item) {
        var draft = source
        draft.frequency = (source.frequency ?? .daily).normalizedForHabit

        let hasReminderTime = source.reminder?.enabled == true
        let seedReminderTime = source.due ?? ReminderPreferences.defaultTime()
        let reminderTime: Date
        if hasReminderTime {
            if draft.dueTimeZone == nil {
                draft.dueTimeZone = HabitReminderSchedule.calendar(
                    timeZoneIdentifier: nil
                ).timeZone.identifier
            }
            reminderTime = HabitReminderSchedule.normalizedReminderTime(
                seedReminderTime,
                frequency: draft.frequency ?? .daily,
                timeZoneIdentifier: draft.dueTimeZone
            )
        } else {
            // A source that was already durably disabled starts a fresh reminder
            // in the current zone. An enabled reminder toggled off *during this
            // session* keeps its source zone in `draft` until that disable is
            // actually saved.
            draft.dueTimeZone = nil
            reminderTime = seedReminderTime
        }

        self.draft = draft
        self.hasReminderTime = hasReminderTime
        self.reminderTime = reminderTime
        self.normalizedBaseline = Self.persistenceProjection(
            draft: draft,
            hasReminderTime: hasReminderTime,
            reminderTime: reminderTime,
            live: source
        )
    }

    mutating func reset(from source: Item) {
        self = HabitEditSession(source: source)
    }

    func itemForPersistence(live: Item) -> Item {
        Self.persistenceProjection(
            draft: draft,
            hasReminderTime: hasReminderTime,
            reminderTime: reminderTime,
            live: live
        )
    }

    func isDirty(live: Item) -> Bool {
        var baseline = normalizedBaseline
        // Completion history is live while the setup form is open. It is
        // merged into both sides so logging progress never creates a phantom
        // setup edit or gets overwritten by a later save.
        baseline.completions = live.completions
        return itemForPersistence(live: live) != baseline
    }

    private static func persistenceProjection(
        draft: Item,
        hasReminderTime: Bool,
        reminderTime: Date,
        live: Item
    ) -> Item {
        var result = draft
        result.frequency = (result.frequency ?? .daily).normalizedForHabit
        if hasReminderTime {
            let timeZoneIdentifier = result.dueTimeZone ?? TimeZone.current.identifier
            result.due = HabitReminderSchedule.normalizedReminderTime(
                reminderTime,
                frequency: result.frequency ?? .daily,
                timeZoneIdentifier: timeZoneIdentifier
            )
            result.dueAllDay = false
            result.dueTimeZone = timeZoneIdentifier
            result.reminder = Reminder(
                enabled: true,
                early: result.reminder?.early
            )
        } else {
            result.due = nil
            result.dueTimeZone = nil
            result.reminder = nil
        }
        result.completions = live.completions
        return result
    }
}

/// A read-first habit surface. Opening a habit is a frequent progress check;
/// editing its setup is deliberately an explicit secondary action.
///
/// Completion history mutates live store state. The editor works on a draft and
/// merges the latest live completions back in before saving so an edit can never
/// overwrite progress logged while this screen is open.
struct HabitDetailView: View {
    let item: Item
    let store: ItemStore
    let onBeginMove: ((Item) -> Void)?

    private let fixedNow: Date?
    private let notificationStatusProvider: @Sendable () async -> HabitNotificationStatus
    private let requestNotificationAuthorization: @Sendable () async -> Bool
    private let rescheduleReminder: @Sendable (Item) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var editSession: HabitEditSession
    @State private var showingDeleteConfirm = false
    @State private var showingDiscardConfirm = false
    @State private var showSectionPicker = false
    @State private var entrySheet: EntrySheet?
    @State private var persistenceOperation: PersistenceOperation?
    @State private var persistenceFailure: PersistenceFailure?

    private enum PersistenceOperation: Equatable {
        case save
        case delete

        var failureTitle: String {
            switch self {
            case .save: "Couldn’t Save Habit"
            case .delete: "Couldn’t Delete Habit"
            }
        }
    }

    private struct PersistenceFailure: Equatable {
        let operation: PersistenceOperation
        let message: String
    }

    private enum EntrySheet: Identifiable {
        case add(Date)
        case edit(HabitCompletion)

        var id: String {
            switch self {
            case .add(let date): "add-\(date.timeIntervalSince1970)"
            case .edit(let completion): "edit-\(completion.id.uuidString)"
            }
        }
    }

    init(
        item: Item,
        store: ItemStore,
        onBeginMove: ((Item) -> Void)? = nil,
        now: Date? = nil,
        notificationStatusProvider: @escaping @Sendable () async -> HabitNotificationStatus = {
            await HabitNotificationStatus.current()
        },
        requestNotificationAuthorization: @escaping @Sendable () async -> Bool = {
            await NotificationScheduler.shared.requestAuthorizationIfNeeded()
        },
        rescheduleReminder: @escaping @Sendable (Item) async -> Void = { item in
            await NotificationScheduler.shared.schedule(item)
        }
    ) {
        self.item = item
        self.store = store
        self.onBeginMove = onBeginMove
        self.fixedNow = now
        self.notificationStatusProvider = notificationStatusProvider
        self.requestNotificationAuthorization = requestNotificationAuthorization
        self.rescheduleReminder = rescheduleReminder

        _editSession = State(initialValue: HabitEditSession(source: item))
    }

    private var live: Item { store.item(item.id) ?? item }

    var body: some View {
        NavigationStack {
            Group {
                if isEditing {
                    editContent
                } else {
                    overviewContent
                }
            }
            .disabled(isPersistenceOperationInFlight)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("Delete this habit?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { delete() }
                    .disabled(isPersistenceOperationInFlight)
                    .accessibilityIdentifier("habit.delete.confirm")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("habit.delete.cancel")
            } message: {
                Text("\"\(editSession.draft.title)\" will move to Recently Deleted.")
            }
            .confirmationDialog(
                "Discard changes?",
                isPresented: $showingDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) {
                    finishEditing(discardingChanges: true)
                }
                .accessibilityIdentifier("habit.discard.confirm")
                Button("Keep Editing", role: .cancel) {}
                    .accessibilityIdentifier("habit.discard.cancel")
            } message: {
                Text("Your changes to this habit haven’t been saved.")
            }
            .alert(
                persistenceFailure?.operation.failureTitle ?? "Couldn’t Update Habit",
                isPresented: isShowingPersistenceFailure
            ) {
                Button("Try Again") { retryFailedOperation() }
                    .accessibilityIdentifier("habit.persistence.error.retry")
                Button("Keep Open", role: .cancel) {}
                    .accessibilityIdentifier("habit.persistence.error.dismiss")
            } message: {
                if let persistenceFailure {
                    Text(persistenceFailure.message)
                }
            }
            .sheet(isPresented: $showSectionPicker) {
                SectionPickerSheet(
                    store: store,
                    listId: editSession.draft.listId,
                    section: Binding(
                        get: { editSession.draft.section },
                        set: { editSession.draft.section = $0 }
                    )
                )
                .tint(.primary)
            }
            .sheet(item: $entrySheet) { sheet in
                completionSheet(for: sheet)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(
            isPersistenceOperationInFlight
                || (isEditing && isDirty)
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .principal) {
                DetailSheetHeaderTitle(
                    item: live,
                    store: store,
                    standaloneLabel: "Edit Habit",
                    accessibilityId: "habit.parent",
                    onBeginMove: onBeginMove.map { begin in
                        { item in
                            dismiss()
                            begin(item)
                        }
                    }
                )
                .disabled(isDirty)
            }

            ToolbarItem(placement: .cancellationAction) {
                Button { cancelEditing() } label: {
                    Image(systemName: "xmark")
                        .accessibilityLabel("Cancel")
                }
                .disabled(isPersistenceOperationInFlight)
                .accessibilityIdentifier("habit.edit.cancel")
            }

            ToolbarItem(placement: .confirmationAction) {
                Button { save() } label: {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .accessibilityLabel("Save")
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(ListsTokens.accent)
                .disabled(
                    !isDirty
                        || isPersistenceOperationInFlight
                        || editSession.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityIdentifier("habit.save")
            }
        } else {
            ToolbarItem(placement: .principal) {
                Text("Habit")
                    .font(ListsTypography.headline)
                    .accessibilityAddTraits(.isHeader)
            }

            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .accessibilityLabel("Close")
                }
                .disabled(isPersistenceOperationInFlight)
                .accessibilityIdentifier("habit.close")
            }

            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { beginEditing() }
                    .disabled(isPersistenceOperationInFlight)
                    .accessibilityIdentifier("habit.edit")
            }
        }
    }

    @ViewBuilder
    private var overviewContent: some View {
        if let fixedNow {
            makeOverview(now: fixedNow)
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                makeOverview(now: context.date)
            }
        }
    }

    private func makeOverview(now: Date) -> some View {
        HabitOverviewContent(
            item: live,
            store: store,
            now: now,
            actionNow: { fixedNow ?? .now },
            notificationStatusProvider: notificationStatusProvider,
            requestNotificationAuthorization: requestNotificationAuthorization,
            rescheduleReminder: rescheduleReminder,
            onAddCompletion: { entrySheet = .add($0) },
            onEditCompletion: { entrySheet = .edit($0) }
        )
    }

    private var editContent: some View {
        HabitDetailsForm(
            draft: $editSession.draft,
            hasReminderTime: $editSession.hasReminderTime,
            reminderTime: $editSession.reminderTime,
            lists: store.lists,
            onReminderEnabled: {},
            onShowSectionPicker: { showSectionPicker = true },
            onDelete: { showingDeleteConfirm = true }
        )
    }

    @ViewBuilder
    private func completionSheet(for sheet: EntrySheet) -> some View {
        switch sheet {
        case .add(let date):
            CompletionEntrySheet(
                title: "Add Completion",
                initialDate: date,
                allowDelete: false,
                allowRange: true,
                onSave: { newDate in
                    try await store.addCompletion(item.id, at: newDate)
                },
                onSaveRange: { dates in
                    try await store.addCompletions(item.id, on: dates)
                },
                onDelete: nil
            )
        case .edit(let completion):
            CompletionEntrySheet(
                title: "Edit Completion",
                initialDate: completion.at,
                allowDelete: true,
                allowRange: false,
                onSave: { newDate in
                    try await store.updateCompletion(
                        item.id,
                        completionId: completion.id,
                        to: newDate
                    )
                },
                onSaveRange: nil,
                onDelete: {
                    try await store.deleteCompletion(
                        item.id,
                        completionId: completion.id
                    )
                }
            )
        }
    }

    private var workingDraft: Item { editSession.itemForPersistence(live: live) }

    private var isDirty: Bool { editSession.isDirty(live: live) }
    private var isPersistenceOperationInFlight: Bool { persistenceOperation != nil }

    private var isShowingPersistenceFailure: Binding<Bool> {
        Binding(
            get: { persistenceFailure != nil },
            set: { isPresented in
                if !isPresented { persistenceFailure = nil }
            }
        )
    }

    private func beginEditing() {
        resetDraft(from: live)
        isEditing = true
    }

    private func cancelEditing() {
        if isDirty {
            showingDiscardConfirm = true
        } else {
            finishEditing(discardingChanges: true)
        }
    }

    private func finishEditing(discardingChanges: Bool) {
        if discardingChanges { resetDraft(from: live) }
        showingDiscardConfirm = false
        isEditing = false
    }

    private func resetDraft(from source: Item) {
        editSession.reset(from: source)
    }

    private func save() {
        guard persistenceOperation == nil else { return }
        let toSave = workingDraft
        let shouldRequestNotificationAuthorization =
            live.reminder?.enabled != true && toSave.reminder?.enabled == true
        persistenceOperation = .save
        persistenceFailure = nil
        Task {
            do {
                try await store.updateWithSubtreeCascades(toSave)
                if shouldRequestNotificationAuthorization {
                    let granted = await requestNotificationAuthorization()
                    if granted {
                        await rescheduleReminder(store.item(item.id) ?? toSave)
                    }
                }
                persistenceOperation = nil
                resetDraft(from: store.item(item.id) ?? toSave)
                isEditing = false
            } catch {
                persistenceOperation = nil
                persistenceFailure = PersistenceFailure(
                    operation: .save,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func delete() {
        guard persistenceOperation == nil else { return }
        persistenceOperation = .delete
        persistenceFailure = nil
        Task {
            do {
                try await store.softDelete(editSession.draft.id)
                persistenceOperation = nil
                dismiss()
            } catch {
                persistenceOperation = nil
                persistenceFailure = PersistenceFailure(
                    operation: .delete,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func retryFailedOperation() {
        guard let operation = persistenceFailure?.operation else { return }
        persistenceFailure = nil
        switch operation {
        case .save: save()
        case .delete: delete()
        }
    }
}
