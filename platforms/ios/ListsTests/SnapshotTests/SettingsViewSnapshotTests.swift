import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lists

@MainActor
final class SettingsViewSnapshotTests: XCTestCase {

    @MainActor
    private func host(store: ItemStore) -> UIHostingController<some View> {
        let view = SettingsView(
            store: store,
            autoListPrefs: AutoListPreferences(),
            notificationStatusProvider: { .notDetermined },
            requestNotificationAuthorization: { false }
        )
        let vc = UIHostingController(rootView: view)
        vc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        return vc
    }

    @MainActor
    func testSettings_iPhone16_Light() async throws {
        let store = try await TestStore.seeded()
        assertSnapshot(of: host(store: store), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testSettings_iPhone16_Dark() async throws {
        let store = try await TestStore.seeded()
        assertSnapshot(
            of: host(store: store),
            as: .image(on: SnapshotEnvironment.iPhone16Light, traits: SnapshotEnvironment.darkTraits)
        )
    }

    @MainActor
    func testSettings_iPhoneSe_Light() async throws {
        let store = try await TestStore.seeded()
        assertSnapshot(of: host(store: store), as: .image(on: SnapshotEnvironment.iPhoneSeLight))
    }
}
