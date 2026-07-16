import Testing
@testable import Lists

struct SampleDataTests {
    @Test func seededHabitsDoNotPersistMarkdownBodies() {
        let items = SampleData.seedItems(
            inboxId: ItemList.inboxId,
            now: ISO8601.date(from: "2026-06-23T10:00:00.000Z")!
        )

        let habits = items.filter { $0.type == .habit }

        #expect(!habits.isEmpty)
        #expect(habits.allSatisfy { $0.body.isEmpty })
    }

    @Test func seededContentDoesNotAdvertiseNonCurrentProducts() {
        let items = SampleData.seedItems(
            inboxId: ItemList.inboxId,
            now: ISO8601.date(from: "2026-06-23T10:00:00.000Z")!
        )
        let lists = SampleData.seedLists(
            now: ISO8601.date(from: "2026-06-23T10:00:00.000Z")!
        )
        let visibleSnippets = items.map { "\($0.title)\n\($0.body)" } + lists.map(\.name)
        let visibleContent = visibleSnippets.joined(separator: "\n")

        for nonCurrentTerm in [
            "iCal",
            "sync",
            "shared lists",
            "web companion",
            "AlarmKit",
            "side app",
            "export flow",
            "rebuild cache",
            "sprint 1",
            "design schema",
            "build editor",
            "library rebuild"
        ] {
            #expect(
                !visibleContent.localizedCaseInsensitiveContains(nonCurrentTerm),
                "Seed data should demo current behavior, not advertise non-current product: \(nonCurrentTerm)"
            )
        }
    }

    @Test func seededContentIncludesInspectableRecurrenceHistory() {
        let items = SampleData.seedItems(
            inboxId: ItemList.inboxId,
            now: ISO8601.date(from: "2026-06-23T10:00:00.000Z")!
        )
        let recurringDemos = items.filter { !$0.recurrenceOccurrences.isEmpty }

        #expect(recurringDemos.count >= 2)
        #expect(recurringDemos.allSatisfy {
            $0.recurrence != nil
                && $0.due != nil
                && $0.recurrenceOccurrences.filter { $0.status == .open }.count == 1
        })
        #expect(recurringDemos.contains { item in
            item.recurrenceOccurrences.contains { $0.status == .completed }
                && item.recurrenceOccurrences.contains { $0.status == .missed }
        })
    }
}
