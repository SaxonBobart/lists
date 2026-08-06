import SwiftUI

struct CalendarMonthView: View {
    private struct Week: Identifiable {
        let id: Date
        let days: [Date]
    }

    let anchor: Date
    @Binding var selectedDate: Date
    let density: CalendarMonthDensity
    let showWeekends: Bool
    let showWeekNumbers: Bool
    let calendar: Calendar
    let tint: Color
    let index: CalendarEntryIndex
    let colorForEntry: (CalendarEntry) -> Color
    let canToggle: (CalendarEntry) -> Bool
    let onToggle: (CalendarEntry) -> Void
    let onOpen: (CalendarEntry) -> Void
    var onDuplicate: (CalendarEntry) -> Void = { _ in }
    var onMoveToDay: (UUID, Date, Date) -> Bool = { _, _, _ in false }

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
            monthGrid
            Divider()
                .padding(.top, 8)
            selectedDayAgenda
        }
        .background(Color(.systemBackground))
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            if showWeekNumbers {
                Text("#")
                    .frame(width: 24)
            }
            ForEach(weekdayDates, id: \.self) { date in
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }

    private var monthGrid: some View {
        VStack(spacing: 2) {
            ForEach(weeks) { week in
                HStack(spacing: 4) {
                    if showWeekNumbers {
                        Text("\(calendar.component(.weekOfYear, from: week.id))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 24)
                    }
                    ForEach(visibleDates(in: week.days), id: \.self) { day in
                        dayButton(day)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func dayButton(_ day: Date) -> some View {
        let entries = index.entries(on: day)
        let selected = calendar.isDate(day, inSameDayAs: selectedDate)
        let today = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: anchor, toGranularity: .month)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedDate = day
            }
        } label: {
            CalendarMonthDayLabel(
                day: day,
                entries: entries,
                density: density,
                isToday: today,
                isSelected: selected,
                isInMonth: inMonth,
                tint: tint,
                colorForEntry: colorForEntry
            )
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { payloads, _ in
            guard let payload = payloads.first,
                  let drag = Self.parseDragPayload(payload) else {
                return false
            }
            selectedDate = day
            return onMoveToDay(drag.itemId, drag.start, day)
        }
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(accessibilityValue(for: entries.count))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(
            "calendar.month.day.\(CalendarDateMath.dayIdentifier(day, calendar: calendar))"
        )
    }

    private var selectedDayAgenda: some View {
        ScrollView {
            CalendarAgendaDaySection(
                day: selectedDate,
                entries: index.entries(on: selectedDate),
                calendar: calendar,
                colorForEntry: colorForEntry,
                canToggle: canToggle,
                onToggle: onToggle,
                onOpen: onOpen,
                onDuplicate: onDuplicate,
                dragPayload: { entry in
                    entry.isEditableOccurrence ? Self.dragPayload(for: entry) : nil
                }
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .accessibilityIdentifier("calendar.month.agenda")
    }

    private static func dragPayload(for entry: CalendarEntry) -> String {
        "calendar-entry|\(entry.itemId.uuidString)|\(entry.start.timeIntervalSince1970)"
    }

    private func accessibilityValue(for count: Int) -> String {
        switch count {
        case 0: return "No items"
        case 1: return "1 item"
        default: return "\(count) items"
        }
    }

    private static func parseDragPayload(_ payload: String) -> (itemId: UUID, start: Date)? {
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "calendar-entry",
              let itemId = UUID(uuidString: String(parts[1])),
              let seconds = TimeInterval(parts[2]) else {
            return nil
        }
        return (itemId, Date(timeIntervalSince1970: seconds))
    }

    private var weeks: [Week] {
        let dates = CalendarDateMath.days(
            in: CalendarDateMath.monthGridInterval(containing: anchor, calendar: calendar),
            calendar: calendar
        )
        return stride(from: 0, to: dates.count, by: 7).compactMap { start in
            let days = Array(dates[start..<min(start + 7, dates.count)])
            guard let first = days.first else { return nil }
            return Week(id: first, days: days)
        }
    }

    private var weekdayDates: [Date] {
        guard let first = weeks.first?.days.first else { return [] }
        return CalendarDateMath.visibleWeekdays(
            from: first,
            showWeekends: showWeekends,
            calendar: calendar
        )
    }

    private func visibleDates(in week: [Date]) -> [Date] {
        showWeekends ? week : week.filter { !calendar.isDateInWeekend($0) }
    }
}

private struct CalendarMonthDayLabel: View {
    let day: Date
    let entries: [CalendarEntry]
    let density: CalendarMonthDensity
    let isToday: Bool
    let isSelected: Bool
    let isInMonth: Bool
    let tint: Color
    let colorForEntry: (CalendarEntry) -> Color

    var body: some View {
        VStack(spacing: 4) {
            Text(day.formatted(.dateTime.day()))
                .font(.subheadline.weight(isToday || isSelected ? .bold : .medium))
                .foregroundStyle(dayForeground)
                .frame(width: 30, height: 30)
                .background(dayBackground)

            entryIndicator
                .frame(height: indicatorHeight)
        }
        .frame(maxWidth: .infinity, minHeight: cellHeight, alignment: .top)
        .contentShape(.rect)
    }

    private var dayForeground: Color {
        if isToday { return .white }
        return isInMonth ? .primary : .secondary
    }

    @ViewBuilder
    private var dayBackground: some View {
        if isToday {
            Circle().fill(tint)
        } else if isSelected {
            Circle().fill(tint.opacity(0.14))
                .overlay { Circle().strokeBorder(tint, lineWidth: 1.5) }
        }
    }

    @ViewBuilder
    private var entryIndicator: some View {
        switch density {
        case .compact:
            HStack(spacing: 2) {
                ForEach(Array(entries.prefix(3))) { entry in
                    Circle()
                        .fill(colorForEntry(entry))
                        .frame(width: 4, height: 4)
                }
            }
        case .stacked:
            HStack(spacing: 2) {
                ForEach(Array(entries.prefix(3))) { entry in
                    Capsule()
                        .fill(colorForEntry(entry))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 26)
        case .details:
            if let first = entries.first {
                HStack(spacing: 3) {
                    Capsule()
                        .fill(colorForEntry(first))
                        .frame(width: 14, height: 4)
                    if entries.count > 1 {
                        Text("+\(entries.count - 1)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var indicatorHeight: CGFloat {
        density == .compact ? 4 : 10
    }

    private var cellHeight: CGFloat {
        density == .compact ? 40 : 46
    }
}
