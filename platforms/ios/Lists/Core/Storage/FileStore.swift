import Foundation
import Yams

/// Owns all file I/O against the on-disk Lists library.
///
/// Layout:
///
///     <root>/<sanitized list name>/.list.yml
///     <root>/<sanitized list name>/<sanitized item title>.md
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
    public enum RestoreJournalError: Error, Equatable, LocalizedError, Sendable {
        case pendingOperation
        case journalChanged

        public var errorDescription: String? {
            switch self {
            case .pendingOperation:
                "Another library restore must finish first."
            case .journalChanged:
                "The pending library restore changed unexpectedly."
            }
        }
    }

    public struct RestoreJournal: Codable, Sendable {
        private static let currentFormatVersion = 1

        public enum Kind: String, Codable, Sendable {
            case item
            case list
        }

        public let kind: Kind
        public let rootId: String
        public let deletedAt: Date
        public let expectedItemIds: [String]
        public let expectedListIds: [String]
        public let formatVersion: Int

        public var hasMemberManifest: Bool {
            guard formatVersion == Self.currentFormatVersion else { return false }
            switch kind {
            case .item:
                return expectedItemIds.contains(rootId)
            case .list:
                return expectedListIds.contains(rootId)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case rootId
            case deletedAt
            case expectedItemIds
            case expectedListIds
            case formatVersion
        }

        public init(
            kind: Kind,
            rootId: String,
            deletedAt: Date,
            expectedItemIds: [String] = [],
            expectedListIds: [String] = []
        ) {
            self.kind = kind
            self.rootId = rootId
            self.deletedAt = deletedAt
            var itemIds = Set(expectedItemIds)
            var listIds = Set(expectedListIds)
            switch kind {
            case .item:
                itemIds.insert(rootId)
            case .list:
                listIds.insert(rootId)
            }
            self.expectedItemIds = itemIds.sorted()
            self.expectedListIds = listIds.sorted()
            self.formatVersion = Self.currentFormatVersion
        }

        /// Decode pre-manifest journals without pretending they are complete.
        /// ItemStore recognizes `formatVersion == 0` and keeps the operation
        /// blocked; recomputing a smaller batch after a corrupt member moved to
        /// quarantine could otherwise overwrite hierarchy or permit expiry
        /// purge to destroy part of the user's requested restore.
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            kind = try values.decode(Kind.self, forKey: .kind)
            rootId = try values.decode(String.self, forKey: .rootId)
            deletedAt = try values.decode(Date.self, forKey: .deletedAt)
            let decodedVersion = try values.decodeIfPresent(
                Int.self,
                forKey: .formatVersion
            ) ?? 0
            formatVersion = decodedVersion
            if decodedVersion == Self.currentFormatVersion {
                expectedItemIds = try values.decode(
                    [String].self,
                    forKey: .expectedItemIds
                ).sorted()
                expectedListIds = try values.decode(
                    [String].self,
                    forKey: .expectedListIds
                ).sorted()
            } else {
                expectedItemIds = try values.decodeIfPresent(
                    [String].self,
                    forKey: .expectedItemIds
                )?.sorted() ?? []
                expectedListIds = try values.decodeIfPresent(
                    [String].self,
                    forKey: .expectedListIds
                )?.sorted() ?? []
            }
        }

        fileprivate func matches(_ other: RestoreJournal) -> Bool {
            kind == other.kind
                && rootId == other.rootId
                && abs(deletedAt.timeIntervalSince(other.deletedAt)) < 0.001
        }
    }

    /// Durable intent for a multi-file soft deletion. Unlike restore, several
    /// independent deletions may be pending after unrelated storage failures,
    /// so these records are stored as a small array.
    public struct DeletionJournal: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case item
            case list
        }

        public let kind: Kind
        public let rootId: String
        public let deletedAt: Date

        public init(kind: Kind, rootId: String, deletedAt: Date) {
            self.kind = kind
            self.rootId = rootId
            self.deletedAt = deletedAt
        }

        fileprivate func matches(_ other: DeletionJournal) -> Bool {
            kind == other.kind
                && rootId == other.rootId
                && abs(deletedAt.timeIntervalSince(other.deletedAt)) < 0.001
        }
    }

    public let root: URL
    private var pathById: [String: URL] = [:]
    private var itemPathById: [UUID: URL] = [:]
    private var restoreJournalURL: URL {
        root.appendingPathComponent(".restore-journal.json")
    }
    private var deletionJournalURL: URL {
        root.appendingPathComponent(".deletion-journals.json")
    }

    public init(root: URL) {
        self.root = root
    }

    public func rootURL() -> URL {
        root
    }

    public func documentFileNames() -> [UUID: String] {
        itemPathById.mapValues(\.lastPathComponent)
    }

    public func documentFileName(for id: UUID) -> String? {
        itemPathById[id]?.lastPathComponent
    }

    /// Establish one durable restore intent before any member of its batch is
    /// made active. An identical journal is an idempotent retry; a different
    /// pending restore is preserved and rejected rather than overwritten.
    public func beginRestore(_ requested: RestoreJournal) throws -> RestoreJournal {
        if let existing = try pendingRestore() {
            guard existing.hasMemberManifest,
                  existing.matches(requested) else {
                throw RestoreJournalError.pendingOperation
            }
            return existing
        }

        try ensureRoot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(requested).write(to: restoreJournalURL, options: .atomic)
        return requested
    }

    public func pendingRestore() throws -> RestoreJournal? {
        guard FileManager.default.fileExists(atPath: restoreJournalURL.path) else {
            return nil
        }
        return try JSONDecoder().decode(
            RestoreJournal.self,
            from: Data(contentsOf: restoreJournalURL)
        )
    }

    public func finishRestore(_ completed: RestoreJournal) throws {
        guard let existing = try pendingRestore() else { return }
        guard existing.hasMemberManifest,
              completed.hasMemberManifest,
              existing.matches(completed) else {
            throw RestoreJournalError.journalChanged
        }
        try FileManager.default.removeItem(at: restoreJournalURL)
    }

    @discardableResult
    public func beginDeletion(_ requested: DeletionJournal) throws -> DeletionJournal {
        try ensureRoot()
        var journals = try pendingDeletions()
        if let existing = journals.first(where: {
            $0.kind == requested.kind && $0.rootId == requested.rootId
        }) {
            return existing
        }
        journals.append(requested)
        try writeDeletionJournals(journals)
        return requested
    }

    public func pendingDeletions() throws -> [DeletionJournal] {
        guard FileManager.default.fileExists(atPath: deletionJournalURL.path) else {
            return []
        }
        return try JSONDecoder().decode(
            [DeletionJournal].self,
            from: Data(contentsOf: deletionJournalURL)
        )
    }

    public func finishDeletion(_ completed: DeletionJournal) throws {
        var journals = try pendingDeletions()
        journals.removeAll { $0.matches(completed) }
        try writeDeletionJournals(journals)
    }

    public func cancelDeletion(kind: DeletionJournal.Kind, rootId: String) throws {
        var journals = try pendingDeletions()
        journals.removeAll { $0.kind == kind && $0.rootId == rootId }
        try writeDeletionJournals(journals)
    }

    private func writeDeletionJournals(_ journals: [DeletionJournal]) throws {
        if journals.isEmpty {
            if FileManager.default.fileExists(atPath: deletionJournalURL.path) {
                try FileManager.default.removeItem(at: deletionJournalURL)
            }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(journals).write(
            to: deletionJournalURL,
            options: .atomic
        )
    }

    // MARK: - Roots

    public func ensureRoot() throws {
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true
        )
    }

    /// Builds a complete replacement library beside the live root, then swaps
    /// it into place. The old root remains available for rollback until the
    /// staged library has been installed successfully.
    public func replaceContents(lists: [ItemList], items: [Item]) async throws {
        let fileManager = FileManager.default
        let parent = root.deletingLastPathComponent()
        let nonce = UUID().uuidString
        let stagingRoot = parent.appendingPathComponent(".Lists-staging-\(nonce)", isDirectory: true)
        let rollbackRoot = parent.appendingPathComponent(".Lists-rollback-\(nonce)", isDirectory: true)
        let stagingStore = FileStore(root: stagingRoot)

        defer {
            try? fileManager.removeItem(at: stagingRoot)
        }

        try await stagingStore.ensureRoot()
        for list in lists {
            try await stagingStore.writeList(list)
        }
        for item in items {
            try await stagingStore.writeItem(item)
        }
        _ = try await stagingStore.loadAll()

        let hadLiveRoot = fileManager.fileExists(atPath: root.path)
        if hadLiveRoot {
            try fileManager.moveItem(at: root, to: rollbackRoot)
        }

        do {
            try fileManager.moveItem(at: stagingRoot, to: root)
        } catch {
            if hadLiveRoot, fileManager.fileExists(atPath: rollbackRoot.path) {
                do {
                    try fileManager.moveItem(at: rollbackRoot, to: root)
                } catch let rollbackError {
                    // Preserve the rollback directory for manual recovery if
                    // restoring it to the live path also fails.
                    throw rollbackError
                }
            }
            throw error
        }

        if hadLiveRoot {
            try? fileManager.removeItem(at: rollbackRoot)
        }
        _ = try loadAll()
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
        try writeItem(item, in: dir)
    }

    private func writeItem(_ item: Item, in dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let existing = findExistingItemFiles(item.id).filter {
            $0.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL
        }
        let url = try documentURL(for: item, in: dir, preserving: existing)
        let content = try FrontmatterCodec.encode(item)
        try content.write(to: url, atomically: true, encoding: .utf8)
        itemPathById[item.id] = url.standardizedFileURL
        for old in existing where old.standardizedFileURL != url.standardizedFileURL {
            try FileManager.default.removeItem(at: old)
        }
    }

    /// A save must never be silently dropped because the item's list folder
    /// isn't mapped (a quarantined list header, or an item file carrying a
    /// stray `list:` id). Fall back to the folder the item's file already lives
    /// in; as a last resort, materialize a *visible* "Recovered" list so the
    /// data lands somewhere that loads on the next launch instead of vanishing.
    private func writableDirectory(for item: Item) throws -> URL {
        if let dir = pathById[item.listId] { return dir }
        if let existing = findExistingItemFile(item.id) {
            return existing.deletingLastPathComponent()
        }
        return try materializeRecoveryList(for: item.listId)
    }

    /// Search the library by the stable id in frontmatter. Filenames are
    /// intentionally human-readable and can change when a title changes;
    /// `.skipsHiddenFiles` keeps the quarantine bin out of the walk.
    private func findExistingItemFile(_ id: UUID) -> URL? {
        findExistingItemFiles(id).first
    }

    private func findExistingItemFiles(_ id: UUID) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.caseInsensitiveCompare("md") == .orderedSame }
            .filter {
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            }
            .filter { (try? readItem(at: $0).id) == id }
            .sorted { $0.path < $1.path }
    }

    /// Resolve the old copy before a move writes anything. When a list header
    /// was quarantined its id is no longer mapped, so prefer the candidate
    /// whose frontmatter still declares the old list. If several ambiguous
    /// copies exist, preserve them all rather than guessing which one to
    /// delete; duplicate recovery handles that separately during loading.
    private func sourceItemFile(_ id: UUID, listId: String) -> URL? {
        let candidates = findExistingItemFiles(id)
        let declaredMatches = candidates.filter {
            (try? readItem(at: $0).listId) == listId
        }
        return declaredMatches.count == 1 ? declaredMatches[0] : nil
    }

    /// A valid list folder can exist even when this actor's map has not seen
    /// it yet. Reuse that folder before materializing a Recovery list, while
    /// keeping the lookup deterministic if malformed storage contains more
    /// than one header with the same id.
    private func existingListDirectory(for listId: String) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let matches = enumerator
            .compactMap { $0 as? URL }
            .filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
            .filter {
                let header = $0.appendingPathComponent(".list.yml")
                return fm.fileExists(atPath: header.path)
                    && (try? readList(at: header).id) == listId
            }
            .sorted { $0.path < $1.path }
        return matches.first
    }

    private func destinationDirectory(for listId: String) throws -> URL {
        if let mapped = pathById[listId] { return mapped }
        if let existing = existingListDirectory(for: listId) {
            pathById[listId] = existing
            return existing
        }
        return try materializeRecoveryList(for: listId)
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
    /// folder. Writes the new file first, then removes the old one — a crash in
    /// between leaves a recoverable duplicate, never a lost item. An unmapped
    /// destination is materialized as a visible Recovery list; an unmapped or
    /// ambiguous source is searched by id/frontmatter and preserved when it
    /// cannot be identified safely.
    @discardableResult
    public func moveItem(_ item: Item, fromListId oldListId: String) throws -> Item {
        guard oldListId != item.listId else {
            try writeItem(item)
            return item
        }

        let sourceURL = sourceItemFile(item.id, listId: oldListId)
        let destinationDir = try destinationDirectory(for: item.listId)
        let existingDestination = findExistingItemFiles(item.id).filter {
            $0.deletingLastPathComponent().standardizedFileURL == destinationDir.standardizedFileURL
        }
        let encodedItem = Data(try FrontmatterCodec.encode(item).utf8)
        if let existingCopy = existingDestination.first {
            let existing = try Data(contentsOf: existingCopy)
            if existing != encodedItem {
                let existingItem = try readItem(at: existingCopy)
                guard Self.sameMovePayload(existingItem, item) else {
                    throw CocoaError(.fileWriteFileExists, userInfo: [
                        NSFilePathErrorKey: existingCopy.path,
                        NSLocalizedDescriptionKey: "A different item with id \(item.id) already exists in the destination list."
                    ])
                }
            }
        }
        let destinationURL = try documentURL(
            for: item,
            in: destinationDir,
            preserving: existingDestination
        ).standardizedFileURL

        // Copy first. Only after the new bytes are safely in a distinct list
        // folder may the captured old copy be removed.
        let createdDestination: Bool
        let persistedItem: Item
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let existing = try Data(contentsOf: destinationURL)
            if existing == encodedItem {
                persistedItem = item
            } else {
                let existingItem = try readItem(at: destinationURL)
                guard Self.sameMovePayload(existingItem, item) else {
                    throw CocoaError(.fileWriteFileExists, userInfo: [
                        NSFilePathErrorKey: destinationURL.path,
                        NSLocalizedDescriptionKey: "A different item with id \(item.id) already exists in the destination list."
                    ])
                }
                // A prior copy-first attempt can differ only by the retry's
                // fresh modifiedAt. Keep those already-safe destination bytes
                // and report their exact model back to ItemStore.
                persistedItem = existingItem
            }
            createdDestination = false
        } else {
            try writeItem(item, in: destinationDir)
            createdDestination = true
            persistedItem = item
        }

        if let sourceURL = sourceURL?.standardizedFileURL,
           sourceURL != destinationURL,
           FileManager.default.fileExists(atPath: sourceURL.path) {
            do {
                try FileManager.default.removeItem(at: sourceURL)
            } catch {
                // The original still exists, so roll back only the destination
                // this call created and only while its bytes remain ours. A
                // process crash still leaves the deliberate recoverable copy;
                // an ordinary runtime failure leaves one authoritative file
                // and can be retried with a fresh payload safely.
                if createdDestination,
                   FileManager.default.fileExists(atPath: sourceURL.path),
                   (try? Data(contentsOf: destinationURL)) == encodedItem {
                    try? FileManager.default.removeItem(at: destinationURL)
                }
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    itemPathById[item.id] = sourceURL
                }
                throw error
            }
        }
        itemPathById[item.id] = destinationURL
        return persistedItem
    }

    private static func sameMovePayload(_ lhs: Item, _ rhs: Item) -> Bool {
        var lhs = lhs
        lhs.modifiedAt = rhs.modifiedAt

        // Compare the canonical durable representation, not raw in-memory
        // `Date` precision. YAML round-tripping can trim sub-millisecond
        // fractions from created/due/completion dates, which must not make an
        // otherwise identical copy-first crash residue look like conflicting
        // user data.
        guard let lhsEncoded = try? FrontmatterCodec.encode(lhs),
              let rhsEncoded = try? FrontmatterCodec.encode(rhs) else {
            return false
        }
        return lhsEncoded == rhsEncoded
    }

    public func readItem(at url: URL) throws -> Item {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try FrontmatterCodec.decode(content)
    }

    public func deleteItem(_ item: Item) throws {
        // An unmapped list id must not abort the delete — the file would
        // silently resurrect on the next launch ("I deleted it and it came
        // back"). Fall back to wherever the item's file actually lives; if it
        // isn't on disk at all there is nothing to remove.
        let url: URL
        if let dir = pathById[item.listId],
           let existing = findExistingItemFiles(item.id).first(where: {
               $0.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL
           }) {
            url = existing
        } else if let existing = findExistingItemFile(item.id) {
            url = existing
        } else {
            return
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        itemPathById[item.id] = nil
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
        for (id, url) in itemPathById where
            url.path == removedPath || url.path.hasPrefix(removedPath + "/") {
            itemPathById.removeValue(forKey: id)
        }
    }

    // MARK: - Bulk load

    private struct LoadedItemSource: Sendable {
        let item: Item
        let url: URL
        let containingListId: String?
        let containingDirectory: URL
        let rawData: Data
    }

    private struct IndexedItemSource {
        let discoveryIndex: Int
        let source: LoadedItemSource
    }

    private struct IndexedListSource {
        let discoveryIndex: Int
        let source: LoadedList
    }

    public struct LoadedList: Sendable {
        public let list: ItemList
        public let items: [Item]
        let directory: URL
        let headerURL: URL
        let rawHeaderData: Data
    }

    /// A file isolated during `loadAll`, or a recovery operation that could
    /// not be completed safely. Files moved to `<root>/.quarantine/` retain
    /// their original bytes; `originalPath` drives the recovery banner/log.
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

    /// Walks list headers first, resolves duplicate identities and physical
    /// nesting, then discovers every regular `*.md` file globally. Global item
    /// discovery recovers files beside missing/corrupt headers while continuing
    /// to ignore `.quarantine` and `_`-prefixed auxiliary files.
    ///
    /// Loading is **per-file resilient**: a single corrupt / truncated /
    /// unknown file is quarantined — moved into `<root>/.quarantine/`, never
    /// deleted — and reported in `LoadResult.quarantined`, while the rest of
    /// the library always loads. One bad file can never brick the whole
    /// library.
    ///
    /// Also performs a silent in-place migration from the legacy
    /// `<root>/<listId>/` layout to the sanitized-name layout: when a list's
    /// folder basename doesn't match `sanitize(list.name)`, the folder is
    /// renamed before its children are walked.
    public func loadAll() throws -> LoadResult {
        let fm = FileManager.default
        pathById.removeAll()
        itemPathById.removeAll()
        guard fm.fileExists(atPath: root.path) else {
            return LoadResult(lists: [], quarantined: [])
        }

        var results: [LoadedList] = []
        var quarantined: [QuarantinedFile] = []
        try walk(root, into: &results, quarantined: &quarantined)
        var blockedListIds: Set<String> = []
        results = resolveDuplicateLists(
            results,
            blockedListIds: &blockedListIds,
            quarantined: &quarantined
        )
        results = canonicalizeListDirectories(
            results,
            blockedListIds: &blockedListIds,
            quarantined: &quarantined
        )
        pathById = Dictionary(
            results.map { ($0.list.id, $0.directory) },
            uniquingKeysWith: { _, later in later }
        )
        let itemSources = discoverItemSources(
            alongside: results,
            quarantined: &quarantined
        )
        results = resolveDuplicateItems(
            itemSources,
            in: results,
            blockedListIds: blockedListIds,
            quarantined: &quarantined
        )
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
        let rawHeaderData: Data
        do {
            rawHeaderData = try Data(contentsOf: listFile)
            guard let yaml = String(data: rawHeaderData, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            list = try YAMLDecoder().decode(ItemList.self, from: yaml)
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
            entries = try fm.contentsOfDirectory(
                at: effectiveDir,
                includingPropertiesForKeys: [.isDirectoryKey]
            ).sorted { $0.standardizedFileURL.path < $1.standardizedFileURL.path }
        } catch {
            // The list header parsed, but its folder can't be listed
            // (permissions / I/O error). Surface the folder and keep its
            // now-itemless list rather than aborting the whole library load.
            recordUnreadable(effectiveDir, error: error, into: &quarantined)
            results.append(LoadedList(
                list: list,
                items: [],
                directory: effectiveDir,
                headerURL: effectiveDir.appendingPathComponent(".list.yml"),
                rawHeaderData: rawHeaderData
            ))
            return
        }
        results.append(LoadedList(
            list: list,
            items: [],
            directory: effectiveDir,
            headerURL: effectiveDir.appendingPathComponent(".list.yml"),
            rawHeaderData: rawHeaderData
        ))

        let subdirs = entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        for sub in subdirs {
            try walk(sub, into: &results, quarantined: &quarantined)
        }
    }

    /// Collapse duplicate list headers before item placement. Only the losing
    /// header is isolated: its direct items and nested child folders remain in
    /// discovery so unique data can move under the retained logical list.
    private func resolveDuplicateLists(
        _ lists: [LoadedList],
        blockedListIds: inout Set<String>,
        quarantined: inout [QuarantinedFile]
    ) -> [LoadedList] {
        var groups: [String: [IndexedListSource]] = [:]
        for (index, list) in lists.enumerated() {
            groups[list.list.id, default: []].append(IndexedListSource(
                discoveryIndex: index,
                source: list
            ))
        }

        var winners: [IndexedListSource] = []
        for id in groups.keys.sorted() {
            guard let candidates = groups[id] else { continue }
            let ordered = candidates.sorted(by: listSourceIsPreferred)
            guard let winner = ordered.first else { continue }

            var isolatedEveryLoser = true
            for loser in ordered.dropFirst() {
                isolatedEveryLoser = quarantine(
                    loser.source.headerURL,
                    reason: "Duplicate list id \(id); kept \(winner.source.headerURL.path)",
                    into: &quarantined
                ) && isolatedEveryLoser
            }

            if isolatedEveryLoser {
                winners.append(winner)
            } else {
                blockedListIds.insert(id)
                recordIssue(
                    winner.source.headerURL,
                    reason: "List id \(id) remains ambiguous because a duplicate header could not be isolated",
                    into: &quarantined
                )
            }
        }

        return winners
            .sorted { $0.discoveryIndex < $1.discoveryIndex }
            .map(\.source)
    }

    private func listSourceIsPreferred(
        _ lhs: IndexedListSource,
        _ rhs: IndexedListSource
    ) -> Bool {
        if lhs.source.list.lamport != rhs.source.list.lamport {
            return lhs.source.list.lamport > rhs.source.list.lamport
        }
        if lhs.source.list.modifiedAt != rhs.source.list.modifiedAt {
            return lhs.source.list.modifiedAt > rhs.source.list.modifiedAt
        }

        let lhsIsTombstone = lhs.source.list.deletedAt != nil
        let rhsIsTombstone = rhs.source.list.deletedAt != nil
        if lhsIsTombstone != rhsIsTombstone {
            return lhsIsTombstone
        }

        if lhs.source.rawHeaderData != rhs.source.rawHeaderData {
            return lhs.source.rawHeaderData.lexicographicallyPrecedes(
                rhs.source.rawHeaderData
            )
        }
        return lhs.source.headerURL.standardizedFileURL.path
            < rhs.source.headerURL.standardizedFileURL.path
    }

    /// Make physical list nesting match the resolved parent graph before item
    /// discovery. Moving the whole directory preserves headers, items,
    /// descendants, and unknown auxiliary bytes together.
    private func canonicalizeListDirectories(
        _ lists: [LoadedList],
        blockedListIds: inout Set<String>,
        quarantined: inout [QuarantinedFile]
    ) -> [LoadedList] {
        var resolved = lists
        let listById = Dictionary(
            lists.map { ($0.list.id, $0.list) },
            uniquingKeysWith: { _, later in later }
        )

        func safeParentId(for list: ItemList) -> String? {
            guard let parentId = list.parentId,
                  parentId != list.id,
                  let parent = listById[parentId],
                  parent.deletedAt == nil || list.deletedAt != nil else {
                return nil
            }
            var seen: Set<String> = [list.id]
            var cursor: String? = parentId
            while let id = cursor, let current = listById[id] {
                guard seen.insert(id).inserted else { return nil }
                cursor = current.parentId
            }
            return parentId
        }

        func depth(of list: ItemList) -> Int {
            var depth = 0
            var seen: Set<String> = [list.id]
            var cursor = safeParentId(for: list)
            while let id = cursor,
                  let parent = listById[id],
                  seen.insert(id).inserted {
                depth += 1
                cursor = safeParentId(for: parent)
            }
            return depth
        }

        func logicallyDescends(_ candidate: ItemList, from ancestorId: String) -> Bool {
            var seen: Set<String> = [candidate.id]
            var cursor = candidate.parentId
            while let id = cursor,
                  let parent = listById[id],
                  seen.insert(id).inserted {
                if id == ancestorId { return true }
                cursor = parent.parentId
            }
            return false
        }

        let order = lists.indices.sorted {
            let lhsDepth = depth(of: lists[$0].list)
            let rhsDepth = depth(of: lists[$1].list)
            if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }
            return lists[$0].list.id < lists[$1].list.id
        }
        let fm = FileManager.default

        for index in order {
            let list = resolved[index].list
            guard !blockedListIds.contains(list.id) else { continue }
            let current = resolved[index].directory.standardizedFileURL

            let parentDirectory: URL
            if let parentId = safeParentId(for: list),
               let parent = resolved.first(where: { $0.list.id == parentId }),
               !blockedListIds.contains(parentId) {
                parentDirectory = parent.directory.standardizedFileURL
            } else {
                parentDirectory = root.standardizedFileURL
            }

            var candidateName = Self.sanitize(list.name)
            var suffix = 2
            var target = parentDirectory.appendingPathComponent(
                candidateName,
                isDirectory: true
            ).standardizedFileURL
            while fm.fileExists(atPath: target.path), target != current {
                candidateName = "\(Self.sanitize(list.name)) (\(suffix))"
                suffix += 1
                target = parentDirectory.appendingPathComponent(
                    candidateName,
                    isDirectory: true
                ).standardizedFileURL
            }
            guard target != current else { continue }

            do {
                guard !target.path.hasPrefix(current.path + "/") else {
                    throw CocoaError(.fileWriteInvalidFileName, userInfo: [
                        NSFilePathErrorKey: target.path
                    ])
                }
                try fm.createDirectory(
                    at: parentDirectory,
                    withIntermediateDirectories: true
                )
                try fm.moveItem(at: current, to: target)

                for descendantIndex in resolved.indices {
                    let oldDirectory = resolved[descendantIndex].directory
                        .standardizedFileURL
                    guard oldDirectory == current
                            || oldDirectory.path.hasPrefix(current.path + "/") else {
                        continue
                    }
                    let relativePath = String(
                        oldDirectory.path.dropFirst(current.path.count)
                    ).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let newDirectory = relativePath.isEmpty
                        ? target
                        : target.appendingPathComponent(relativePath, isDirectory: true)
                    let previous = resolved[descendantIndex]
                    resolved[descendantIndex] = LoadedList(
                        list: previous.list,
                        items: previous.items,
                        directory: newDirectory,
                        headerURL: newDirectory.appendingPathComponent(".list.yml"),
                        rawHeaderData: previous.rawHeaderData
                    )
                }
            } catch {
                let failedId = list.id
                let failedPath = current.path
                for candidate in resolved where
                    candidate.directory.standardizedFileURL == current
                        || candidate.directory.standardizedFileURL.path.hasPrefix(failedPath + "/")
                        || logicallyDescends(candidate.list, from: failedId) {
                    blockedListIds.insert(candidate.list.id)
                }
                recordIssue(
                    current,
                    reason: "Could not place list \(failedId) under its resolved parent: \(error)",
                    into: &quarantined
                )
            }
        }

        return resolved.filter { !blockedListIds.contains($0.list.id) }
    }

    /// Read every live item candidate after list discovery has settled folder
    /// migrations. This includes files beside missing or quarantined headers,
    /// which would otherwise be invisible and could make bootstrap mistake a
    /// damaged library for an empty one.
    private func discoverItemSources(
        alongside lists: [LoadedList],
        quarantined: inout [QuarantinedFile]
    ) -> [LoadedItemSource] {
        let directoryToListId = Dictionary(
            lists.map { ($0.directory.standardizedFileURL.path, $0.list.id) },
            uniquingKeysWith: { _, later in later }
        )
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            recordIssue(
                root,
                reason: "Could not enumerate item files",
                into: &quarantined
            )
            return []
        }

        let urls = enumerator
            .compactMap { $0 as? URL }
            .filter {
                $0.pathExtension == "md"
                    && !$0.lastPathComponent.hasPrefix("_")
                    && (try? $0.resourceValues(
                        forKeys: [.isRegularFileKey]
                    ))?.isRegularFile == true
            }
            .sorted { $0.standardizedFileURL.path < $1.standardizedFileURL.path }

        var sources: [LoadedItemSource] = []
        for url in urls {
            do {
                let rawData = try Data(contentsOf: url)
                guard let content = String(data: rawData, encoding: .utf8) else {
                    throw CocoaError(.fileReadInapplicableStringEncoding)
                }
                let item = try FrontmatterCodec.decode(content)
                let directory = url.deletingLastPathComponent().standardizedFileURL
                sources.append(LoadedItemSource(
                    item: item,
                    url: url,
                    containingListId: directoryToListId[directory.path],
                    containingDirectory: directory,
                    rawData: rawData
                ))
            } catch {
                quarantine(url, error: error, into: &quarantined)
            }
        }
        return sources
    }

    /// Resolve crash-left duplicate UUIDs before ItemStore sees them. The
    /// chosen value is deterministic from stored content, every losing file is
    /// moved aside byte-for-byte, and the winner is copied into its declared
    /// list using the canonical UUID filename when possible.
    private func resolveDuplicateItems(
        _ itemSources: [LoadedItemSource],
        in lists: [LoadedList],
        blockedListIds: Set<String>,
        quarantined: inout [QuarantinedFile]
    ) -> [LoadedList] {
        var groups: [UUID: [IndexedItemSource]] = [:]
        for (discoveryIndex, source) in itemSources.enumerated() {
            groups[source.item.id, default: []].append(IndexedItemSource(
                discoveryIndex: discoveryIndex,
                source: source
            ))
        }

        var orderedGroups: [[IndexedItemSource]] = []
        for id in groups.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let candidates = groups[id] else { continue }
            let ordered = candidates.sorted(by: itemSourceIsPreferred)
            if !ordered.isEmpty { orderedGroups.append(ordered) }
        }

        var resolvedLists = lists
        let preferredSources = orderedGroups.compactMap(\.first)
        let missingListIds = Set(preferredSources.map(\.source.item.listId)).filter {
            !blockedListIds.contains($0)
                && canonicalListIndex(for: $0, in: resolvedLists) == nil
        }
        for listId in missingListIds.sorted() {
            guard let source = preferredSources.first(where: {
                $0.source.item.listId == listId
            })?.source else { continue }
            do {
                let directory = try materializeRecoveryList(for: listId)
                let headerURL = directory.appendingPathComponent(".list.yml")
                let rawHeaderData = try Data(contentsOf: headerURL)
                let list = try readList(at: headerURL)
                resolvedLists.append(LoadedList(
                    list: list,
                    items: [],
                    directory: directory,
                    headerURL: headerURL,
                    rawHeaderData: rawHeaderData
                ))
            } catch {
                recordIssue(
                    source.url,
                    reason: "Could not materialize recovered list \(listId): \(error)",
                    into: &quarantined
                )
            }
        }

        var resolvedSources: [(Int, Int, LoadedItemSource)] = []
        for ordered in orderedGroups {
            guard let preferred = ordered.first else { continue }
            guard let selected = ordered.first(where: {
                !blockedListIds.contains($0.source.item.listId)
                    && canonicalListIndex(
                        for: $0.source.item.listId,
                        in: resolvedLists
                    ) != nil
            }), let targetIndex = canonicalListIndex(
                for: selected.source.item.listId,
                in: resolvedLists
            ) else {
                recordIssue(
                    preferred.source.url,
                    reason: "No safe list container is available for item \(preferred.source.item.id)",
                    into: &quarantined
                )
                continue
            }

            var isolatedEveryLoser = true
            for loser in ordered where loser.source.url != selected.source.url {
                isolatedEveryLoser = quarantine(
                    loser.source.url,
                    reason: "Duplicate item id \(selected.source.item.id); kept \(selected.source.url.path)",
                    into: &quarantined
                ) && isolatedEveryLoser
            }
            guard isolatedEveryLoser else {
                recordIssue(
                    selected.source.url,
                    reason: "Item id \(selected.source.item.id) remains ambiguous because a duplicate could not be isolated",
                    into: &quarantined
                )
                continue
            }

            let targetDirectory = resolvedLists[targetIndex].directory
            guard let canonical = canonicalize(
                selected.source,
                into: targetDirectory,
                quarantined: &quarantined
            ) else { continue }
            itemPathById[canonical.item.id] = canonical.url.standardizedFileURL
            resolvedSources.append((selected.discoveryIndex, targetIndex, canonical))
        }

        resolvedSources.sort { $0.0 < $1.0 }
        var sourcesByList = Array(
            repeating: [LoadedItemSource](),
            count: resolvedLists.count
        )
        for (_, targetIndex, source) in resolvedSources {
            sourcesByList[targetIndex].append(source)
        }

        return resolvedLists.enumerated().map { index, loaded in
            let sources = sourcesByList[index]
            return LoadedList(
                list: loaded.list,
                items: sources.map(\.item),
                directory: loaded.directory,
                headerURL: loaded.headerURL,
                rawHeaderData: loaded.rawHeaderData
            )
        }
    }

    private func itemSourceIsPreferred(
        _ lhs: IndexedItemSource,
        _ rhs: IndexedItemSource
    ) -> Bool {
        if lhs.source.item.modifiedAt != rhs.source.item.modifiedAt {
            return lhs.source.item.modifiedAt > rhs.source.item.modifiedAt
        }

        let lhsIsTombstone = lhs.source.item.deletedAt != nil
        let rhsIsTombstone = rhs.source.item.deletedAt != nil
        if lhsIsTombstone != rhsIsTombstone {
            return lhsIsTombstone
        }

        let lhsCanonical = canonicalScore(lhs.source)
        let rhsCanonical = canonicalScore(rhs.source)
        if lhsCanonical != rhsCanonical {
            return lhsCanonical > rhsCanonical
        }

        if lhs.source.rawData != rhs.source.rawData {
            return lhs.source.rawData.lexicographicallyPrecedes(rhs.source.rawData)
        }
        return lhs.source.url.path < rhs.source.url.path
    }

    private func canonicalScore(_ source: LoadedItemSource) -> Int {
        var score = 0
        if source.url.lastPathComponent == Self.documentBaseFileName(for: source.item) {
            score += 1
        }
        if source.containingListId == source.item.listId {
            score += 1
        }
        if pathById[source.item.listId]?.standardizedFileURL
            == source.containingDirectory.standardizedFileURL {
            score += 1
        }
        return score
    }

    private func canonicalListIndex(
        for listId: String,
        in lists: [LoadedList]
    ) -> Int? {
        guard let mapped = pathById[listId]?.standardizedFileURL else {
            return nil
        }
        return lists.firstIndex {
            $0.list.id == listId
                && $0.directory.standardizedFileURL == mapped
        }
    }

    private func canonicalize(
        _ source: LoadedItemSource,
        into directory: URL,
        quarantined: inout [QuarantinedFile]
    ) -> LoadedItemSource? {
        let destination: URL
        do {
            destination = try documentURL(
                for: source.item,
                in: directory,
                preserving: [source.url]
            ).standardizedFileURL
        } catch {
            recordIssue(
                source.url,
                reason: "Could not choose a readable filename for item \(source.item.id): \(error)",
                into: &quarantined
            )
            return nil
        }
        let original = source.url.standardizedFileURL
        guard original != destination else { return source }

        do {
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw CocoaError(.fileWriteFileExists, userInfo: [
                    NSFilePathErrorKey: destination.path
                ])
            }
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try source.rawData.write(to: destination, options: .atomic)
            try FileManager.default.removeItem(at: original)
            return LoadedItemSource(
                item: source.item,
                url: destination,
                containingListId: source.item.listId,
                containingDirectory: directory,
                rawData: source.rawData
            )
        } catch {
            recordIssue(
                original,
                reason: "Could not canonicalize item \(source.item.id): \(error)",
                into: &quarantined
            )
            return nil
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
            entries = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey]
            ).sorted { $0.standardizedFileURL.path < $1.standardizedFileURL.path }
        } catch {
            // An unreadable directory degrades to a recorded issue, not a
            // failed load; its siblings still get walked.
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
    @discardableResult
    private func quarantine(
        _ url: URL,
        error: Error,
        into acc: inout [QuarantinedFile]
    ) -> Bool {
        quarantine(url, reason: String(describing: error), into: &acc)
    }

    @discardableResult
    private func quarantine(
        _ url: URL,
        reason: String,
        into acc: inout [QuarantinedFile]
    ) -> Bool {
        let fm = FileManager.default
        let qDir = root.appendingPathComponent(".quarantine", isDirectory: true)
        let original = url.path
        do {
            try fm.createDirectory(at: qDir, withIntermediateDirectories: true)
            var dest = qDir.appendingPathComponent(url.lastPathComponent)
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                let base = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension
                dest = qDir.appendingPathComponent(
                    ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
                )
                n += 1
            }
            try fm.moveItem(at: url, to: dest)
            acc.append(QuarantinedFile(originalPath: original, reason: reason))
            return true
        } catch {
            acc.append(QuarantinedFile(
                originalPath: original,
                reason: "\(reason). Quarantine move failed: \(error)"
            ))
            return false
        }
    }

    private func recordIssue(
        _ url: URL,
        reason: String,
        into acc: inout [QuarantinedFile]
    ) {
        acc.append(QuarantinedFile(originalPath: url.path, reason: reason))
    }

    /// Record a directory that couldn't be enumerated without moving anything:
    /// the folder stays where it is, but the failure surfaces in
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

    static func documentBaseFileName(for item: Item) -> String {
        "\(sanitize(item.title)).md"
    }

    /// Select a readable filename without ever overwriting a different item.
    /// A previously disambiguated `Title (2).md` remains stable until the
    /// title itself changes. Numeric suffixes preserve old, imported, or
    /// temporarily duplicated titles without leaking UUIDs or losing data.
    private func documentURL(for item: Item,
                             in directory: URL,
                             preserving existing: [URL]) throws -> URL {
        let base = Self.sanitize(item.title)
        let scopedExisting = existing.filter {
            $0.deletingLastPathComponent().standardizedFileURL
                == directory.standardizedFileURL
        }
        if let current = scopedExisting.first(where: { candidate in
            let stem = candidate.deletingPathExtension().lastPathComponent
            guard stem == base || stem.hasPrefix("\(base) (") else { return false }
            return (try? readItem(at: candidate).id) == item.id
        }) {
            return current
        }

        // A directory occupying the exact document name is not an ordinary
        // duplicate-title collision. Silently escaping to `Title (2).md`
        // would hide a malformed/external library layout and make the file's
        // public identity disagree with its title. Preserve the directory and
        // surface the conflict so the caller can recover deliberately.
        let requested = directory.appendingPathComponent("\(base).md")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: requested.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            throw CocoaError(.fileWriteFileExists, userInfo: [
                NSFilePathErrorKey: requested.path,
                NSLocalizedDescriptionKey: "A directory already occupies the document path \(requested.lastPathComponent)."
            ])
        }

        var suffix = 1
        while true {
            let stem = suffix == 1 ? base : "\(base) (\(suffix))"
            let candidate = directory.appendingPathComponent("\(stem).md")
            guard FileManager.default.fileExists(atPath: candidate.path) else {
                return candidate
            }
            if (try? readItem(at: candidate).id) == item.id {
                return candidate
            }
            suffix += 1
        }
    }
}
