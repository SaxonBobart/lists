import SwiftUI

struct HabitCompletionLogView: View {
    let habitId: UUID
    let store: ItemStore
    let onAddCompletion: () -> Void
    let onEditCompletion: (HabitCompletion) -> Void

    var body: some View {
        List {
            Section {
                Button {
                    onAddCompletion()
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
                        let timeLabel = Self.timeFormatter.string(from: entry.at)
                        Button {
                            onEditCompletion(entry)
                        } label: {
                            HStack(spacing: ListsSpacing.s3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(ListsTokens.accent)
                                Text(timeLabel)
                                    .foregroundStyle(ListsTokens.Foreground.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(ListsTokens.Foreground.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit completion at \(timeLabel)")
                        .accessibilityIdentifier("habit.log.entry")
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { try? await store.deleteCompletion(habitId, completionId: entry.id) }
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
        .navigationTitle("All completions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct DayGroup: Identifiable {
        let id: String
        let title: String
        let date: Date
        let entries: [HabitCompletion]
    }

    private var logGroups: [DayGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: completions) { cal.startOfDay(for: $0.at) }
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

    private var completions: [HabitCompletion] {
        store.item(habitId)?.completions ?? []
    }

    private func dayTitle(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return Self.dayHeaderFormatter.string(from: day)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()
}
