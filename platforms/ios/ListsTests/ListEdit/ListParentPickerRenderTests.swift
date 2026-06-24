import SwiftUI
import Testing
import UIKit
@testable import Lists

/// Render smoke coverage for the list hierarchy picker. Item moving has its
/// own in-place shelf; this sheet is only for assigning a parent to a list.
@MainActor
struct ListParentPickerRenderTests {
    private func makeList(
        id: String,
        name: String,
        position: Double,
        parentId: String? = nil
    ) -> ItemList {
        ItemList(
            id: id,
            name: name,
            icon: "folder",
            color: .blue,
            createdAt: .now,
            modifiedAt: .now,
            position: position,
            parentId: parentId
        )
    }

    private func makeStore() async throws -> ItemStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsParentPickerRender-\(UUID().uuidString)")
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "work", name: "Work", position: 1))
        try await setup.writeList(makeList(id: "projects", name: "Projects", position: 2, parentId: "work"))

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        return store
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
        #expect(controller.view != nil, "list parent picker must build and lay out without crashing")
        window?.isHidden = true
        window?.rootViewController = nil
    }

    @Test func parentPickerSheetRenders() async throws {
        let store = try await makeStore()

        host(
            ParentPickerSheet(
                store: store,
                movingListId: "projects",
                initialSelection: "work",
                onPick: { _ in }
            )
        )
    }
}
