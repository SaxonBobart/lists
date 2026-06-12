import XCTest
@testable import Lists

/// DI-1 (folds in AGENT-1): `type:` decoding must be permissive. An unknown
/// value — a future type, or a corrupted field — must NOT throw. It falls back
/// to `.task` so one stray value can never abort the whole-library load. Known
/// values must still round-trip exactly.
final class ItemTypeDecodingTests: XCTestCase {

    /// A valid frontmatter document with its `type:` value swapped for `typeRaw`.
    /// Encoding a real item first means every other field (esp. the date format)
    /// is genuine, so the test varies only `type`.
    private func frontmatter(typeRaw: String) throws -> String {
        let item = Item(type: .task, title: "Sample", listId: "inbox")
        let encoded = try FrontmatterCodec.encode(item)
        return encoded.replacingOccurrences(of: "type: task", with: "type: \(typeRaw)")
    }

    func testUnknownTypeFallsBackToTask() throws {
        let decoded = try FrontmatterCodec.decode(frontmatter(typeRaw: "question"))
        XCTAssertEqual(decoded.type, .task,
                       "An unknown `type:` must decode as .task, not throw or vanish")
    }

    func testKnownTypesPreservedExactly() throws {
        for type in Item.ItemType.allCases {
            let item = Item(type: type, title: "X", listId: "inbox")
            let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))
            XCTAssertEqual(decoded.type, type, "Known type \(type) must round-trip unchanged")
        }
    }

    // MARK: - Event fields (start + end; completable opt-in)

    func testEventFieldsRoundTrip() throws {
        var event = Item(type: .event, title: "Dinner", listId: "inbox")
        event.due = ISO8601.date(from: "2026-06-12T18:00:00.000Z")
        event.end = ISO8601.date(from: "2026-06-12T20:30:00.000Z")

        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(event))

        XCTAssertEqual(decoded.type, .event)
        XCTAssertEqual(decoded.due, event.due, "due is the event's start")
        XCTAssertEqual(decoded.end, event.end)
        XCTAssertFalse(decoded.completable, "events default to non-completable")
    }

    func testCompletableEventRoundTripsDoneState() throws {
        var event = Item(type: .event, title: "Pick up cake", listId: "inbox",
                         done: true, completable: true)
        event.due = ISO8601.date(from: "2026-06-12T14:00:00.000Z")

        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(event))

        XCTAssertTrue(decoded.completable)
        XCTAssertTrue(decoded.done)
        XCTAssertTrue(decoded.isComplete, "a ticked completable event reads as complete")
    }

    /// Codec backward-compat: an event with nil `end` encodes without an `end:` field
    /// and decodes back to nil — the file format tolerates a missing end (older files,
    /// iCal round-trips). The app always seeds an end in the UI; this test verifies
    /// the codec layer handles a nil end cleanly without crashing or writing junk.
    func testEventWithMissingEndOmitsEndFieldOnDisk() throws {
        var event = Item(type: .event, title: "Dentist", listId: "inbox")
        event.due = ISO8601.date(from: "2026-06-12T15:00:00.000Z")

        let encoded = try FrontmatterCodec.encode(event)

        XCTAssertFalse(encoded.contains("end:"), "a nil end must not write an end: field")
        XCTAssertNil(try FrontmatterCodec.decode(encoded).end)
    }

    func testPastNonCompletableEventIsNeverComplete() {
        var event = Item(type: .event, title: "Birthday dinner", listId: "inbox")
        event.due = Date(timeIntervalSinceNow: -86_400)
        XCTAssertFalse(event.isComplete, "a passed event isn't 'completed' — it's just past")
    }
}
