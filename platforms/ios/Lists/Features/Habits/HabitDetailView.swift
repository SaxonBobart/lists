import SwiftUI

/// Detail screen for a habit. A top segmented picker switches between two tabs:
///   • **Overview** — two stat cards (streak + this-cycle count), a per-cycle
///     contribution grid, and a "Recent" list with a See All push to the full,
///     editable completion log.
///   • **Details** — the editable form (habit settings + standard organisation).
///
/// Overview (and the pushed log) mutate the store immediately and read **live**
/// state via `store.item`; only Details uses the `draft` + Save flow.
struct HabitDetailView: View {
    let item: Item
    let store: ItemStore
    let onBeginMove: ((Item) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .overview
    @State private var draft: Item
    @State private var hasReminderTime: Bool
    @State private var reminderTime: Date
    @State private var showingDeleteConfirm = false
    @State private var showSectionPicker = false
    @State private var entrySheet: EntrySheet?

    enum Mode: Hashable { case overview, details }

    /// Add a fresh entry, or edit an existing one. Identifiable for `.sheet(item:)`.
    private enum EntrySheet: Identifiable {
        case add(Date)
        case edit(HabitCompletion)
        var id: String {
            switch self {
            case .add(let date): return "add-\(date.timeIntervalSince1970)"
            case .edit(let c):   return "edit-\(c.id.uuidString)"
            }
        }
    }

    init(item: Item, store: ItemStore, onBeginMove: ((Item) -> Void)? = nil) {
        self.item = item
        self.store = store
        self.onBeginMove = onBeginMove
        // Fold any legacy cadence onto daily/weekly/monthly so the picker shows a
        // valid selection; saving the form then heals the stored value.
        var normalized = item
        normalized.frequency = (item.frequency ?? .daily).normalizedForHabit
        _draft = State(initialValue: normalized)
        _hasReminderTime = State(initialValue: item.reminder?.enabled == true)
        _reminderTime = State(initialValue: item.due ?? Self.defaultReminderTime())
    }

    /// Live snapshot from the observed store, so Overview/Log reflect completions
    /// logged this session immediately.
    private var live: Item { store.item(item.id) ?? item }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .overview: overviewContent
                case .details:  editContent
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Mode", selection: $mode) {
                    Text("Overview").tag(Mode.overview)
                    Text("Details").tag(Mode.details)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .glassEffect()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .accessibilityIdentifier("habit.mode")
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    DetailSheetHeaderTitle(
                        item: item,
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
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel(isDirty ? "Cancel" : "Done")
                    }
                    .tint(Color.primary)
                    .accessibilityIdentifier("habit.cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .accessibilityLabel("Save")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(ListsTokens.accent)
                    .disabled(!isDirty)
                    .accessibilityIdentifier("habit.save")
                }
            }
            .alert("Delete this habit?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\"\(draft.title)\" will move to Recently Deleted.")
            }
            .sheet(isPresented: $showSectionPicker) {
                SectionPickerSheet(
                    store: store,
                    listId: draft.listId,
                    section: Binding(
                        get: { draft.section },
                        set: { draft.section = $0 }
                    )
                )
                .tint(.primary)
            }
            .sheet(item: $entrySheet) { sheet in
                switch sheet {
                case .add(let date):
                    CompletionEntrySheet(
                        title: "Add Completion", initialDate: date,
                        allowDelete: false, allowRange: true,
                        onSave: { newDate in Task { try? await store.addCompletion(item.id, at: newDate) } },
                        onSaveRange: { dates in Task { try? await store.addCompletions(item.id, on: dates) } },
                        onDelete: nil)
                case .edit(let completion):
                    CompletionEntrySheet(
                        title: "Edit Completion", initialDate: completion.at,
                        allowDelete: true, allowRange: false,
                        onSave: { newDate in Task { try? await store.updateCompletion(item.id, completionId: completion.id, to: newDate) } },
                        onSaveRange: nil,
                        onDelete: { Task { try? await store.deleteCompletion(item.id, completionId: completion.id) } })
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Overview

    private var overviewContent: some View {
        HabitOverviewContent(
            item: live,
            store: store,
            onAddCompletion: { entrySheet = .add($0) },
            onEditCompletion: { entrySheet = .edit($0) }
        )
    }

    // MARK: - Edit (form)

    private var editContent: some View {
        HabitDetailsForm(
            draft: $draft,
            hasReminderTime: $hasReminderTime,
            reminderTime: $reminderTime,
            lists: store.lists,
            onShowSectionPicker: { showSectionPicker = true },
            onDelete: { showingDeleteConfirm = true }
        )
    }

    // MARK: - Save/delete

    private static func defaultReminderTime() -> Date {
        ReminderPreferences.defaultTime()
    }

    /// The form edits everything except `completions` (which the Log owns). Carry
    /// the live completions through so saving a form edit never clobbers entries
    /// logged this session.
    private var workingDraft: Item {
        var d = draft
        if hasReminderTime {
            d.due = reminderTime
            d.dueAllDay = false
            d.reminder = Reminder(enabled: true, early: d.reminder?.early)
        } else {
            d.due = nil
            d.reminder = nil
        }
        d.completions = live.completions
        return d
    }

    private var isDirty: Bool { workingDraft != live }

    private func save() {
        var toSave = workingDraft
        let (cleanedTitle, parsedTags) = Tag.extractInline(from: toSave.title)
        if !cleanedTitle.isEmpty { toSave.title = cleanedTitle }
        if !parsedTags.isEmpty {
            var merged = toSave.tags
            for tag in parsedTags where !merged.contains(where: { $0.lowercased() == tag.lowercased() }) {
                merged.append(tag)
            }
            toSave.tags = merged
        }
        Task {
            try? await store.updateWithSubtreeCascades(toSave)
            dismiss()
        }
    }

    private func delete() {
        Task {
            try? await store.softDelete(draft.id)
            dismiss()
        }
    }
}
