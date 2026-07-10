import Foundation
import Testing
@testable import Lists

/// Changing an item's `listId` must delete the stale file in the old list's
/// folder, so a reload can never read two copies.
@MainActor
struct CrossListMoveTests {

    private func freshRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsMove-\(UUID().uuidString)")
    }

    private func makeList(id: String, name: String, sections: [ListSection] = []) -> ItemList {
        ItemList(id: id, name: name, icon: "tray", color: .blue,
                 createdAt: .now, modifiedAt: .now, position: 0, sections: sections)
    }

    /// Returns a bootstrapped store over a root seeded with lists Alpha(A) and
    /// Bravo(B) plus one task in A, and the on-disk URLs for both folders.
    private func seededStore() async throws -> (store: ItemStore, item: Item, aFile: URL, bFile: URL) {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))
        let item = Item(type: .task, title: "Movable", listId: "A")
        try await setup.writeItem(item)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let fileName = "\(item.id.uuidString).md"
        return (store, item,
                root.appendingPathComponent("Alpha").appendingPathComponent(fileName),
                root.appendingPathComponent("Bravo").appendingPathComponent(fileName))
    }

    @Test
    func moveDeletesOldFileAndReloadsOnce() async throws {
        let (store, item, aFile, bFile) = try await seededStore()

        var moved = try #require(store.items.first { $0.id == item.id })
        moved.listId = "B"
        try await store.update(moved)

        #expect(FileManager.default.fileExists(atPath: aFile.path) == false, "old file removed")
        #expect(FileManager.default.fileExists(atPath: bFile.path), "new file written")

        // A cold reload sees exactly one copy, in the new list.
        let reload = try await FileStore(root: aFile.deletingLastPathComponent().deletingLastPathComponent())
            .loadAll()
        let matches = reload.lists.flatMap(\.items).filter { $0.id == item.id }
        #expect(matches.count == 1)
        #expect(matches.first?.listId == "B")
    }

    @Test
    func updateWithoutListChangeKeepsSingleFile() async throws {
        let (store, item, aFile, bFile) = try await seededStore()

        var edited = try #require(store.items.first { $0.id == item.id })
        edited.title = "Renamed"
        try await store.update(edited)

        #expect(FileManager.default.fileExists(atPath: aFile.path), "stays in A")
        #expect(FileManager.default.fileExists(atPath: bFile.path) == false)
    }

    @Test
    func applyUpdateSyncMoveDeletesOldFile() async throws {
        let (store, item, aFile, bFile) = try await seededStore()

        var moved = try #require(store.items.first { $0.id == item.id })
        moved.listId = "B"
        store.applyUpdateSync(moved)

        // applyUpdateSync persists on a detached Task; poll for the result.
        for _ in 0..<60 where FileManager.default.fileExists(atPath: aFile.path) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(FileManager.default.fileExists(atPath: aFile.path) == false)
        #expect(FileManager.default.fileExists(atPath: bFile.path))
    }

    @Test
    func moveToUnmappedDestinationMaterializesRecoveryBeforeDeletingSource() async throws {
        let root = freshRoot()
        let fileStore = FileStore(root: root)
        try await fileStore.ensureRoot()
        try await fileStore.writeList(makeList(id: "A", name: "Alpha"))
        let item = Item(type: .task, title: "Recover me", listId: "A")
        try await fileStore.writeItem(item)

        let source = try await fileStore.listDirectory(for: "A")
            .appendingPathComponent("\(item.id.uuidString).md")
        var moved = item
        moved.listId = "missing-destination"
        try await fileStore.moveItem(moved, fromListId: "A")

        let destinationDirectory = try await fileStore.listDirectory(
            for: "missing-destination"
        )
        let destination = destinationDirectory
            .appendingPathComponent("\(item.id.uuidString).md")
        #expect(FileManager.default.fileExists(atPath: source.path) == false)
        #expect(FileManager.default.fileExists(atPath: destination.path))

        let loaded = try await fileStore.loadAll()
        let recoveredList = try #require(
            loaded.lists.first { $0.list.id == "missing-destination" }
        )
        #expect(recoveredList.list.name.hasPrefix("Recovered"))
        #expect(recoveredList.items.map(\.id) == [item.id])
    }

    @Test
    func moveWithUnmappedSourceStillRemovesCapturedOldCopy() async throws {
        let root = freshRoot()
        let fileStore = FileStore(root: root)
        try await fileStore.ensureRoot()
        try await fileStore.writeList(makeList(id: "A", name: "Alpha"))
        try await fileStore.writeList(makeList(id: "B", name: "Bravo"))
        let item = Item(type: .task, title: "Move from recovery", listId: "A")
        try await fileStore.writeItem(item)

        let sourceDirectory = try await fileStore.listDirectory(for: "A")
        let source = sourceDirectory
            .appendingPathComponent("\(item.id.uuidString).md")
        try "not: [valid yaml".write(
            to: sourceDirectory.appendingPathComponent(".list.yml"),
            atomically: true,
            encoding: .utf8
        )
        _ = try await fileStore.loadAll()

        var moved = item
        moved.listId = "B"
        try await fileStore.moveItem(moved, fromListId: "A")

        let destination = try await fileStore.listDirectory(for: "B")
            .appendingPathComponent("\(item.id.uuidString).md")
        #expect(FileManager.default.fileExists(atPath: source.path) == false)
        #expect(FileManager.default.fileExists(atPath: destination.path))

        let loaded = try await fileStore.loadAll()
        let matches = loaded.lists.flatMap(\.items).filter { $0.id == item.id }
        #expect(matches.count == 1)
        #expect(matches.first?.listId == "B")
    }

    @Test
    func freshFileStoreReusesExistingDestinationList() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))
        let item = Item(type: .task, title: "Fresh actor move", listId: "A")
        try await setup.writeItem(item)

        let fresh = FileStore(root: root)
        var moved = item
        moved.listId = "B"
        try await fresh.moveItem(moved, fromListId: "A")

        let destinationDirectory = try await fresh.listDirectory(for: "B")
        #expect(destinationDirectory.lastPathComponent == "Bravo")
        let rootEntries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        #expect(rootEntries.contains { $0.lastPathComponent.hasPrefix("Recovered B") } == false)

        let loaded = try await fresh.loadAll()
        #expect(loaded.lists.filter { $0.list.id == "B" }.count == 1)
        #expect(loaded.lists.flatMap(\.items).filter { $0.id == item.id }.count == 1)
    }

    @Test
    func moveRefusesToOverwriteDivergentDestinationCopy() async throws {
        let root = freshRoot()
        let fileStore = FileStore(root: root)
        try await fileStore.ensureRoot()
        try await fileStore.writeList(makeList(id: "A", name: "Alpha"))
        try await fileStore.writeList(makeList(id: "B", name: "Bravo"))

        let id = UUID()
        let sourceItem = Item(id: id, type: .task, title: "Source version", listId: "A")
        let destinationItem = Item(id: id, type: .task, title: "Destination version", listId: "B")
        try await fileStore.writeItem(sourceItem)
        try await fileStore.writeItem(destinationItem)

        let fileName = "\(id.uuidString).md"
        let sourceURL = try await fileStore.listDirectory(for: "A")
            .appendingPathComponent(fileName)
        let destinationURL = try await fileStore.listDirectory(for: "B")
            .appendingPathComponent(fileName)
        let sourceBefore = try Data(contentsOf: sourceURL)
        let destinationBefore = try Data(contentsOf: destinationURL)

        var moved = sourceItem
        moved.listId = "B"
        do {
            try await fileStore.moveItem(moved, fromListId: "A")
            Issue.record("a move must not overwrite a divergent destination copy")
        } catch {
            #expect(error.localizedDescription.contains("different item"))
        }

        #expect(try Data(contentsOf: sourceURL) == sourceBefore)
        #expect(try Data(contentsOf: destinationURL) == destinationBefore)
    }

    @Test
    func movePreservesMultiplePlausibleSourceCopies() async throws {
        let root = freshRoot()
        let fileStore = FileStore(root: root)
        try await fileStore.ensureRoot()
        try await fileStore.writeList(makeList(id: "A", name: "Alpha"))
        try await fileStore.writeList(makeList(id: "B", name: "Bravo"))
        try await fileStore.writeList(makeList(id: "C", name: "Clone"))

        let item = Item(type: .task, title: "Ambiguous source", listId: "A")
        try await fileStore.writeItem(item)
        let fileName = "\(item.id.uuidString).md"
        let sourceA = try await fileStore.listDirectory(for: "A")
            .appendingPathComponent(fileName)
        let sourceClone = try await fileStore.listDirectory(for: "C")
            .appendingPathComponent(fileName)
        try FrontmatterCodec.encode(item).write(
            to: sourceClone,
            atomically: true,
            encoding: .utf8
        )

        var moved = item
        moved.listId = "B"
        try await fileStore.moveItem(moved, fromListId: "A")

        let destination = try await fileStore.listDirectory(for: "B")
            .appendingPathComponent(fileName)
        #expect(FileManager.default.fileExists(atPath: sourceA.path))
        #expect(FileManager.default.fileExists(atPath: sourceClone.path))
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    /// Regression: moving a parent item to another section must carry its whole
    /// subtree (children render under the parent regardless of their own
    /// section). Before the fix, descendants kept the OLD section id, so
    /// deleting the section they'd visually left soft-deleted them.

    @Test
    func moveParentBetweenSectionsCarriesSubtreeAndSurvivesOldSectionDelete() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let createdA = try await store.addSection(in: "A", name: "Section A")
        let createdB = try await store.addSection(in: "A", name: "Section B")
        let secA = try #require(createdA)
        let secB = try #require(createdB)
        let keyA = secA.id.uuidString
        let keyB = secB.id.uuidString

        let parent = Item(type: .task, title: "Parent", listId: "A", section: keyA)
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", section: keyA, parentId: parent.id)
        try await store.add(child)
        let grand = Item(type: .task, title: "Grandchild", listId: "A", section: keyA, parentId: child.id)
        try await store.add(grand)

        // Move only the parent to Section B (mirrors a drag / "Move to Section").
        try await store.bulkMove([parent.id], toSection: keyB)

        #expect(store.items.first { $0.id == parent.id }?.section == keyB)
        #expect(store.items.first { $0.id == child.id }?.section == keyB, "child followed the parent")
        #expect(store.items.first { $0.id == grand.id }?.section == keyB, "grandchild followed the parent")

        // Deleting the section the subtree LEFT must not sweep it up.
        try await store.deleteSection(secA.id, in: "A", cascadingItems: true)

        for id in [parent.id, child.id, grand.id] {
            let live = store.items.first { $0.id == id }
            #expect(live != nil, "item \(id) should still exist")
            #expect(live?.deletedAt == nil, "item \(id) must survive deletion of the old section")
        }
    }

    @Test
    func bulkMoveParentToListCarriesSubtreeOnDisk() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let createdSection = try await store.addSection(in: "A", name: "Section A")
        let section = try #require(createdSection)
        let key = section.id.uuidString
        let parent = Item(type: .task, title: "Parent", listId: "A", section: key)
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", section: key, parentId: parent.id)
        try await store.add(child)
        let grand = Item(type: .task, title: "Grandchild", listId: "A", section: key, parentId: child.id)
        try await store.add(grand)

        try await store.bulkMove([parent.id], toListId: "B")

        for id in [parent.id, child.id, grand.id] {
            let item = try #require(store.items.first { $0.id == id })
            #expect(item.listId == "B")
            #expect(item.section == nil)
        }

        let reload = try await FileStore(root: root).loadAll()
        let reloadedItems = reload.lists.flatMap(\.items)
        for id in [parent.id, child.id, grand.id] {
            let matches = reloadedItems.filter { $0.id == id }
            #expect(matches.count == 1)
            #expect(matches.first?.listId == "B")
        }
    }

    @Test
    func syncListCascadeClearsStaleSectionWhenDescendantAlreadyInDestinationList() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(
            type: .task,
            title: "Already there",
            listId: "B",
            section: UUID().uuidString,
            parentId: parent.id
        )
        try await store.add(child)

        store.applyListCascadeSync(toDescendantsOf: parent.id, listId: "B")

        let updated = try #require(store.items.first { $0.id == child.id })
        #expect(updated.listId == "B")
        #expect(updated.section == nil)
    }

    @Test
    func updateWithSubtreeCascadesCarriesDescendantsToNewList() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let createdSection = try await store.addSection(in: "A", name: "Section A")
        let section = try #require(createdSection)
        let key = section.id.uuidString
        let parent = Item(type: .task, title: "Parent", listId: "A", section: key)
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", section: key, parentId: parent.id)
        try await store.add(child)

        var moved = try #require(store.item(parent.id))
        moved.listId = "B"
        moved.section = nil
        try await store.updateWithSubtreeCascades(moved)

        #expect(store.item(parent.id)?.listId == "B")
        #expect(store.item(child.id)?.listId == "B")
        #expect(store.item(child.id)?.section == nil)
    }

    @Test
    func updateWithSubtreeCascadesClearsParentWhenChildMovesToDifferentList() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let createdSection = try await store.addSection(in: "A", name: "Section A")
        let section = try #require(createdSection)
        let key = section.id.uuidString
        let parent = Item(type: .task, title: "Parent", listId: "A", section: key)
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", section: key, parentId: parent.id)
        try await store.add(child)
        let grandchild = Item(type: .task, title: "Grandchild", listId: "A", section: key, parentId: child.id)
        try await store.add(grandchild)

        var moved = try #require(store.item(child.id))
        moved.listId = "B"
        try await store.updateWithSubtreeCascades(moved)

        #expect(store.item(parent.id)?.listId == "A")
        #expect(store.item(child.id)?.listId == "B")
        #expect(store.item(child.id)?.parentId == nil)
        #expect(store.item(child.id)?.section == nil)
        #expect(store.item(grandchild.id)?.listId == "B")
        #expect(store.item(grandchild.id)?.parentId == child.id)
        #expect(store.item(grandchild.id)?.section == nil)
    }

    @Test
    func syncUpdateWithSubtreeCascadesCarriesDescendantsToNewSection() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let createdA = try await store.addSection(in: "A", name: "Section A")
        let createdB = try await store.addSection(in: "A", name: "Section B")
        let sectionA = try #require(createdA)
        let sectionB = try #require(createdB)
        let keyA = sectionA.id.uuidString
        let keyB = sectionB.id.uuidString
        let parent = Item(type: .task, title: "Parent", listId: "A", section: keyA)
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", section: keyA, parentId: parent.id)
        try await store.add(child)

        var moved = try #require(store.item(parent.id))
        moved.section = keyB
        store.applyUpdateWithSubtreeCascadesSync(moved)

        #expect(store.item(parent.id)?.section == keyB)
        #expect(store.item(child.id)?.section == keyB)
    }

    @Test
    func syncUpdateWithSubtreeCascadesCarriesDescendantsToNewList() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let createdSection = try await store.addSection(in: "A", name: "Section A")
        let section = try #require(createdSection)
        let key = section.id.uuidString
        let parent = Item(type: .task, title: "Parent", listId: "A", section: key)
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", section: key, parentId: parent.id)
        try await store.add(child)

        var moved = try #require(store.item(parent.id))
        moved.listId = "B"
        moved.section = nil
        store.applyUpdateWithSubtreeCascadesSync(moved)

        #expect(store.item(parent.id)?.listId == "B")
        #expect(store.item(child.id)?.listId == "B")
        #expect(store.item(child.id)?.section == nil)
    }

    @Test
    func syncUpdateWithSubtreeCascadesKeepsChildInParentSection() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let createdA = try await store.addSection(in: "A", name: "Section A")
        let createdB = try await store.addSection(in: "A", name: "Section B")
        let sectionA = try #require(createdA)
        let sectionB = try #require(createdB)
        let keyA = sectionA.id.uuidString
        let keyB = sectionB.id.uuidString
        let parent = Item(type: .task, title: "Parent", listId: "A", section: keyA)
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", section: keyA, parentId: parent.id)
        try await store.add(child)

        var editedChild = try #require(store.item(child.id))
        editedChild.section = keyB
        store.applyUpdateWithSubtreeCascadesSync(editedChild)

        #expect(store.item(child.id)?.parentId == parent.id)
        #expect(store.item(child.id)?.section == keyA)
    }

    @Test
    func addInheritsParentSection() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let createdA = try await store.addSection(in: "A", name: "Section A")
        let createdB = try await store.addSection(in: "A", name: "Section B")
        let sectionA = try #require(createdA)
        let sectionB = try #require(createdB)
        let keyA = sectionA.id.uuidString
        let keyB = sectionB.id.uuidString
        let parent = Item(type: .task, title: "Parent", listId: "A", section: keyA)
        try await store.add(parent)

        let child = Item(type: .task, title: "Child", listId: "A", section: keyB, parentId: parent.id)
        try await store.add(child)

        #expect(store.item(child.id)?.parentId == parent.id)
        #expect(store.item(child.id)?.section == keyA)
    }

    @Test
    func addClearsCrossListParentAndStaleSection() async throws {
        let root = freshRoot()
        let staleSection = ListSection(name: "Old Section", position: 1)
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha", sections: [staleSection]))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let parent = Item(type: .task, title: "Parent", listId: "A", section: staleSection.id.uuidString)
        try await store.add(parent)
        let child = Item(
            type: .task,
            title: "Child",
            listId: "B",
            section: staleSection.id.uuidString,
            parentId: parent.id
        )
        try await store.add(child)

        #expect(store.item(child.id)?.parentId == nil)
        #expect(store.item(child.id)?.section == nil)
    }

    @Test
    func updateClearsCrossListParentAndStaleSection() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let createdSection = try await store.addSection(in: "A", name: "Section A")
        let section = try #require(createdSection)
        let key = section.id.uuidString
        let parent = Item(type: .task, title: "Parent", listId: "A", section: key)
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", section: key, parentId: parent.id)
        try await store.add(child)

        var moved = try #require(store.item(child.id))
        moved.listId = "B"
        try await store.update(moved)

        #expect(store.item(child.id)?.parentId == nil)
        #expect(store.item(child.id)?.section == nil)
    }

    @Test
    func applyUpdateSyncInheritsParentSection() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let createdA = try await store.addSection(in: "A", name: "Section A")
        let createdB = try await store.addSection(in: "A", name: "Section B")
        let sectionA = try #require(createdA)
        let sectionB = try #require(createdB)
        let keyA = sectionA.id.uuidString
        let keyB = sectionB.id.uuidString
        let parent = Item(type: .task, title: "Parent", listId: "A", section: keyA)
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", section: keyB)
        try await store.add(child)

        var editedChild = try #require(store.item(child.id))
        editedChild.parentId = parent.id
        store.applyUpdateSync(editedChild)

        #expect(store.item(child.id)?.parentId == parent.id)
        #expect(store.item(child.id)?.section == keyA)
    }

    @Test
    func addInlineItemClearsStaleSection() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let createdSection = try await store.addSection(in: "A", name: "Section A")
        let section = try #require(createdSection)

        let id = store.addInlineItem(type: .task, listId: "B", section: section.id.uuidString)

        #expect(store.item(id)?.section == nil)
    }

    @Test
    func bulkMoveChildOnlyToListClearsOldParentAndCarriesItsSubtree() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let createdSection = try await store.addSection(in: "A", name: "Section A")
        let section = try #require(createdSection)
        let key = section.id.uuidString
        let parent = Item(type: .task, title: "Parent", listId: "A", section: key)
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", section: key, parentId: parent.id)
        try await store.add(child)
        let grandchild = Item(type: .task, title: "Grandchild", listId: "A", section: key, parentId: child.id)
        try await store.add(grandchild)

        try await store.bulkMove([child.id], toListId: "B")

        #expect(store.item(parent.id)?.listId == "A")
        #expect(store.item(child.id)?.listId == "B")
        #expect(store.item(child.id)?.parentId == nil)
        #expect(store.item(child.id)?.section == nil)
        #expect(store.item(grandchild.id)?.listId == "B")
        #expect(store.item(grandchild.id)?.parentId == child.id)
        #expect(store.item(grandchild.id)?.section == nil)
    }

    @Test
    func bulkMoveChildToCurrentListLeavesParentAlone() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        try await store.add(child)

        try await store.bulkMove([child.id], toListId: "A")

        #expect(store.item(child.id)?.listId == "A")
        #expect(store.item(child.id)?.parentId == parent.id)
    }

    @Test
    func bulkMoveParentAndChildToListMovesParentOnceAndPreservesChildParent() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        try await store.add(child)

        try await store.bulkMove([parent.id, child.id], toListId: "B")

        #expect(store.item(parent.id)?.listId == "B")
        #expect(store.item(parent.id)?.parentId == nil)
        #expect(store.item(child.id)?.listId == "B")
        #expect(store.item(child.id)?.parentId == parent.id)
    }

    @Test
    func applyMoveSyncUnderParentInheritsSectionAndCarriesDescendants() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let createdA = try await store.addSection(in: "A", name: "Section A")
        let createdB = try await store.addSection(in: "A", name: "Section B")
        let sectionA = try #require(createdA)
        let sectionB = try #require(createdB)
        let keyA = sectionA.id.uuidString
        let keyB = sectionB.id.uuidString
        let moving = Item(type: .task, title: "Moving", listId: "A", section: keyA)
        try await store.add(moving)
        let child = Item(type: .task, title: "Child", listId: "A", section: keyA, parentId: moving.id)
        try await store.add(child)
        let destinationParent = Item(type: .task, title: "Destination", listId: "A", section: keyB)
        try await store.add(destinationParent)

        let moved = store.applyMoveSync(itemId: moving.id, toListId: "A", parentId: destinationParent.id)

        #expect(moved)
        #expect(store.item(moving.id)?.parentId == destinationParent.id)
        #expect(store.item(moving.id)?.section == keyB)
        #expect(store.item(child.id)?.section == keyB)
    }

    @Test
    func applyMoveSyncRejectsMovingItemUnderDescendant() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        try await store.add(child)

        let moved = store.applyMoveSync(itemId: parent.id, toListId: "A", parentId: child.id)

        #expect(moved == false)
        #expect(store.item(parent.id)?.parentId == nil)
    }

    @Test
    func descendantWalkTerminatesIfStoredHierarchyHasCycle() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        var parent = Item(type: .task, title: "Parent", listId: "A")
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        parent.parentId = child.id
        try await store.add(parent)
        try await store.add(child)

        #expect(store.itemDescendantIds(of: parent.id) == [child.id])
    }

    @Test
    func addAndUpdateListClearInvalidParentIds() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        var selfParent = makeList(id: "A", name: "Alpha")
        selfParent.parentId = "A"
        try await store.addList(selfParent)
        #expect(store.lists.first { $0.id == "A" }?.parentId == nil, "a list cannot parent itself")

        var missingParent = try #require(store.lists.first { $0.id == "A" })
        missingParent.parentId = "missing"
        try await store.updateList(missingParent)
        #expect(store.lists.first { $0.id == "A" }?.parentId == nil, "a missing parent would hide the list")
    }

    @Test
    func updateListClearsDescendantParent() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let parent = makeList(id: "A", name: "Alpha")
        var child = makeList(id: "B", name: "Bravo")
        child.parentId = "A"
        try await store.addList(parent)
        try await store.addList(child)

        var updatedParent = try #require(store.lists.first { $0.id == "A" })
        updatedParent.parentId = "B"
        try await store.updateList(updatedParent)

        #expect(store.lists.first { $0.id == "A" }?.parentId == nil, "a list cannot move under its descendant")
        #expect(store.lists.first { $0.id == "B" }?.parentId == "A", "the child relationship stays intact")
    }

    @Test
    func moveListRejectsMissingParent() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        try await store.addList(makeList(id: "A", name: "Alpha"))

        try await store.moveList("A", toParent: "missing")

        #expect(store.lists.first { $0.id == "A" }?.parentId == nil)
    }

    @Test
    func listReorderRejectsMissingParent() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        try await store.addList(makeList(id: "A", name: "Alpha"))

        let changed = store.applyListReorderSync(
            movedId: "A",
            toParent: "missing",
            flatOrderedIds: ["A"]
        )

        #expect(changed == false)
        #expect(store.lists.first { $0.id == "A" }?.parentId == nil)
    }

    @Test
    func listReorderRejectsDeletedParent() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        try await store.addList(makeList(id: "A", name: "Alpha"))
        var deletedParent = makeList(id: "B", name: "Bravo")
        deletedParent.deletedAt = .now
        try await store.addList(deletedParent)

        let changed = store.applyListReorderSync(
            movedId: "A",
            toParent: "B",
            flatOrderedIds: ["A"]
        )

        #expect(changed == false)
        #expect(store.lists.first { $0.id == "A" }?.parentId == nil)
    }
}
