import SwiftUI
import Testing
import UIKit
@testable import Lists

/// Render smoke coverage for the temporary move UI. The product rule is that
/// move mode is an in-place shelf plus destination rows, so these views should
/// mount without needing the old item-parent picker route.
@MainActor
struct MoveDestinationRenderTests {
    private func makeStore() async throws -> ItemStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsMoveDestinationRender-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        return store
    }

    private func host(_ view: some View, height: CGFloat = 96) {
        let frame = CGRect(x: 0, y: 0, width: 393, height: height)
        let controller = UIHostingController(rootView: view.frame(width: 393, height: height))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:))
        if let window {
            window.frame = frame
            window.rootViewController = controller
            window.makeKeyAndVisible()
        }
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        #expect(controller.view != nil, "move destination UI must build and lay out without crashing")
        window?.isHidden = true
        window?.rootViewController = nil
    }

    @Test func moveShelfRendersForActiveSession() async throws {
        let store = try await makeStore()
        let item = Item(type: .task, title: "Pack charger", listId: ItemList.inboxId)
        try await store.add(item)
        let session = ItemMoveSession()
        session.begin(item: item)

        host(MoveShelfView(session: session, store: store))
    }

    @Test func noneDestinationRowRenders() {
        host(
            MoveNoneDestinationRow(listName: "Travel", listColor: .blue) {},
            height: 72
        )
    }

    @Test func shelfDropTargetRenders() async throws {
        let store = try await makeStore()
        let item = Item(type: .task, title: "Book tickets", listId: ItemList.inboxId)
        try await store.add(item)

        host(MoveShelfDropTargetView(item: item, store: store, onBeginMove: { _ in }))
    }
}
