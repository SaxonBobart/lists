import SwiftUI
import Testing
@testable import Lists

@MainActor @Suite(.serialized)
struct DatabaseRenderTests {
    private func fixture() async throws -> (ItemStore, ItemList, Item, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DatabaseRender-" + UUID().uuidString)
        let files = FileStore(root: root); try await files.ensureRoot()
        var list = ItemList.makeInbox(); list.name = "Project"
        let status = DatabaseField(name: "Status", kind: .select, options: [.init(name: "Planned"), .init(name: "Doing")])
        let estimate = DatabaseField(name: "Estimate", kind: .number)
        list.databaseFields = [status, estimate]; try await files.writeList(list)
        let store = ItemStore(store: files); try await store.bootstrap()
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
