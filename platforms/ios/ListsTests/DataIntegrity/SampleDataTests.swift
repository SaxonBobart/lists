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
}
