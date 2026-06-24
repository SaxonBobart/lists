import Foundation
import Testing
@testable import Lists

/// `type:` decoding must be permissive. An unknown value — a future type, or a
/// corrupted field — must NOT throw. It falls back to `.task` so one stray value
/// can never abort the whole-library load. Known values must still round-trip
/// exactly.
struct ItemTypeDecodingTests {

    /// A valid frontmatter document with its `type:` value swapped for `typeRaw`.
    /// Encoding a real item first means every other field (esp. the date format)
    /// is genuine, so the test varies only `type`.
    private func frontmatter(typeRaw: String) throws -> String {
        let item = Item(type: .task, title: "Sample", listId: "inbox")
        let encoded = try FrontmatterCodec.encode(item)
        return encoded.replacingOccurrences(of: "type: task", with: "type: \(typeRaw)")
    }

    @Test func unknownTypeFallsBackToTask() throws {
        let decoded = try FrontmatterCodec.decode(frontmatter(typeRaw: "question"))
        #expect(decoded.type == .task,
                "An unknown `type:` must decode as .task, not throw or vanish")
    }

    @Test func knownTypesPreservedExactly() throws {
        for type in Item.ItemType.allCases {
            let item = Item(type: type, title: "X", listId: "inbox")
            let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))
            #expect(decoded.type == type, "Known type \(type) must round-trip unchanged")
        }
    }

    // MARK: - Event fields (start + end; completable opt-in)

    @Test func eventFieldsRoundTrip() throws {
        var event = Item(type: .event, title: "Dinner", listId: "inbox")
        event.due = ISO8601.date(from: "2026-06-12T18:00:00.000Z")
        event.end = ISO8601.date(from: "2026-06-12T20:30:00.000Z")

        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(event))

        #expect(decoded.type == .event)
        #expect(decoded.due == event.due, "due is the event's start")
        #expect(decoded.end == event.end)
        #expect(!decoded.completable, "events default to non-completable")
    }

    @Test func completableEventRoundTripsDoneState() throws {
        var event = Item(type: .event, title: "Pick up cake", listId: "inbox",
                         done: true, completable: true)
        event.due = ISO8601.date(from: "2026-06-12T14:00:00.000Z")

        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(event))

        #expect(decoded.completable)
        #expect(decoded.done)
        #expect(decoded.isComplete, "a ticked completable event reads as complete")
    }

    /// Codec backward-compat: an event with nil `end` encodes without an `end:` field
    /// and decodes back to nil. The app always seeds an end in the UI; this test
    /// verifies the codec layer handles a nil end cleanly without crashing or
    /// writing junk.
    @Test func eventWithMissingEndOmitsEndFieldOnDisk() throws {
        var event = Item(type: .event, title: "Dentist", listId: "inbox")
        event.due = ISO8601.date(from: "2026-06-12T15:00:00.000Z")

        let encoded = try FrontmatterCodec.encode(event)

        #expect(!encoded.contains("end:"), "a nil end must not write an end: field")
        #expect(try FrontmatterCodec.decode(encoded).end == nil)
    }

    @Test func pastNonCompletableEventIsNeverComplete() {
        var event = Item(type: .event, title: "Birthday dinner", listId: "inbox")
        event.due = Date(timeIntervalSinceNow: -86_400)
        #expect(!event.isComplete, "a passed event isn't 'completed' — it's just past")
    }

    @Test func overdueMeansPastUnfinishedActionableWork() {
        let now = ISO8601.date(from: "2026-06-23T12:00:00.000Z")!
        let yesterday = ISO8601.date(from: "2026-06-22T09:00:00.000Z")!

        let task = Item(type: .task, title: "Task", listId: "inbox", due: yesterday)
        let doneTask = Item(type: .task, title: "Done", listId: "inbox", done: true, due: yesterday)
        let calendarEvent = Item(
            type: .event,
            title: "Past event",
            listId: "inbox",
            due: yesterday,
            end: yesterday.addingTimeInterval(3_600)
        )
        let completableEvent = Item(
            type: .event,
            title: "Pick up cake",
            listId: "inbox",
            due: yesterday,
            end: yesterday.addingTimeInterval(3_600),
            completable: true
        )
        let habit = Item(
            type: .habit,
            title: "Hydrate",
            listId: "inbox",
            due: yesterday,
            frequency: .daily
        )

        #expect(task.isOverdue(now: now))
        #expect(!doneTask.isOverdue(now: now))
        #expect(!calendarEvent.isOverdue(now: now))
        #expect(completableEvent.isOverdue(now: now))
        #expect(!habit.isOverdue(now: now), "habit dates drive reminders, not overdue pressure")
    }
}
