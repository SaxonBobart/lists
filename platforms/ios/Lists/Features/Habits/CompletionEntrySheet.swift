import SwiftUI

/// Add or edit a single completion's date and time. "Edit the time" and
/// "move to another day" are the same operation since the timestamp is absolute.
struct CompletionEntrySheet: View {
    let title: String
    let allowDelete: Bool
    /// Adding, but not editing, offers a "Date Range" tab that backfills one
    /// completion per day across a start-end range.
    let allowRange: Bool
    let onSave: (Date) async throws -> Void
    let onSaveRange: (([Date]) async throws -> Void)?
    let onDelete: (() async throws -> Void)?

    private enum EntryMode: Hashable { case single, range }
    private enum Operation {
        case saving
        case deleting

        var errorTitle: String {
            switch self {
            case .saving: "Couldn’t Save Completion"
            case .deleting: "Couldn’t Delete Completion"
            }
        }
    }

    private struct OperationFailure {
        let operation: Operation
        let message: String
    }

    @State private var mode: EntryMode = .single
    @State private var date: Date
    @State private var endDate: Date
    @State private var activeOperation: Operation?
    @State private var operationFailure: OperationFailure?
    @Environment(\.dismiss) private var dismiss

    init(title: String,
         initialDate: Date,
         allowDelete: Bool,
         allowRange: Bool,
         onSave: @escaping (Date) async throws -> Void,
         onSaveRange: (([Date]) async throws -> Void)?,
         onDelete: (() async throws -> Void)?) {
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
                            delete(using: onDelete)
                        } label: {
                            Label("Delete entry", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .accessibilityIdentifier("habit.entry.delete")
                    }
                }
            }
            .disabled(activeOperation != nil)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").accessibilityLabel("Cancel")
                    }
                    .tint(.primary)
                    .disabled(activeOperation != nil)
                    .accessibilityIdentifier("habit.entry.cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark").accessibilityLabel("Save")
                    }
                    .tint(.primary)
                    .disabled(activeOperation != nil)
                    .accessibilityIdentifier("habit.entry.save")
                }
            }
            .alert(
                operationFailure?.operation.errorTitle ?? "Couldn’t Update Completion",
                isPresented: isShowingOperationFailure
            ) {
                Button("OK", role: .cancel) {}
                    .accessibilityIdentifier("habit.entry.persistence.error.dismiss")
            } message: {
                if let operationFailure {
                    Text(operationFailure.message)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(activeOperation != nil)
    }

    private var isShowingOperationFailure: Binding<Bool> {
        Binding(
            get: { operationFailure != nil },
            set: { isPresented in
                if !isPresented {
                    operationFailure = nil
                }
            }
        )
    }

    private func save() {
        guard activeOperation == nil else { return }
        let operation = Operation.saving
        let singleDate = date
        let dates = rangeDates
        let rangeAction = onSaveRange
        activeOperation = operation

        Task {
            do {
                if isRange, let rangeAction {
                    try await rangeAction(dates)
                } else {
                    try await onSave(singleDate)
                }
                activeOperation = nil
                dismiss()
            } catch {
                activeOperation = nil
                operationFailure = OperationFailure(
                    operation: operation,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func delete(using action: @escaping () async throws -> Void) {
        guard activeOperation == nil else { return }
        let operation = Operation.deleting
        activeOperation = operation

        Task {
            do {
                try await action()
                activeOperation = nil
                dismiss()
            } catch {
                activeOperation = nil
                operationFailure = OperationFailure(
                    operation: operation,
                    message: error.localizedDescription
                )
            }
        }
    }
}
