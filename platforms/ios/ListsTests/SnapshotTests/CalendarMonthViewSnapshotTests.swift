import SwiftUI
import SnapshotTesting
import XCTest
@testable import Lists

private struct CalendarMonthSnapshotHost: View {
    @State var selectedDate: Date
    let anchor: Date
    let calendar: Calendar
    let index: CalendarEntryIndex

    var body: some View {
        CalendarMonthView(
            anchor: anchor,
            selectedDate: $selectedDate,
            density: .details,
            showWeekends: true,
            showWeekNumbers: false,
            calendar: calendar,
            tint: .blue,
            index: index,
            colorForEntry: { entry in
                entry.listId == "work" ? .orange : .blue
            },
            canToggle: { _ in false },
            onToggle: { _ in },
            onOpen: { _ in }
        )
        .background(Color(.systemBackground))
    }
}

private struct CalendarTimelineSnapshotHost: View {
    @State private var selectedDate: Date
    let days: [Date]
    let calendar: Calendar
    let index: CalendarEntryIndex
    let columns: Int

    init(selectedDate: Date, days: [Date], calendar: Calendar, index: CalendarEntryIndex, columns: Int = 2) {
        _selectedDate = State(initialValue: selectedDate)
        self.days = days
        self.calendar = calendar
        self.index = index
        self.columns = columns
    }

    var body: some View {
        CalendarTimelineView(
            days: days,
            selectedDate: $selectedDate,
            index: index,
            calendar: calendar,
            tint: .blue,
            colorForEntry: { $0.listId == "work" ? .orange : .blue },
            onOpen: { _ in },
            onReschedule: { _, _, _ in },
            onDuplicate: { _ in },
            onCreateAt: { _ in },
            visibleColumnCount: columns
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
    }
}

@MainActor
final class CalendarMonthViewSnapshotTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_AU")
        value.timeZone = .current
        value.firstWeekday = 2
        return value
    }

    private func date(
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: 2024,
            month: 7,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func entry(
        title: String,
        listId: String,
        start: Date,
        end: Date,
        allDay: Bool,
        type: Item.ItemType = .event
    ) -> CalendarEntry {
        let itemId = UUID()
        return CalendarEntry(
            id: .init(
                itemId: itemId,
                source: .current,
                scheduledAt: start,
                occurrenceId: nil
            ),
            itemId: itemId,
            title: title,
            type: type,
            listId: listId,
            section: nil,
            start: start,
            end: end,
            isAllDay: allDay,
            status: .open,
            isCompletable: type == .task,
            priority: .none,
            flagged: false,
            hasRecurrence: false
        )
    }

    private func monthView() -> some View {
        let anchor = date(17)
        let interval = CalendarDateMath.monthGridInterval(
            containing: anchor,
            calendar: calendar
        )
        let entries = [
            entry(
                title: "Release planning",
                listId: "work",
                start: date(15),
                end: date(16),
                allDay: true
            ),
            entry(
                title: "Write announcement",
                listId: "personal",
                start: date(17, 9),
                end: date(17, 9, 30),
                allDay: false,
                type: .task
            ),
            entry(
                title: "Design review",
                listId: "work",
                start: date(17, 14),
                end: date(17, 15, 30),
                allDay: false
            ),
            entry(
                title: "Conference",
                listId: "personal",
                start: date(22),
                end: date(25),
                allDay: true
            )
        ]
        return CalendarMonthSnapshotHost(
            selectedDate: anchor,
            anchor: anchor,
            calendar: calendar,
            index: CalendarEntryIndex(
                entries: entries,
                interval: interval,
                calendar: calendar
            )
        )
    }

    private func sampleEntries() -> [CalendarEntry] {
        [
            entry(
                title: "Release planning",
                listId: "work",
                start: date(15),
                end: date(16),
                allDay: true
            ),
            entry(
                title: "Write announcement",
                listId: "personal",
                start: date(17, 9),
                end: date(17, 9, 30),
                allDay: false,
                type: .task
            ),
            entry(
                title: "Design review",
                listId: "work",
                start: date(17, 14),
                end: date(17, 15, 30),
                allDay: false
            ),
            entry(
                title: "Conference",
                listId: "personal",
                start: date(22),
                end: date(25),
                allDay: true
            )
        ]
    }

    private func sampleIndex(in interval: DateInterval) -> CalendarEntryIndex {
        CalendarEntryIndex(entries: sampleEntries(), interval: interval, calendar: calendar)
    }

    private func agendaView() -> some View {
        let interval = DateInterval(start: date(15), end: date(26))
        return CalendarAgendaView(
            days: CalendarDateMath.days(in: interval, calendar: calendar),
            index: sampleIndex(in: interval),
            calendar: calendar,
            colorForEntry: { $0.listId == "work" ? .orange : .blue },
            canToggle: { $0.type == .task },
            onToggle: { _ in },
            onOpen: { _ in }
        )
        .background(Color(.systemBackground))
    }

    private func timelineView() -> some View {
        let days = [date(17), date(18), date(19)]
        let interval = DateInterval(start: days[0], end: date(20))
        return CalendarTimelineSnapshotHost(
            selectedDate: days[0],
            days: days,
            calendar: calendar,
            index: sampleIndex(in: interval)
        )
    }

    private func yearView() -> some View {
        let interval = CalendarDateMath.yearInterval(containing: date(17), calendar: calendar)
        return CalendarYearView(
            anchor: date(17),
            calendar: calendar,
            index: sampleIndex(in: interval),
            showWeekends: true,
            showWeekNumbers: false,
            tint: .blue,
            colorForEntry: { $0.listId == "work" ? .orange : .blue },
            onSelectMonth: { _ in }
        )
        .background(Color(.systemBackground))
    }

    func testMonthDetails_Light() {
        assertSnapshot(
            of: monthView(),
            as: .image(
                layout: .fixed(width: 393, height: 700),
                traits: SnapshotEnvironment.fixedLightTraits
            )
        )
    }

    func testMonthDetails_Dark() {
        assertSnapshot(
            of: monthView(),
            as: .image(
                layout: .fixed(width: 393, height: 700),
                traits: SnapshotEnvironment.fixedDarkTraits
            )
        )
    }

    func testAgenda_Light() {
        assertSnapshot(
            of: agendaView(),
            as: .image(
                layout: .fixed(width: 393, height: 700),
                traits: SnapshotEnvironment.fixedLightTraits
            )
        )
    }

    func testTwoDayTimeline_Light() {
        assertSnapshot(
            of: timelineView(),
            as: .image(
                layout: .fixed(width: 393, height: 700),
                traits: SnapshotEnvironment.fixedLightTraits
            )
        )
    }

    private func crowdedTimeline(columns: Int) -> some View {
        let days = (15...24).map { date($0) }
        let interval = DateInterval(start: days[0], end: date(25))
        var entries = sampleEntries()
        for number in 1...5 {
            entries.append(entry(title: "All-day planning item \(number) with a longer title", listId: "work",
                start: date(15), end: date(17), allDay: true))
        }
        entries.append(entry(title: "Morning planning", listId: "personal", start: date(15, 9), end: date(15, 10, 30), allDay: false))
        return CalendarTimelineSnapshotHost(selectedDate: days[0], days: days, calendar: calendar,
            index: CalendarEntryIndex(entries: entries, interval: interval, calendar: calendar), columns: columns)
    }

    func testTwoDayTimeline_Dark() {
        assertSnapshot(of: timelineView(), as: .image(layout: .fixed(width: 393, height: 700), traits: SnapshotEnvironment.fixedDarkTraits))
    }

    func testAllDayTimeline_Light() {
        assertSnapshot(of: crowdedTimeline(columns: 2), as: .image(layout: .fixed(width: 393, height: 700), traits: SnapshotEnvironment.fixedLightTraits))
    }

    func testWeekTimeline_Dark() {
        assertSnapshot(of: crowdedTimeline(columns: 7), as: .image(layout: .fixed(width: 1024, height: 768), traits: SnapshotEnvironment.fixedDarkTraits))
    }

    func testWeekTimeline_MonthBoundary_Light() {
        let days = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: date(29))! }
        let interval = DateInterval(start: days[0], end: calendar.date(byAdding: .day, value: 7, to: days[0])!)
        let entries = [
            entry(title: "Conference spanning July and August", listId: "work", start: days[0], end: days[5], allDay: true),
            entry(title: "Design review with the whole team", listId: "personal", start: date(31, 9), end: date(31, 11), allDay: false)
        ]
        let view = CalendarTimelineSnapshotHost(selectedDate: days[0], days: days, calendar: calendar,
            index: CalendarEntryIndex(entries: entries, interval: interval, calendar: calendar), columns: 7)
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 1024, height: 768), traits: SnapshotEnvironment.fixedLightTraits))
    }

    func testTimeline_LargerText() {
        assertSnapshot(of: crowdedTimeline(columns: 2).dynamicTypeSize(.xxxLarge), as: .image(layout: .fixed(width: 393, height: 700), traits: SnapshotEnvironment.fixedLightTraits))
    }

    private func currentTimeView() -> some View {
        ZStack(alignment: .topLeading) {
            Color(.systemBackground)
            Rectangle().fill(Color.primary.opacity(0.17))
                .frame(width: 337, height: 0.5).offset(x: 56, y: 40)
            Text("2pm").font(.caption).foregroundStyle(.secondary)
                .frame(width: 49, height: 18, alignment: .trailing).offset(y: 31)
            CalendarTimelineCurrentTime(date: date(17, 13, 56), calendar: calendar,
                width: 393, column: 0, columnCount: 2)
                .offset(y: 40 - 4.0 / 60 * CalendarTimelineGeometry.hourHeight)
        }
        .environment(\.locale, Locale(identifier: "en_AU"))
        .frame(width: 393, height: 80)
    }

    func testCurrentTime_Light() {
        assertSnapshot(of: currentTimeView(), as: .image(layout: .fixed(width: 393, height: 80), traits: SnapshotEnvironment.fixedLightTraits))
    }

    func testCurrentTime_Dark() {
        assertSnapshot(of: currentTimeView(), as: .image(layout: .fixed(width: 393, height: 80), traits: SnapshotEnvironment.fixedDarkTraits))
    }

    func testYear_Light() {
        assertSnapshot(
            of: yearView(),
            as: .image(
                layout: .fixed(width: 393, height: 700),
                traits: SnapshotEnvironment.fixedLightTraits
            )
        )
    }
}
