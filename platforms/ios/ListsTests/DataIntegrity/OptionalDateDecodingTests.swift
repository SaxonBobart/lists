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
}
