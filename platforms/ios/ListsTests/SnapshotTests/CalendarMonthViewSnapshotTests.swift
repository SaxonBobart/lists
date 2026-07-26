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
}
