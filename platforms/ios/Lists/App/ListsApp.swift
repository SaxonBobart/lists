import OSLog
import SwiftUI

@main
struct ListsApp: App {
    private static let logger = Logger(subsystem: "io.github.saxonbobart.lists", category: "bootstrap")

    @State private var store = ItemStore(
        store: FileStore(root: Self.listsRoot())
    )

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .fontDesign(.default)
                .task {
                    do {
                        try await store.bootstrap()
                    } catch {
                        // Keep the app from hanging on the loading screen. A
                        // user-visible recovery surface belongs in Settings.
                        Self.logger.error("Lists.bootstrap failed: \(String(describing: error), privacy: .private)")
                    }
                }
        }
    }

    private static func listsRoot() -> URL {
        let root = StorageRoot.defaultListsDirectory()
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-data") {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }
}
