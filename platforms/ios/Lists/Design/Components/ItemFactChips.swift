import SwiftUI

/// Date/end/repeat/priority/flag chips for row-like item surfaces. Tags stay
/// separate because normal rows render tag text, while inline editing swaps the
/// tag line for an editable field.
struct ItemFactChips: View {
    let item: Item
    let isOverdue: Bool
    var wraps: Bool = true

    var body: some View {
        if Self.hasFacts(for: item) {
            Group {
                if wraps {
                    ViewThatFits(in: .horizontal) {
                        chipsLine
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) { dateChip; endChip; repeatChip }
                            HStack(spacing: 6) { priorityChip; flagChip }
                        }
                    }
                } else {
                    chipsLine
                }
            }
            .font(ListsTypography.footnote)
            .foregroundStyle(ListsTokens.Foreground.secondary)
            .lineLimit(1)
        }
    }

    static func hasFacts(for item: Item) -> Bool {
        dateString(for: item) != nil
            || endString(for: item) != nil
            || item.recurrence?.rrule != nil
            || item.priority != .none
            || item.flagged
    }

    static func dateString(for item: Item) -> String? {
        guard let due = item.due else { return nil }

        let datePart = shortDate(due)
        if item.dueAllDay {
            return datePart
        }
        let timePart = due.formatted(date: .omitted, time: .shortened)
        return "\(datePart), \(timePart)"
    }

    static func endString(for item: Item) -> String? {
        guard item.type == .event, let end = item.end else { return nil }
        if let due = item.due,
           Calendar.current.isDate(end, inSameDayAs: due), !item.dueAllDay {
            return end.formatted(date: .omitted, time: .shortened)
        }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: end)
    }

    private var chipsLine: some View {
        HStack(spacing: 6) {
            dateChip
            endChip
            repeatChip
            priorityChip
            flagChip
        }
    }

    @ViewBuilder private var dateChip: some View {
        if let date = Self.dateString(for: item) {
            Text(date)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isOverdue
                                 ? ListsTokens.Semantic.danger
                                 : ListsTokens.Foreground.secondary)
        }
    }

    @ViewBuilder private var endChip: some View {
        if let end = Self.endString(for: item) {
            Text("→ \(end)")
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder private var repeatChip: some View {
        if let rrule = item.recurrence?.rrule {
            HStack(spacing: 3) {
                Image(systemName: "repeat")
                Text(RepeatPreset.summary(forRRule: rrule))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder private var priorityChip: some View {
        if item.priority != .none {
            Text(priorityText)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(priorityColor)
        }
    }

    @ViewBuilder private var flagChip: some View {
        if item.flagged {
            Image(systemName: "flag.fill")
                .foregroundStyle(ListsTokens.Semantic.warning)
        }
    }

    private var priorityText: String {
        switch item.priority {
        case .high:   return "!!!"
        case .medium: return "!!"
        case .low:    return "!"
        case .none:   return ""
        }
    }

    private var priorityColor: Color {
        switch item.priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .yellow
        case .none:   return .clear
        }
    }

    private static func shortDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInTomorrow(date)  { return "Tomorrow" }
        if cal.isDateInYesterday(date) { return "Yesterday" }

        let startToday = cal.startOfDay(for: .now)
        let startDate = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: startToday, to: startDate).day ?? 0

        let f = DateFormatter()
        f.locale = Locale.current
        if (-6...6).contains(days) {
            f.dateFormat = "EEE"
        } else {
            f.dateStyle = .short
            f.timeStyle = .none
        }
        return f.string(from: date)
    }
}
