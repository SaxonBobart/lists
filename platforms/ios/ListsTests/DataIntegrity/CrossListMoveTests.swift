import XCTest
@testable import Lists

/// DI-2: changing an item's `listId` must delete the stale file in the old
/// list's folder, so a reload can never read two copies (the "zombie that
/// reappears after you delete one" bug).
@MainActor
final class CrossListMoveTests: XCTestCase {

    private func freshRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsMove-\(UUID().uuidString)")
    }

    private func makeList(id: String, name: String) -> ItemList {
        ItemList(id: id, name: name, icon: "tray", color: .blue,
                 createdAt: .now, modifiedAt: .now, position: 0)
    }

    /// Returns a bootstrapped store over a root seeded with lists Alpha(A) and
    /// Bravo(B) plus one task in A, and the on-disk URLs for both folders.
    private func seededStore() async throws -> (store: ItemStore, item: Item, aFile: URL, bFile: URL) {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))
        let item = Item(type: .task, title: "Movable", listId: "A")
        try await setup.writeItem(item)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let fileName = "\(item.id.uuidString).md"
        return (store, item,
                root.appendingPathComponent("Alpha").appendingPathComponent(fileName),
                root.appendingPathComponent("Bravo").appendingPathComponent(fileName))
    }

    func testMoveDeletesOldFileAndReloadsOnce() async throws {
        let (store, item, aFile, bFile) = try await seededStore()

        var moved = try XCTUnwrap(store.items.first { $0.id == item.id })
        moved.listId = "B"
        try await store.update(moved)

        XCTAssertFalse(FileManager.default.fileExists(atPath: aFile.path), "old file removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bFile.path), "new file written")

        // A cold reload sees exactly one copy, in the new list.
        let reload = try await FileStore(root: aFile.deletingLastPathComponent().deletingLastPathComponent())
            .loadAll()
        let matches = reload.lists.flatMap(\.items).filter { $0.id == item.id }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.listId, "B")
    }

    func testUpdateWithoutListChangeKeepsSingleFile() async throws {
        let (store, item, aFile, bFile) = try await seededStore()

        var edited = try XCTUnwrap(store.items.first { $0.id == item.id })
        edited.title = "Renamed"
        try await store.update(edited)

        XCTAssertTrue(FileManager.default.fileExists(atPath: aFile.path), "stays in A")
        XCTAssertFalse(FileManager.default.fileExists(atPath: bFile.path))
    }

    func testApplyUpdateSyncMoveDeletesOldFile() async throws {
        let (store, item, aFile, bFile) = try await seededStore()

        var moved = try XCTUnwrap(store.items.first { $0.id == item.id })
        moved.listId = "B"
        store.applyUpdateSync(moved)

        // applyUpdateSync persists on a detached Task; poll for the result.
        for _ in 0..<60 where FileManager.default.fileExists(atPath: aFile.path) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: aFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bFile.path))
    }
}
