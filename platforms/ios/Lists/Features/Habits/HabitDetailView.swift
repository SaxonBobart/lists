import SwiftUI

/// Detail screen for a habit. Top-of-sheet segmented picker switches
/// between **Stats** (header + cycle progress + 12-month heatmap, default)
/// and **Details** (editable form mirroring the New Item habit fields,
/// plus the standard organisation controls).
struct HabitDetailView: View {
    let item: Item
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .stats
    @State private var draft: Item
    @State private var hasReminderTime: Bool
    @State private var reminderTime: Date
    @State private var showingDeleteConfirm = false
    @State private var showSectionPicker = false
    @State private var isShowingMarkdownEditor = false

    enum Mode: Hashable { case stats, details }

    init(item: Item, store: ItemStore) {
        self.item = item
        self.store = store
        _draft = State(initialValue: item)
        _hasReminderTime = State(initialValue: item.reminder?.enabled == true)
        _reminderTime = State(initialValue: item.due ?? Self.defaultReminderTime())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    Text("Stats").tag(Mode.stats)
                    Text("Details").tag(Mode.details)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

                Group {
                    switch mode {
                    case .stats:   statsContent
                    case .details: detailsContent
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Habit")
                        .font(ListsTypography.headline)
                        .foregroundStyle(ListsTokens.Foreground.primary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel("Cancel")
                    }
                    .tint(isDirty ? Color.red : Color.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                            .accessibilityLabel("Save")
                    }
                    .tint(isDirty ? Color.blue : Color.primary)
                    .disabled(!isDirty)
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
            .fullScreenCover(isPresented: $isShowingMarkdownEditor) {
                MarkdownEditorView(text: $draft.body, title: draft.title) {
                    isShowingMarkdownEditor = false
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Stats

    private var statsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ListsSpacing.s4) {
                headerCard
                progressCard
                heatmapCard
                Spacer().frame(height: ListsSpacing.s8)
            }
            .padding(.horizontal, ListsSpacing.s4)
            .padding(.top, ListsSpacing.s4)
        }
        .background(ListsTokens.Background.grouped)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s2) {
            Text(item.title)
                .font(ListsTypography.title2)
                .foregroundStyle(ListsTokens.Foreground.primary)
            HStack(spacing: ListsSpacing.s4) {
                stat(label: "Frequency", value: frequencyText)
                stat(label: "Goal", value: "\(item.goalPerCycle)")
                if item.showStreak {
                    stat(label: "Streak", value: "\(streak)")
                }
            }
        }
        .padding(ListsSpacing.s4)
        .background(card)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s3) {
            Text("This cycle")
                .font(ListsTypography.footnote.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(ListsTokens.Foreground.secondary)

            HStack(spacing: ListsSpacing.s4) {
                ZStack {
                    Circle()
                        .stroke(ListsTokens.Heatmap.empty, lineWidth: 8)
                        .frame(width: 78, height: 78)
                    Circle()
                        .trim(from: 0, to: cycleProgress)
                        .stroke(ListsTokens.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 78, height: 78)
                    VStack(spacing: 0) {
                        Text("\(currentCount)")
                            .font(ListsTypography.title2)
                            .foregroundStyle(ListsTokens.Foreground.primary)
                        Text("of \(item.goalPerCycle)")
                            .font(ListsTypography.caption1)
                            .foregroundStyle(ListsTokens.Foreground.tertiary)
                    }
                }

                Spacer()

                Button {
                    Task { try? await store.incrementHabit(item.id) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text("+1")
                            .font(ListsTypography.headline)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, ListsSpacing.s4)
                    .padding(.vertical, ListsSpacing.s3)
                    .background(
                        RoundedRectangle(cornerRadius: ListsRadius.lg, style: .continuous)
                            .fill(currentCount >= item.goalPerCycle
                                  ? ListsTokens.Foreground.tertiary
                                  : ListsTokens.accent)
                    )
                }
                .disabled(currentCount >= item.goalPerCycle)
                .buttonStyle(.plain)
            }
        }
        .padding(ListsSpacing.s4)
        .background(card)
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: ListsSpacing.s3) {
            Text("Last 12 months")
                .font(ListsTypography.footnote.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(ListsTokens.Foreground.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HabitHeatmap(item: item)
            }
        }
        .padding(ListsSpacing.s4)
        .background(card)
    }

    // MARK: - Details (editable)

    private var detailsContent: some View {
        Form {
            titleAndTagsSection
            habitSection
            detailsSection
            deleteSection
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
    }

    private var titleAndTagsSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .center)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Title", text: $draft.title, axis: .vertical)
                        .font(.title3)
                        .lineLimit(1...6)
                    TagInputView(tags: $draft.tags)
                    inlineNotesRow
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var inlineNotesRow: some View {
        HStack(alignment: .top, spacing: 6) {
            TextField("Notes", text: $draft.body, axis: .vertical)
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

    private var habitSection: some View {
        Section("Habit") {
            Picker(selection: Binding(
                get: { draft.frequency ?? .daily },
                set: { draft.frequency = $0 }
            )) {
                ForEach(HabitFrequency.allCases, id: \.self) { f in
                    Text(displayName(for: f)).tag(f)
                }
            } label: {
                Label("Frequency", systemImage: "repeat")
                    .labelStyle(GlyphLabelStyle())
            }

            Stepper(value: $draft.goalPerCycle, in: 1...99) {
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .center)
                    Text("Goal per cycle")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(draft.goalPerCycle)")
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: reminderBinding) {
                rowLabel(title: "Reminder", systemImage: "bell")
            }
            .tint(.green)

            if hasReminderTime {
                DatePicker(
                    selection: $reminderTime,
                    displayedComponents: .hourAndMinute
                ) {
                    Label("Time", systemImage: "clock")
                        .labelStyle(GlyphLabelStyle())
                }
            }

            Toggle(isOn: $draft.showStreak) {
                rowLabel(title: "Show streak", systemImage: "flame")
            }
            .tint(.green)
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            Toggle(isOn: $draft.flagged) {
                rowLabel(title: "Flag", systemImage: "flag")
            }
            .tint(.green)

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
                    if let s = draft.section, !s.isEmpty {
                        Text(s)
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

    // MARK: - Helpers

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(ListsTypography.title3)
                .foregroundStyle(ListsTokens.Foreground.primary)
            Text(label)
                .font(ListsTypography.caption1)
                .foregroundStyle(ListsTokens.Foreground.tertiary)
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: ListsRadius.card, style: .continuous)
            .fill(ListsTokens.Background.elevated)
    }

    private var currentCount: Int {
        let key = HabitCycle.key(for: item.frequency ?? .daily, on: .now)
        return item.completionLog[key] ?? 0
    }

    private var cycleProgress: Double {
        guard item.goalPerCycle > 0 else { return 0 }
        return min(1.0, Double(currentCount) / Double(item.goalPerCycle))
    }

    private var streak: Int { HabitStats.streak(for: item) }

    private var frequencyText: String { displayName(for: item.frequency ?? .daily) }

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
        return d
    }

    private var isDirty: Bool { workingDraft != item }

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
