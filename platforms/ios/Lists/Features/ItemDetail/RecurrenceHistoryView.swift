import SwiftUI

/// Item-scoped occurrence history for recurring tasks and completable events.
/// Historical corrections mutate only the ledger entry; the live due date and
/// notification schedule remain authoritative.
struct RecurrenceHistoryView: View {
    let itemId: UUID
    let store: ItemStore

    @State private var selectedOccurrence: RecurrenceOccurrence?

    var body: some View {
        List {
            if let item = liveItem {
                currentSection(item)
                historySection(item)
            } else {
                ContentUnavailableView(
                    "Item Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This recurring item can no longer be opened.")
                )
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ListsTokens.Background.grouped)
        .navigationTitle("Completion History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedOccurrence) { occurrence in
            RecurrenceOccurrenceEditorSheet(
                itemId: itemId,
                occurrence: occurrence,
                store: store
            )
        }
    }

    @ViewBuilder
    private func currentSection(_ item: Item) -> some View {
        if let current = item.recurrenceOccurrences.first(where: { $0.status == .open }) {
            Section("Current") {
                RecurrenceOccurrenceRow(occurrence: current, isEditable: false)
                    .accessibilityIdentifier(
                        "recurrence.history.current.\(current.id.uuidString.lowercased())"
                    )
            }
        } else if item.done == false, let due = item.due {
            Section("Current") {
                RecurrenceCurrentRow(scheduledAt: due)
                    .accessibilityIdentifier("recurrence.history.current.pending")
            }
        }
    }

    private func historySection(_ item: Item) -> some View {
        Section("Past Occurrences") {
            if closedOccurrences(in: item).isEmpty {
                ContentUnavailableView(
                    "No Past Occurrences",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Completed and missed occurrences will appear here.")
                )
                .accessibilityIdentifier("recurrence.history.empty")
            } else {
                ForEach(closedOccurrences(in: item)) { occurrence in
                    Button {
                        selectedOccurrence = occurrence
                    } label: {
                        RecurrenceOccurrenceRow(occurrence: occurrence, isEditable: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this occurrence for correction")
                    .accessibilityIdentifier(
                        "recurrence.history.entry.\(occurrence.id.uuidString.lowercased())"
                    )
                }
            }
        }
    }

    private var liveItem: Item? {
        store.item(itemId)
    }

    private func closedOccurrences(in item: Item) -> [RecurrenceOccurrence] {
        item.recurrenceOccurrences
            .filter { $0.status != .open }
            .sorted {
                if $0.scheduledAt != $1.scheduledAt {
                    return $0.scheduledAt > $1.scheduledAt
                }
                return $0.id.uuidString > $1.id.uuidString
            }
    }
}

private struct RecurrenceOccurrenceRow: View {
    let occurrence: RecurrenceOccurrence
    let isEditable: Bool

    var body: some View {
        HStack(spacing: ListsSpacing.s3) {
            Image(systemName: statusSystemImage)
                .font(.system(size: 21))
                .foregroundStyle(statusColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ListsSpacing.s1) {
                Text(occurrence.scheduledAt, format: .dateTime.weekday(.abbreviated).month().day().year())
                    .font(ListsTypography.body)
                    .foregroundStyle(ListsTokens.Foreground.primary)

                statusDetail
                    .font(ListsTypography.footnote)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isEditable {
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(ListsTokens.Foreground.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch occurrence.status {
        case .open:
            Text("Current · Scheduled \(occurrence.scheduledAt, format: .dateTime.hour().minute())")
        case .completed:
            if let completedAt = occurrence.completedAt {
                Text("Completed \(completedAt, format: .dateTime.month().day().hour().minute())")
            } else {
                Text("Completed")
            }
        case .missed:
            Text("Missed · Scheduled \(occurrence.scheduledAt, format: .dateTime.hour().minute())")
        }
    }

    private var statusSystemImage: String {
        switch occurrence.status {
        case .open: "circle"
        case .completed: "checkmark.circle.fill"
        case .missed: "minus.circle.fill"
        }
    }

    private var statusColor: Color {
        switch occurrence.status {
        case .open: ListsTokens.Foreground.tertiary
        case .completed: ListsTokens.accent
        case .missed: ListsTokens.Foreground.secondary
        }
    }
}

private struct RecurrenceCurrentRow: View {
    let scheduledAt: Date

    var body: some View {
        HStack(spacing: ListsSpacing.s3) {
            Image(systemName: "circle")
                .font(.system(size: 21))
                .foregroundStyle(ListsTokens.Foreground.tertiary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ListsSpacing.s1) {
                Text(scheduledAt, format: .dateTime.weekday(.abbreviated).month().day().year())
                    .font(ListsTypography.body)
                Text("Current · Scheduled \(scheduledAt, format: .dateTime.hour().minute())")
                    .font(ListsTypography.footnote)
                    .foregroundStyle(ListsTokens.Foreground.secondary)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

private struct RecurrenceOccurrenceEditorSheet: View {
    let itemId: UUID
    let occurrence: RecurrenceOccurrence
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss
    @State private var status: RecurrenceOccurrence.Status
    @State private var completedAt: Date
    @State private var isSaving = false
    @State private var saveFailureMessage: String?

    init(itemId: UUID, occurrence: RecurrenceOccurrence, store: ItemStore) {
        self.itemId = itemId
        self.occurrence = occurrence
        self.store = store
        _status = State(initialValue: occurrence.status)
        _completedAt = State(initialValue: occurrence.completedAt ?? occurrence.scheduledAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scheduled") {
                    LabeledContent("Date") {
                        Text(occurrence.scheduledAt, format: .dateTime.month().day().year())
                    }
                    LabeledContent("Time") {
                        Text(occurrence.scheduledAt, format: .dateTime.hour().minute())
                    }
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        Text("Completed").tag(RecurrenceOccurrence.Status.completed)
                        Text("Missed").tag(RecurrenceOccurrence.Status.missed)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("recurrence.entry.status")

                    if status == .completed {
                        DatePicker("Completed", selection: $completedAt)
                            .datePickerStyle(.graphical)
                            .accessibilityIdentifier("recurrence.entry.completed")
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle("Correct Occurrence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel("Cancel")
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("recurrence.entry.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Saving")
                        } else {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .accessibilityLabel("Save")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(ListsTokens.accent)
                    .disabled(isSaving || !isDirty)
                    .accessibilityIdentifier("recurrence.entry.save")
                }
            }
            .alert("Couldn’t Update Occurrence", isPresented: isShowingSaveFailure) {
                Button("Try Again") { save() }
                    .accessibilityIdentifier("recurrence.entry.error.retry")
                Button("Not Now", role: .cancel) {}
                    .accessibilityIdentifier("recurrence.entry.error.dismiss")
            } message: {
                Text(saveFailureMessage ?? "The occurrence could not be updated.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
    }

    private var isDirty: Bool {
        status != occurrence.status
            || (status == .completed && completedAt != occurrence.completedAt)
    }

    private var isShowingSaveFailure: Binding<Bool> {
        Binding(
            get: { saveFailureMessage != nil },
            set: { isPresented in
                if !isPresented { saveFailureMessage = nil }
            }
        )
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        saveFailureMessage = nil
        Task {
            do {
                try await store.correctRecurrenceOccurrence(
                    itemId,
                    occurrenceId: occurrence.id,
                    status: status,
                    completedAt: status == .completed ? completedAt : nil
                )
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                saveFailureMessage = error.localizedDescription
            }
        }
    }
}
