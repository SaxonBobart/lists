import Foundation
import Testing
@testable import Lists

struct ItemDescriptionTests {
    private func request(_ type: Item.ItemType = .task) -> ItemDescriptionRequest {
        .init(description: "Wash Penny tomorrow at 9", seed: Item(type: type, title: "Wash Penny tomorrow at 9", listId: ItemList.inboxId),
              destinations: [], referenceDate: Date(timeIntervalSince1970: 1_789_171_200),
              localeIdentifier: "en_AU", timeZoneIdentifier: "Australia/Brisbane")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LISTS_LIVE_DESCRIPTION_QA"] == "1"),
          arguments: ["House Cleaning tommorrow 9am", "House Cleaning tomorrow 9am", "House Cleaning tomorrow at 9 am"])
    func liveHouseCleaningDescription(description: String) async throws {
        var input = request()
        input.description = description
        input.seed.title = input.description
        input.referenceDate = .now
        let output = try await FoundationItemDescriptionInterpreter().extract(input)
        #expect(output.item.title.lowercased() == "house cleaning")
        let due = try #require(output.item.due)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: input.timeZoneIdentifier)!
        #expect(calendar.isDate(due, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: input.referenceDate)!))
        #expect(calendar.component(.hour, from: due) == 9)
    }

    @Test func unrequestedModelDefaultsCannotClearProperties() throws {
        var input = request()
        input.seed.flagged = true
        input.seed.tags = ["pets"]
        let properties = ItemDescriptionProperties(requestedFields: [.title], title: "Wash Penny",
            earlyReminder: .init(value: 0, unit: .hour), flagged: false, tags: [], listName: "", completable: false)
        let output = try ItemDescriptionNormalizer.normalize(properties, request: input)
        #expect(output.item.flagged)
        #expect(output.item.tags == ["pets"])
        #expect(output.item.listId == input.seed.listId)
        #expect(output.item.reminder == nil)
    }

    @Test func omittedPropertiesPreserveSeed() throws {
        var input = request()
        input.seed.flagged = true
        input.seed.tags = ["pets"]
        let output = try ItemDescriptionNormalizer.normalize(.init(title: "Wash Penny"), request: input)
        #expect(output.item.id == input.seed.id)
        #expect(output.item.flagged)
        #expect(output.item.tags == ["pets"])
        #expect(output.item.due == nil)
    }

    @Test func exactDateAndTime() throws {
        let output = try ItemDescriptionNormalizer.normalize(
            .init(title: "Wash Penny", schedule: .init(startDate: "2026-09-16", startTime: "09:00")), request: request())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: output.item.due!)
        #expect(components.year == 2026 && components.month == 9 && components.day == 16 && components.hour == 9)
        #expect(output.item.reminder == nil)
        #expect(output.item.triggers?.alarm == nil)
    }

    @Test func invalidDateIsRejected() {
        #expect(throws: ItemDescriptionInterpretationError.self) {
            try ItemDescriptionNormalizer.normalize(.init(schedule: .init(startDate: "2026-02-30")), request: request())
        }
    }

    @Test func allDayEventEndIsExclusive() throws {
        let output = try ItemDescriptionNormalizer.normalize(
            .init(schedule: .init(startDate: "2026-09-16", endDate: "2026-09-17", allDay: true)), request: request(.event))
        #expect(output.item.end!.timeIntervalSince(output.item.due!) == 172_800)
    }

    @Test func unknownDestinationIsRejected() {
        #expect(throws: ItemDescriptionInterpretationError.self) {
            try ItemDescriptionNormalizer.normalize(.init(listName: "Invented"), request: request())
        }
    }

    @Test func manualFieldsWinAndIdentityRemains() {
        var current = request().seed
        current.flagged = true
        var proposal = Item(type: .event, title: "Proposal", listId: ItemList.inboxId)
        proposal.flagged = false
        let merged = ItemDescriptionMerge.applying(.init(item: proposal, fields: [.title, .flagged]),
                                                   to: current, lockedFields: [.flagged])
        #expect(merged.flagged)
        #expect(merged.title == "Proposal")
        #expect(merged.id == current.id)
        #expect(merged.type == .task)
    }

    @Test @MainActor func unavailableModelAllowsManualEntry() async {
        let session = ItemDescriptionSession(interpreter: UnavailableInterpreter())
        let result = await session.resolve(request())
        #expect(result == nil)
        #expect(!session.isAnalyzing)
        #expect(session.statusMessage != nil)
    }

    @Test @MainActor func canceledRequestCannotApply() async throws {
        let session = ItemDescriptionSession(interpreter: SlowInterpreter(), debounce: .zero)
        var applied = false
        session.schedule(request()) { _ in applied = true }
        session.cancel()
        try await Task.sleep(for: .milliseconds(30))
        #expect(!applied)
        #expect(!session.isAnalyzing)
    }

    @Test @MainActor func deadlineAllowsManualFallback() async {
        let session = ItemDescriptionSession(interpreter: SlowInterpreter(), timeout: .milliseconds(1))
        let result = await session.resolve(request())
        #expect(result == nil)
        #expect(!session.isAnalyzing)
        #expect(session.statusMessage != nil)
    }
}

private struct UnavailableInterpreter: ItemDescriptionInterpreting {
    func availability(locale: Locale) -> ItemDescriptionAvailability { .unavailable("Unavailable") }
    func extract(_ request: ItemDescriptionRequest) async throws -> ItemDescriptionExtraction {
        throw CancellationError()
    }
}
private struct SlowInterpreter: ItemDescriptionInterpreting {
    func availability(locale: Locale) -> ItemDescriptionAvailability { .available }
    func extract(_ request: ItemDescriptionRequest) async throws -> ItemDescriptionExtraction {
        try await Task.sleep(for: .milliseconds(100))
        return .init(item: request.seed, fields: [])
    }
}
