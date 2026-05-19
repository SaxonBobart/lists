import Foundation
import Yams

/// Owns all file I/O against the on-disk Lists library.
///
/// Layout:
///
///     <root>/<sanitized list name>/.list.yml
///     <root>/<sanitized list name>/<itemId>.md
///     <root>/<parent name>/<child name>/.list.yml          (nested lists)
///
/// Folder names mirror the list's display name (sanitized for the
/// filesystem); the list's stable id lives inside `.list.yml`. A parent
/// list's children sit alongside its item files as sub-folders, each with
/// their own `.list.yml`. Nesting depth is unlimited.
///
/// The actor maintains a `listId → URL` map populated by `loadAll()` and
/// kept in sync by `writeList` / `deleteList`. Callers reference lists by id
/// only — paths are an internal concern.
public actor FileStore {
    public let root: URL
    private var pathById: [String: URL] = [:]

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
        let targetDir = try resolveTargetURL(for: list)
        let existingDir = pathById[list.id]

        if let existingDir, existingDir != targetDir {
            // Rename / reparent: move the existing folder (with all its items
            // and nested children) to the new path.
            if FileManager.default.fileExists(atPath: existingDir.path) {
                try FileManager.default.createDirectory(
                    at: targetDir.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: existingDir, to: targetDir)
            } else {
                try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            }
        } else {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }

        let url = targetDir.appendingPathComponent(".list.yml")
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = false
        let yaml = try encoder.encode(list)
        try yaml.write(to: url, atomically: true, encoding: .utf8)

        pathById[list.id] = targetDir
        if let existingDir, existingDir != targetDir {
            refreshDescendantPaths(under: targetDir)
        }
    }

    public func readList(at url: URL) throws -> ItemList {
        let yaml = try String(contentsOf: url, encoding: .utf8)
        return try YAMLDecoder().decode(ItemList.self, from: yaml)
    }

    // MARK: - Items

    public func writeItem(_ item: Item) throws {
        let dir = try listDirectory(for: item.listId)
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
        let dir = try listDirectory(for: item.listId)
        let url = dir.appendingPathComponent("\(item.id.uuidString).md")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Hard-deletes an entire list folder (including .list.yml, items, and
    /// any nested sub-list folders).
    public func deleteList(_ list: ItemList) throws {
        guard let dir = pathById[list.id] else { return }
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        pathById.removeValue(forKey: list.id)
        // Drop any descendants whose URL is under the removed folder — they
        // no longer exist on disk.
        let removedPath = dir.path
        for (id, url) in pathById where url.path.hasPrefix(removedPath + "/") {
            pathById.removeValue(forKey: id)
        }
    }

    // MARK: - Bulk load

    public struct LoadedList: Sendable {
        public let list: ItemList
        public let items: [Item]
    }

    /// Walks the on-disk tree starting at `root`. Any directory containing
    /// `.list.yml` is a list folder; its `*.md` siblings (non-recursive at
    /// that level) are its items; its sub-directories are recursed into for
    /// nested lists.
    ///
    /// Also performs a silent in-place migration from the legacy
    /// `<root>/<listId>/` layout to the sanitized-name layout: when a list's
    /// folder basename doesn't match `sanitize(list.name)`, the folder is
    /// renamed before its children are walked.
    public func loadAll() throws -> [LoadedList] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        pathById.removeAll()

        var results: [LoadedList] = []
        try walk(root, into: &results)
        return results
    }

    private func walk(_ dir: URL, into results: inout [LoadedList]) throws {
        let fm = FileManager.default
        let listFile = dir.appendingPathComponent(".list.yml")
        let isListFolder = (dir != root) && fm.fileExists(atPath: listFile.path)

        if isListFolder {
            let list = try readList(at: listFile)
            // Migration: if the folder basename doesn't already match the
            // sanitized display name, rename it now. New nesting layout
            // expects display-name folders.
            var effectiveDir = dir
            let desiredBase = Self.sanitize(list.name)
            if dir.lastPathComponent != desiredBase {
                let parentDir = dir.deletingLastPathComponent()
                var candidate = desiredBase
                var suffix = 2
                var target = parentDir.appendingPathComponent(candidate, isDirectory: true)
                while fm.fileExists(atPath: target.path) && target != dir {
                    candidate = "\(desiredBase) (\(suffix))"
                    suffix += 1
                    target = parentDir.appendingPathComponent(candidate, isDirectory: true)
                }
                if target != dir {
                    do {
                        try fm.moveItem(at: dir, to: target)
                        effectiveDir = target
                    } catch {
                        // Best-effort migration — keep going with the old path
                        // rather than failing the entire load.
                        effectiveDir = dir
                    }
                }
            }

            let entries = try fm.contentsOfDirectory(at: effectiveDir, includingPropertiesForKeys: [.isDirectoryKey])
            let itemFiles = entries.filter { $0.pathExtension == "md" }
            let items = try itemFiles.map { try readItem(at: $0) }
            results.append(LoadedList(list: list, items: items))
            pathById[list.id] = effectiveDir

            let subdirs = entries.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
            for sub in subdirs {
                try walk(sub, into: &results)
            }
        } else {
            let entries = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
            let subdirs = entries.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
            for sub in subdirs {
                try walk(sub, into: &results)
            }
        }
    }

    // MARK: - Helpers

    /// Returns the on-disk URL for a known list. The list must have been
    /// loaded or written previously.
    public func listDirectory(for listId: String) throws -> URL {
        if let url = pathById[listId] { return url }
        throw CocoaError(.fileNoSuchFile, userInfo: [
            NSLocalizedDescriptionKey: "No on-disk folder mapped for list id \(listId)"
        ])
    }

    /// Compute the desired on-disk URL for a list based on its (current)
    /// parent chain + sanitized name, resolving any folder-name collision
    /// against siblings.
    private func resolveTargetURL(for list: ItemList) throws -> URL {
        let parentDir: URL
        if let parentId = list.parentId, let p = pathById[parentId] {
            parentDir = p
        } else {
            parentDir = root
        }

        let base = Self.sanitize(list.name)
        let currentDir = pathById[list.id]

        var candidate = base
        var suffix = 2
        while true {
            let url = parentDir.appendingPathComponent(candidate, isDirectory: true)
            if url == currentDir {
                return url
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            candidate = "\(base) (\(suffix))"
            suffix += 1
        }
    }

    /// After a move, descendants of `dir` need their `pathById` entries
    /// repointed at their new locations. Re-walks the subtree and reads
    /// `.list.yml`s to refresh the map.
    private func refreshDescendantPaths(under dir: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            guard
                (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            let listFile = url.appendingPathComponent(".list.yml")
            guard fm.fileExists(atPath: listFile.path) else { continue }
            if let list = try? readList(at: listFile) {
                pathById[list.id] = url
            }
        }
    }

    /// Sanitize a list's display name into a folder-safe component.
    /// Strips filesystem-illegal chars, leading dots (no hidden folders),
    /// trailing whitespace/dots, and clamps length. Empty result → `Untitled`.
    static func sanitize(_ name: String) -> String {
        let illegal: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\0"]
        var s = String(name.map { illegal.contains($0) ? "-" : $0 })
        while s.hasPrefix(".") { s.removeFirst() }
        while let last = s.last, last == "." || last.isWhitespace {
            s.removeLast()
        }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.count > 80 {
            s = String(s.prefix(80))
        }
        return s.isEmpty ? "Untitled" : s
    }
}
