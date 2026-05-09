import SwiftUI

@main
struct ListsApp: App {
    @State private var store = ItemStore(
        store: FileStore(root: StorageRoot.defaultListsDirectory())
    )

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
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
}
