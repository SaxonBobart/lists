import SwiftUI

struct CalendarMonthView: View {
    private struct Week: Identifiable {
        let id: Date
        let days: [Date]
    }

    /// Plain memoization avoids allocating three date grids on every drag frame.
    /// It is deliberately not observable: only changing view inputs redraws UI.
    @MainActor private final class MonthDateCache {
        var calendar: Calendar?
        var values: [Date: [Week]] = [:]
        func weeks(in month: Date, calendar: Calendar) -> [Week] {
            if self.calendar != calendar { values.removeAll(); self.calendar = calendar }
            let key = calendar.dateInterval(of: .month, for: month)?.start ?? month
            if let cached = values[key] { return cached }
            let dates = CalendarDateMath.days(in: CalendarDateMath.monthGridInterval(containing: month, calendar: calendar), calendar: calendar)
            let result = stride(from: 0, to: dates.count, by: 7).map { start in
                let days = Array(dates[start..<min(start + 7, dates.count)])
                return Week(id: days[0], days: days)
            }
            if values.count >= 9 { values.removeAll() }
            values[key] = result
            return result
        }
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
    var actionsForEntry: ((CalendarEntry) -> ItemActions?)? = nil
    var onMoveToDay: (UUID, Date, Date) -> Bool = { _, _, _ in false }

    var layout: CalendarNavigationState.MonthLayout = .list
    var onOpenDay: (Date) -> Void = { _ in }
    var onPageMonth: (Int) -> Void = { _ in }
    var onDominantMonth: (Date) -> Void = { _ in }
    var navigationHeader: AnyView = AnyView(EmptyView())
    @State private var overviewHeight: CGFloat = 0
    private var overviewRowHeight: CGFloat {
        max(layout == .details ? 88 : 50, (overviewHeight - headerHeight - 110) / CGFloat(max(1, weeks.count)))
    }
    @State private var overviewWidth: CGFloat = 393
    @State private var headerHeight: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var settling = false
    @State private var dominantPage = 0
    @State private var monthDateCache = MonthDateCache()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if layout == .list {
                monthPager
            } else {
                overview
            }
            if layout == .list {
            Divider()
            if index.entries(on: selectedDate).isEmpty {
                Text("No Items").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 64)
                    .accessibilityIdentifier("calendar.month.empty")
            } else {
                selectedDayAgenda
            }
            }
        }
        .background(Color(.systemBackground))
    }

    /// Full-month layouts share the same dates, projection and selection as
    /// Month List. Details never materializes projected occurrence documents.
    private var overview: some View {
        GeometryReader { geometry in
            let availableSize = geometry.size
            monthPager
                .onGeometryChange(for: CGSize.self) { _ in availableSize } action: { size in
                    overviewWidth = size.width
                    overviewHeight = size.height
                }
        }
        .accessibilityIdentifier("calendar.month.\(layout.rawValue)")
    }

    private func overviewDay(_ day: Date, month: Date, rowHeight: CGFloat) -> some View {
        let entries = index.entries(on: day)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        return Button {
            if inMonth && !settling && abs(dragOffset) < 3 { onOpenDay(day) }
        } label: {
        VStack(alignment: .leading, spacing: 3) {
            if inMonth {
                CalendarMonthDayLabel(day: day, entries: entries, density: density,
                    isToday: calendar.isDateInToday(day), isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                    isInMonth: inMonth, isWeekend: calendar.isDateInWeekend(day), tint: tint, colorForEntry: colorForEntry)
                    .frame(height: 48)
                if layout == .details {
                    ForEach(Array(entries.prefix(2))) { entry in
                        Text(entry.title).font(.caption2).lineLimit(1)
                            .foregroundStyle(colorForEntry(entry))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 3).padding(.vertical, 3)
                            .background(colorForEntry(entry).opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                    }
                    if entries.count > 2 { Text("+\(entries.count - 2) more").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .top)
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(!inMonth)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(accessibilityValue(for: entries.count))
        .dropDestination(for: String.self, isEnabled: inMonth) { payloads, _ in
            if let payload = payloads.first, let drag = Self.parseDragPayload(payload) {
                selectedDate = day
                _ = onMoveToDay(drag.itemId, drag.start, day)
            }
        }
        .accessibilityIdentifier("calendar.month.day.\(CalendarDateMath.dayIdentifier(day, calendar: calendar))")
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
        .padding(.horizontal, 0)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }

    private var pageHeight: CGFloat { gridHeight(anchor) }
    private var previousHeight: CGFloat { gridHeight(CalendarDateMath.monthPage(anchor, offset: -1, calendar: calendar)) }
    private var viewportHeight: CGFloat {
        let direction = dragOffset < 0 ? 1 : -1
        let target = gridHeight(CalendarDateMath.monthPage(anchor, offset: direction, calendar: calendar))
        let distance = direction == 1 ? pageHeight : previousHeight
        return pageHeight + (target - pageHeight) * min(1, abs(dragOffset) / distance)
    }
    private func gridHeight(_ month: Date) -> CGFloat {
        CGFloat(weeks(in: month).count) * (layout == .list ? 50 : overviewRowHeight)
    }

    private var pageMonths: [Date] {
        (-1...1).compactMap {
            calendar.dateInterval(of: .month,
                for: CalendarDateMath.monthPage(anchor, offset: $0, calendar: calendar))?.start
        }
    }

    private var monthPages: some View {
        ZStack(alignment: .top) {
            ForEach(pageMonths, id: \.self) { month in
                let offset = month < (calendar.dateInterval(of: .month, for: anchor)?.start ?? anchor) ? -1
                    : (calendar.isDate(month, equalTo: anchor, toGranularity: .month) ? 0 : 1)
                monthGrid(month)
                    .frame(width: layout == .list ? nil : overviewWidth)
                    .offset(y: (offset == -1 ? -previousHeight : CGFloat(offset) * pageHeight) + dragOffset + headerHeight)
                    .allowsHitTesting(offset == 0 && !settling && abs(dragOffset) < 3)
                    .accessibilityElement(children: offset == 0 ? .contain : .ignore)
                    .accessibilityHidden(offset != 0)
            }
        }
    }

    private var monthPager: some View {
        monthPages
        .frame(height: viewportHeight + headerHeight, alignment: .top)
        .clipped()
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                navigationHeader
                weekdayHeader
                Divider()
            }
            .background(Color(.systemBackground))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
        }
        .contentShape(.rect)
        .highPriorityGesture(DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !settling, abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffset = max(-pageHeight, min(previousHeight, value.translation.height))
                let distance = dragOffset < 0 ? pageHeight : previousHeight
                let direction = abs(dragOffset) > distance / 2 ? (dragOffset < 0 ? 1 : -1) : 0
                if dominantPage != direction {
                    dominantPage = direction
                    onDominantMonth(CalendarDateMath.monthPage(anchor, offset: direction, calendar: calendar))
                }
            }
            .onEnded { value in
                guard !settling else { return }
                let direction = CalendarDateMath.monthPageDirection(translation: value.translation,
                    predicted: value.predictedEndTranslation)
                settling = true
                if dominantPage != direction {
                    dominantPage = direction
                    onDominantMonth(CalendarDateMath.monthPage(anchor, offset: direction, calendar: calendar))
                }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
                    dragOffset = direction == -1 ? previousHeight : -CGFloat(direction) * pageHeight
                } completion: {
                    var transaction = Transaction(); transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        if direction != 0 { onPageMonth(direction) }
                        dragOffset = 0
                        settling = false
                        dominantPage = 0
                    }
                }
            })
        .accessibilityAction(named: "Next month") { onPageMonth(1) }
        .accessibilityAction(named: "Previous month") { onPageMonth(-1) }
        .accessibilityIdentifier("calendar.month.grid")
    }

    private func monthGrid(_ month: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(weeks(in: month)) { week in
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 0) {
                    if showWeekNumbers {
                        Text("\(calendar.component(.weekOfYear, from: week.id))")
                            .font(.caption2).foregroundStyle(.tertiary).frame(width: 24)
                    }
                    ForEach(visibleDates(in: week.days), id: \.self) { day in
                        if calendar.isDate(day, equalTo: month, toGranularity: .month) {
                            if layout == .list { dayButton(day, month: month) }
                            else {
                                overviewDay(day, month: month, rowHeight: overviewRowHeight - 1)
                                    .frame(width: max(1, (overviewWidth - (showWeekNumbers ? 24 : 0)) / CGFloat(showWeekends ? 7 : 5)))
                                    .clipped()
                            }
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: layout == .list ? 49 : overviewRowHeight - 1)
                                .accessibilityHidden(true)
                        }
                    }
                    }.frame(height: layout == .list ? 49 : overviewRowHeight - 1)
                }.frame(height: layout == .list ? 50 : overviewRowHeight)
            }
        }
    }

    private func dayButton(_ day: Date, month: Date) -> some View {
        let entries = index.entries(on: day)
        let selected = calendar.isDate(day, inSameDayAs: selectedDate)
        let today = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)

        return CalendarMonthDayLabel(
                day: day,
                entries: entries,
                density: density,
                isToday: today,
                isSelected: selected,
                isInMonth: inMonth,
                isWeekend: calendar.isDateInWeekend(day),
                tint: tint,
                colorForEntry: colorForEntry
            )
        .gesture(LongPressGesture(minimumDuration: 0.25, maximumDistance: 10)
            .exclusively(before: TapGesture())
            .onEnded { result in
                guard !settling, abs(dragOffset) < 3 else { return }
                switch result {
                case .first:
                    UISelectionFeedbackGenerator().selectionChanged()
                    onOpenDay(day)
                case .second: selectedDate = day
                }
            })
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selectedDate = day }
        .accessibilityAction(named: "Open day") { onOpenDay(day) }
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

    @State private var agendaScrolled = false

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
                actionsForEntry: actionsForEntry,
                dragPayload: { entry in
                    entry.isEditableOccurrence ? Self.dragPayload(for: entry) : nil
                },
                showsHeader: false
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 1
        } action: { _, scrolled in agendaScrolled = scrolled }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide))).font(.headline)
                Text(selectedDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .overlay(alignment: .bottom) { if agendaScrolled { Divider() } }
            .accessibilityIdentifier("calendar.month.agenda.header")
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

    private var weeks: [Week] { weeks(in: anchor) }

    private func weeks(in month: Date) -> [Week] {
        monthDateCache.weeks(in: month, calendar: calendar)
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
    let isWeekend: Bool
    let tint: Color
    let colorForEntry: (CalendarEntry) -> Color

    @ScaledMetric(relativeTo: .body) private var dayFontSize = 19.0

    var body: some View {
        VStack(spacing: 4) {
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: dayFontSize, weight: .semibold))
                .foregroundStyle(dayForeground)
                .frame(width: 30, height: 30)
                .background(dayBackground)

            entryIndicator
                .frame(height: indicatorHeight)
        }
        .padding(.top, 3)
        .frame(maxWidth: .infinity, minHeight: cellHeight, alignment: .top)
        .contentShape(.rect)
    }

    private var dayForeground: Color {
        if isSelected { return isToday ? .white : Color(.systemBackground) }
        if isToday { return tint }
        return isWeekend ? .secondary : .primary
    }

    @ViewBuilder
    private var dayBackground: some View {
        if isSelected {
            Circle().fill(isToday ? tint : Color.primary)
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
        case .details:
            if let first = entries.first {
                HStack(spacing: 3) {
                    Capsule()
                        .fill(colorForEntry(first))
                        .frame(width: 14, height: 4)
                    Text("\(entries.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var indicatorHeight: CGFloat {
        density == .compact ? 4 : 10
    }

    private var cellHeight: CGFloat {
        49
    }
}
