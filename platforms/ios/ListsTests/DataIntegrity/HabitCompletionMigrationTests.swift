import Foundation
import Testing
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
struct HabitCompletionMigrationTests {

    // MARK: - Pure migration helper

    @Test func dailyCountMigratesToEventsInTheSameCycle() {
        let day = "2026-05-20"
        let events = HabitCompletion.migrate(legacyLog: [day: 3])

        #expect(events.count == 3, "a count of 3 must become 3 events")
        for event in events {
            #expect(HabitCycle.key(for: .daily, on: event.at) == day,
                    "every synthesized event must fall in its original daily cycle")
        }
    }

    @Test func weeklyCountMigratesToEventsInTheSameCycle() {
        // Use a real week key so the test doesn't hard-code ISO week math.
        let anchor = ISO8601.date(from: "2026-05-20T00:00:00.000Z")!
        let weekKey = HabitCycle.key(for: .weekly, on: anchor)

        let events = HabitCompletion.migrate(legacyLog: [weekKey: 2])

        #expect(events.count == 2)
        for event in events {
            #expect(HabitCycle.key(for: .weekly, on: event.at) == weekKey,
                    "weekly events must regroup into the same ISO-week cycle")
        }
    }

    @Test func monthlyCountMigratesToEventsInTheSameCycle() {
        let monthKey = "2026-03"
        let events = HabitCompletion.migrate(legacyLog: [monthKey: 5])

        #expect(events.count == 5)
        for event in events {
            #expect(HabitCycle.key(for: .monthly, on: event.at) == monthKey)
        }
    }

    @Test func zeroCountProducesNoEvents() {
        let events = HabitCompletion.migrate(legacyLog: ["2026-05-20": 0])
        #expect(events.isEmpty, "a zero count must not synthesize a phantom event")
    }

    @Test func migrationCoversEveryCycleKey() {
        let log = ["2026-05-18": 1, "2026-05-19": 2, "2026-05-20": 1]
        let events = HabitCompletion.migrate(legacyLog: log)
        #expect(events.count == 4, "1 + 2 + 1 events")

        let regrouped = Dictionary(grouping: events, by: { HabitCycle.key(for: .daily, on: $0.at) })
            .mapValues(\.count)
        #expect(regrouped == log, "regrouping events must reproduce the original counts")
    }

    /// A legacy log whose keys don't match the habit's *current* frequency (the
    /// cadence was changed after counts were recorded) must still migrate:
    /// keys are parsed by shape, never dropped silently.
    @Test func mixedShapeKeysAllMigrate() {
        let log = [
            "2025-11-03": 1,          // daily key
            "2025-W46": 2,            // weekly key
            "2025-10": 1,             // monthly key
            "2025-Q2": 1,             // quarterly key
            "2025-H1": 1,             // half-year key
            "2024": 3,                // yearly key
            "2025-11-03T07:00": 1,    // hourly key
        ]
        let events = HabitCompletion.migrate(legacyLog: log)
        #expect(events.count == 10, "every count survives regardless of key shape")
    }

    @Test func historyFromAChangedFrequencySurvives() {
        // Recorded while the habit was weekly; the habit is daily today.
        let anchor = ISO8601.date(from: "2026-05-20T00:00:00.000Z")!
        let weekKey = HabitCycle.key(for: .weekly, on: anchor)

        let events = HabitCompletion.migrate(legacyLog: [weekKey: 2])

        #expect(events.count == 2, "weekly-keyed history must not vanish for a now-daily habit")
        for event in events {
            #expect(HabitCycle.key(for: .weekly, on: event.at) == weekKey,
                    "events still land inside the original week")
        }
    }

    // MARK: - Decode integration (legacy → completions)

    @Test func legacyCompletionLogDecodesIntoCompletions() throws {
        let doc = try legacyHabitDocument(completionLog: ["2026-05-20": 3, "2026-05-19": 1])
        let item = try FrontmatterCodec.decode(doc)

        #expect(item.completions.count == 4, "3 + 1 legacy completions become 4 events")
        #expect(item.completionLog["2026-05-20"] == 3,
                "the computed getter must reconstruct the original daily count")
        #expect(item.completionLog["2026-05-19"] == 1)
    }

    // MARK: - Encode (one-way, never re-writes the legacy key)

    @Test func encodingAHabitWritesCompletionsNotLegacyKey() throws {
        var item = Item(type: .habit, title: "Water", listId: "inbox",
                        frequency: .daily, goalPerCycle: 3)
        item.completions = [HabitCompletion(at: ISO8601.date(from: "2026-05-20T09:14:00.000Z")!)]

        let encoded = try FrontmatterCodec.encode(item)

        #expect(encoded.contains("completions:"),
                "new habits must serialize the timestamped events array")
        #expect(!encoded.contains("completion_log:"),
                "the legacy count key must never be written again")
    }

    @Test func completionsRoundTripExactly() throws {
        var item = Item(type: .habit, title: "Water", listId: "inbox",
                        frequency: .daily, goalPerCycle: 3)
        item.completions = [
            HabitCompletion(at: ISO8601.date(from: "2026-05-20T09:14:00.000Z")!),
            HabitCompletion(at: ISO8601.date(from: "2026-05-20T18:02:00.000Z")!)
        ]

        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))

        #expect(decoded.completions == item.completions,
                "completions must survive an encode/decode round-trip unchanged")
    }

    @Test func migratedHabitDropsLegacyKeyOnReencode() throws {
        // Decode legacy, then re-encode: the file should now be in the new shape.
        let doc = try legacyHabitDocument(completionLog: ["2026-05-20": 2])
        let migrated = try FrontmatterCodec.decode(doc)
        let reencoded = try FrontmatterCodec.encode(migrated)

        #expect(!reencoded.contains("completion_log:"))
        #expect(reencoded.contains("completions:"))
        // And a second decode is stable (idempotent).
        let again = try FrontmatterCodec.decode(reencoded)
        #expect(again.completions.count == 2)
    }

    @Test func malformedCompletionEventIsSkippedNotFatal() throws {
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
            Issue.record("could not find closing frontmatter delimiter")
            return
        }
        let doc = String(encoded[..<closer.lowerBound]) + block + String(encoded[closer.lowerBound...])

        let item = try FrontmatterCodec.decode(doc)
        #expect(item.completions.count == 1,
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
            Issue.record("could not find closing frontmatter delimiter")
            return encoded
        }
        return String(encoded[..<closer.lowerBound]) + block + String(encoded[closer.lowerBound...])
    }
}
