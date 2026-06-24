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
