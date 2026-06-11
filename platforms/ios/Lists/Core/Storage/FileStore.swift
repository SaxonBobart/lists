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
        let dir = try writableDirectory(for: item)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(item.id.uuidString).md")
        let content = try FrontmatterCodec.encode(item)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// PERSIST-2: a save must never be silently dropped because the item's
    /// list folder isn't mapped (a quarantined list header, or an item file
    /// carrying a stray `list:` id). Fall back to the folder the item's file
    /// already lives in; as a last resort, materialize a *visible* "Recovered"
    /// list so the data lands somewhere that loads on the next launch instead
    /// of vanishing.
    private func writableDirectory(for item: Item) throws -> URL {
        if let dir = pathById[item.listId] { return dir }
        if let existing = findExistingItemFile(item.id) {
            return existing.deletingLastPathComponent()
        }
        return try materializeRecoveryList(for: item.listId)
    }

    /// Search the library for `<id>.md`. `.skipsHiddenFiles` keeps the
    /// `.quarantine` bin out of the walk.
    private func findExistingItemFile(_ id: UUID) -> URL? {
        let fm = FileManager.default
        let name = "\(id.uuidString).md"
        guard let enumerator = fm.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == name {
            return url
        }
        return nil
    }

    /// Create (and map) a real list folder with a valid `.list.yml` for an
    /// unmapped list id, so recovered writes surface in the sidebar on the
    /// next launch instead of sitting in a folder the load walker skips.
    private func materializeRecoveryList(for listId: String) throws -> URL {
        let list = ItemList(
            id: listId,
            name: "Recovered \(listId.prefix(8))",
            icon: "exclamationmark.triangle",
            color: .grey,
            createdAt: .now,
            modifiedAt: .now,
            position: 9_999
        )
        try writeList(list)
        return try listDirectory(for: listId)
    }

    /// Move an item's file from `oldListId`'s folder to its current `listId`
    /// folder (DI-2). Writes the new file first, then removes the old one
    /// — write-then-delete, so a crash in between leaves a recoverable
    /// duplicate, never a lost item. No-op delete when the list didn't change
    /// or the old folder isn't mapped (e.g. it failed to load under DI-1): the
    /// new file is still written, so this is always at least as safe as before.
    public func moveItem(_ item: Item, fromListId oldListId: String) throws {
        try writeItem(item)
        guard oldListId != item.listId else { return }
        if let oldDir = pathById[oldListId] {
            let oldURL = oldDir.appendingPathComponent("\(item.id.uuidString).md")
            if FileManager.default.fileExists(atPath: oldURL.path) {
                try FileManager.default.removeItem(at: oldURL)
            }
        }
    }

    public func readItem(at url: URL) throws -> Item {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try FrontmatterCodec.decode(content)
    }

    public func deleteItem(_ item: Item) throws {
        // PERSIST-2: an unmapped list id must not abort the delete — the file
        // would silently resurrect on the next launch ("I deleted it and it
        // came back"). Fall back to wherever the item's file actually lives;
        // if it isn't on disk at all there is nothing to remove.
        let url: URL
        if let dir = pathById[item.listId] {
            url = dir.appendingPathComponent("\(item.id.uuidString).md")
        } else if let existing = findExistingItemFile(item.id) {
            url = existing
        } else {
            return
        }
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

    /// A file that failed to parse during `loadAll` and was moved aside into
    /// `<root>/.quarantine/` so it can't re-fail every launch but stays
    /// recoverable. `originalPath` is the pre-move location (for the banner/log).
    public struct QuarantinedFile: Sendable {
        public let originalPath: String
        public let reason: String
    }

    /// The result of a full load: every list/item that parsed, plus any files
    /// that were quarantined because they didn't.
    public struct LoadResult: Sendable {
        public let lists: [LoadedList]
        public let quarantined: [QuarantinedFile]
    }

    /// Walks the on-disk tree starting at `root`. Any directory containing
    /// `.list.yml` is a list folder; its `*.md` siblings (non-recursive at that
    /// level, skipping `_`-prefixed aux files) are its items; its sub-directories
    /// are recursed into for nested lists.
    ///
    /// Loading is **per-file resilient** (DI-1): a single corrupt / truncated /
    /// unknown file is quarantined — moved into `<root>/.quarantine/`, never
    /// deleted — and reported in `LoadResult.quarantined`, while the rest of the
    /// library always loads. One bad file can never brick the whole library.
    ///
    /// Also performs a silent in-place migration from the legacy
    /// `<root>/<listId>/` layout to the sanitized-name layout: when a list's
    /// folder basename doesn't match `sanitize(list.name)`, the folder is
    /// renamed before its children are walked.
    public func loadAll() throws -> LoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else {
            return LoadResult(lists: [], quarantined: [])
        }
        pathById.removeAll()

        var results: [LoadedList] = []
        var quarantined: [QuarantinedFile] = []
        try walk(root, into: &results, quarantined: &quarantined)
        return LoadResult(lists: results, quarantined: quarantined)
    }

    private func walk(
        _ dir: URL,
        into results: inout [LoadedList],
        quarantined: inout [QuarantinedFile]
    ) throws {
        let fm = FileManager.default
        // Never descend into the quarantine bin (it has no .list.yml today, but
        // the guard makes intent explicit and stops stray junk re-importing).
        if dir.lastPathComponent == ".quarantine" { return }

        let listFile = dir.appendingPathComponent(".list.yml")
        let isListFolder = (dir != root) && fm.fileExists(atPath: listFile.path)

        guard isListFolder else {
            try walkSubdirsOnly(dir, into: &results, quarantined: &quarantined)
            return
        }

        let list: ItemList
        do {
            list = try readList(at: listFile)
        } catch {
            // No valid list header for this folder: quarantine it, but still
            // recurse into subdirectories so nested lists aren't stranded.
            quarantine(listFile, error: error, into: &quarantined)
            try walkSubdirsOnly(dir, into: &results, quarantined: &quarantined)
            return
        }

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

        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(at: effectiveDir, includingPropertiesForKeys: [.isDirectoryKey])
        } catch {
            // PERSIST-1: the list header parsed, but its folder can't be listed
            // (permissions / I/O error). Surface the folder and keep its
            // (now itemless) list rather than aborting the whole library load.
            recordUnreadable(effectiveDir, error: error, into: &quarantined)
            results.append(LoadedList(list: list, items: []))
            pathById[list.id] = effectiveDir
            return
        }
        // Skip `_`-prefixed aux/heartbeat files (AGENT-2); they are not items.
        let itemFiles = entries.filter {
            $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix("_")
        }
        var items: [Item] = []
        for url in itemFiles {
            do {
                items.append(try readItem(at: url))
            } catch {
                quarantine(url, error: error, into: &quarantined)
            }
        }
        results.append(LoadedList(list: list, items: items))
        pathById[list.id] = effectiveDir

        let subdirs = entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        for sub in subdirs {
            try walk(sub, into: &results, quarantined: &quarantined)
        }
    }

    /// Recurse only into a directory's sub-directories — used at `root`, and
    /// when a folder's own `.list.yml` was quarantined but nested lists remain.
    private func walkSubdirsOnly(
        _ dir: URL,
        into results: inout [LoadedList],
        quarantined: inout [QuarantinedFile]
    ) throws {
        let fm = FileManager.default
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
        } catch {
            // PERSIST-1: an unreadable directory degrades to a recorded issue,
            // not a failed load — its siblings still get walked.
            recordUnreadable(dir, error: error, into: &quarantined)
            return
        }
        for sub in entries
        where (try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            try walk(sub, into: &results, quarantined: &quarantined)
        }
    }

    /// Move a file that failed to parse into `<root>/.quarantine/` (best-effort;
    /// if the move fails the file simply stays put). Never overwrites a
    /// previously-quarantined file of the same name.
    private func quarantine(_ url: URL, error: Error, into acc: inout [QuarantinedFile]) {
        let fm = FileManager.default
        let qDir = root.appendingPathComponent(".quarantine", isDirectory: true)
        try? fm.createDirectory(at: qDir, withIntermediateDirectories: true)
        var dest = qDir.appendingPathComponent(url.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            dest = qDir.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        }
        let original = url.path
        try? fm.moveItem(at: url, to: dest)
        acc.append(QuarantinedFile(originalPath: original, reason: String(describing: error)))
    }

    /// Record a directory that couldn't be enumerated (PERSIST-1) without moving
    /// anything — the folder stays where it is, but the failure surfaces in
    /// `LoadResult.quarantined` instead of aborting the entire load.
    private func recordUnreadable(_ dir: URL, error: Error, into acc: inout [QuarantinedFile]) {
        acc.append(QuarantinedFile(
            originalPath: dir.path,
            reason: "Could not read directory: \(String(describing: error))"))
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
