import OSLog
import SwiftUI
import UIKit

@main
struct ListsApp: App {
    private static let logger = Logger(subsystem: "io.github.saxonbobart.lists", category: "bootstrap")

    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingWriteFlusher = PendingWriteFlusher()
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
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .inactive else { return }
                    pendingWriteFlusher.flush(store: store)
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

    /// Retained editor writes are memory-backed until FileStore accepts them.
    /// Ask iOS for a short, balanced background execution window as the scene
    /// becomes inactive so suspension cannot routinely strand the last edit.
    @MainActor
    private final class PendingWriteFlusher {
        private var identifier: UIBackgroundTaskIdentifier = .invalid
        private var flushTask: Task<Void, Never>?

        func flush(store: ItemStore) {
            guard flushTask == nil else { return }
            let application = UIApplication.shared
            identifier = application.beginBackgroundTask(
                withName: "Finish pending Lists writes"
            ) { [weak self] in
                guard let self else { return }
                ListsApp.logger.error("Background time expired while saving pending edits")
                self.flushTask?.cancel()
                self.endBackgroundAssertion()
            }

            flushTask = Task { @MainActor [weak self] in
                defer {
                    self?.flushTask = nil
                    self?.endBackgroundAssertion()
                }
                do {
                    try await store.flushPendingWrites()
                } catch {
                    ListsApp.logger.error("""
                        Lists could not flush pending edits while becoming inactive: \
                        \(String(describing: error), privacy: .private)
                        """)
                }
            }
        }

        private func endBackgroundAssertion() {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
}
