import SwiftUI

struct DocumentRecurrenceHistoryCard: View {
    let itemId: UUID
    let store: ItemStore

    var body: some View {
        Section("History") {
            NavigationLink {
                RecurrenceHistoryView(itemId: itemId, store: store)
            } label: {
                DetailFormDisclosureRowLabel(
                    title: "Completion History",
                    value: historySummary,
                    systemImage: "clock.arrow.circlepath"
                )
            }
            .accessibilityIdentifier("document.recurrence.history")
        }
    }

    private var historySummary: String {
        guard let item = store.item(itemId) else { return "Unavailable" }
        let count = item.recurrenceOccurrences.lazy.filter { $0.status != .open }.count
        if count == 0 { return "No past occurrences" }
        return "\(count) \(count == 1 ? "occurrence" : "occurrences")"
    }
}
