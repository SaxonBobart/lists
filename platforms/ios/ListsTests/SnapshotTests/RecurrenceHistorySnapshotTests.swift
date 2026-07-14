import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lists

@MainActor
final class RecurrenceHistorySnapshotTests: XCTestCase {
    private func host(itemId: UUID, store: ItemStore) -> UIHostingController<some View> {
        let view = NavigationStack {
            RecurrenceHistoryView(itemId: itemId, store: store)
        }
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        return controller
    }

    func testHistory_iPhone16_Light() async throws {
        let store = try await TestStore.seeded()
        let missedAt = try XCTUnwrap(ISO8601.date(from: "2026-07-12T09:00:00.000Z"))
        let completedScheduledAt = try XCTUnwrap(
            ISO8601.date(from: "2026-07-13T09:00:00.000Z")
        )
        let completedAt = try XCTUnwrap(ISO8601.date(from: "2026-07-13T09:18:00.000Z"))
        let currentAt = try XCTUnwrap(ISO8601.date(from: "2026-07-14T09:00:00.000Z"))
        let item = Item(
            type: .task,
            title: "Daily planning",
            listId: ItemList.inboxId,
            due: currentAt,
            recurrence: Recurrence(rrule: "FREQ=DAILY"),
            recurrenceOccurrences: [
                RecurrenceOccurrence(scheduledAt: missedAt, status: .missed),
                RecurrenceOccurrence(
                    scheduledAt: completedScheduledAt,
                    status: .completed,
                    completedAt: completedAt
                ),
                RecurrenceOccurrence(scheduledAt: currentAt, status: .open)
            ]
        )
        try await store.add(item)

        assertSnapshot(
            of: host(itemId: item.id, store: store),
            as: .image(
                on: SnapshotEnvironment.iPhone16Light,
                drawHierarchyInKeyWindow: true
            )
        )
    }
}
