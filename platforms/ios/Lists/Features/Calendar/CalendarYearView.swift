import SwiftUI

struct CalendarYearView: View {
    private struct Week: Identifiable {
        let id: Date
        let days: [Date]
    }

    let anchor: Date
    let calendar: Calendar
    let showWeekends: Bool
    let showWeekNumbers: Bool
    let tint: Color
    let onSelectMonth: (Date) -> Void

    @State private var years: [Date] = []
    @State private var scrolledYear: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(anchor: Date, calendar: Calendar,
         showWeekends: Bool, showWeekNumbers: Bool, tint: Color,
         onSelectMonth: @escaping (Date) -> Void) {
        self.anchor = anchor
        self.calendar = calendar
        self.showWeekends = showWeekends
        self.showWeekNumbers = showWeekNumbers
        self.tint = tint
        self.onSelectMonth = onSelectMonth
        let year = CalendarDateMath.yearInterval(containing: anchor, calendar: calendar).start
        self.years = (-1...1).compactMap { calendar.date(byAdding: .year, value: $0, to: year) }
        self.scrolledYear = year
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 60) {
                ForEach(years, id: \.self) { year in
                    VStack(spacing: 20) {
                        Text(year, format: .dateTime.year())
                            .font(.largeTitle.bold())
                            .foregroundStyle(calendar.isDate(year, equalTo: .now, toGranularity: .year) ? tint : .primary)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("calendar.year.heading.\(calendar.component(.year, from: year))")
                        let yearMonths = months(in: year)
                        VStack(spacing: 24) {
                            ForEach(0..<4, id: \.self) { row in
                                HStack(alignment: .top, spacing: 18) {
                                    ForEach(Array(yearMonths[(row * 3)..<(row * 3 + 3)]), id: \.self) { month in
                                        miniMonth(month).frame(maxWidth: .infinity, alignment: .topLeading)
                                    }
                                }
                            }
                        }
                    }
                    .id(year)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .scrollPosition(id: $scrolledYear, anchor: .top)
        .accessibilityIdentifier("calendar.year.scroll")
        .onAppear { reveal(anchor) }
        .onChange(of: anchor) { _, date in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) { reveal(date) }
        }
        .onChange(of: scrolledYear) { _, year in
            guard let year else { return }
            extend(around: year)
        }
    }

    private func reveal(_ date: Date) {
        let year = CalendarDateMath.yearInterval(containing: date, calendar: calendar).start
        extend(around: year)
        scrolledYear = year
    }

    private func extend(around year: Date) {
        let neighbors = (-1...1).compactMap { calendar.date(byAdding: .year, value: $0, to: year) }
        let expanded = Array(Set(years + neighbors)).sorted()
        if expanded != years { years = expanded }

    }

    private func miniMonth(_ month: Date) -> some View {
        Button {
            onSelectMonth(month)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(month.formatted(.dateTime.month(.abbreviated)))
                    .font(.headline)
                    .foregroundStyle(calendar.isDate(month, equalTo: .now, toGranularity: .month) ? tint : .primary)

                let grid = gridDays(for: month)
                VStack(spacing: 3) {
                    ForEach(grid) { week in
                        HStack(spacing: 2) {
                            if showWeekNumbers {
                                Text("\(calendar.component(.weekOfYear, from: week.id))")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 14)
                            }
                            ForEach(visibleDates(in: week.days), id: \.self) { day in
                                miniDay(day, month: month)
                            }
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
        .accessibilityHint("Show month")
        .accessibilityIdentifier(
            "calendar.year.month.\(calendar.component(.year, from: month)).\(calendar.component(.month, from: month))"
        )
    }

    private func miniDay(_ day: Date, month: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        return VStack(spacing: 1) {
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 9, weight: calendar.isDateInToday(day) ? .bold : .regular))
                .foregroundStyle(
                    inMonth && calendar.isDateInToday(day)
                        ? Color.white
                        : (inMonth ? Color.primary : Color.clear)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 16)
                .background {
                    if inMonth && calendar.isDateInToday(day) {
                        Circle().fill(tint)
                    }
                }
            Color.clear.frame(height: 3)
        }
    }

    private func months(in date: Date) -> [Date] {
        let year = CalendarDateMath.yearInterval(containing: date, calendar: calendar)
        return (0..<12).compactMap {
            calendar.date(byAdding: .month, value: $0, to: year.start)
        }
    }

    private func gridDays(for month: Date) -> [Week] {
        let start = CalendarDateMath.monthGridInterval(containing: month, calendar: calendar).start
        let dates = (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        return stride(from: 0, to: dates.count, by: 7).compactMap { start in
            let days = Array(dates[start..<min(start + 7, dates.count)])
            guard let first = days.first else { return nil }
            return Week(id: first, days: days)
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
