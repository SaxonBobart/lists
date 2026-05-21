import Foundation
@testable import Lists

/// Builds an in-memory ItemStore against a fresh temp directory and runs
/// the seed bootstrap. Use in snapshot tests that need a populated store
/// (Sidebar, ListDetail, TodayView, smart lists).
enum TestStore {
    @MainActor
    static func seeded() async throws -> ItemStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsSnapshot-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        return store
    }
}
