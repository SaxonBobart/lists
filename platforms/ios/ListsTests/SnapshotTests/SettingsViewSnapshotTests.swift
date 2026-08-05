import Foundation
import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lists

@MainActor
final class SettingsViewSnapshotTests: XCTestCase {

    @MainActor
    private func host(store: ItemStore, defaults: UserDefaults) -> UIHostingController<some View> {
        let view = SettingsView(
            store: store,
            autoListPrefs: AutoListPreferences(defaults: defaults),
            listViewPrefs: ListViewPreferences(defaults: defaults),
            reminderDefaults: defaults,
            notificationStatusProvider: { .notDetermined },
            requestNotificationAuthorization: { false }
        )
        .defaultAppStorage(defaults)
        let vc = UIHostingController(rootView: view)
        vc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        return vc
    }

    private func freshDefaults() -> UserDefaults {
        let suiteName = "SettingsSnapshot-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    func testSettings_iPhone16_Light() async throws {
        let store = try await TestStore.seeded()
        assertSnapshot(
            of: host(store: store, defaults: freshDefaults()),
            as: .image(
                on: SnapshotEnvironment.iPhone16Light,
                drawHierarchyInKeyWindow: true
            )
        )
    }

    @MainActor
    func testSettings_iPhone16_Dark() async throws {
        let store = try await TestStore.seeded()
        assertSnapshot(
            of: host(store: store, defaults: freshDefaults()),
            as: .image(
                on: SnapshotEnvironment.iPhone16Light,
                drawHierarchyInKeyWindow: true,
                traits: SnapshotEnvironment.darkTraits
            )
        )
    }

    @MainActor
    func testSettings_iPhoneSe_Light() async throws {
        let store = try await TestStore.seeded()
        assertSnapshot(
            of: host(store: store, defaults: freshDefaults()),
            as: .image(
                on: SnapshotEnvironment.iPhoneSeLight,
                drawHierarchyInKeyWindow: true
            )
        )
    }
}
