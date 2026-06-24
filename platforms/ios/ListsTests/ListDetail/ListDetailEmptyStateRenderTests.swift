import SwiftUI
import Testing
import UIKit
@testable import Lists

@MainActor
struct ListDetailEmptyStateRenderTests {
    @Test func emptyStateRenders() {
        let frame = CGRect(x: 0, y: 0, width: 393, height: 300)
        let view = ListDetailEmptyStateView(icon: "tray.fill", color: .blue)
            .frame(width: frame.width, height: frame.height)
        let controller = UIHostingController(rootView: view)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:))
        if let window {
            window.frame = frame
            window.rootViewController = controller
            window.makeKeyAndVisible()
        }
        controller.view.frame = frame
        controller.view.layoutIfNeeded()

        #expect(controller.view != nil, "list detail empty state must build and lay out without crashing")

        window?.isHidden = true
        window?.rootViewController = nil
    }
}
