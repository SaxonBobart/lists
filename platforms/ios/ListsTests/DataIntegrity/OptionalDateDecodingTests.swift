import XCTest
@testable import Lists

/// DI-3: an optional date that is *present but unparseable* must fail safe.
/// Previously a garbage `deleted_at`/`due`/`completed_at` mapped to nil — which
/// silently dropped the value (and, for `deleted_at`, resurrected a deleted
/// item). Now it throws, so DI-1's per-file quarantine catches the file and the
/// item stays out of the live set. An *absent* optional date still means nil.
final class OptionalDateDecodingTests: XCTestCase {

    /// Valid item frontmatter (with due/completed_at/deleted_at all set), then
    /// the named date field's value replaced with garbage.
    private func itemFrontmatter(corrupting key: String) throws -> String {
        var item = Item(type: .task, title: "X", listId: "l1")
        item.due = .now
        item.completedAt = .now
        item.deletedAt = .now
        let encoded = try FrontmatterCodec.encode(item)
        return encoded.replacingOccurrences(
            of: "(?m)^\(key): .*$", with: "\(key): not-a-real-date",
            options: .regularExpression)
    }

    func testGarbageDueThrows() throws {
        XCTAssertThrowsError(try FrontmatterCodec.decode(itemFrontmatter(corrupting: "due")))
    }

    func testGarbageCompletedAtThrows() throws {
        XCTAssertThrowsError(try FrontmatterCodec.decode(itemFrontmatter(corrupting: "completed_at")))
    }

    func testGarbageDeletedAtThrows() throws {
        XCTAssertThrowsError(try FrontmatterCodec.decode(itemFrontmatter(corrupting: "deleted_at")))
    }

    func testAbsentOptionalDatesStillDecodeAsNil() throws {
        // A plain item has no due/completed_at/deleted_at — absence is fine.
        let item = try FrontmatterCodec.decode(
            FrontmatterCodec.encode(Item(type: .task, title: "X", listId: "l1")))
        XCTAssertNil(item.due)
        XCTAssertNil(item.completedAt)
        XCTAssertNil(item.deletedAt)
    }

    /// Integration with DI-1: a list whose `deleted_at` is corrupt on disk is
    /// quarantined rather than silently resurrected into the live set.
    func testListWithGarbageDeletedAtIsQuarantined() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsDI3-\(UUID().uuidString)")
        let store = FileStore(root: root)
        try await store.ensureRoot()
        try await store.writeList(ItemList(id: "l1", name: "Work", icon: "tray", color: .blue,
                                           createdAt: .now, modifiedAt: .now, position: 0,
                                           deletedAt: .now))
        let listFile = try await store.listDirectory(for: "l1").appendingPathComponent(".list.yml")
        let corrupted = try String(contentsOf: listFile, encoding: .utf8)
            .replacingOccurrences(of: "(?m)^deleted_at: .*$",
                                  with: "deleted_at: not-a-real-date",
                                  options: .regularExpression)
        try corrupted.write(to: listFile, atomically: true, encoding: .utf8)

        let result = try await store.loadAll()

        XCTAssertEqual(result.quarantined.count, 1)
        XCTAssertFalse(result.lists.contains { $0.list.id == "l1" })
    }

    // MARK: - MODEL-ALLDAY-1: all-day dates are calendar days, not instants

    func testAllDayDueEncodesAsDayStringAndRoundTripsTheSameDay() throws {
        var item = Item(type: .task, title: "Birthday", listId: "l1")
        item.dueAllDay = true
        item.due = Calendar.current.startOfDay(for: .now)

        let encoded = try FrontmatterCodec.encode(item)
        let dayString = ISO8601.localDayString(from: item.due!)
        let dueLine = encoded.split(separator: "\n").first { $0.hasPrefix("due:") }.map(String.init)
        XCTAssertNotNil(dueLine)
        XCTAssertTrue(dueLine?.contains(dayString) ?? false,
                      "an all-day due is written as a bare yyyy-MM-dd day")
        XCTAssertFalse(dueLine?.contains("T") ?? true,
                       "no timestamp tail on the due line — day-only encoding is real now")

        let decoded = try FrontmatterCodec.decode(encoded)
        XCTAssertTrue(Calendar.current.isDate(try XCTUnwrap(decoded.due),
                                              inSameDayAs: item.due!),
                      "reload lands on the same local calendar day — no off-by-one drift")
        XCTAssertTrue(decoded.dueAllDay)
    }

    func testTimedDueStillRoundTripsAsAnExactInstant() throws {
        var item = Item(type: .task, title: "Call", listId: "l1")
        item.due = ISO8601.date(from: "2026-06-12T09:30:00.000Z")
        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))
        XCTAssertEqual(decoded.due, item.due, "timed dues are exact instants, unchanged")
    }

    // MARK: - MODEL-TYPEFLIP-1: habit history survives a type flip

    func testCompletionsSurviveEncodeAfterTypeFlip() throws {
        var habit = Item(type: .habit, title: "Stretch", listId: "l1",
                         frequency: .daily, goalPerCycle: 1)
        habit.completions = [
            HabitCompletion(at: ISO8601.date(from: "2026-05-20T09:00:00.000Z")!),
            HabitCompletion(at: ISO8601.date(from: "2026-05-21T09:00:00.000Z")!),
        ]
        habit.type = .task   // a future convert-to-task path

        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(habit))
        XCTAssertEqual(decoded.completions.count, 2,
                       "months of habit history must not be stripped by a type flip's next save")
    }

    // MARK: - FM-1: a body containing a `---` line survives the round-trip

    func testBodyWithHorizontalRuleRoundTrips() throws {
        var item = Item(type: .note, title: "Doc", listId: "l1")
        item.body = "intro\n\n---\n\noutro"
        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))
        // The codec normalizes a trailing newline onto the body; tolerate that,
        // but any mis-split at the --- would still drop `outro` and fail here.
        XCTAssertEqual(decoded.body.trimmingCharacters(in: .newlines), item.body,
                       "a column-0 --- in the body must not be mistaken for the frontmatter closer")
    }
}
