import SwiftUI
import Testing
@testable import Lists

@MainActor @Suite(.serialized)
struct DatabaseRenderTests {
    private func fixture(hooks: ItemStore.MaintenanceTestHooks = .init()) async throws -> (ItemStore, ItemList, Item, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DatabaseRender-" + UUID().uuidString)
        let files = FileStore(root: root); try await files.ensureRoot()
        var list = ItemList.makeInbox(); list.name = "Project"
        let status = DatabaseField(name: "Status", kind: .select, options: [.init(name: "Planned"), .init(name: "Doing")])
        let estimate = DatabaseField(name: "Estimate", kind: .number)
        list.databaseFields = [status, estimate]; try await files.writeList(list)
        let store = ItemStore(store: files, maintenanceTestHooks: hooks); try await store.bootstrap()
        var parent = Item(type: .task, title: "Prepare the release", body: "Review the brief and collect feedback.", listId: list.id)
        #expect(DatabaseSchema.set(status.options[0].id.uuidString, field: status, in: &parent))
        #expect(DatabaseSchema.set("12", field: estimate, in: &parent))
        try await store.add(parent)
        var child = Item(type: .task, title: "Check the screenshots", listId: list.id, parentId: parent.id)
        #expect(DatabaseSchema.set("2", field: estimate, in: &child)); try await store.add(child)
        var note = Item(type: .note, title: "Design notes", body: "# A clear plan\n\nKeep the useful details together.", listId: list.id)
        #expect(DatabaseSchema.set(status.options[1].id.uuidString, field: status, in: &note)); try await store.add(note)
        return (store, list, note, root)
    }
    @Test func tableBoardAndDocumentRenderAndTitleHasNoDuplicateAccessory() async throws {
        let (store, list, note, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for layout in ["table", "columns", "list"] {
            var view = DatabaseView(); view.layout = layout; view.columns += list.databaseFields.map(\.key)
            if layout == "columns" { view.groupBy = list.databaseFields[0].key }
            try await render(NavigationStack {
                DatabaseItemsView(store: store, list: list, view: view, onOpen: { _ in }, onMove: { _ in }, onAdd: {})
                    .navigationTitle("Project").navigationBarTitleDisplayMode(.inline)
            }, name: "database-" + layout)
        }
        var narrow = DatabaseView(); narrow.columns += list.databaseFields.map(\.key)
        try await render(DatabaseItemsView(store: store, list: list, view: narrow, onOpen: { _ in }, onMove: { _ in }, onAdd: {}),
                         name: "database-narrow-light", width: 320, size: .accessibility2, scheme: .light)
        try await render(ItemDocumentView(item: note, store: store, onBeginMove: { _ in }),
                         name: "document-narrow-light", width: 320, size: .accessibility2, scheme: .light)
        try await render(ItemDocumentView(item: note, store: store, onBeginMove: { _ in }), name: "document-properties") { host in
            @MainActor func textViews(_ view: UIView) -> [UITextView] {
                if let text = view as? UITextView { return [text] }
                return view.subviews.flatMap(textViews)
            }
            let views = textViews(host.view)
            let title = try #require(views.first { $0.accessibilityIdentifier == "document.title" })
            #expect(title.inputAccessoryView == nil)
            let body = try #require(views.first { $0.accessibilityIdentifier == "document.body" })
            #expect(body.inputAccessoryView is MarkdownReminderToolbar)
        }
    }
    @Test func compactAndDetailsMonthRenderFromSharedProjection() async throws {
        let (store, list, _, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = DateComponents(calendar: calendar, year: 2026, month: 10, day: 16, hour: 9).date!
        let event = Item(type: .event, title: "Review meeting", listId: list.id, due: date, end: date.addingTimeInterval(3600))
        try await store.add(event)
        let prefs = CalendarProjectionPreferences(recurrenceVisibility: .visibleRange, showTasks: true, showEvents: true,
            showNotes: true, showCompletedItems: true, showCompletedHistory: false, showMissedHistory: false, hiddenListIds: [])
        let interval = CalendarDateMath.monthGridInterval(containing: date, calendar: calendar)
        let entries = CalendarProjection.entries(items: store.items, in: interval, preferences: prefs, now: date, calendar: calendar)
        let index = CalendarEntryIndex(entries: entries, interval: interval, calendar: calendar)
        for layout in [CalendarNavigationState.MonthLayout.compact, .details, .list] {
            try await render(CalendarMonthView(anchor: date, selectedDate: .constant(date), density: .compact,
                showWeekends: true, showWeekNumbers: false, calendar: calendar, tint: .pink, index: index,
                colorForEntry: { _ in .pink }, canToggle: { _ in true }, onToggle: { _ in }, onOpen: { _ in },
                layout: layout, navigationHeader: AnyView(Text("October").font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(16))), name: "month-" + layout.rawValue)
        }
    }
    @Test func independentCellWritesPreserveEachOtherAndDocumentText() async throws {
        let (store, list, note, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let status = list.databaseFields[0], estimate = list.databaseFields[1]
        async let first: Void = store.updateDatabaseValue("27", field: estimate, itemID: note.id)
        async let second: Void = store.updateDatabaseValue(status.options[0].id.uuidString, field: status, itemID: note.id)
        #expect(store.applyDocumentTextSync(note.id, title: nil, body: "Concurrent document text"))
        _ = try await (first, second)
        try await store.flushPendingWrites()
        let cold = ItemStore(store: FileStore(root: root)); try await cold.bootstrap()
        let saved = try #require(cold.item(note.id))
        #expect(DatabaseSchema.property(estimate, in: saved)?.value == "27")
        #expect(DatabaseSchema.property(status, in: saved)?.value == status.options[0].id.uuidString)
        #expect(saved.body.trimmingCharacters(in: .newlines) == "Concurrent document text")
    }

    @Test func rejectedPropertyValuesDoNotBlockMaintenance() async throws {
        let (store, list, note, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let number = list.databaseFields[1]
        #expect(!store.applyDatabaseValueSync("invalid number", field: number, itemID: note.id))
        await #expect(throws: DatabaseValueError.self) { try await store.updateDatabaseValue("invalid number", field: number, itemID: note.id) }
        await #expect(throws: DatabaseValueError.self) { try await store.updateDatabaseValue("2", field: number, itemID: UUID()) }
        try await store.reloadFromDisk()
        #expect(DatabaseSchema.property(number, in: try #require(store.item(note.id))) == nil)
    }

    @Test func inlineEditsRemainDurableWithoutAFieldBlurOrDraftLifetime() async throws {
        let (store, list, note, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let number = list.databaseFields[1]
        do {
            let draft = DatabaseValueDraft(raw: "")
            for value in ["1", "12", "123"] {
                draft.edit(value, field: number) { store.applyDatabaseValueSync($0, field: number, itemID: note.id) }
            }
            #expect(DatabaseSchema.property(number, in: try #require(store.item(note.id)))?.value == "123")
        }
        // No focus-change/save callback runs before this maintenance boundary.
        try await store.reloadFromDisk()
        let cold = ItemStore(store: FileStore(root: root)); try await cold.bootstrap()
        #expect(DatabaseSchema.property(number, in: try #require(cold.item(note.id)))?.value == "123")
    }

    @Test func inlineTextAndQueuedSelectionPreserveOtherFieldsAcrossMaintenance() async throws {
        let (store, list, note, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let text = DatabaseField(name: "Notes", kind: .text)
        try await store.saveDatabaseFields(list.databaseFields + [text], in: list.id)
        let status = list.databaseFields[0]
        async let selection: Void = store.updateDatabaseValue(status.options[0].id.uuidString, field: status, itemID: note.id)
        for raw in ["Draft", "Draft\nwith two lines"] {
            #expect(store.applyDatabaseValueSync(raw, field: text, itemID: note.id))
        }
        #expect(store.applyDocumentTextSync(note.id, body: "Independent document edit"))
        try await selection
        try await store.reloadFromDisk()
        let saved = try #require(store.item(note.id))
        #expect(DatabaseSchema.property(text, in: saved)?.value == "Draft\nwith two lines")
        #expect(DatabaseSchema.property(status, in: saved)?.value == status.options[0].id.uuidString)
        #expect(saved.body.trimmingCharacters(in: .newlines) == "Independent document edit")
    }

    @Test func inlineEditPreservesASelectionAcceptedWhileItsSaveIsSuspended() async throws {
        let gate = PropertyAcceptanceGate()
        var hooks = ItemStore.MaintenanceTestHooks()
        hooks.databaseValueAccepted = { await gate.pause() }
        let (store, list, note, root) = try await fixture(hooks: hooks)
        defer { try? FileManager.default.removeItem(at: root); gate.open() }
        let status = list.databaseFields[0], number = list.databaseFields[1]
        let selected = status.options[0].id.uuidString
        gate.enabled = true
        let selection = Task { try await store.updateDatabaseValue(selected, field: status, itemID: note.id) }
        for await _ in gate.reached.stream { break }
        #expect(DatabaseSchema.property(status, in: try #require(store.item(note.id)))?.value == selected)
        #expect(store.applyDatabaseValueSync("42", field: number, itemID: note.id))
        gate.open()
        try await selection.value
        try await store.reloadFromDisk()
        let saved = try #require(store.item(note.id))
        #expect(DatabaseSchema.property(status, in: saved)?.value == selected)
        #expect(DatabaseSchema.property(number, in: saved)?.value == "42")
    }

    @Test func liveValueDraftValidatesRetainsFailuresAndSavesRapidChangesInOrder() async {
        let field = DatabaseField(name: "Estimate", kind: .number)
        let draft = DatabaseValueDraft(raw: "")
        var writes: [String] = []
        draft.save("not a number", field: field, using: { writes.append($0) })
        #expect(draft.error != nil && writes.isEmpty)
        for value in ["1", "2", "1"] {
            draft.save(value, field: field, using: { value in await Task.yield(); writes.append(value) })
        }
        await draft.finishSaving()
        #expect(writes == ["1", "2", "1"])
        #expect(draft.raw == "1" && draft.error == nil && draft.pendingSaves == 0)
        draft.save("3", field: field, using: { _ in throw DatabaseValueError.invalidValue })
        await draft.finishSaving()
        draft.receive("1", editing: false)
        #expect(draft.raw == "3" && draft.error != nil)
        draft.save(draft.raw, field: field, using: { writes.append($0) })
        await draft.finishSaving()
        #expect(draft.raw == "3" && draft.error == nil)
    }

    @Test func boundedTableHasOneScrollSurfaceAndPinnedHeaders() async throws {
        let (store, list, _, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<20 {
            try await store.add(Item(type: .task, title: "Table row \(index)", listId: list.id))
        }
        var view = DatabaseView(); view.columns += list.databaseFields.map(\.key)
        try await render(DatabaseItemsView(store: store, list: list, view: view, onOpen: { _ in }, onMove: { _ in }, onAdd: {}), name: "database-bounded") { host in
            @MainActor func collections(_ view: UIView) -> [UICollectionView] {
                (view as? UICollectionView).map { [$0] } ?? view.subviews.flatMap(collections)
            }
            let tables = collections(host.view)
            #expect(tables.count == 1)
            let table = try #require(tables.first)
            #expect(!table.bounces && !table.alwaysBounceHorizontal && !table.alwaysBounceVertical)
            #expect(table.contentSize.width > table.bounds.width)
            #expect(table.contentSize.height > table.bounds.height)
            table.setContentOffset(CGPoint(x: 100, y: 160), animated: false)
            table.layoutIfNeeded()
            let header = try #require(table.collectionViewLayout.layoutAttributesForSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0)))
            #expect(header.frame.minY == table.contentOffset.y)
        }
    }

    private func render<V: View>(_ view: V, name: String, width: CGFloat = 393, size: DynamicTypeSize = .large, scheme: ColorScheme = .dark, inspect: ((UIHostingController<AnyView>) throws -> Void)? = nil) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 852)
        let host = UIHostingController(rootView: AnyView(view.environment(\.dynamicTypeSize, size).preferredColorScheme(scheme)))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(500)); host.view.layoutIfNeeded()
        try inspect?(host)
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        try image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/lists-audit-" + name + ".png"))
    }
}

@MainActor private final class PropertyAcceptanceGate {
    var enabled = false
    let reached = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let resumed = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    func pause() async {
        guard enabled else { return }
        reached.continuation.yield(())
        for await _ in resumed.stream { return }
    }
    func open() { resumed.continuation.yield(()); resumed.continuation.finish() }
}
