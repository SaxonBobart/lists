import Foundation
import UIKit
import UniformTypeIdentifiers

/// A destination is independent of the screen offering Paste. No date means
/// preserve the copied schedule; a slot changes the start, never the duration.
struct ItemPasteDestination {
    var listId: String?
    var section: String?
    var parentId: UUID?
    var afterId: UUID?
    var schedule: CalendarCaptureSchedule?
}

struct ItemClipboardPayload: Codable, Sendable {
    var version = 1
    var documents: [String]
    var attachments: [String: Data]
    var cutRoot: UUID?
    var cutToken: UUID?

    func items() throws -> [Item] {
        guard version == 1, !documents.isEmpty else { throw ItemClipboard.Failure.invalidContents }
        let items = try documents.map(FrontmatterCodec.decode)
        guard Set(items.map(\.id)).count == items.count else { throw ItemClipboard.Failure.invalidContents }
        return items
    }
}

@MainActor @Observable final class ItemClipboard {
    static let shared = ItemClipboard()
    static let typeIdentifier = "io.github.saxonbobart.lists.items"
    private(set) var revision = 0
    private var cached: ItemClipboardPayload?
    private var copiedChangeCount = -1
    private var busy = false
    private let consumedKey = "lists.clipboard.consumed-cuts"
    private var undoCutOperation: (@MainActor () async throws -> Void)?
    var canUndoCut: Bool { undoCutOperation != nil }

    func registerUndoCut(_ operation: @escaping @MainActor () async throws -> Void) {
        undoCutOperation = operation
    }

    func undoCut() async throws {
        guard !busy, let operation = undoCutOperation else { return }
        busy = true
        defer { busy = false }
        try await operation()
        undoCutOperation = nil
    }

    enum Failure: LocalizedError {
        case invalidContents, busy, missingDestination
        var errorDescription: String? {
            switch self {
            case .invalidContents: "The clipboard does not contain a Lists item."
            case .busy: "Another clipboard operation is still finishing."
            case .missingDestination: "Choose an active list before pasting."
            }
        }
    }

    // Inspects types only. Clipboard content is read exclusively after Paste.
    var canPaste: Bool {
        _ = revision
        return UIPasteboard.general.contains(pasteboardTypes: [Self.typeIdentifier])
    }

    func read() throws -> ItemClipboardPayload {
        if copiedChangeCount == UIPasteboard.general.changeCount, let cached { return cached }
        guard let data = UIPasteboard.general.data(forPasteboardType: Self.typeIdentifier) else { throw Failure.invalidContents }
        let payload = try JSONDecoder().decode(ItemClipboardPayload.self, from: data)
        _ = try payload.items()
        return payload
    }

    func prepare(_ item: Item, store: ItemStore, includeChildren: Bool = true) async throws -> ItemClipboardPayload {
        var members = [item]
        var known: Set<UUID> = [item.id]
        if includeChildren {
            var offset = 0
            while offset < members.count {
                for child in store.items.filter({ $0.parentId == members[offset].id && $0.deletedAt == nil })
                    .sorted(by: { $0.sortIndex < $1.sortIndex }) where known.insert(child.id).inserted {
                    members.append(child)
                }
                offset += 1
            }
        }
        var attachments: [String: Data] = [:]
        let paths = Set(members.flatMap { item in
            MarkdownMediaReference.references(in: item.body).compactMap { MarkdownAttachmentIndex.canonicalPath($0.path) }
        })
        for path in paths {
            let url = try await store.attachmentURL(for: path)
            attachments[path] = try Data(contentsOf: url)
        }
        return try .init(documents: members.map(FrontmatterCodec.encode), attachments: attachments)
    }

    func write(_ payload: ItemClipboardPayload) throws {
        let data = try JSONEncoder().encode(payload)
        let markdown = payload.documents.joined(separator: "\n\n")
        UIPasteboard.general.setItems([[Self.typeIdentifier: data, UTType.utf8PlainText.identifier: markdown]])
        cached = payload
        copiedChangeCount = UIPasteboard.general.changeCount
        revision += 1
    }

    func copy(_ item: Item, store: ItemStore) async throws { try write(await prepare(item, store: store)) }

    func cut(_ item: Item, store: ItemStore, undoManager: UndoManager?) async throws {
        guard !busy else { throw Failure.busy }
        busy = true
        defer { busy = false }
        var payload = try await prepare(item, store: store)
        payload.cutRoot = item.id
        payload.cutToken = UUID()
        try write(payload)
        try await store.softDelete(item.id)
        undoCutOperation = { try await store.restore(item.id) }
        undoManager?.registerUndo(withTarget: store) { target in
            Task { @MainActor in
                do { try await target.restore(item.id) }
                catch { target.reportClipboardFailure(error) }
            }
        }
        undoManager?.setActionName("Cut")
    }

    static func copies(_ originals: [Item], destination: ItemPasteDestination, now: Date = .now) -> [Item] {
        guard let root = originals.first else { return [] }
        let ids = Dictionary(uniqueKeysWithValues: originals.map { ($0.id, UUID()) })
        let shift = destination.schedule.flatMap { schedule in root.due.map { schedule.start.timeIntervalSince($0) } } ?? 0
        return originals.enumerated().map { index, original in
            var item = original
            item.id = ids[original.id]!
            item.calendarImport = nil
            item.parentId = index == 0 ? destination.parentId : original.parentId.flatMap { ids[$0] }
            item.listId = destination.listId ?? root.listId
            item.section = destination.section
            item.createdAt = now
            item.modifiedAt = now
            item.deletedAt = nil
            item.done = false
            item.completedAt = nil
            item.completions = []
            item.recurrenceOccurrences = []
            item.recurrenceSourceId = nil
            item.recurrenceSuccessorId = nil
            if let schedule = destination.schedule {
                if index == 0 {
                    let duration = original.end.flatMap { end in original.due.map { end.timeIntervalSince($0) } }
                    item.due = schedule.start
                    item.dueAllDay = schedule.isAllDay
                    item.end = item.type == .event ? schedule.start.addingTimeInterval(duration ?? 3600) : nil
                    if schedule.isAllDay && item.type == .event { EventDefaults.normalize(&item) }
                } else {
                    item.due = original.due?.addingTimeInterval(shift)
                    item.end = original.end?.addingTimeInterval(shift)
                }
            }
            return item
        }
    }

    @discardableResult
    func paste(_ payload: ItemClipboardPayload? = nil, into destination: ItemPasteDestination,
               store: ItemStore, editedRoot: Item? = nil) async throws -> Item {
        guard !busy else { throw Failure.busy }
        busy = true
        defer { busy = false }
        let payload = try payload ?? read()
        var originals = try payload.items()
        let unedited = originals
        if var editedRoot {
            let root = originals[0]
            editedRoot.id = root.id
            if let location = root.triggers?.location {
                if editedRoot.triggers == nil { editedRoot.triggers = Triggers() }
                editedRoot.triggers?.location = location
            }
            let shift = root.due.flatMap { old in editedRoot.due.map { $0.timeIntervalSince(old) } } ?? 0
            for index in originals.indices.dropFirst() {
                originals[index].due = originals[index].due?.addingTimeInterval(shift)
                originals[index].end = originals[index].end?.addingTimeInterval(shift)
            }
            originals[0] = editedRoot
        }
        var destination = destination
        let sourceList = originals[0].listId
        destination.listId = [destination.listId, sourceList, ItemList.inboxId].compactMap { $0 }.first { id in
            store.lists.contains { $0.id == id && $0.deletedAt == nil }
        }
        guard destination.listId != nil else { throw Failure.missingDestination }
        // Attachments remain valid even if the cut source has been purged.
        guard payload.attachments.keys.allSatisfy({ MarkdownAttachmentIndex.canonicalPath($0) != nil }) else {
            throw Failure.invalidContents
        }
        var attachmentReplacements: [String: String] = [:]
        for (path, data) in payload.attachments {
            guard let canonical = MarkdownAttachmentIndex.canonicalPath(path) else { throw Failure.invalidContents }
            let existing = try? await store.attachmentURL(for: path)
            let existingData = existing.flatMap { try? Data(contentsOf: $0) }
            if existingData != data {
                let attachment = try await store.importAttachment(data: data, originalFileName: (path as NSString).lastPathComponent)
                attachmentReplacements[canonical] = attachment.relativePath
            }
        }
        for index in originals.indices {
            for reference in MarkdownMediaReference.references(in: originals[index].body).reversed() {
                guard let path = MarkdownAttachmentIndex.canonicalPath(reference.path),
                      let replacement = attachmentReplacements[path] else { continue }
                originals[index].body = (originals[index].body as NSString)
                    .replacingCharacters(in: reference.destinationRange, with: replacement)
            }
        }
        var copies = Self.copies(originals, destination: destination)
        // Copies have new identities, so ordinary move-time link rewriting
        // cannot rebase them. Make their attachment links portable here too.
        for index in copies.indices {
            for reference in MarkdownMediaReference.references(in: copies[index].body).reversed() {
                let rebased = DocumentMarkdownIndex.attachmentDestination(reference.path, from: copies[index], lists: store.lists)
                copies[index].body = (copies[index].body as NSString)
                    .replacingCharacters(in: reference.destinationRange, with: rebased)
            }
        }
        let consumed = Set(UserDefaults.standard.stringArray(forKey: consumedKey) ?? [])
        if let cutID = payload.cutRoot, let token = payload.cutToken, !consumed.contains(token.uuidString),
           let cut = store.item(cutID), cut.deletedAt != nil {
            try await store.restore(cutID)
            do {
                for (original, copy) in zip(originals, copies) {
                    guard let previous = store.item(original.id) else { throw Failure.invalidContents }
                    var moved = original
                    moved.createdAt = previous.createdAt
                    moved.deletedAt = nil
                    moved.listId = copy.listId
                    moved.section = copy.section
                    moved.parentId = original.id == cutID ? destination.parentId : original.parentId
                    moved.due = copy.due
                    moved.end = copy.end
                    moved.dueAllDay = copy.dueAllDay
                    moved.body = copy.body
                    moved.title = copy.title
                    try await store.update(moved)
                }
                try await insertOrder(root: cutID, destination: destination, store: store)
                UserDefaults.standard.set(Array(consumed.union([token.uuidString])), forKey: consumedKey)
                undoCutOperation = nil
                return store.item(cutID) ?? cut
            } catch {
                // Restore the original cut state if the move cannot complete.
                for original in unedited { try? await store.update(original) }
                try? await store.softDelete(cutID)
                throw error
            }
        }
        var added: [UUID] = []
        do {
            for copy in copies { try await store.add(copy); added.append(copy.id) }
            try await insertOrder(root: copies[0].id, destination: destination, store: store)
            return store.item(copies[0].id) ?? copies[0]
        } catch {
            // A partial paste is recoverable but must not appear as success.
            if let root = added.first { try? await store.softDelete(root) }
            throw error
        }
    }

    private func insertOrder(root: UUID, destination: ItemPasteDestination, store: ItemStore) async throws {
        guard let listId = destination.listId else { return }
        var siblings = store.items.filter {
            $0.deletedAt == nil && $0.listId == listId && $0.section == destination.section && $0.parentId == destination.parentId && $0.id != root
        }.sorted { $0.sortIndex < $1.sortIndex }.map(\.id)
        let index = destination.afterId.flatMap { siblings.firstIndex(of: $0).map { $0 + 1 } } ?? siblings.count
        siblings.insert(root, at: index)
        try await store.reorderItems(in: listId, flatOrderedIds: siblings)
    }
}
