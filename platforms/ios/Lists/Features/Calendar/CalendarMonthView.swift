import SwiftUI

struct CalendarMonthView: View {
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
        ScrollView {
            VStack(spacing: 10) {
                weekdayHeader
                monthGrid

                Divider()
                    .padding(.top, 2)

                CalendarAgendaDaySection(
                    day: selectedDate,
                    entries: index.entries(on: selectedDate),
                    calendar: calendar,
                    colorForEntry: colorForEntry,
                    canToggle: canToggle,
                    onToggle: onToggle,
                    onOpen: onOpen,
                    onDuplicate: onDuplicate
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .padding(.top, 6)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            if showWeekNumbers {
                Text("#")
                    .frame(width: 22)
            }
            ForEach(weekdayDates, id: \.self) { date in
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .accessibilityHidden(true)
    }

    private var monthGrid: some View {
        VStack(spacing: 5) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(alignment: .top, spacing: 4) {
                    if showWeekNumbers {
                        Text("\(calendar.component(.weekOfYear, from: week[0]))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, height: cellHeight, alignment: .top)
                            .padding(.top, 8)
                    }
                    ForEach(visibleDates(in: week), id: \.self) { day in
                        dayCell(day)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func dayCell(_ day: Date) -> some View {
        let entries = index.entries(on: day)
        let selected = calendar.isDate(day, inSameDayAs: selectedDate)
        let today = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: anchor, toGranularity: .month)
        let maximumVisibleEntries = density == .compact ? 4 : (density == .stacked ? 3 : 2)
        let dayForeground: Color = today ? .white : (inMonth ? .primary : .secondary)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Text(day.formatted(.dateTime.day()))
                    .font(.caption.weight(today || selected ? .bold : .medium))
                    .foregroundStyle(dayForeground)
                    .frame(width: 22, height: 22)
                    .background(dayNumberBackground(today: today, selected: selected))
                Spacer(minLength: 0)
            }

            if density == .compact {
                HStack(spacing: 2) {
                    ForEach(Array(entries.prefix(maximumVisibleEntries))) { entry in
                        Circle()
                            .fill(colorForEntry(entry))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(entries.prefix(maximumVisibleEntries))) { entry in
                    entryChip(entry, day: day)
                }
            }

            if entries.count > maximumVisibleEntries {
                Text("+\(entries.count - maximumVisibleEntries)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: cellHeight, alignment: .topLeading)
        .background(
            selected ? tint.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedDate = day
            }
        }
        .dropDestination(for: String.self) { payloads, _ in
            guard let payload = payloads.first,
                  let drag = Self.parseDragPayload(payload) else {
                return false
            }
            selectedDate = day
            return onMoveToDay(drag.itemId, drag.start, day)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(entries.isEmpty ? "No items" : "\(entries.count) items")
        .accessibilityIdentifier(
            "calendar.month.day.\(CalendarDateMath.dayIdentifier(day, calendar: calendar))"
        )
    }

    @ViewBuilder
    private func entryChip(_ entry: CalendarEntry, day: Date) -> some View {
        let chip = CalendarEntryChip(
            entry: entry,
            color: colorForEntry(entry),
            compact: density == .stacked,
            onOpen: { onOpen(entry) },
            onDuplicate: { onDuplicate(entry) },
            instanceIdentifier: monthEntryIdentifier(entry, day: day)
        )
        if entry.isEditableOccurrence {
            chip.draggable(Self.dragPayload(for: entry))
        } else {
            chip
        }
    }

    private func monthEntryIdentifier(_ entry: CalendarEntry, day: Date) -> String {
        let dayId = CalendarDateMath.dayIdentifier(day, calendar: calendar)
        return "calendar.month.entry.\(entry.itemId.uuidString).\(entry.id.source.rawValue).\(dayId)"
    }

    private static func dragPayload(for entry: CalendarEntry) -> String {
        "calendar-entry|\(entry.itemId.uuidString)|\(entry.start.timeIntervalSince1970)"
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

    @ViewBuilder
    private func dayNumberBackground(today: Bool, selected: Bool) -> some View {
        if today {
            Circle().fill(tint)
        } else if selected {
            Circle().strokeBorder(tint, lineWidth: 1.5)
        }
    }

    private var cellHeight: CGFloat {
        switch density {
        case .compact: return 48
        case .stacked: return 66
        case .details: return 82
        }
    }

    private var weeks: [[Date]] {
        let dates = CalendarDateMath.days(
            in: CalendarDateMath.monthGridInterval(containing: anchor, calendar: calendar),
            calendar: calendar
        )
        return stride(from: 0, to: dates.count, by: 7).map {
            Array(dates[$0..<min($0 + 7, dates.count)])
        }
    }

    private var weekdayDates: [Date] {
        guard let first = weeks.first?.first else { return [] }
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
