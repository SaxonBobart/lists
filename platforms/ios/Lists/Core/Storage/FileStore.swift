import Foundation
import Yams

/// Owns all file I/O against the on-disk Lists library.
///
/// Layout (per `shared/format/filenames.md`):
///
///     <root>/<listId>/.list.yml
///     <root>/<listId>/<itemId>.md
///
public actor FileStore {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    // MARK: - Roots

    public func ensureRoot() throws {
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true
        )
    }

    // MARK: - Lists

    public func writeList(_ list: ItemList) throws {
        let dir = listDirectory(for: list.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(".list.yml")
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = false
        let yaml = try encoder.encode(list)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }

    public func readList(at url: URL) throws -> ItemList {
        let yaml = try String(contentsOf: url, encoding: .utf8)
        return try YAMLDecoder().decode(ItemList.self, from: yaml)
    }

    // MARK: - Items

    public func writeItem(_ item: Item) throws {
        let dir = listDirectory(for: item.listId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(item.id.uuidString).md")
        let content = try FrontmatterCodec.encode(item)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    public func readItem(at url: URL) throws -> Item {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try FrontmatterCodec.decode(content)
    }

    public func deleteItem(_ item: Item) throws {
        let url = listDirectory(for: item.listId)
            .appendingPathComponent("\(item.id.uuidString).md")
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Bulk load

    public struct LoadedList: Sendable {
        public let list: ItemList
        public let items: [Item]
    }

    public func loadAll() throws -> [LoadedList] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }

        let dirs = try fm
            .contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }

        return try dirs.compactMap { dir -> LoadedList? in
            let listFile = dir.appendingPathComponent(".list.yml")
            guard fm.fileExists(atPath: listFile.path) else { return nil }
            let list = try readList(at: listFile)

            let itemFiles = try fm
                .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "md" }

            let items = try itemFiles.map { try readItem(at: $0) }
            return LoadedList(list: list, items: items)
        }
    }

    // MARK: - Helpers

    private func listDirectory(for listId: String) -> URL {
        root.appendingPathComponent(listId, isDirectory: true)
    }
}
