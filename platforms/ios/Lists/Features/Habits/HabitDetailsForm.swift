import SwiftUI

struct HabitDetailsForm: View {
    @Binding var draft: Item
    @Binding var hasReminderTime: Bool
    @Binding var reminderTime: Date
    let lists: [ItemList]
    let onShowSectionPicker: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Form {
            titleAndTagsSection
            habitSection
            detailsSection
            deleteSection
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        // Explicit grouped backdrop so the section cards contrast against the
        // sheet in light mode.
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
                    Text(f.habitDisplayName).tag(f)
                }
            } label: {
                Label("Frequency", systemImage: "repeat")
                    .labelStyle(GlyphLabelStyle())
            }
            .accessibilityIdentifier("habit.frequency")

            Toggle(isOn: $draft.flexibleGoal) {
                DetailFormRowLabel(title: "Flexible goal", systemImage: "calendar.badge.clock")
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
                DetailFormRowLabel(title: "Reminder", systemImage: "bell")
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
                DetailFormRowLabel(title: "Show streak", systemImage: "flame")
            }
            .tint(.green)
            .accessibilityIdentifier("habit.showStreak")
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            Toggle(isOn: $draft.flagged) {
                DetailFormRowLabel(title: "Flag", systemImage: "flag")
            }
            .tint(.green)
            .accessibilityIdentifier("habit.flag")

            ItemPriorityPickerRow(priority: $draft.priority)
                .accessibilityIdentifier("habit.priority")

            Button {
                onShowSectionPicker()
            } label: {
                DetailFormDisclosureRowLabel(
                    title: "Section",
                    value: resolvedSectionName,
                    systemImage: "square.dashed"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("habit.section")

            DetailFormListMenuRow(
                lists: activeLists,
                selectedListId: draft.listId,
                selectedList: selectedList
            ) { list in
                if draft.listId != list.id {
                    draft.listId = list.id
                    draft.section = nil
                }
            }
            .accessibilityIdentifier("habit.list")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Habit", systemImage: "trash")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .tint(.red)
            .accessibilityIdentifier("habit.delete")
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

    private var activeLists: [ItemList] {
        lists.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }

    private var selectedList: ItemList? {
        lists.first { $0.id == draft.listId }
    }

    private var resolvedSectionName: String? {
        guard let s = draft.section, !s.isEmpty else { return nil }
        return selectedList?.sections.first { $0.id.uuidString == s }?.name
    }

    /// With a flexible goal the per-cycle number reads as "do it N times across
    /// the cycle" ("Times today" / "this week" / "this month"); otherwise it's a
    /// fixed per-cycle target.
    private var goalStepperLabel: String {
        guard draft.flexibleGoal else { return "Goal per cycle" }
        return "Times \(HabitStats.cycleNoun(for: draft.frequency ?? .daily))"
    }

}
