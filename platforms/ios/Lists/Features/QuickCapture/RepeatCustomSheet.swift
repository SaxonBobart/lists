import SwiftUI

/// Apple Reminders-style custom recurrence editor. Drives a `RecurrenceRule`
/// and returns its composed RRULE on apply. End Repeat (UNTIL) is still handled
/// by a separate row in the host sheet, so this editor only emits the FREQ rule.
struct CustomRepeatSheet: View {
    let initialRRule: String?
    let startDate: Date
    let onApply: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rule: RecurrenceRule
    @FocusState private var intervalFocused: Bool

    init(initialRRule: String?, startDate: Date = .now, onApply: @escaping (String) -> Void) {
        self.initialRRule = initialRRule
        self.startDate = startDate
        self.onApply = onApply
        let seeded = initialRRule.flatMap { RecurrenceRule.parse($0, date: startDate) }
            ?? RecurrenceRule.makeDefault(from: startDate)
        _rule = State(initialValue: seeded)
    }

    var body: some View {
        NavigationStack {
            Form {
                frequencySection
                switch rule.frequency {
                case .hourly, .daily: EmptyView()
                case .weekly:         weeklySection
                case .monthly:        monthlySection
                case .yearly:         yearlySection
                }
            }
            .navigationTitle("Custom")
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
                        onApply(rule.rrule)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark").fontWeight(.semibold).accessibilityLabel("Done")
                    }
                    .tint(.primary)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { intervalFocused = false }
                }
            }
            .tint(ListsTokens.accent)
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Frequency + Every

    private var frequencySection: some View {
        Section(footer: Text(rule.summary)) {
            Picker("Frequency", selection: $rule.frequency) {
                ForEach(RecurrenceRule.Frequency.allCases) { f in
                    Text(f.displayName).tag(f)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Text("Every")
                Spacer()
                TextField("1", value: $rule.interval, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($intervalFocused)
                    .frame(width: 60)
                    .onChange(of: rule.interval) { _, value in
                        let clamped = min(999, max(1, value))
                        if clamped != value { rule.interval = clamped }
                    }
            }
        }
        .animation(.default, value: rule.frequency)
    }

    // MARK: Weekly

    private var weeklySection: some View {
        Section {
            ForEach(RecurrenceWeekday.allCases) { day in
                Button {
                    toggle(day, in: \.weekdays, allowEmpty: true)
                } label: {
                    HStack {
                        Text(day.fullName).foregroundStyle(.primary)
                        Spacer()
                        if rule.weekdays.contains(day) {
                            Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Monthly

    private var monthlySection: some View {
        Section {
            modeRow(title: "Each", isOn: rule.monthlyMode == .each) { rule.monthlyMode = .each }
            modeRow(title: "On the…", isOn: rule.monthlyMode == .onThe) { rule.monthlyMode = .onThe }

            if rule.monthlyMode == .each {
                NumberGrid(
                    values: Array(1...31),
                    columns: 7,
                    isSelected: { rule.monthDays.contains($0) },
                    label: { "\($0)" },
                    onTap: { toggle($0, in: \.monthDays, allowEmpty: false) }
                )
                .listRowInsets(EdgeInsets())
            } else {
                ordinalWeekdayPicker
            }
        }
    }

    // MARK: Yearly

    private var yearlySection: some View {
        Group {
            Section {
                NumberGrid(
                    values: Array(1...12),
                    columns: 4,
                    isSelected: { rule.months.contains($0) },
                    label: { Calendar.current.shortMonthSymbols[$0 - 1] },
                    onTap: { toggle($0, in: \.months, allowEmpty: false) }
                )
                .listRowInsets(EdgeInsets())
            }
            Section {
                Toggle("Days of Week", isOn: $rule.yearlyUsesDaysOfWeek)
                    .tint(.green)
                if rule.yearlyUsesDaysOfWeek {
                    ordinalWeekdayPicker
                }
            }
        }
    }

    // MARK: Shared pieces

    /// Side-by-side ordinal (first…last) + weekday wheels.
    private var ordinalWeekdayPicker: some View {
        HStack(spacing: 0) {
            Picker("Ordinal", selection: $rule.ordinal) {
                ForEach(RecurrenceOrdinal.allCases) { Text($0.word).tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Picker("Weekday", selection: $rule.ordinalWeekday) {
                ForEach(RecurrenceWeekday.allCases) { Text($0.fullName).tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
        .labelsHidden()
        .frame(height: 160)
        .listRowInsets(EdgeInsets())
    }

    private func modeRow(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Toggle membership in a `Set` field, optionally keeping at least one.
    private func toggle<T: Hashable>(_ value: T, in keyPath: WritableKeyPath<RecurrenceRule, Set<T>>, allowEmpty: Bool) {
        var set = rule[keyPath: keyPath]
        if set.contains(value) {
            if !allowEmpty && set.count == 1 { return }   // keep at least one
            set.remove(value)
        } else {
            set.insert(value)
        }
        rule[keyPath: keyPath] = set
    }
}

/// A bordered grid of tappable numbers/labels (calendar days, months), with a
/// blue highlight on the selected cells — matches the Reminders pickers.
private struct NumberGrid: View {
    let values: [Int]
    let columns: Int
    let isSelected: (Int) -> Bool
    let label: (Int) -> String
    let onTap: (Int) -> Void

    var body: some View {
        let grid = Array(repeating: GridItem(.flexible(), spacing: 0), count: columns)
        LazyVGrid(columns: grid, spacing: 0) {
            ForEach(values, id: \.self) { value in
                let selected = isSelected(value)
                Button { onTap(value) } label: {
                    Text(label(value))
                        .font(.body)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selected ? ListsTokens.accent : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(
                    Rectangle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
            }
        }
    }
}
