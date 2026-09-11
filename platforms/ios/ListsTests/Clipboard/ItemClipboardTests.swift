import Foundation
import Testing
import UIKit
@testable import Lists

@Suite(.serialized) @MainActor struct ItemClipboardTests {
    private func store() async throws -> ItemStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Clipboard-\(UUID())")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        return store
    }
    @Test func copiesKeepRepeatAndMetadataButRemapHierarchy() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let root = Item(type: .event, title: "Meeting", body: "**Notes**", listId: "inbox", tags: ["work"],
            done: true, due: start, end: start.addingTimeInterval(3600), priority: .high, flagged: true,
            reminder: .init(enabled: true, early: .init(value: 10, unit: .minute)), recurrence: .init(rrule: "FREQ=WEEKLY"))
        let child = Item(type: .task, title: "Prepare", listId: "inbox", parentId: root.id)
        let pasted = ItemClipboard.copies([root, child], destination: .init(listId: "destination", section: "section"))
        #expect(pasted[0].id != root.id)
        #expect(pasted[1].parentId == pasted[0].id)
        #expect(pasted[0].recurrence == root.recurrence)
        #expect(pasted[0].reminder == root.reminder)
        #expect(pasted[0].body == root.body)
        #expect(pasted[0].priority == .high && pasted[0].flagged)
        #expect(!pasted[0].done && pasted[0].recurrenceOccurrences.isEmpty)
        #expect(pasted[0].due == start)
    }
    @Test func slotPasteKeepsEventDurationAndTaskInstant() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let slot = start.addingTimeInterval(86400)
        let event = Item(type: .event, title: "Event", listId: "inbox", due: start, end: start.addingTimeInterval(5400))
        let copied = ItemClipboard.copies([event], destination: .init(schedule: .init(start: slot, isAllDay: false)))[0]
        #expect(copied.due == slot && copied.end == slot.addingTimeInterval(5400))
        let task = Item(type: .task, title: "Task", listId: "inbox", due: start)
        let taskCopy = ItemClipboard.copies([task], destination: .init(schedule: .init(start: slot, isAllDay: false)))[0]
        #expect(taskCopy.due == slot && taskCopy.end == nil)
    }
    @Test func payloadRoundTripsMarkdownBodyAndAttachments() async throws {
        let store = try await store()
        let file = try await store.importAttachment(data: Data("attachment".utf8), originalFileName: "test.txt")
        let item = Item(type: .note, title: "Note", body: "[File](\(file.relativePath))\nBody", listId: ItemList.inboxId)
        let payload = try await ItemClipboard.shared.prepare(item, store: store)
        let decoded = try JSONDecoder().decode(ItemClipboardPayload.self, from: JSONEncoder().encode(payload))
        #expect(try decoded.items()[0].body.contains("Body"))
        #expect(decoded.attachments[file.relativePath] == Data("attachment".utf8))
    }
    @Test func immediateCutMovesOnceThenCopies() async throws {
        let store = try await store()
        let root = Item(type: .task, title: "Cut root", listId: ItemList.inboxId)
        let child = Item(type: .note, title: "Child", listId: root.listId, parentId: root.id)
        try await store.add(root)
        try await store.add(child)
        let clipboard = ItemClipboard()
        try await clipboard.cut(root, store: store, undoManager: nil)
        #expect(store.item(root.id)?.deletedAt != nil)
        #expect(store.item(child.id)?.deletedAt != nil)
        let first = try await clipboard.paste(into: .init(listId: root.listId), store: store)
        #expect(first.id == root.id && first.deletedAt == nil)
        #expect(store.item(child.id)?.deletedAt == nil)
        let second = try await clipboard.paste(into: .init(listId: root.listId), store: store)
        #expect(second.id != root.id)
        #expect(store.items.contains { $0.parentId == second.id && $0.deletedAt == nil })
    }
    @Test func draftReadDoesNotCreateAnythingAndPasteInsertsBeneath() async throws {
        let store = try await store()
        let first = Item(type: .task, title: "First", listId: ItemList.inboxId, sortIndex: 0)
        let last = Item(type: .task, title: "Last", listId: ItemList.inboxId, sortIndex: 1)
        try await store.add(first); try await store.add(last)
        let clipboard = ItemClipboard()
        try await clipboard.copy(first, store: store)
        let count = store.items.count
        let payload = try clipboard.read()
        #expect(store.items.count == count)
        let pasted = try await clipboard.paste(payload, into: .init(listId: first.listId, afterId: first.id), store: store)
        let ordered = store.items.filter { [first.id, last.id, pasted.id].contains($0.id) }.sorted { $0.sortIndex < $1.sortIndex }
        #expect(ordered.map(\.id) == [first.id, pasted.id, last.id])
    }
    @Test func futureOccurrenceExclusionRoundTripsAndDoesNotAdvanceCurrent() throws {
        let current = Date(timeIntervalSince1970: 1_800_000_000)
        let future = current.addingTimeInterval(86400)
        let item = Item(type: .task, title: "Repeat", listId: ItemList.inboxId, due: current,
            recurrence: .init(rrule: "FREQ=DAILY", excludedDates: [ISO8601.string(from: future)]))
        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))
        #expect(decoded.due == current)
        #expect(decoded.recurrence?.excludes(future) == true)
        let next = try #require(CalendarTimelinePolicy.deletingCurrentOccurrence(from: decoded))
        #expect(next.due == future.addingTimeInterval(86400))
    }
    @Test func cutUndoRestoresTreeAndLaterPasteCopies() async throws {
        let store = try await store()
        let item = Item(type: .task, title: "Undo", listId: ItemList.inboxId)
        try await store.add(item)
        let clipboard = ItemClipboard()
        try await clipboard.cut(item, store: store, undoManager: nil)
        #expect(clipboard.canUndoCut)
        try await clipboard.undoCut()
        #expect(store.item(item.id)?.deletedAt == nil)
        #expect(!clipboard.canUndoCut)
        let pasted = try await clipboard.paste(into: .init(listId: item.listId), store: store)
        #expect(pasted.id != item.id)
    }

    @Test func consumedCutCannotMoveTwiceEvenAfterAnotherDeletion() async throws {
        let store = try await store()
        let item = Item(type: .task, title: "Once", listId: ItemList.inboxId)
        try await store.add(item)
        let clipboard = ItemClipboard()
        try await clipboard.cut(item, store: store, undoManager: nil)
        let payload = try clipboard.read()
        let moved = try await clipboard.paste(payload, into: .init(listId: item.listId), store: store)
        try await store.softDelete(moved.id)
        let copied = try await clipboard.paste(payload, into: .init(listId: item.listId), store: store)
        #expect(copied.id != moved.id)
    }

    @Test func cutDraftPreservesEditedMetadataAndChildScheduleOffsets() async throws {
        let store = try await store()
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        let item = Item(type: .event, title: "Event", listId: ItemList.inboxId, due: time, end: time.addingTimeInterval(3600))
        let child = Item(type: .task, title: "Prepare", listId: item.listId, parentId: item.id, due: time.addingTimeInterval(-600))
        try await store.add(item); try await store.add(child)
        let clipboard = ItemClipboard()
        try await clipboard.cut(item, store: store, undoManager: nil)
        var draft = item
        draft.id = UUID()
        draft.due = time.addingTimeInterval(86400)
        draft.end = draft.due?.addingTimeInterval(5400)
        draft.flagged = true
        draft.priority = .high
        draft.tags = ["new"]
        draft.recurrence = .init(rrule: "FREQ=WEEKLY")
        let result = try await clipboard.paste(into: .init(listId: item.listId), store: store, editedRoot: draft)
        #expect(result.id == item.id)
        #expect(result.flagged && result.priority == .high && result.tags == ["new"])
        #expect(result.recurrence?.rrule == "FREQ=WEEKLY")
        #expect(store.item(child.id)?.due == time.addingTimeInterval(86400 - 600))
    }

    @Test func malformedClipboardFailsBeforeChangingLibrary() async throws {
        let store = try await store()
        let item = Item(type: .task, title: "Keep", listId: ItemList.inboxId)
        try await store.add(item)
        let before = store.items
        let payload = ItemClipboardPayload(documents: ["invalid"], attachments: [:])
        await #expect(throws: (any Error).self) {
            try await ItemClipboard().paste(payload, into: .init(listId: item.listId), store: store)
        }
        #expect(store.items == before)
    }

    @Test func nativeMenuUsesMediumHeaderAndCompactEditOrder() async throws {
        let store = try await store()
        let item = Item(type: .task, title: "Menu", listId: ItemList.inboxId)
        let actions = ItemActions(item: item, store: store, onOpen: {}, onDelete: {}, onError: { _ in })
        let header = try #require(actions.menu().children.first as? UIMenu)
        #expect(header.preferredElementSize == .medium)
        #expect(header.children.map(\.title) == ["Details", "Flag", "Delete"])
        #expect(actions.menu(compact: true).children.prefix(4).map(\.title) == ["Cut", "Copy", "Delete", "Duplicate"])
    }

}
