import SwiftUI
import Testing
import UIKit
@testable import Lists

/// Render smoke coverage for the document detail route. The document page hosts
/// UIKit-backed title/body editors, so this follows the existing
/// HabitDetailViewRenderTests pattern: lay the view out in a real window and
/// assert the view graph builds without crashing.
@MainActor
struct ItemDocumentViewRenderTests {
    @Test func endEditingResignsPropertyInputInTheDocumentWindow() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let title = UITextView(frame: CGRect(x: 0, y: 0, width: 300, height: 40))
        let propertyInput = UITextField(frame: CGRect(x: 0, y: 50, width: 300, height: 40))
        controller.view.addSubview(title)
        controller.view.addSubview(propertyInput)
        controller.view.layoutIfNeeded()
        let bridge = DocumentFocusBridge()
        bridge.titleView = title
        #expect(propertyInput.becomeFirstResponder())
        #expect(propertyInput.isFirstResponder)
        bridge.endEditing()
        #expect(!propertyInput.isFirstResponder)
    }

    private func host(_ view: some View) {
        let frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let controller = UIHostingController(rootView: view.frame(width: 393, height: 852))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:))
        if let window {
            window.frame = frame
            window.rootViewController = controller
            window.makeKeyAndVisible()
        }
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        #expect(controller.view != nil, "the document detail route must build and lay out without crashing")
        window?.isHidden = true
        window?.rootViewController = nil
    }

    @Test func taskDocumentRouteRenders() async throws {
        let store = try await TestStore.seeded()
        var item = Item(
            type: .task,
            title: "Pay phone bill",
            listId: ItemList.inboxId,
            tags: ["finance"],
            due: .now,
            dueAllDay: false,
            priority: .high,
            flagged: true,
            reminder: Reminder(enabled: true, early: nil)
        )
        item.body = "Confirmation number and account notes."
        try await store.add(item)

        host(ItemDetailSheet(item: item, store: store))
    }

    @Test func eventDocumentRouteRenders() async throws {
        let store = try await TestStore.seeded()
        var event = Item(
            type: .event,
            title: "Lunch with Alex",
            listId: ItemList.inboxId,
            tags: ["family"],
            due: .now,
            dueAllDay: false
        )
        event.end = Date().addingTimeInterval(3600)
        event.body = "Meet at the corner table."
        try await store.add(event)

        host(ItemDetailSheet(item: event, store: store))
    }
}

@MainActor
struct DocumentPropertyVisibilityTests {
    @Test func freshPageShowsOnlyActiveValues() {
        let visibility = DocumentPropertyVisibility()
        #expect(!visibility.shows(.flag, active: false))
        #expect(!visibility.shows(.priority, active: false))
        #expect(visibility.shows(.tags, active: true))
    }

    @Test func explicitFieldRemainsVisibleWithoutAValue() {
        var visibility = DocumentPropertyVisibility()
        visibility.add(.date)
        #expect(visibility.shows(.date, active: false))
    }

    @Test func hideOverridesActiveValueAndAddRevealsIt() {
        var visibility = DocumentPropertyVisibility()
        visibility.add(.flag)
        visibility.hide(.flag)
        #expect(!visibility.shows(.flag, active: true))
        visibility.add(.flag)
        #expect(visibility.shows(.flag, active: true))
    }

    @Test func preferencesPersistPerItemAndRetainUnknownFutureFields() throws {
        let suite = "document-visibility-tests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UUID(), second = UUID()
        var visibility = DocumentPropertyVisibility(selected: ["future-property"], hidden: [])
        visibility.add(.date)
        visibility.hide(.flag)
        visibility.save(for: first, defaults: defaults)
        #expect(DocumentPropertyVisibility.load(for: first, defaults: defaults) == visibility)
        #expect(DocumentPropertyVisibility.load(for: second, defaults: defaults) == DocumentPropertyVisibility())
    }
}
