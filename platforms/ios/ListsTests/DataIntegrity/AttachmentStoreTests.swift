import Foundation
import SwiftUI
import UIKit
import Testing
@testable import Lists

struct AttachmentStoreTests {
    @Test func aliasedLibraryRootImportsMovesAndReloadsOriginalBytes() async throws {
        let directory = freshRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let realRoot = directory.appendingPathComponent("real/Lists", isDirectory: true)
        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        let alias = directory.appendingPathComponent("sandbox-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: realRoot.deletingLastPathComponent())
        let files = FileStore(root: alias.appendingPathComponent("Lists", isDirectory: true))
        try await files.writeList(.makeInbox())
        let destination = ItemList(id: "destination", name: "Destination", icon: "folder", color: .blue,
                                   createdAt: .now, modifiedAt: .now, position: 1)
        try await files.writeList(destination)
        let source = directory.appendingPathComponent("original.csv")
        let bytes = Data("name,value\nOriginal,42\n".utf8)
        try bytes.write(to: source)
        let imported = try await files.importStandaloneFile(fileURL: source, into: ItemList.inboxId)
        let moved = try await files.moveStandaloneFile(imported, to: destination.id, sortIndex: 0)
        #expect(try Data(contentsOf: await files.standaloneFileURL(moved)) == bytes)
        #expect(try await files.standaloneFiles(in: ItemList.inboxId).isEmpty)
        #expect(try await files.standaloneFiles(in: destination.id).map(\.id) == [moved.id])
        let attachment = try await files.importAttachment(data: bytes, originalFileName: "document.csv")
        #expect(try Data(contentsOf: await files.attachmentURL(for: attachment.relativePath)) == bytes)
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test @MainActor func sharedAttachmentMoveIntoDocumentKeepsOtherLinks() async throws {
        let root = freshRoot()
        let files = FileStore(root: root); try await files.ensureRoot(); try await files.writeList(.makeInbox())
        let other = ItemList(id: "other", name: "Other", icon: "folder", color: .blue, createdAt: .now, modifiedAt: .now, position: 1)
        try await files.writeList(other)
        let store = ItemStore(store: files); try await store.bootstrap()
        let bytes = Data("%PDF keep shared links".utf8)
        let attachment = try await store.importAttachment(data: bytes, originalFileName: "shared.pdf")
        let link = "[Shared](../\(attachment.relativePath))"
        let source = Item(type: .note, title: "Source", body: link, listId: ItemList.inboxId)
        let existing = Item(type: .task, title: "Existing reference", body: link, listId: ItemList.inboxId)
        let destination = Item(type: .event, title: "Destination", body: link, listId: other.id)
        try await store.add(source); try await store.add(existing); try await store.add(destination)
        let promoted = try await store.unlinkAttachment(attachment.relativePath, from: source.id, fileName: "shared.pdf")
        try await store.moveStandaloneFile(promoted, to: other.id)
        let moved = try #require(store.standaloneFiles.first { $0.id == promoted.id })
        try await store.attachStandaloneFile(moved, to: destination.id)
        #expect(store.standaloneFiles.isEmpty)
        #expect(store.item(existing.id)?.body == link)
        #expect(store.item(source.id)?.body == "")
        let destinationItem = try #require(store.item(destination.id))
        let refs = MarkdownMediaReference.distinctReferences(in: destinationItem.body)
        #expect(refs.count == 2)
        #expect(refs.contains { MarkdownAttachmentIndex.canonicalPath($0.path) == attachment.relativePath })
        for ref in refs {
            let url = try await store.attachmentURL(for: ref.path)
            #expect(try Data(contentsOf: url) == bytes)
        }
        #expect(try await store.deletedStandaloneFiles().contains { $0.id == promoted.id })
        try await store.flushPendingWrites()
        let reload = ItemStore(store: FileStore(root: root)); try await reload.bootstrap()
        #expect(reload.item(existing.id)?.body.trimmingCharacters(in: .newlines) == link)
        let originalURL = try await reload.attachmentURL(for: attachment.relativePath)
        #expect(try Data(contentsOf: originalURL) == bytes)
        let reloadedDestination = try #require(reload.item(destination.id))
        #expect(MarkdownMediaReference.distinctReferences(in: reloadedDestination.body).count == 2)
    }


    @Test @MainActor func sharedAttachmentUnlinkRecoveryAndBodyUndoPreserveEveryReference() async throws {
        let root = freshRoot()
        let files = FileStore(root: root)
        try await files.ensureRoot()
        try await files.writeList(.makeInbox())
        let store = ItemStore(store: files)
        try await store.bootstrap()
        let bytes = Data("%PDF shared content".utf8)
        let attachment = try await store.importAttachment(data: bytes, originalFileName: "shared.pdf")
        let link = "[Shared](../\(attachment.relativePath))"
        let original = "Before \(link) and \(link) after.\n`\(link)`"
        let a = Item(type: .note, title: "A", body: original, listId: ItemList.inboxId)
        let b = Item(type: .note, title: "B", body: link, listId: ItemList.inboxId)
        try await store.add(a); try await store.add(b)
        #expect(store.attachmentReferenceCount(attachment.relativePath, excluding: a.id) == 1)
        let kept = try await store.unlinkAttachment(attachment.relativePath, from: a.id, fileName: "shared.pdf")
        #expect(store.item(a.id)?.body == "Before  and  after.\n`\(link)`")
        #expect(store.item(b.id)?.body == link)
        let originalURL = try await store.attachmentURL(for: attachment.relativePath)
        let keptURL = try await store.standaloneFileURL(kept)
        #expect(try Data(contentsOf: originalURL) == bytes)
        #expect(try Data(contentsOf: keptURL) == bytes)
        #expect(store.standaloneFiles.count == 1)
        try await store.undoAttachmentUnlink(kept, documentID: a.id, body: original)
        #expect(store.standaloneFiles.isEmpty)
        #expect(store.item(a.id)?.body == original)
        let deleted = try await store.unlinkAttachment(attachment.relativePath, from: a.id, fileName: "shared.pdf", toRecentlyDeleted: true)
        #expect(deleted.deletedAt != nil)
        #expect(store.item(b.id)?.body == link)
        #expect(try Data(contentsOf: originalURL) == bytes)
        try await store.undoAttachmentUnlink(deleted, documentID: a.id, body: original)
        #expect(store.standaloneFiles.isEmpty)
        try await store.flushPendingWrites()
        let reload = ItemStore(store: FileStore(root: root)); try await reload.bootstrap()
        #expect(reload.item(a.id)?.body.trimmingCharacters(in: .newlines) == original)
        #expect(reload.item(b.id)?.body.trimmingCharacters(in: .newlines) == link)
        #expect(reload.standaloneFiles.isEmpty)
    }

    @Test @MainActor func fileMoveSessionUsesExistingDestinationsAndCanAttachToAnItem() async throws {
        let root = freshRoot()
        let files = FileStore(root: root)
        try await files.ensureRoot(); try await files.writeList(.makeInbox())
        let other = ItemList(id: "other", name: "Other", icon: "folder", color: .blue, createdAt: .now, modifiedAt: .now, position: 1)
        try await files.writeList(other)
        let store = ItemStore(store: files); try await store.bootstrap()
        let document = Item(type: .note, title: "Destination", listId: other.id)
        try await store.add(document)
        let source = root.appendingPathComponent("input.pdf")
        let bytes = Data("%PDF shelf file".utf8); try bytes.write(to: source)
        let file = try await store.importStandaloneFile(fileURL: source, into: ItemList.inboxId)
        let session = ItemMoveSession(); session.begin(file: file)
        #expect(session.isActive)
        #expect(session.movingTitle(in: store) == file.fileName)
        #expect(session.canPickParent(document.id, in: store))
        try await store.moveStandaloneFile(file, to: other.id, section: "Work")
        let moved = try #require(store.standaloneFiles.first { $0.id == file.id })
        #expect(moved.section == "Work")
        try await store.attachStandaloneFile(moved, to: document.id)
        session.cancelIfMovingItemUnavailable(in: store)
        #expect(!session.isActive)
        #expect(store.standaloneFiles.isEmpty)
        let attachedDocument = try #require(store.item(document.id))
        let ref = try #require(MarkdownMediaReference.references(in: attachedDocument.body).first)
        let linked = try await store.attachmentURL(for: ref.path)
        #expect(try Data(contentsOf: linked) == bytes)
        #expect(try Data(contentsOf: source) == bytes)
        #expect(try await store.deletedStandaloneFiles().contains { $0.id == file.id })
        try await store.flushPendingWrites()
        let reload = ItemStore(store: FileStore(root: root)); try await reload.bootstrap()
        #expect(MarkdownMediaReference.references(in: try #require(reload.item(document.id)).body).count == 1)
    }

    @Test @MainActor func backspaceAndDanglingLinksNeverDeleteBytes() async throws {
        let root = freshRoot()
        let files = FileStore(root: root); try await files.ensureRoot(); try await files.writeList(.makeInbox())
        let store = ItemStore(store: files); try await store.bootstrap()
        let attachment = try await store.importAttachment(data: Data("keep me".utf8), originalFileName: "keep.txt")
        var document = Item(type: .note, title: "Backspace", body: "[Keep](../\(attachment.relativePath))", listId: ItemList.inboxId)
        try await store.add(document)
        document.body = ""; try await store.update(document)
        let url = try await store.attachmentURL(for: attachment.relativePath)
        #expect(try Data(contentsOf: url) == Data("keep me".utf8))
        let dangling = "Attachments/missing.pdf"
        document.body = "[Missing](../\(dangling))"; try await store.update(document)
        await #expect(throws: AttachmentStorageError.self) { try await store.unlinkAttachment(dangling, from: document.id, fileName: "missing.pdf") }
        #expect(store.item(document.id)?.body == document.body)
        #expect(store.standaloneFiles.isEmpty)
    }


    @Test @MainActor func collectionSnapshotInterleavesFilesAndWiresNativeActions() async throws {
        let root = freshRoot()
        let files = FileStore(root: root)
        try await files.ensureRoot()
        try await files.writeList(.makeInbox())
        let store = ItemStore(store: files)
        try await store.bootstrap()
        let first = Item(type: .note, title: "First", listId: ItemList.inboxId, sortIndex: 0)
        let last = Item(type: .task, title: "Last", listId: ItemList.inboxId, sortIndex: 1)
        try await store.add(first)
        try await store.add(last)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("NativeActions-" + UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: source) }
        try Data("%PDF native action fixture".utf8).write(to: source)
        let file = try await store.importStandaloneFile(fileURL: source, into: ItemList.inboxId)
        try await store.placeCollectionEntry(.file(file.id), in: ItemList.inboxId, before: .item(last.id))
        let defaultsName = "FileActions-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let view = ListDetailCollectionView(
            store: store, listId: ItemList.inboxId, prefs: ListViewPreferences(defaults: defaults), listColor: .blue,
            bridge: ListDetailBridge(), inSelectMode: .constant(false), selection: .constant([]),
            editingItemId: .constant(nil), editingSectionKey: .constant(nil), lingeringIds: [],
            defaultNewItemType: .task, moveSession: ItemMoveSession(),
            documentLinkSession: DocumentLinkSession(), onToggleItem: { _ in }, onSelectToggle: { _ in },
            onPromptDeleteSection: { _, _ in }, onSoftDeleteSubList: { _ in }, onSoftDeleteItem: { _ in },
            onPromoteOthers: { _ in }, onRenameSection: { _, _ in }, onShowItemDetail: { _ in },
            onOpenSubList: { _ in }, onBeginInlineEdit: { _ in }, onBeginMove: { _ in },
            onEndInlineEdit: { _ in }, onEndEditSection: {})
        let coordinator = view.makeCoordinator()
        coordinator.parent = view
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 393, height: 800), collectionViewLayout: UICollectionViewFlowLayout())
        coordinator.setupDataSource(for: collection)
        coordinator.applySnapshot(animated: false)
        let rows = coordinator.dataSource.snapshot().itemIdentifiers
        #expect(rows == [.item(id: first.id, indent: 0), .file(id: file.id), .item(id: last.id, indent: 0)])
        let path = try #require(coordinator.dataSource.indexPath(for: .file(id: file.id)))
        #expect(coordinator.trailingSwipeActions(for: path)?.actions.map(\.title) == ["Delete", "Open"])
        #expect(coordinator.leadingSwipeActions(for: path)?.actions.map(\.title) == ["Move"])
        let menu = coordinator.fileMenu(file, from: collection)
        #expect(menu.children.compactMap { ($0 as? UIAction)?.title } == ["Open", "Move", "Delete"])
        #expect(coordinator.collectionView(collection, contextMenuConfigurationForItemAt: path, point: .zero) != nil)
    }

    @Test @MainActor func mixedFileOrderingMovesAndRecoveryPersistWithoutWrappers() async throws {
        let root = freshRoot()
        let files = FileStore(root: root)
        try await files.ensureRoot()
        let inbox = ItemList.makeInbox()
        let destination = ItemList(id: "file-destination", name: "Destination", icon: "folder", color: .blue, createdAt: .now, modifiedAt: .now, position: 1)
        try await files.writeList(inbox)
        try await files.writeList(destination)
        let store = ItemStore(store: files)
        try await store.bootstrap()
        let first = Item(type: .note, title: "First", listId: inbox.id, sortIndex: 0)
        let last = Item(type: .task, title: "Last", listId: inbox.id, sortIndex: 1)
        let child = Item(type: .note, title: "Independent child", listId: inbox.id, parentId: first.id)
        try await store.add(first)
        try await store.add(last)
        try await store.add(child)
        let input = FileManager.default.temporaryDirectory.appendingPathComponent("FileOrderInput-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: input) }
        let source = input.appendingPathComponent("brief.pdf")
        let bytes = Data("%PDF local bytes".utf8)
        try bytes.write(to: source)
        let file = try await store.importStandaloneFile(fileURL: source, into: inbox.id)
        try await store.placeCollectionEntry(.file(file.id), in: inbox.id, before: .item(last.id))
        #expect(store.collectionEntries(in: inbox.id) == [.item(first.id), .file(file.id), .item(last.id)])
        try await store.placeCollectionEntry(.item(last.id), in: inbox.id, before: .file(file.id))
        #expect(store.collectionEntries(in: inbox.id) == [.item(first.id), .item(last.id), .file(file.id)])
        try await store.reorderItems(in: inbox.id, flatOrderedIds: [last.id, first.id, child.id])
        #expect(store.collectionEntries(in: inbox.id) == [.item(last.id), .item(first.id), .file(file.id)])
        #expect(store.item(child.id)?.parentId == first.id)
        try await store.flushPendingWrites()
        let reload = ItemStore(store: FileStore(root: root))
        try await reload.bootstrap()
        #expect(reload.collectionEntries(in: inbox.id) == store.collectionEntries(in: inbox.id))
        let current = try #require(reload.standaloneFiles.first)
        let duplicate = try await reload.importStandaloneFile(fileURL: source, into: destination.id)
        try await reload.moveStandaloneFile(current, to: destination.id)
        let moved = try #require(reload.standaloneFiles.first { $0.id == file.id })
        #expect(moved.listID == destination.id)
        #expect(moved.fileName == "brief (2).pdf")
        let movedURL = try await reload.standaloneFileURL(moved)
        #expect(try Data(contentsOf: movedURL) == bytes)
        #expect(try Data(contentsOf: source) == bytes)
        let deleted = try await reload.deleteStandaloneFile(moved)
        #expect(!reload.standaloneFiles.contains { $0.id == file.id })
        #expect(try await reload.deletedStandaloneFiles().map(\.id).contains(file.id))
        let afterDelete = ItemStore(store: FileStore(root: root))
        try await afterDelete.bootstrap()
        #expect(!afterDelete.standaloneFiles.contains { $0.id == file.id })
        try await afterDelete.restoreStandaloneFile(deleted)
        let restored = try #require(afterDelete.standaloneFiles.first { $0.id == file.id })
        #expect(restored.listID == destination.id)
        #expect(afterDelete.standaloneFiles.contains { $0.id == duplicate.id })
        let restoredURL = try await afterDelete.standaloneFileURL(restored)
        #expect(try Data(contentsOf: restoredURL) == bytes)
        #expect(afterDelete.items.count == 3)
        let final = ItemStore(store: FileStore(root: root))
        try await final.bootstrap()
        #expect(final.standaloneFiles.sorted { $0.id < $1.id } == afterDelete.standaloneFiles.sorted { $0.id < $1.id })
    }

    @Test func unindexedStandaloneFilesRemainReadableWithoutMigration() async throws {
        let root = freshRoot()
        let files = FileStore(root: root)
        try await files.ensureRoot()
        let list = ItemList.makeInbox()
        try await files.writeList(list)
        let directory = try await files.listDirectory(for: list.id).appendingPathComponent(".files")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "legacy-" + String(repeating: "x", count: 220) + ".txt"
        let raw = directory.appendingPathComponent(name)
        let bytes = Data("existing raw file".utf8)
        try bytes.write(to: raw)
        let loaded = try await files.loadStandaloneFiles()
        let file = try #require(loaded.first)
        #expect(file.fileName == name)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".standalone-files.json").path))
        let placed = try await files.updateStandaloneFilePlacement(file, sortIndex: 1, section: nil)
        #expect(try Data(contentsOf: raw) == bytes)
        #expect(try await files.loadStandaloneFiles().first?.sortIndex == 1)
        let deleted = try await files.deleteStandaloneFile(placed)
        #expect(UUID(uuidString: deleted.id) != nil)
        #expect(!FileManager.default.fileExists(atPath: raw.path))
        let restored = try await files.restoreStandaloneFile(deleted)
        let restoredURL = try await files.standaloneFileURL(restored)
        #expect(try Data(contentsOf: restoredURL) == bytes)
        #expect(restored.fileName == name)
        #expect(restored.sortIndex == 1)
    }

    @Test @MainActor func standaloneFilesRemainFilesAcrossImportRenameReloadAndExport() async throws {
        let root = freshRoot()
        let files = FileStore(root: root)
        try await files.ensureRoot()
        var list = ItemList.makeInbox()
        try await files.writeList(list)
        let inputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Lists-FileInput-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: inputDirectory) }
        let source = inputDirectory.appendingPathComponent("brief.md")
        let bytes = Data("# An ordinary Markdown file, with no item frontmatter".utf8)
        try bytes.write(to: source)
        let store = ItemStore(store: files)
        try await store.bootstrap()
        let first = try await store.importStandaloneFile(fileURL: source, into: list.id)
        let second = try await store.importStandaloneFile(fileURL: source, into: list.id)
        #expect(first.fileName == "brief.md")
        #expect(second.fileName == "brief (2).md")
        #expect(store.items.isEmpty)
        #expect(store.standaloneFiles.count == 2)
        list.name = "Renamed collection"
        try await store.updateList(list)
        let resolved = try await store.standaloneFileURL(first)
        #expect(try Data(contentsOf: resolved) == bytes)
        #expect(try Data(contentsOf: source) == bytes)
        let reloaded = ItemStore(store: FileStore(root: root))
        try await reloaded.bootstrap()
        #expect(reloaded.items.isEmpty)
        #expect(Set(reloaded.standaloneFiles.map(\.id)) == Set([first.id, second.id]))
        let reloadedURL = try await reloaded.standaloneFileURL(first)
        #expect(try Data(contentsOf: reloadedURL) == bytes)
        let archive = try LibraryExporter.exportLibrary(at: root)
        let exported = String(decoding: try Data(contentsOf: archive), as: UTF8.self)
        #expect(exported.contains(".files/brief.md"))
        #expect(exported.contains("An ordinary Markdown file"))
    }

    @Test func managedMarkdownAttachmentsAreNotDecodedAsItems() async throws {
        let root = freshRoot()
        let files = FileStore(root: root)
        try await files.ensureRoot()
        try await files.writeList(.makeInbox())
        let attachment = try await files.importAttachment(data: Data("# Plain uploaded Markdown".utf8), originalFileName: "example.md")
        let loaded = try await files.loadAll()
        #expect(loaded.lists.flatMap(\.items).isEmpty)
        #expect(loaded.quarantined.isEmpty)
        _ = try await files.attachmentURL(for: attachment.relativePath)
    }

    @Test func standaloneImportsRejectRedirectedDirectoriesWithoutChangingSource() async throws {
        let root = freshRoot()
        let files = FileStore(root: root)
        try await files.ensureRoot()
        let list = ItemList.makeInbox()
        try await files.writeList(list)
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.pdf")
        let bytes = Data("source bytes".utf8)
        try bytes.write(to: source)
        let listDirectory = try await files.listDirectory(for: list.id)
        try FileManager.default.createSymbolicLink(at: listDirectory.appendingPathComponent(".files"), withDestinationURL: outside)
        await #expect(throws: AttachmentStorageError.self) {
            _ = try await files.importStandaloneFile(fileURL: source, into: list.id)
        }
        #expect(try Data(contentsOf: source) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test @MainActor func linkedAttachmentsPersistAcrossReloadWithoutChangingItemPlacement() async throws {
        let root = freshRoot()
        let files = FileStore(root: root)
        try await files.ensureRoot()
        try await files.writeList(.makeInbox())
        let store = ItemStore(store: files)
        try await store.bootstrap()
        let attachment = try await store.importAttachment(data: Data("shared file".utf8), originalFileName: "brief.pdf")
        let original = Item(type: .note, title: "Original placement", body: "[Brief](\(attachment.relativePath))\n", listId: "inbox")
        try await store.add(original)
        var expected = [original]
        for type in [Item.ItemType.note, .task, .event] {
            var parent = Item(type: type, title: "Parent \(type.rawValue)", listId: "inbox")
            try await store.add(parent)
            let child = Item(type: .note, title: "Independent child", listId: "inbox", parentId: parent.id)
            try await store.add(child)
            parent.body = "[Brief](\(attachment.relativePath))\n"
            try await store.update(parent)
            expected += [parent, child]
        }
        try await store.flushPendingWrites()
        let reloaded = ItemStore(store: FileStore(root: root))
        try await reloaded.bootstrap()
        #expect(Set(reloaded.items.map(\.id)) == Set(expected.map(\.id)))
        for item in expected {
            let saved = try #require(reloaded.item(item.id))
            #expect(saved.parentId == item.parentId)
            #expect(saved.listId == item.listId)
            #expect(saved.body == item.body)
        }
        let previewURL = try await reloaded.attachmentURL(for: attachment.relativePath)
        #expect(try Data(contentsOf: previewURL) == Data("shared file".utf8))
    }

    @Test func attachmentDisclosureDeduplicatesPathsWithoutIncludingCodeExamples() {
        let body = """
        [Report](../Attachments/report.pdf)
        ![Another reference](Attachments/report.pdf)
        [Photo](Attachments/photo.png)
        `[Example](Attachments/example.txt)`
        ```
        [Sample](Attachments/sample.txt)
        ```
        """
        let references = MarkdownMediaReference.distinctReferences(in: body)
        #expect(references.map(\.label) == ["Report", "Photo"])
        #expect(references.map(\.path) == ["../Attachments/report.pdf", "Attachments/photo.png"])
    }

    @Test func repeatedFileImportsKeepIndependentCopiesAndTheOriginalFile() async throws {
        let root = freshRoot()
        let store = FileStore(root: root)
        let source = root.appendingPathComponent("original.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bytes = Data("original contents".utf8)
        try bytes.write(to: source)
        let first = try await store.importAttachment(fileURL: source)
        let second = try await store.importAttachment(fileURL: source)
        #expect(first.relativePath != second.relativePath)
        let firstURL = try await store.attachmentURL(for: first.relativePath)
        let secondURL = try await store.attachmentURL(for: second.relativePath)
        #expect(try Data(contentsOf: firstURL) == bytes)
        #expect(try Data(contentsOf: secondURL) == bytes)
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test func importsResolveOnlyInsideAttachmentRootAndExportWithLibrary() async throws {
        let root = freshRoot()
        let store = FileStore(root: root)
        let payload = Data("image-payload".utf8)

        let attachment = try await store.importAttachment(
            data: payload,
            originalFileName: "Holiday Photo.PNG"
        )

        #expect(attachment.relativePath.hasPrefix("Attachments/"))
        #expect(attachment.relativePath.hasSuffix(".png"))
        #expect(attachment.byteCount == payload.count)
        let resolved = try await store.attachmentURL(for: attachment.relativePath)
        #expect(try Data(contentsOf: resolved) == payload)

        await #expect(throws: AttachmentStorageError.self) {
            _ = try await store.attachmentURL(for: "Attachments/../secret.txt")
        }
        await #expect(throws: AttachmentStorageError.self) {
            _ = try await store.attachmentURL(for: "/tmp/secret.txt")
        }

        let archive = try LibraryExporter.exportLibrary(at: root)
        let archiveBytes = String(decoding: try Data(contentsOf: archive), as: UTF8.self)
        #expect(archiveBytes.contains("Lists/\(attachment.relativePath)"))
        #expect(archiveBytes.contains("image-payload"))
    }

    @Test func markdownReferencesProtectFilesAndQuarantineIsRecoverable() async throws {
        let root = freshRoot()
        let store = FileStore(root: root)
        let kept = try await store.importAttachment(
            data: Data("kept".utf8),
            originalFileName: "kept.jpg"
        )
        let orphan = try await store.importAttachment(
            data: Data("orphan".utf8),
            originalFileName: "orphan.pdf"
        )
        let markdown = "Photo ![Alt](\(kept.relativePath)) and [file](\(kept.relativePath))"
        let references = MarkdownAttachmentIndex.referencedPaths(in: markdown)
        #expect(references == [kept.relativePath])

        let quarantined = try await store.quarantineUnreferencedAttachments(
            referencedPaths: references
        )
        #expect(quarantined == [orphan.relativePath])
        _ = try await store.attachmentURL(for: kept.relativePath)
        await #expect(throws: AttachmentStorageError.self) {
            _ = try await store.attachmentURL(for: orphan.relativePath)
        }

        let restored = try await store.restoreQuarantinedAttachment(fileName: orphan.fileName)
        #expect(restored.relativePath == orphan.relativePath)
        let restoredURL = try await store.attachmentURL(for: orphan.relativePath)
        #expect(try Data(contentsOf: restoredURL) == Data("orphan".utf8))
    }

    @Test func escapedAttachmentLabelsUseTheSameIndexAsTheEditor() async throws {
        let root = freshRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileStore(root: root)
        let attachment = try await store.importAttachment(data: Data("photo".utf8), originalFileName: "photo.png")
        let source = "Before 😀 ![Photo \\[version 2\\]](../../\(attachment.relativePath)) after"
        let references = MarkdownMediaReference.references(in: source)
        #expect(references.count == 1)
        #expect(references.first?.label == "Photo [version 2]")
        #expect(MarkdownAttachmentIndex.referencedPaths(in: source) == [attachment.relativePath])
        let quarantined = try await store.quarantineUnreferencedAttachments(
            referencedPaths: MarkdownAttachmentIndex.referencedPaths(in: source)
        )
        #expect(quarantined.isEmpty)
        _ = try await store.attachmentURL(for: attachment.relativePath)
    }

    @Test func attachmentDescriptionEscapesRoundTripWithoutAccumulatingBackslashes() throws {
        let label = #"Report [version 2] \ original"#
        let source = "[\(DocumentMarkdownLinkBuilder.escapedLabel(label))](Attachments/report.pdf)"
        let reference = try #require(MarkdownMediaReference.references(in: source).first)
        #expect(reference.label == label)
        #expect("[\(DocumentMarkdownLinkBuilder.escapedLabel(reference.label))](\(reference.path))" == source)
    }

    @Test func semanticAttachmentsUseTheSameEscapedLabelsAsLiveMarkdown() throws {
        let source = "![Photo \\[original\\]](../Attachments/photo.png)\n\n[PDF \\[original\\]](../Attachments/file.pdf)"
        let blocks = SemanticMarkdownBlockParser.blocks(from: source)
        #expect(blocks.count == 2)
        let image = try #require(blocks.first)
        guard case .image(let alt, let path) = image.kind else {
            Issue.record("Expected a semantic image for the escaped attachment label")
            return
        }
        #expect(alt == "Photo [original]")
        #expect(path == "../Attachments/photo.png")
        let file = try #require(blocks.last)
        guard case .linkCard(let label, let url) = file.kind else {
            Issue.record("Expected a semantic file card for the escaped attachment label")
            return
        }
        #expect(label == "PDF [original]")
        #expect(url.relativeString == "../Attachments/file.pdf")
    }

    @Test(arguments: [
        "~~~markdown\n[Example](https://example.com)\n~~~",
        "````markdown\n```\n[Example](https://example.com)\n````",
        "  ```markdown\n[Example](https://example.com)"
    ])
    func linksInCodeUseSharedFenceBoundaries(source: String) {
        #expect(MarkdownInlineLink.links(in: source).isEmpty)
        let withProse = source + "\n" + (source.hasSuffix("~~~") || source.hasSuffix("````") ? "Visit https://outside.example" : "")
        if withProse != source + "\n" {
            #expect(MarkdownInlineLink.links(in: withProse).map(\.destination) == ["https://outside.example"])
        }
    }

    @Test func selectedSymbolicLinksImportIndependentFileContents() async throws {
        let directory = freshRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("original.pdf")
        let link = directory.appendingPathComponent("selected.pdf")
        let bytes = Data("independent attachment".utf8)
        try bytes.write(to: source)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let store = FileStore(root: directory.appendingPathComponent("Library"))
        let imported = try await store.importAttachment(fileURL: link)
        try FileManager.default.removeItem(at: source)
        let saved = try await store.attachmentURL(for: imported.relativePath)
        #expect(try Data(contentsOf: saved) == bytes)
        #expect(try saved.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
    }

    @Test func directoriesCannotBeImportedOrOpenedAsAttachments() async throws {
        let root = freshRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Attachments/folder.pdf", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("contents".utf8).write(to: folder.appendingPathComponent("file.txt"))
        let store = FileStore(root: root)
        await #expect(throws: AttachmentStorageError.self) {
            _ = try await store.importAttachment(fileURL: folder)
        }
        await #expect(throws: AttachmentStorageError.self) {
            _ = try await store.attachmentURL(for: "Attachments/folder.pdf")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Attachments").path) == ["folder.pdf"])
    }

    @Test func quarantineCannotTraverseASymlinkedAttachmentDirectory() async throws {
        let directory = freshRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("Library")
        let outside = directory.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let original = outside.appendingPathComponent("photo.png")
        try Data("untouched".utf8).write(to: original)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Attachments"), withDestinationURL: outside)
        let store = FileStore(root: root)
        await #expect(throws: AttachmentStorageError.self) {
            _ = try await store.quarantineUnreferencedAttachments(referencedPaths: [])
        }
        #expect(try Data(contentsOf: original) == Data("untouched".utf8))
    }

    @Test func attachmentRecoveryRejectsRedirectedTrashAndDestinationDirectories() async throws {
        for redirectedName in ["Attachments", ".attachments-trash"] {
            let directory = freshRoot()
            defer { try? FileManager.default.removeItem(at: directory) }
            let root = directory.appendingPathComponent("Library")
            let outside = directory.appendingPathComponent("Outside")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(redirectedName), withDestinationURL: outside)
            let trash = root.appendingPathComponent(".attachments-trash")
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            let original = trash.appendingPathComponent("photo.png")
            try Data("untouched".utf8).write(to: original)
            let store = FileStore(root: root)
            await #expect(throws: AttachmentStorageError.self) {
                _ = try await store.restoreQuarantinedAttachment(fileName: "photo.png")
            }
            #expect(try Data(contentsOf: original) == Data("untouched".utf8))
        }
    }

    @Test func attachmentRecoveryRejectsASymlinkedFile() async throws {
        let root = freshRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let trash = root.appendingPathComponent(".attachments-trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("original.txt")
        try Data("untouched".utf8).write(to: original)
        try FileManager.default.createSymbolicLink(at: trash.appendingPathComponent("link.txt"), withDestinationURL: original)
        let store = FileStore(root: root)
        await #expect(throws: AttachmentStorageError.self) {
            _ = try await store.restoreQuarantinedAttachment(fileName: "link.txt")
        }
        #expect(try Data(contentsOf: original) == Data("untouched".utf8))
    }

    private func freshRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsAttachments-\(UUID().uuidString)", isDirectory: true)
    }
}

@MainActor
struct FileMoveCommandTests {
    @Test func listPreviewOmitsOnlyStandaloneAttachmentBlocks() {
        let link = "[Brief](../Attachments/fixture.pdf)"
        let image = "![Drawing](../Attachments/drawing.png)"
        #expect(MarkdownMediaReference.listPreviewSource(in: "Short preview.\n\n\(link)\n\n\(image)") == "Short preview.")
        #expect(MarkdownMediaReference.listPreviewSource(in: "\(link)\n\n\(image)").isEmpty)
        #expect(MarkdownMediaReference.listPreviewSource(in: "Read \(link) today.") == "Read \(link) today.")
        let examples = "First paragraph.\n\nSecond paragraph.\n```markdown\n\(link)\n```"
        #expect(MarkdownMediaReference.listPreviewSource(in: examples) == examples)
    }

    @Test func attachmentDisclosureDoesNotReserveEmptyPreviewHeight() async throws {
        let (store, _, _, _, _) = try await fixture()
        let ordinary = Item(type: .note, title: "Reference note", body: "Short preview.", listId: ItemList.inboxId)
        let attached = Item(type: .note, title: "Reference note", body: "Short preview.\n\n[Brief](../Attachments/fixture.pdf)", listId: ItemList.inboxId)
        try await store.add(ordinary); try await store.add(attached)
        func height(_ item: Item, indent: Int) -> CGFloat {
            let row = ItemRow(item: item, isOverdue: false, store: store, onToggle: {}, indent: indent, enablesSwipeActions: false)
            return UIHostingController(rootView: row).sizeThatFits(in: CGSize(width: 393, height: 2000)).height
        }
        #expect(abs(height(ordinary, indent: 0) - height(attached, indent: 0)) < 1)
        #expect(abs(height(ordinary, indent: 1) - height(attached, indent: 1)) < 1)
    }


    private func fixture() async throws -> (ItemStore, StandaloneFile, ListDetailCollectionView.Coordinator, UICollectionView, ItemMoveSession) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileMoveCommand-" + UUID().uuidString)
        let files = FileStore(root: root)
        try await files.ensureRoot()
        try await files.writeList(.makeInbox())
        let store = ItemStore(store: files)
        try await store.bootstrap()
        let source = root.appendingPathComponent("command.pdf")
        try Data("%PDF command fixture".utf8).write(to: source)
        let file = try await store.importStandaloneFile(fileURL: source, into: ItemList.inboxId)
        let session = ItemMoveSession()
        let prefs = ListViewPreferences(defaults: UserDefaults(suiteName: "FileCommand-" + UUID().uuidString)!)
        let view = ListDetailCollectionView(
            store: store, listId: ItemList.inboxId, prefs: prefs, listColor: .blue,
            bridge: ListDetailBridge(), inSelectMode: .constant(false), selection: .constant([]),
            editingItemId: .constant(nil), editingSectionKey: .constant(nil), lingeringIds: [],
            defaultNewItemType: .task, moveSession: session,
            documentLinkSession: DocumentLinkSession(), onToggleItem: { _ in }, onSelectToggle: { _ in },
            onPromptDeleteSection: { _, _ in }, onSoftDeleteSubList: { _ in }, onSoftDeleteItem: { _ in },
            onPromoteOthers: { _ in }, onRenameSection: { _, _ in }, onShowItemDetail: { _ in },
            onOpenSubList: { _ in }, onBeginInlineEdit: { _ in }, onBeginMove: { _ in },
            onEndInlineEdit: { _ in }, onEndEditSection: {})
        let coordinator = view.makeCoordinator()
        coordinator.parent = view
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 393, height: 812), collectionViewLayout: UICollectionViewFlowLayout())
        coordinator.setupDataSource(for: collection)
        coordinator.applySnapshot(animated: false)
        return (store, file, coordinator, collection, session)
    }

    @Test func actualSwipeAndContextMoveCommandsActivateSharedSession() async throws {
        let (store, file, coordinator, collection, session) = try await fixture()
        let path = try #require(coordinator.dataSource.indexPath(for: .file(id: file.id)))
        let swipe = try #require(coordinator.leadingSwipeActions(for: path)?.actions.first)
        var completed = false
        swipe.handler(swipe, collection) { completed = $0 }
        #expect(completed)
        #expect(session.isActive)
        #expect(session.movingFileID == file.id)
        #expect(session.movingTitle(in: store) == file.fileName)
        session.cancel()
        let move = try #require(coordinator.fileMenu(file, from: collection).children.compactMap { $0 as? UIAction }.first { $0.title == "Move" })
        let control = UIButton()
        control.addAction(move, for: .touchUpInside)
        control.sendActions(for: .touchUpInside)
        #expect(session.isActive)
        #expect(session.movingFileID == file.id)
        #expect(coordinator.leadingSwipeActions(for: path) == nil)
    }

    @Test func revealedMoveRailIsNotCoveredByTransparentPanAnchor() async throws {
        let (_, file, coordinator, collection, _) = try await fixture()
        let path = try #require(coordinator.dataSource.indexPath(for: .file(id: file.id)))
        collection.layoutIfNeeded()
        let configuration = try #require(coordinator.leadingSwipeActions(for: path))
        let content = Button {} label: { FileRowContent(title: file.fileName, subtitle: "24 bytes", isImage: false) }
            .buttonStyle(.plain)
        let host = UIHostingController(rootView: VStack(spacing: 0) {
            CapsuleSwipeRow(leading: configuration, trailing: nil, content: content, revealedOffset: 82)
            Spacer()
        }.frame(width: 393))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 812)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        for _ in 0..<10 { try await Task.sleep(for: .milliseconds(20)); host.view.layoutIfNeeded() }
        func anchor(in view: UIView) -> HorizontalRowPan.PanAnchor? {
            if let found = view as? HorizontalRowPan.PanAnchor { return found }
            for child in view.subviews { if let found = anchor(in: child) { return found } }
            return nil
        }
        let gestureAnchor = try #require(anchor(in: host.view))
        let point = gestureAnchor.convert(CGPoint(x: 32, y: gestureAnchor.bounds.midY), to: host.view)
        let hit = try #require(host.view.hitTest(point, with: nil))
        #expect(hit !== gestureAnchor, "The pan observer intercepts taps meant for the revealed Move button")
    }
}
