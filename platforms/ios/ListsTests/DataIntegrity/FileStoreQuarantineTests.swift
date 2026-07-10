import Foundation
import Testing
import Yams
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

    // MARK: - Duplicate and orphan recovery

    @Test
    func newerDuplicateWinsAndOlderBytesAreQuarantinedIdempotently() async throws {
        let (store, root) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "A", name: "Alpha"))
        try await store.writeList(makeList(id: "B", name: "Bravo"))

        let id = UUID()
        let older = Item(
            id: id,
            type: .note,
            title: "Older source",
            body: "Do not lose these bytes",
            listId: "A",
            createdAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = Item(
            id: id,
            type: .note,
            title: "Newer destination",
            body: "Current body",
            listId: "B",
            createdAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        try await store.writeItem(older)
        try await store.writeItem(newer)

        let olderURL = try await store.listDirectory(for: "A")
            .appendingPathComponent("\(id.uuidString).md")
        let olderBytes = try Data(contentsOf: olderURL)

        let first = try await store.loadAll()
        let loaded = first.lists.flatMap(\.items).filter { $0.id == id }
        #expect(loaded.count == 1)
        #expect(loaded.first?.title == "Newer destination")
        #expect(loaded.first?.listId == "B")
        #expect(first.quarantined.count == 1)
        #expect(first.quarantined.first?.originalPath == olderURL.path)
        #expect(first.quarantined.first?.reason.contains("Duplicate item id") == true)

        let quarantineFiles = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent(".quarantine", isDirectory: true),
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        let preserved = try #require(quarantineFiles.first {
            $0.lastPathComponent.hasPrefix(id.uuidString)
        })
        #expect(try Data(contentsOf: preserved) == olderBytes)

        let second = try await store.loadAll()
        #expect(second.lists.flatMap(\.items).filter { $0.id == id }.count == 1)
        #expect(second.quarantined.isEmpty)
    }

    @Test
    func tombstoneWinsAnExactModifiedTimestampTie() async throws {
        let (store, _) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "A", name: "Alpha"))
        try await store.writeList(makeList(id: "B", name: "Bravo"))

        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 500)
        let active = Item(
            id: id,
            type: .task,
            title: "Active copy",
            listId: "A",
            createdAt: timestamp,
            modifiedAt: timestamp
        )
        let deleted = Item(
            id: id,
            type: .task,
            title: "Deleted copy",
            listId: "B",
            createdAt: timestamp,
            modifiedAt: timestamp,
            deletedAt: timestamp
        )
        try await store.writeItem(active)
        try await store.writeItem(deleted)

        let result = try await store.loadAll()
        let winner = try #require(
            result.lists.flatMap(\.items).first { $0.id == id }
        )
        #expect(result.lists.flatMap(\.items).filter { $0.id == id }.count == 1)
        #expect(winner.title == "Deleted copy")
        #expect(winner.deletedAt == timestamp)
    }

    @Test
    func headerlessMisnamedItemMovesRawBytesIntoItsDeclaredList() async throws {
        let (store, root) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "B", name: "Bravo"))

        let item = Item(type: .note, title: "Recovered orphan", listId: "B")
        let encoded = try FrontmatterCodec.encode(item)
        let enriched = encoded.replacingOccurrences(
            of: "---\n",
            with: "---\nfuture_field: keep-me\n",
            options: [],
            range: encoded.startIndex..<encoded.index(encoded.startIndex, offsetBy: 4)
        )
        let rawBytes = Data(enriched.utf8)
        let orphanDirectory = root.appendingPathComponent("Headerless", isDirectory: true)
        try FileManager.default.createDirectory(
            at: orphanDirectory,
            withIntermediateDirectories: true
        )
        let orphanURL = orphanDirectory.appendingPathComponent("legacy-name.md")
        try rawBytes.write(to: orphanURL, options: .atomic)

        let result = try await store.loadAll()
        let canonicalURL = try await store.listDirectory(for: "B")
            .appendingPathComponent("\(item.id.uuidString).md")
        #expect(FileManager.default.fileExists(atPath: orphanURL.path) == false)
        #expect(try Data(contentsOf: canonicalURL) == rawBytes)
        #expect(result.lists.first { $0.list.id == "B" }?.items.map(\.id) == [item.id])
        #expect(result.quarantined.isEmpty)
    }

    @Test
    func itemBesideCorruptHeaderGetsVisibleRecoveredList() async throws {
        let (store, root) = makeStore()
        try await store.ensureRoot()

        let damaged = root.appendingPathComponent("Damaged", isDirectory: true)
        try FileManager.default.createDirectory(at: damaged, withIntermediateDirectories: true)
        try "broken: [header".write(
            to: damaged.appendingPathComponent(".list.yml"),
            atomically: true,
            encoding: .utf8
        )
        let item = Item(type: .task, title: "Still recoverable", listId: "ghost")
        let originalURL = damaged.appendingPathComponent("\(item.id.uuidString).md")
        try FrontmatterCodec.encode(item).write(
            to: originalURL,
            atomically: true,
            encoding: .utf8
        )

        let result = try await store.loadAll()
        let recovered = try #require(result.lists.first { $0.list.id == "ghost" })
        #expect(recovered.list.name.hasPrefix("Recovered"))
        #expect(recovered.items.map(\.id) == [item.id])
        #expect(FileManager.default.fileExists(atPath: originalURL.path) == false)
        #expect(result.quarantined.contains {
            $0.originalPath.hasSuffix("Damaged/.list.yml")
        })

        let second = try await store.loadAll()
        #expect(second.lists.first { $0.list.id == "ghost" }?.items.map(\.id) == [item.id])
        #expect(second.quarantined.isEmpty)
    }

    @Test
    func duplicateListHeaderKeepsUniqueItemsAndNestedChildren() async throws {
        let (store, root) = makeStore()
        try await store.ensureRoot()
        let older = ItemList(
            id: "duplicate-list",
            name: "Older Folder",
            icon: "tray",
            color: .blue,
            createdAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 100),
            position: 0,
            lamport: 1
        )
        let newer = ItemList(
            id: "duplicate-list",
            name: "Newer Folder",
            icon: "tray.fill",
            color: .green,
            createdAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 200),
            position: 0,
            lamport: 2
        )
        let child = makeList(
            id: "unique-child",
            name: "Unique Child",
            parentId: "duplicate-list"
        )
        let encoder = YAMLEncoder()

        let olderDirectory = root.appendingPathComponent("Older Folder", isDirectory: true)
        let newerDirectory = root.appendingPathComponent("Newer Folder", isDirectory: true)
        let childDirectory = olderDirectory.appendingPathComponent("Unique Child", isDirectory: true)
        try FileManager.default.createDirectory(at: childDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newerDirectory, withIntermediateDirectories: true)
        let olderHeader = olderDirectory.appendingPathComponent(".list.yml")
        let newerHeader = newerDirectory.appendingPathComponent(".list.yml")
        try encoder.encode(older).write(to: olderHeader, atomically: true, encoding: .utf8)
        try encoder.encode(newer).write(to: newerHeader, atomically: true, encoding: .utf8)
        try encoder.encode(child).write(
            to: childDirectory.appendingPathComponent(".list.yml"),
            atomically: true,
            encoding: .utf8
        )
        let olderHeaderBytes = try Data(contentsOf: olderHeader)

        let oldItem = Item(type: .task, title: "From older folder", listId: older.id)
        let newItem = Item(type: .task, title: "From newer folder", listId: newer.id)
        let childItem = Item(type: .task, title: "Child item", listId: child.id)
        try FrontmatterCodec.encode(oldItem).write(
            to: olderDirectory.appendingPathComponent("\(oldItem.id.uuidString).md"),
            atomically: true,
            encoding: .utf8
        )
        try FrontmatterCodec.encode(newItem).write(
            to: newerDirectory.appendingPathComponent("\(newItem.id.uuidString).md"),
            atomically: true,
            encoding: .utf8
        )
        try FrontmatterCodec.encode(childItem).write(
            to: childDirectory.appendingPathComponent("\(childItem.id.uuidString).md"),
            atomically: true,
            encoding: .utf8
        )

        let first = try await store.loadAll()
        let retained = first.lists.filter { $0.list.id == older.id }
        #expect(retained.count == 1)
        #expect(retained.first?.list.name == newer.name)
        #expect(Set(retained.first?.items.map(\.title) ?? []) == Set([
            "From older folder", "From newer folder"
        ]))
        #expect(first.lists.first { $0.list.id == child.id }?.list.parentId == older.id)
        #expect(first.lists.first { $0.list.id == child.id }?.items.map(\.title) == ["Child item"])
        let childPath = try await store.listDirectory(for: child.id)
        #expect(childPath.deletingLastPathComponent().lastPathComponent == newer.name)

        let quarantineFiles = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent(".quarantine", isDirectory: true),
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        let preservedHeader = try #require(quarantineFiles.first {
            $0.lastPathComponent.hasPrefix(".list")
        })
        #expect(try Data(contentsOf: preservedHeader) == olderHeaderBytes)

        let second = try await store.loadAll()
        #expect(second.lists.filter { $0.list.id == older.id }.count == 1)
        #expect(second.lists.first { $0.list.id == older.id }?.items.count == 2)
        #expect(second.lists.first { $0.list.id == child.id }?.items.count == 1)
        #expect(second.quarantined.isEmpty)

        let retainedWinner = try #require(second.lists.first { $0.list.id == older.id })
        try await store.deleteList(retainedWinner.list)
        let afterDelete = try await store.loadAll()
        #expect(afterDelete.lists.contains { $0.list.id == older.id } == false)
        #expect(afterDelete.lists.contains { $0.list.id == child.id } == false)
        #expect(afterDelete.lists.flatMap(\.items).isEmpty)
    }

    @Test
    func failedDuplicateIsolationLeavesEveryCopyInactiveAndUntouched() async throws {
        let (store, root) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "A", name: "Alpha"))
        try await store.writeList(makeList(id: "B", name: "Bravo"))
        let id = UUID()
        let older = Item(id: id, type: .task, title: "Older", listId: "A")
        let newer = Item(
            id: id,
            type: .task,
            title: "Newer",
            listId: "B",
            modifiedAt: older.modifiedAt.addingTimeInterval(1)
        )
        try await store.writeItem(older)
        try await store.writeItem(newer)
        let olderURL = try await store.listDirectory(for: "A")
            .appendingPathComponent("\(id.uuidString).md")
        let newerURL = try await store.listDirectory(for: "B")
            .appendingPathComponent("\(id.uuidString).md")
        let olderBytes = try Data(contentsOf: olderURL)
        let newerBytes = try Data(contentsOf: newerURL)
        try Data("quarantine blocked".utf8).write(
            to: root.appendingPathComponent(".quarantine"),
            options: .atomic
        )

        let result = try await store.loadAll()
        #expect(result.lists.flatMap(\.items).contains { $0.id == id } == false)
        #expect(try Data(contentsOf: olderURL) == olderBytes)
        #expect(try Data(contentsOf: newerURL) == newerBytes)
        #expect(result.quarantined.contains { $0.reason.contains("Quarantine move failed") })
    }

    @Test
    func canonicalTargetCollisionNeverOverwritesEitherIdentity() async throws {
        let (store, root) = makeStore()
        try await store.ensureRoot()
        try await store.writeList(makeList(id: "B", name: "Bravo"))
        let requestedId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let blockingId = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let requested = Item(
            id: requestedId,
            type: .note,
            title: "Requested identity",
            listId: "B"
        )
        let blocking = Item(
            id: blockingId,
            type: .note,
            title: "Blocking identity",
            listId: "B"
        )
        let orphanDirectory = root.appendingPathComponent("A-Orphan", isDirectory: true)
        try FileManager.default.createDirectory(at: orphanDirectory, withIntermediateDirectories: true)
        let requestedURL = orphanDirectory.appendingPathComponent("legacy.md")
        let requestedBytes = Data(try FrontmatterCodec.encode(requested).utf8)
        try requestedBytes.write(to: requestedURL, options: .atomic)

        let bravo = try await store.listDirectory(for: "B")
        let occupiedURL = bravo.appendingPathComponent("\(requestedId.uuidString).md")
        let blockingBytes = Data(try FrontmatterCodec.encode(blocking).utf8)
        try blockingBytes.write(to: occupiedURL, options: .atomic)

        let result = try await store.loadAll()
        #expect(result.lists.flatMap(\.items).contains { $0.id == requestedId } == false)
        #expect(result.lists.flatMap(\.items).contains { $0.id == blockingId })
        #expect(try Data(contentsOf: requestedURL) == requestedBytes)
        let blockingCanonical = bravo.appendingPathComponent("\(blockingId.uuidString).md")
        #expect(try Data(contentsOf: blockingCanonical) == blockingBytes)
        #expect(result.quarantined.contains { $0.reason.contains("Could not canonicalize") })
    }
}
