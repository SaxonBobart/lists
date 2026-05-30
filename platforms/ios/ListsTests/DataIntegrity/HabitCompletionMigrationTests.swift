import XCTest
@testable import Lists

/// Habit completions moved from a per-cycle count dictionary
/// (`completion_log: [String: Int]`) to an array of timestamped events
/// (`completions: [HabitCompletion]`). These tests pin:
///   1. the one-way migration of legacy counts into synthesized events, and
///   2. that the legacy `completion_log` key is read on decode but never
///      written again on encode (a clean, idempotent migration).
///
/// The load-bearing invariant: a synthesized event must group back into the
/// SAME cycle key it came from, so the computed `completionLog` getter
/// reconstructs the original counts exactly.
final class HabitCompletionMigrationTests: XCTestCase {

    // MARK: - Pure migration helper

    func testDailyCountMigratesToEventsInTheSameCycle() {
        let day = "2026-05-20"
        let events = HabitCompletion.migrate(legacyLog: [day: 3], frequency: .daily)

        XCTAssertEqual(events.count, 3, "a count of 3 must become 3 events")
        for event in events {
            XCTAssertEqual(HabitCycle.key(for: .daily, on: event.at), day,
                           "every synthesized event must fall in its original daily cycle")
        }
    }

    func testWeeklyCountMigratesToEventsInTheSameCycle() {
        // Use a real week key so the test doesn't hard-code ISO week math.
        let anchor = ISO8601.date(from: "2026-05-20T00:00:00.000Z")!
        let weekKey = HabitCycle.key(for: .weekly, on: anchor)

        let events = HabitCompletion.migrate(legacyLog: [weekKey: 2], frequency: .weekly)

        XCTAssertEqual(events.count, 2)
        for event in events {
            XCTAssertEqual(HabitCycle.key(for: .weekly, on: event.at), weekKey,
                           "weekly events must regroup into the same ISO-week cycle")
        }
    }

    func testMonthlyCountMigratesToEventsInTheSameCycle() {
        let monthKey = "2026-03"
        let events = HabitCompletion.migrate(legacyLog: [monthKey: 5], frequency: .monthly)

        XCTAssertEqual(events.count, 5)
        for event in events {
            XCTAssertEqual(HabitCycle.key(for: .monthly, on: event.at), monthKey)
        }
    }

    func testZeroCountProducesNoEvents() {
        let events = HabitCompletion.migrate(legacyLog: ["2026-05-20": 0], frequency: .daily)
        XCTAssertTrue(events.isEmpty, "a zero count must not synthesize a phantom event")
    }

    func testMigrationCoversEveryCycleKey() {
        let log = ["2026-05-18": 1, "2026-05-19": 2, "2026-05-20": 1]
        let events = HabitCompletion.migrate(legacyLog: log, frequency: .daily)
        XCTAssertEqual(events.count, 4, "1 + 2 + 1 events")

        let regrouped = Dictionary(grouping: events, by: { HabitCycle.key(for: .daily, on: $0.at) })
            .mapValues(\.count)
        XCTAssertEqual(regrouped, log, "regrouping events must reproduce the original counts")
    }

    // MARK: - Decode integration (legacy → completions)

    func testLegacyCompletionLogDecodesIntoCompletions() throws {
        let doc = try legacyHabitDocument(completionLog: ["2026-05-20": 3, "2026-05-19": 1])
        let item = try FrontmatterCodec.decode(doc)

        XCTAssertEqual(item.completions.count, 4, "3 + 1 legacy completions become 4 events")
        XCTAssertEqual(item.completionLog["2026-05-20"], 3,
                       "the computed getter must reconstruct the original daily count")
        XCTAssertEqual(item.completionLog["2026-05-19"], 1)
    }

    // MARK: - Encode (one-way, never re-writes the legacy key)

    func testEncodingAHabitWritesCompletionsNotLegacyKey() throws {
        var item = Item(type: .habit, title: "Water", listId: "inbox",
                        frequency: .daily, goalPerCycle: 3)
        item.completions = [HabitCompletion(at: ISO8601.date(from: "2026-05-20T09:14:00.000Z")!)]

        let encoded = try FrontmatterCodec.encode(item)

        XCTAssertTrue(encoded.contains("completions:"),
                      "new habits must serialize the timestamped events array")
        XCTAssertFalse(encoded.contains("completion_log:"),
                       "the legacy count key must never be written again")
    }

    func testCompletionsRoundTripExactly() throws {
        var item = Item(type: .habit, title: "Water", listId: "inbox",
                        frequency: .daily, goalPerCycle: 3)
        item.completions = [
            HabitCompletion(at: ISO8601.date(from: "2026-05-20T09:14:00.000Z")!),
            HabitCompletion(at: ISO8601.date(from: "2026-05-20T18:02:00.000Z")!)
        ]

        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))

        XCTAssertEqual(decoded.completions, item.completions,
                       "completions must survive an encode/decode round-trip unchanged")
    }

    func testMigratedHabitDropsLegacyKeyOnReencode() throws {
        // Decode legacy, then re-encode: the file should now be in the new shape.
        let doc = try legacyHabitDocument(completionLog: ["2026-05-20": 2])
        let migrated = try FrontmatterCodec.decode(doc)
        let reencoded = try FrontmatterCodec.encode(migrated)

        XCTAssertFalse(reencoded.contains("completion_log:"))
        XCTAssertTrue(reencoded.contains("completions:"))
        // And a second decode is stable (idempotent).
        let again = try FrontmatterCodec.decode(reencoded)
        XCTAssertEqual(again.completions.count, 2)
    }

    func testMalformedCompletionEventIsSkippedNotFatal() throws {
        // DI posture: one corrupted event must be skipped, not abort the whole
        // habit (losing one log entry beats quarantining the file).
        let base = Item(type: .habit, title: "Water", listId: "inbox",
                        frequency: .daily, goalPerCycle: 3)
        let encoded = try FrontmatterCodec.encode(base)
        let block = "completions:\n"
            + "  - id: \(UUID().uuidString)\n"
            + "    at: 2026-05-20T09:14:00.000Z\n"
            + "  - id: \(UUID().uuidString)\n"
            + "    at: not-a-real-date\n"
        guard let closer = encoded.range(of: "---\n", options: .backwards) else {
            XCTFail("could not find closing frontmatter delimiter"); return
        }
        let doc = String(encoded[..<closer.lowerBound]) + block + String(encoded[closer.lowerBound...])

        let item = try FrontmatterCodec.decode(doc)
        XCTAssertEqual(item.completions.count, 1,
                       "the valid event survives; the malformed one is dropped")
    }

    // MARK: - Helpers

    /// Build a legacy on-disk document: a valid new-format habit frontmatter
    /// with a hand-injected `completion_log:` block (and no `completions:`),
    /// exactly as a file written by the old encoder would look.
    private func legacyHabitDocument(
        completionLog: [String: Int],
        frequency: HabitFrequency = .daily
    ) throws -> String {
        let base = Item(type: .habit, title: "Water", listId: "inbox",
                        frequency: frequency, goalPerCycle: 3)
        let encoded = try FrontmatterCodec.encode(base) // empty completions are omitted

        var block = "completion_log:\n"
        for (key, value) in completionLog.sorted(by: { $0.key < $1.key }) {
            block += "  \"\(key)\": \(value)\n"
        }

        // Inject before the closing frontmatter delimiter.
        guard let closer = encoded.range(of: "---\n", options: .backwards) else {
            XCTFail("could not find closing frontmatter delimiter")
            return encoded
        }
        return String(encoded[..<closer.lowerBound]) + block + String(encoded[closer.lowerBound...])
    }
}
