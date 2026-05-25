import XCTest
@testable import Lists

/// DI-1 core: loading is per-file resilient. A single corrupt/truncated/unknown
/// file is quarantined (moved aside, never dropped), the rest of the library
/// always loads, and `loadAll()` reports what was set aside. Folds in AGENT-2
/// (skip `_`-prefixed aux files).
final class FileStoreQuarantineTests: XCTestCase {

    private func makeStore() -> (FileStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsQuarantine-\(UUID().uuidString)")
        return (FileStore(root: root), root)
    }

    private func makeList(id: String, name: String, parentId: String? = nil) -> ItemList {
        ItemList(id: id, name: name, icon: "tray", color: .blue,
                 createdAt: .now, modifiedAt: .now, position: 0, parentId: parentId)
    }

    override func tearDownWithError() throws {
        // best-effort temp cleanup handled by the OS; nothing required here
    }

    func testBadItemQuarantinedAndRestStillLoads() async throws {
        let (store, root) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "l1", name: "Work"))
        try await store.writeItem(Item(type: .task, title: "Keep me", listId: "l1"))

        // A .md with no frontmatter — FrontmatterCodec.decode throws on it.
        let dir = try await store.listDirectory(for: "l1")
        let badURL = dir.appendingPathComponent("\(UUID().uuidString).md")
        try "this is not frontmatter".write(to: badURL, atomically: true, encoding: .utf8)

        let result = try await store.loadAll()

        XCTAssertEqual(result.lists.count, 1)
        XCTAssertEqual(result.lists.first?.items.map(\.title), ["Keep me"])
        XCTAssertEqual(result.quarantined.count, 1)
        XCTAssertEqual(result.quarantined.first?.originalPath, badURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: badURL.path),
                       "the bad file must be moved out of the live tree")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".quarantine").path))
    }

    func testUnknownTypeLoadsButMissingRequiredKeyIsQuarantined() async throws {
        let (store, _) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "l1", name: "Work"))
        let dir = try await store.listDirectory(for: "l1")

        // unknown type → loads as .task (1a), NOT quarantined
        let future = try FrontmatterCodec.encode(Item(type: .task, title: "Future", listId: "l1"))
            .replacingOccurrences(of: "type: task", with: "type: question")
        try future.write(to: dir.appendingPathComponent("\(UUID().uuidString).md"),
                         atomically: true, encoding: .utf8)

        // missing required `id` → quarantined
        let noIdItem = Item(type: .task, title: "NoId", listId: "l1")
        let noId = try FrontmatterCodec.encode(noIdItem)
            .replacingOccurrences(of: "id: \(noIdItem.id.uuidString)\n", with: "")
        try noId.write(to: dir.appendingPathComponent("\(UUID().uuidString).md"),
                       atomically: true, encoding: .utf8)

        let result = try await store.loadAll()

        XCTAssertEqual(result.lists.first?.items.map(\.title), ["Future"],
                       "unknown-type item loads as a task; the id-less item is quarantined")
        XCTAssertEqual(result.lists.first?.items.first?.type, .task)
        XCTAssertEqual(result.quarantined.count, 1)
    }

    func testUnderscorePrefixedFilesAreIgnored() async throws {
        let (store, _) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "l1", name: "Work"))
        try await store.writeItem(Item(type: .task, title: "Real", listId: "l1"))

        let dir = try await store.listDirectory(for: "l1")
        try "not an item, just a heartbeat".write(
            to: dir.appendingPathComponent("_status.md"), atomically: true, encoding: .utf8)

        let result = try await store.loadAll()

        XCTAssertEqual(result.lists.first?.items.map(\.title), ["Real"])
        XCTAssertTrue(result.quarantined.isEmpty, "a _-prefixed file is ignored, not quarantined")
    }

    func testCorruptParentListHeaderKeepsNestedChild() async throws {
        let (store, _) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "p", name: "Parent"))
        try await store.writeList(makeList(id: "c", name: "Child", parentId: "p"))

        // Corrupt the parent's .list.yml; the child folder is nested under it.
        let parentDir = try await store.listDirectory(for: "p")
        try "garbage: [unterminated".write(
            to: parentDir.appendingPathComponent(".list.yml"), atomically: true, encoding: .utf8)

        let result = try await store.loadAll()

        XCTAssertTrue(result.lists.contains { $0.list.id == "c" }, "nested child still loads")
        XCTAssertFalse(result.lists.contains { $0.list.id == "p" }, "corrupt parent is dropped")
        XCTAssertEqual(result.quarantined.count, 1)
    }

    func testValidLibraryHasNoQuarantine() async throws {
        let (store, root) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "l1", name: "Work"))
        try await store.writeItem(Item(type: .task, title: "A", listId: "l1"))
        try await store.writeItem(Item(type: .note, title: "B", listId: "l1"))

        let result = try await store.loadAll()

        XCTAssertEqual(result.lists.first?.items.count, 2)
        XCTAssertTrue(result.quarantined.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".quarantine").path),
            "a fully-valid library must not create a .quarantine folder")
    }
}
