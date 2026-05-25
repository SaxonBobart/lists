import XCTest
@testable import Lists

/// DI-1 (1c): bootstrap must never leave the app wedged on "Loading…", must
/// surface quarantined files, and must not re-seed sample data on top of a
/// library that loaded partially.
@MainActor
final class BootstrapResilienceTests: XCTestCase {

    private func freshRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsBootstrap-\(UUID().uuidString)")
    }

    func testCorruptFileIsSurfacedAndDoesNotReSeed() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(ItemList(id: "l1", name: "Work", icon: "tray", color: .blue,
                                           createdAt: .now, modifiedAt: .now, position: 0))
        try await setup.writeItem(Item(type: .task, title: "good", listId: "l1"))
        let dir = try await setup.listDirectory(for: "l1")
        try "broken".write(to: dir.appendingPathComponent("\(UUID().uuidString).md"),
                           atomically: true, encoding: .utf8)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        XCTAssertTrue(store.isLoaded, "isLoaded must be set even with a partial failure")
        XCTAssertEqual(store.loadIssues.count, 1)
        XCTAssertEqual(store.items.map(\.title), ["good"])
        XCTAssertEqual(store.lists.map(\.id), ["l1"],
                       "a quarantine-only / non-empty load must not re-seed sample data")
    }

    func testEmptyRootStillSeeds() async throws {
        let store = ItemStore(store: FileStore(root: freshRoot()))
        try await store.bootstrap()

        XCTAssertTrue(store.isLoaded)
        XCTAssertTrue(store.loadIssues.isEmpty)
        XCTAssertFalse(store.lists.isEmpty, "a genuinely empty library still seeds sample data")
    }
}
