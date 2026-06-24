import Foundation
import Testing
@testable import Lists

/// Loading is per-file resilient. A single corrupt/truncated/unknown
/// file is quarantined (moved aside, never dropped), the rest of the library
/// always loads, `loadAll()` reports what was set aside, and `_`-prefixed
/// auxiliary files are ignored.
struct FileStoreQuarantineTests {

    private func makeStore() -> (FileStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsQuarantine-\(UUID().uuidString)")
        return (FileStore(root: root), root)
    }

    private func makeList(id: String, name: String, parentId: String? = nil) -> ItemList {
        ItemList(id: id, name: name, icon: "tray", color: .blue,
                 createdAt: .now, modifiedAt: .now, position: 0, parentId: parentId)
    }

    @Test
    func badItemQuarantinedAndRestStillLoads() async throws {
        let (store, root) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "l1", name: "Work"))
        try await store.writeItem(Item(type: .task, title: "Keep me", listId: "l1"))

        // A .md with no frontmatter — FrontmatterCodec.decode throws on it.
        let dir = try await store.listDirectory(for: "l1")
        let badURL = dir.appendingPathComponent("\(UUID().uuidString).md")
        try "this is not frontmatter".write(to: badURL, atomically: true, encoding: .utf8)

        let result = try await store.loadAll()

        #expect(result.lists.count == 1)
        #expect(result.lists.first?.items.map(\.title) == ["Keep me"])
        #expect(result.quarantined.count == 1)
        #expect(result.quarantined.first?.originalPath == badURL.path)
        #expect(FileManager.default.fileExists(atPath: badURL.path) == false, "the bad file must be moved out of the live tree")
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".quarantine").path))
    }

    @Test
    func unknownTypeLoadsButMissingRequiredKeyIsQuarantined() async throws {
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

        #expect(result.lists.first?.items.map(\.title) == ["Future"], "unknown-type item loads as a task; the id-less item is quarantined")
        #expect(result.lists.first?.items.first?.type == .task)
        #expect(result.quarantined.count == 1)
    }

    @Test
    func underscorePrefixedFilesAreIgnored() async throws {
        let (store, _) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "l1", name: "Work"))
        try await store.writeItem(Item(type: .task, title: "Real", listId: "l1"))

        let dir = try await store.listDirectory(for: "l1")
        try "not an item, just a heartbeat".write(
            to: dir.appendingPathComponent("_status.md"), atomically: true, encoding: .utf8)

        let result = try await store.loadAll()

        #expect(result.lists.first?.items.map(\.title) == ["Real"])
        #expect(result.quarantined.isEmpty, "a _-prefixed file is ignored, not quarantined")
    }

    @Test
    func corruptParentListHeaderKeepsNestedChild() async throws {
        let (store, _) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "p", name: "Parent"))
        try await store.writeList(makeList(id: "c", name: "Child", parentId: "p"))

        // Corrupt the parent's .list.yml; the child folder is nested under it.
        let parentDir = try await store.listDirectory(for: "p")
        try "garbage: [unterminated".write(
            to: parentDir.appendingPathComponent(".list.yml"), atomically: true, encoding: .utf8)

        let result = try await store.loadAll()

        #expect(result.lists.contains { $0.list.id == "c" }, "nested child still loads")
        #expect(result.lists.contains { $0.list.id == "p" } == false, "corrupt parent is dropped")
        #expect(result.quarantined.count == 1)
    }

    /// An unreadable sub-directory (permissions / I/O) degrades to a recorded
    /// issue, not a failed load; the valid sibling list still loads.
    /// Skipped (never failed) if the environment doesn't enforce the dir perm.

    @Test
    func unreadableDirectoryDoesNotAbortLoad() async throws {
        let (store, root) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "l1", name: "Work"))
        try await store.writeItem(Item(type: .task, title: "Keep me", listId: "l1"))

        let fm = FileManager.default
        let locked = root.appendingPathComponent("locked", isDirectory: true)
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        // Only assert when the environment actually blocks enumeration.
        if (try? fm.contentsOfDirectory(atPath: locked.path)) != nil {
            try Test.cancel("environment does not enforce directory read permission")
        }

        let result = try await store.loadAll()  // must NOT throw

        #expect(result.lists.contains { $0.list.id == "l1" }, "the valid list still loads despite an unreadable sibling")
        #expect(result.lists.first { $0.list.id == "l1" }?.items.map(\.title) == ["Keep me"])
        #expect(result.quarantined.contains { $0.originalPath.contains("/locked") }, "the unreadable folder is recorded, not silently swallowed")
    }

    @Test
    func validLibraryHasNoQuarantine() async throws {
        let (store, root) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "l1", name: "Work"))
        try await store.writeItem(Item(type: .task, title: "A", listId: "l1"))
        try await store.writeItem(Item(type: .note, title: "B", listId: "l1"))

        let result = try await store.loadAll()

        #expect(result.lists.first?.items.count == 2)
        #expect(result.quarantined.isEmpty)
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".quarantine").path) == false, "a fully-valid library must not create a .quarantine folder")
    }

    // MARK: - Writes/deletes to an unmapped list never vanish

    @Test
    func writeToUnmappedListMaterializesAVisibleRecoveredList() async throws {
        let (store, _) = makeStore()
        try await store.ensureRoot()
        _ = try await store.loadAll()

        let stray = Item(type: .task, title: "Orphan", listId: "ghost-list")
        try await store.writeItem(stray)

        let loaded = try await store.loadAll()
        let recovered = loaded.lists.first { $0.list.id == "ghost-list" }
        #expect(recovered != nil, "the save lands in a real, loadable list — not dropped")
        #expect(recovered?.items.map(\.title) == ["Orphan"])
        #expect(recovered?.list.name.hasPrefix("Recovered") ?? false, "the materialized list is visibly marked as recovered")
    }

    @Test
    func deleteWithUnmappedListIdStillRemovesTheFile() async throws {
        let (store, root) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "l1", name: "Work"))
        let item = Item(type: .task, title: "Doomed", listId: "l1")
        try await store.writeItem(item)

        // A fresh FileStore on the same root with NO loadAll(): nothing is
        // mapped, mimicking the quarantined-header case.
        let fresh = FileStore(root: root)
        try await fresh.deleteItem(item)

        let reloaded = try await FileStore(root: root).loadAll()
        #expect(reloaded.lists.flatMap(\.items).isEmpty, "the file is gone — the item cannot resurrect on next launch")
    }
}
