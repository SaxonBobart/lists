import Foundation
import Testing
@testable import Lists

@MainActor
struct LibraryExporterTests {
    @Test func exportLibraryWritesZipWithListsFolderContents() throws {
        let root = freshRoot()
        let work = root.appendingPathComponent("Work", isDirectory: true)
        let child = work.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "id: work\nname: Work\n".write(
            to: work.appendingPathComponent(".list.yml"),
            atomically: true,
            encoding: .utf8
        )
        try "id: child\nname: Child\n".write(
            to: child.appendingPathComponent(".list.yml"),
            atomically: true,
            encoding: .utf8
        )
        try "---\ntitle: Hello\n---\nBody\n".write(
            to: work.appendingPathComponent("item.md"),
            atomically: true,
            encoding: .utf8
        )

        let exportURL = try LibraryExporter.exportLibrary(
            at: root,
            now: Date(timeIntervalSince1970: 0)
        )

        #expect(exportURL.pathExtension == "zip")
        let names = try zipEntryNames(in: exportURL)
        #expect(names.contains("Lists/"))
        #expect(names.contains("Lists/Work/"))
        #expect(names.contains("Lists/Work/.list.yml"))
        #expect(names.contains("Lists/Work/Child/"))
        #expect(names.contains("Lists/Work/Child/.list.yml"))
        #expect(names.contains("Lists/Work/item.md"))
    }

    @Test func storeExportFlushesPendingInlineWrites() async throws {
        let root = freshRoot()
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let id = store.addInlineItem(type: .task, listId: ItemList.inboxId, section: nil)
        var typed = try #require(store.item(id))
        typed.title = "Exported after typing"
        store.applyUpdateSync(typed)

        let exportURL = try await store.exportLibrary()

        let data = try Data(contentsOf: exportURL)
        let text = String(decoding: data, as: UTF8.self)
        #expect(
            text.contains("Exported after typing"),
            "export must wait for deferred row-edit writes before zipping the library"
        )
    }

    @Test func storeExportRefusesStaleArchiveAfterDeferredFailure() async throws {
        let root = freshRoot()
        let fileStore = FileStore(root: root)
        let store = ItemStore(store: fileStore)
        try await store.bootstrap()

        let inboxDirectory = try await fileStore.listDirectory(for: ItemList.inboxId)
        try FileManager.default.removeItem(at: inboxDirectory)
        try Data("not a directory".utf8).write(to: inboxDirectory)

        var item = try #require(store.items.first { $0.listId == ItemList.inboxId })
        item.title = "Visible only in memory"
        store.applyUpdateSync(item)

        do {
            _ = try await store.exportLibrary()
            Issue.record("export must fail instead of packaging stale on-disk data")
        } catch {
            #expect(error.localizedDescription.contains("couldn't finish saving"))
        }
    }

    @Test func aLaterExportKeepsTheRecentArchiveAvailableForSharing() throws {
        let root = freshRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = try LibraryExporter.exportLibrary(at: root)
        let second = try LibraryExporter.exportLibrary(at: root)

        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    private func freshRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsExport-\(UUID().uuidString)", isDirectory: true)
    }

    private func zipEntryNames(in url: URL) throws -> Set<String> {
        let data = try Data(contentsOf: url)
        let eocdOffset = try #require(lastIndex(of: [0x50, 0x4B, 0x05, 0x06], in: data))
        let entryCount = Int(readUInt16LE(data, at: eocdOffset + 10))
        let centralDirectoryOffset = Int(readUInt32LE(data, at: eocdOffset + 16))

        var names: Set<String> = []
        var offset = centralDirectoryOffset
        for _ in 0..<entryCount {
            #expect(readUInt32LE(data, at: offset) == 0x0201_4B50)
            let nameLength = Int(readUInt16LE(data, at: offset + 28))
            let extraLength = Int(readUInt16LE(data, at: offset + 30))
            let commentLength = Int(readUInt16LE(data, at: offset + 32))
            let nameStart = offset + 46
            let nameEnd = nameStart + nameLength
            let nameData = data[nameStart..<nameEnd]
            names.insert(String(decoding: nameData, as: UTF8.self))
            offset = nameEnd + extraLength + commentLength
        }
        return names
    }

    private func lastIndex(of signature: [UInt8], in data: Data) -> Int? {
        guard data.count >= signature.count else { return nil }
        var index = data.count - signature.count
        while index >= 0 {
            if Array(data[index..<(index + signature.count)]) == signature {
                return index
            }
            if index == 0 { break }
            index -= 1
        }
        return nil
    }

    private func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
