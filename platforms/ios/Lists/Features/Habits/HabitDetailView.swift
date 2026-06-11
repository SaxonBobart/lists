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

    init(item: Item, store: ItemStore) {
        self.item = item
        self.store = store
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
                    DetailSheetHeaderTitle(item: item, store: store, standaloneLabel: "Edit Habit")
                        .accessibilityIdentifier("habit.parent")
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
                            .accessibilityLabel("Save")
                    }
                    .tint(Color.primary)
                    .disabled(!isDirty)
                    .accessibilityIdentifier("habit.save")
                }
            }
            .navigationDestination(for: ThreadDestination.self) { dest in
                if let root = store.items.first(where: { $0.id == dest.rootId }) {
                    ThreadView(root: root, store: store)
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
        ScrollView {
            VStack(alignment: .leading, spacing: ListsSpacing.s4) {
                Text(live.title)
                    .font(ListsTypography.largeTitle.bold())
                    .foregroundStyle(ListsTokens.Foreground.primary)

                HStack(alignment: .top, spacing: ListsSpacing.s4) {
                    streakCard
                    thisCycleCard
                }

                gridCard
                recentCard
                Spacer().frame(height: ListsSpacing.s8)
            }
            .padding(.horizontal, ListsSpacing.s4)
            .padding(.top, ListsSpacing.s4)
        }
        .background(ListsTokens.Background.grouped)
    }

    /// Left card: the streak in the habit's cadence (day/week/month), or — when
    /// the streak is hidden — lifetime total completions.
    @ViewBuilder
    private var streakCard: some View {
        if live.showStreak {
            statCard(icon: "flame.fill", iconTint: .orange,
                     value: "\(streak)", caption: streakCaption,
                     a11yLabel: "Streak", a11yValue: "\(streak) \(streakCaption)")
        } else {
            statCard(icon: "checkmark.circle.fill", iconTint: ListsTokens.accent,
                     value: "\(HabitStats.totalCompletions(for: live))", caption: "completions",
                     a11yLabel: "Total completions",
                     a11yValue: "\(HabitStats.totalCompletions(for: live))")
        }
    }

    /// Right card: this cycle's count toward goal, with quick +1 / −1 logging.
    private var thisCycleCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s2) {
            Image(systemName: "target")
                .font(.headline)
                .foregroundStyle(ListsTokens.accent)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(currentCount)")
                    .font(ListsTypography.largeTitle)
                    .foregroundStyle(ListsTokens.Foreground.primary)
                Text("of \(live.goalPerCycle)")
                    .font(ListsTypography.footnote)
                    .foregroundStyle(ListsTokens.Foreground.tertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cycleCaption)
            .accessibilityValue("\(currentCount) of \(live.goalPerCycle)")

            Text(cycleCaption)
                .font(ListsTypography.footnote)
                .foregroundStyle(ListsTokens.Foreground.secondary)

            HStack(spacing: ListsSpacing.s2) {
                stepperButton(system: "minus", enabled: currentCount > 0,
                              a11y: "Remove one", id: "habit.decrement") {
                    Task { try? await store.removeLatestCompletion(in: .now, for: item.id) }
                }
                stepperButton(system: "plus", enabled: currentCount < live.goalPerCycle,
                              a11y: "Add one", id: "habit.increment") {
                    Task { try? await store.incrementHabit(item.id) }
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ListsSpacing.s4)
        .background(card)
    }

    private func statCard(icon: String, iconTint: Color, value: String, caption: String,
                          a11yLabel: String, a11yValue: String) -> some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s2) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(iconTint)
            Text(value)
                .font(ListsTypography.largeTitle)
                .foregroundStyle(ListsTokens.Foreground.primary)
            Text(caption)
                .font(ListsTypography.footnote)
                .foregroundStyle(ListsTokens.Foreground.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(ListsSpacing.s4)
        .background(card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityValue(a11yValue)
    }

    private func stepperButton(system: String, enabled: Bool, a11y: String, id: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? ListsTokens.accent : ListsTokens.Foreground.tertiary)
                .frame(width: 40, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: ListsRadius.md, style: .continuous)
                        .stroke(enabled ? ListsTokens.accent : ListsTokens.Foreground.tertiary, lineWidth: 1.5)
                )
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
        .accessibilityLabel(a11y)
        .accessibilityIdentifier(id)
    }

    private var gridCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s3) {
            Text(gridTitle)
                .font(ListsTypography.footnote.weight(.semibold))
                .foregroundStyle(ListsTokens.Foreground.secondary)

            HabitHeatmap(item: live, onSelectCycle: { date in
                entrySheet = .add(noon(of: date))
            })

            Text("Tap a square to log it")
                .font(ListsTypography.caption2)
                .foregroundStyle(ListsTokens.Foreground.tertiary)
        }
        .padding(ListsSpacing.s4)
        .background(card)
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s3) {
            HStack {
                Text("Recent")
                    .font(ListsTypography.footnote.weight(.semibold))
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                Spacer()
                if !live.completions.isEmpty {
                    NavigationLink { logScreen } label: {
                        Text("See All").font(ListsTypography.footnote)
                    }
                    .accessibilityIdentifier("habit.seeAll")
                }
            }

            if recentEntries.isEmpty {
                Text("No completions logged yet.")
                    .font(ListsTypography.footnote)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
                    .padding(.vertical, 2)
            } else {
                ForEach(recentEntries) { entry in
                    Button { entrySheet = .edit(entry) } label: { recentRow(entry) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("habit.recent.entry")
                    if entry.id != recentEntries.last?.id {
                        Divider()
                    }
                }
            }

            Button { entrySheet = .add(.now) } label: {
                Label("Add Completion", systemImage: "plus")
            }
            .accessibilityIdentifier("habit.addCompletion")
            .padding(.top, 2)
        }
        .padding(ListsSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private func recentRow(_ entry: HabitCompletion) -> some View {
        HStack(spacing: ListsSpacing.s3) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ListsTokens.accent)
            Text(Self.entryDateFormatter.string(from: entry.at))
                .foregroundStyle(ListsTokens.Foreground.primary)
            Spacer()
            Text(Self.timeFormatter.string(from: entry.at))
                .font(ListsTypography.footnote)
                .foregroundStyle(ListsTokens.Foreground.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    /// The full, editable completion history, pushed from "See All".
    private var logScreen: some View {
        logContent
            .navigationTitle("All completions")
            .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Log

    private var logContent: some View {
        List {
            Section {
                Button {
                    entrySheet = .add(.now)
                } label: {
                    Label("Add entry", systemImage: "plus")
                }
                .accessibilityIdentifier("habit.log.add")
            }

            if logGroups.isEmpty {
                Section {
                    Text("No completions logged yet.")
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                }
            }

            ForEach(logGroups) { group in
                Section(group.title) {
                    ForEach(group.entries) { entry in
                        Button {
                            entrySheet = .edit(entry)
                        } label: {
                            HStack(spacing: ListsSpacing.s3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(ListsTokens.accent)
                                Text(Self.timeFormatter.string(from: entry.at))
                                    .foregroundStyle(ListsTokens.Foreground.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(ListsTokens.Foreground.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("habit.log.entry")
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { try? await store.deleteCompletion(item.id, completionId: entry.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ListsTokens.Background.grouped)
    }

    private struct DayGroup: Identifiable {
        let id: String
        let title: String
        let date: Date
        let entries: [HabitCompletion]
    }

    private var logGroups: [DayGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: live.completions) { cal.startOfDay(for: $0.at) }
        return grouped.map { day, entries in
            DayGroup(
                id: ISO8601.dayString(from: day),
                title: dayTitle(day, calendar: cal),
                date: day,
                entries: entries.sorted { $0.at > $1.at }
            )
        }
        .sorted { $0.date > $1.date }
    }

    private func dayTitle(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return Self.dayHeaderFormatter.string(from: day)
    }

    // MARK: - Edit (form)

    private var editContent: some View {
        Form {
            titleAndTagsSection
            habitSection
            detailsSection
            deleteSection
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        // See ItemDetailSheet — explicit grouped backdrop so the section
        // cards contrast against the sheet in light mode.
        .background(Color(.systemGroupedBackground))
    }

    private var titleAndTagsSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.arrow.trianglehead.clockwise")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .center)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Title", text: $draft.title, axis: .vertical)
                        .font(.title3)
                        .lineLimit(1...6)
                        .accessibilityIdentifier("habit.title")
                    TagInputView(tags: $draft.tags)
                        .accessibilityIdentifier("habit.tags")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var habitSection: some View {
        Section("Habit") {
            Picker(selection: Binding(
                get: { draft.frequency ?? .daily },
                set: { draft.frequency = $0 }
            )) {
                ForEach(HabitFrequency.habitCadences, id: \.self) { f in
                    Text(displayName(for: f)).tag(f)
                }
            } label: {
                Label("Frequency", systemImage: "repeat")
                    .labelStyle(GlyphLabelStyle())
            }
            .accessibilityIdentifier("habit.frequency")

            Toggle(isOn: $draft.flexibleGoal) {
                rowLabel(title: "Flexible goal", systemImage: "calendar.badge.clock")
            }
            .tint(.green)
            .accessibilityIdentifier("habit.flexibleGoal")

            Stepper(value: $draft.goalPerCycle, in: 1...99) {
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .center)
                    Text(goalStepperLabel)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(draft.goalPerCycle)")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("habit.goal")

            Toggle(isOn: reminderBinding) {
                rowLabel(title: "Reminder", systemImage: "bell")
            }
            .tint(.green)
            .accessibilityIdentifier("habit.reminder")

            if hasReminderTime {
                DatePicker(
                    selection: $reminderTime,
                    displayedComponents: .hourAndMinute
                ) {
                    Label("Time", systemImage: "clock")
                        .labelStyle(GlyphLabelStyle())
                }
                .accessibilityIdentifier("habit.reminder.time")
            }

            Toggle(isOn: $draft.showStreak) {
                rowLabel(title: "Show streak", systemImage: "flame")
            }
            .tint(.green)
            .accessibilityIdentifier("habit.showStreak")
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            Toggle(isOn: $draft.flagged) {
                rowLabel(title: "Flag", systemImage: "flag")
            }
            .tint(.green)
            .accessibilityIdentifier("habit.flag")

            Picker(selection: $draft.priority) {
                ForEach(Item.Priority.allCases, id: \.self) { p in
                    Text(displayName(for: p)).tag(p)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: priorityGlyph(for: draft.priority))
                        .imageScale(.small)
                        .foregroundStyle(priorityIconColor(for: draft.priority))
                        .frame(width: 24, alignment: .center)
                    Text("Priority")
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .accessibilityIdentifier("habit.priority")

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
            .accessibilityIdentifier("habit.section")

            Menu {
                ForEach(activeLists, id: \.id) { list in
                    Button {
                        draft.listId = list.id
                    } label: {
                        if list.id == draft.listId {
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
            .accessibilityIdentifier("habit.list")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete Habit", systemImage: "trash")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .tint(.red)
            .accessibilityIdentifier("habit.delete")
        }
    }

    private func rowLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            Text(title)
        }
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { hasReminderTime },
            set: { newValue in
                withAnimation(.smooth) { hasReminderTime = newValue }
            }
        )
    }

    private var selectedList: ItemList? {
        store.lists.first { $0.id == draft.listId }
    }

    private var resolvedSectionName: String? {
        guard let s = draft.section, !s.isEmpty else { return nil }
        return selectedList?.sections.first { $0.id.uuidString == s }?.name
    }

    // MARK: - Flexible-goal helpers

    /// With a flexible goal the per-cycle number reads as "do it N times across
    /// the cycle" ("Times today" / "this week" / "this month"); otherwise it's a
    /// fixed per-cycle target.
    private var goalStepperLabel: String {
        guard draft.flexibleGoal else { return "Goal per cycle" }
        return "Times \(HabitStats.cycleNoun(for: draft.frequency ?? .daily))"
    }

    // MARK: - Stats helpers

    private var card: some View {
        RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
            .fill(ListsTokens.Background.elevated)
    }

    /// The habit's effective cadence — always daily / weekly / monthly even if a
    /// legacy value is still on disk.
    private var cadence: HabitFrequency { (live.frequency ?? .daily).normalizedForHabit }

    private var currentCount: Int {
        let key = HabitCycle.key(for: cadence, on: .now)
        return live.completions.filter { HabitCycle.key(for: cadence, on: $0.at) == key }.count
    }

    private var streak: Int { HabitStats.streak(for: live) }

    private var streakCaption: String {
        switch cadence {
        case .weekly:  return "week streak"
        case .monthly: return "month streak"
        default:       return "day streak"
        }
    }

    /// "Today" / "This week" / "This month" for the cycle card.
    private var cycleCaption: String {
        let noun = HabitStats.cycleNoun(for: cadence)
        return noun.prefix(1).uppercased() + noun.dropFirst()
    }

    private var gridTitle: String {
        switch cadence {
        case .weekly:  return "Last 52 Weeks"
        case .monthly: return "Last 12 Months"
        default:       return "Last 30 Days"
        }
    }

    private var recentEntries: [HabitCompletion] {
        Array(live.completions.sorted { $0.at > $1.at }.prefix(5))
    }

    /// Noon on the given day — lands a logged completion squarely inside the
    /// tapped cycle regardless of timezone.
    private func noon(of date: Date) -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    private var activeLists: [ItemList] {
        store.lists.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
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

    private static func defaultReminderTime() -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let entryDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private static let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

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
            try? await store.update(toSave)
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

// MARK: - Completion entry editor

/// Add or edit a single completion's date & time. "Edit the time" and "move to
/// another day" are the same operation since the timestamp is absolute.
private struct CompletionEntrySheet: View {
    let title: String
    let allowDelete: Bool
    /// Adding (not editing) offers a "Date Range" tab that backfills one
    /// completion per day across a start–end range.
    let allowRange: Bool
    let onSave: (Date) -> Void
    let onSaveRange: (([Date]) -> Void)?
    let onDelete: (() -> Void)?

    private enum EntryMode: Hashable { case single, range }

    @State private var mode: EntryMode = .single
    @State private var date: Date          // single date+time, and the range start
    @State private var endDate: Date       // range end
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialDate: Date, allowDelete: Bool, allowRange: Bool,
         onSave: @escaping (Date) -> Void, onSaveRange: (([Date]) -> Void)?,
         onDelete: (() -> Void)?) {
        self.title = title
        self.allowDelete = allowDelete
        self.allowRange = allowRange
        self.onSave = onSave
        self.onSaveRange = onSaveRange
        self.onDelete = onDelete
        _date = State(initialValue: initialDate)
        _endDate = State(initialValue: initialDate)
    }

    /// One completion per calendar day in [start, end] inclusive, landed at noon.
    private var rangeDates: [Date] {
        let cal = Calendar.current
        let lo = cal.startOfDay(for: min(date, endDate))
        let hi = cal.startOfDay(for: max(date, endDate))
        var out: [Date] = []
        var day = lo
        while day <= hi && out.count < 1000 {
            out.append(cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    private var isRange: Bool { allowRange && mode == .range }

    var body: some View {
        NavigationStack {
            Form {
                if allowRange {
                    Picker("Mode", selection: $mode) {
                        Text("Single Date").tag(EntryMode.single)
                        Text("Date Range").tag(EntryMode.range)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("habit.entry.mode")
                }

                if isRange {
                    Section {
                        DatePicker("Starts", selection: $date, displayedComponents: .date)
                            .accessibilityIdentifier("habit.entry.rangeStart")
                        DatePicker("Ends", selection: $endDate, in: date..., displayedComponents: .date)
                            .accessibilityIdentifier("habit.entry.rangeEnd")
                    } footer: {
                        let n = rangeDates.count
                        Text("\(n) completion\(n == 1 ? "" : "s") will be added")
                    }
                } else {
                    DatePicker("Date & time", selection: $date)
                        .datePickerStyle(.graphical)
                        .accessibilityIdentifier("habit.entry.datetime")
                }

                if allowDelete, let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Delete entry", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .accessibilityIdentifier("habit.entry.delete")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").accessibilityLabel("Cancel")
                    }
                    .tint(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if isRange { onSaveRange?(rangeDates) } else { onSave(date) }
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark").accessibilityLabel("Save")
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("habit.entry.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
