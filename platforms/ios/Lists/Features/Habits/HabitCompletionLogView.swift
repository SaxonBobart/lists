import SwiftUI

struct HabitCompletionLogView: View {
    let habitId: UUID
    let store: ItemStore
    let onAddCompletion: () -> Void
    let onEditCompletion: (HabitCompletion) -> Void

    @State private var deletingCompletionId: UUID?
    @State private var deleteFailure: DeleteFailure?

    private struct DeleteFailure {
        let completionId: UUID
        let message: String
    }

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
                        .accessibilityIdentifier("habit.log.empty")
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
                        .disabled(deletingCompletionId == entry.id)
                        .accessibilityIdentifier(
                            "habit.log.entry.\(entry.id.uuidString.lowercased())"
                        )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteCompletion(entry.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .disabled(deletingCompletionId != nil)
                            .accessibilityIdentifier(
                                "habit.log.entry.\(entry.id.uuidString.lowercased()).delete"
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ListsTokens.Background.grouped)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn’t Delete Completion", isPresented: isShowingDeleteFailure) {
            Button("Try Again") {
                guard let completionId = deleteFailure?.completionId else { return }
                deleteFailure = nil
                deleteCompletion(completionId)
            }
            .accessibilityIdentifier("habit.log.delete.error.retry")
            Button("Not Now", role: .cancel) {}
                .accessibilityIdentifier("habit.log.delete.error.dismiss")
        } message: {
            if let deleteFailure { Text(deleteFailure.message) }
        }
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

    private var isShowingDeleteFailure: Binding<Bool> {
        Binding(
            get: { deleteFailure != nil },
            set: { isPresented in
                if !isPresented { deleteFailure = nil }
            }
        )
    }

    private func deleteCompletion(_ completionId: UUID) {
        guard deletingCompletionId == nil else { return }
        deletingCompletionId = completionId
        Task {
            do {
                try await store.deleteCompletion(habitId, completionId: completionId)
                deletingCompletionId = nil
            } catch {
                deletingCompletionId = nil
                deleteFailure = DeleteFailure(
                    completionId: completionId,
                    message: error.localizedDescription
                )
            }
        }
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
