import SwiftUI

struct CalendarYearView: View {
    let anchor: Date
    let calendar: Calendar
    let index: CalendarEntryIndex
    let showWeekends: Bool
    let showWeekNumbers: Bool
    let tint: Color
    let colorForEntry: (CalendarEntry) -> Color
    let onSelectMonth: (Date) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 18, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                ForEach(months, id: \.self) { month in
                    miniMonth(month)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 92)
        }
    }

    private func miniMonth(_ month: Date) -> some View {
        Button {
            onSelectMonth(month)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(month.formatted(.dateTime.month(.wide)))
                    .font(.headline)
                    .foregroundStyle(.tint)

                HStack(spacing: 2) {
                    if showWeekNumbers {
                        Text("#")
                            .frame(width: 14)
                    }
                    ForEach(weekdayDates(for: month), id: \.self) { date in
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                let grid = gridDays(for: month)
                VStack(spacing: 3) {
                    ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                        HStack(spacing: 2) {
                            if showWeekNumbers {
                                Text("\(calendar.component(.weekOfYear, from: week[0]))")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 14)
                            }
                            ForEach(visibleDates(in: week), id: \.self) { day in
                                miniDay(day, month: month)
                            }
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
        .accessibilityHint("Show month")
        .accessibilityIdentifier(
            "calendar.year.month.\(calendar.component(.month, from: month))"
        )
    }

    private func miniDay(_ day: Date, month: Date) -> some View {
        let count = index.entries(on: day).count
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        return VStack(spacing: 1) {
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 9, weight: calendar.isDateInToday(day) ? .bold : .regular))
                .foregroundStyle(
                    calendar.isDateInToday(day)
                        ? Color.white
                        : (inMonth ? Color.primary : Color.clear)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 16)
                .background {
                    if calendar.isDateInToday(day) {
                        Circle().fill(tint)
                    }
                }
            if count > 0 && inMonth {
                HStack(spacing: 1) {
                    ForEach(Array(index.entries(on: day).prefix(3))) { entry in
                        Circle()
                            .fill(colorForEntry(entry))
                            .frame(width: 2.5, height: 2.5)
                    }
                }
                .frame(height: 3)
            } else {
                Color.clear.frame(height: 3)
            }
        }
    }

    private var months: [Date] {
        let year = CalendarDateMath.yearInterval(containing: anchor, calendar: calendar)
        return (0..<12).compactMap {
            calendar.date(byAdding: .month, value: $0, to: year.start)
        }
    }

    private func gridDays(for month: Date) -> [[Date]] {
        let dates = CalendarDateMath.days(
            in: CalendarDateMath.monthGridInterval(containing: month, calendar: calendar),
            calendar: calendar
        )
        return stride(from: 0, to: dates.count, by: 7).map {
            Array(dates[$0..<min($0 + 7, dates.count)])
        }
    }

    private func weekdayDates(for month: Date) -> [Date] {
        let start = CalendarDateMath.monthGridInterval(
            containing: month,
            calendar: calendar
        ).start
        let dates = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
        return showWeekends ? dates : dates.filter { !calendar.isDateInWeekend($0) }
    }

    private func visibleDates(in week: [Date]) -> [Date] {
        showWeekends ? week : week.filter { !calendar.isDateInWeekend($0) }
    }
}
