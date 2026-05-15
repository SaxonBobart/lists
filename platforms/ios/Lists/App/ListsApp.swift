import SwiftUI

@main
struct ListsApp: App {
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
                        // M0: surface bootstrap failure as console output.
                        // A user-visible error UI lands when settings + maintenance ships.
                        print("Lists.bootstrap failed: \(error)")
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
