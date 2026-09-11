import SwiftUI
import SnapshotTesting
import XCTest
@testable import Lists

@MainActor final class ItemEditingSnapshotTests: XCTestCase {

    private var day: Date { Calendar.current.date(from: DateComponents(year: 2024, month: 7, day: 17))! }
    private func entry(_ title: String, type: Item.ItemType, hour: Double) -> CalendarEntry {
        let id = UUID()
        let start = day.addingTimeInterval(hour * 3600)
        return CalendarEntry(id: .init(itemId: id, source: .current, scheduledAt: start, occurrenceId: nil),
            itemId: id, title: title, type: type, listId: "inbox", section: nil, start: start,
            end: type == .event ? start.addingTimeInterval(3600) : start, isAllDay: false, status: .open,
            isCompletable: type == .task, priority: .high, flagged: true, hasRecurrence: true,
            reminderEnabled: true, alarmEnabled: true)
    }
    private func cards(width: CGFloat, larger: Bool = false) -> some View {
        let event = entry("Design review", type: .event, hour: 9)
        let task = entry("Prepare review notes", type: .task, hour: 9)
        let index = CalendarEntryIndex(entries: [event, task], interval: DateInterval(start: day, duration: 86400), calendar: .current)
        let targets = CalendarTimelineGeometry.targets(days: [day], index: index, width: width, calendar: .current, markerHeight: larger ? 88 : 44)
        return VStack(spacing: 20) {
            CalendarTimelineCanvas(days: [day], targets: targets, preview: nil,
                selection: targets.first(where: { $0.entry.type == .event })?.id,
                width: width, calendar: .current, tint: .blue, color: { _ in .blue },
                onOpen: { _ in }, onDuplicate: { _ in }, onAccessibleMove: { _, _ in }, onAccessibleResize: { _, _, _ in })
                .offset(y: -CalendarTimelineGeometry.y(minute: 8 * 60))
                .frame(height: larger ? 300 : 220, alignment: .top).clipped()
            CalendarAgendaEntryRow(entry: event, color: .blue, canToggle: false, onToggle: {}, onOpen: {}, onDuplicate: {})
                .padding(.horizontal, 16)
            CalendarAgendaEntryRow(entry: task, color: .blue, canToggle: true, onToggle: {}, onOpen: {}, onDuplicate: {})
                .padding(.horizontal, 16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .dynamicTypeSize(larger ? .accessibility1 : .large)
    }
    func testSelectedEventAndTimedTask_Narrow() {
        assertSnapshot(of: cards(width: 393), as: .image(layout: .fixed(width: 393, height: 450), traits: SnapshotEnvironment.fixedDarkTraits))
    }
    func testSelectedEventAndTimedTask_Wide() {
        assertSnapshot(of: cards(width: 768), as: .image(layout: .fixed(width: 768, height: 450), traits: SnapshotEnvironment.fixedLightTraits))
    }
    func testSelectedEventAndTimedTask_Accessibility() {
        assertSnapshot(of: cards(width: 393, larger: true), as: .image(layout: .fixed(width: 393, height: 700), traits: SnapshotEnvironment.fixedDarkTraits))
    }
    func testPasteDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PasteSnapshot-\(UUID())")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        let source = Item(type: .event, title: "Design review", body: "Meeting notes", listId: ItemList.inboxId,
            tags: ["work"], due: day.addingTimeInterval(9 * 3600), end: day.addingTimeInterval(10 * 3600),
            priority: .high, flagged: true, reminder: .init(enabled: true, early: .init(value: 10, unit: .minute)), recurrence: .init(rrule: "FREQ=WEEKLY"))
        try await ItemClipboard.shared.copy(source, store: store)
        let view = QuickCaptureSheet(store: store, defaultListId: ItemList.inboxId,
            initialSchedule: .init(start: day.addingTimeInterval(14 * 3600), isAllDay: false), pasteOnOpen: true)
        assertSnapshot(of: view, as: .image(drawHierarchyInKeyWindow: true, layout: .fixed(width: 393, height: 852), traits: SnapshotEnvironment.fixedDarkTraits))
    }

}
