import Foundation
import XCTest
import SwiftUI
import UIKit
import SnapshotTesting
@testable import Lists

@MainActor
final class SettingsViewSnapshotTests: XCTestCase {
    private func assertSettingsSnapshot(
        on config: ViewImageConfig,
        style: UIUserInterfaceStyle = .light,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) async throws {
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }
        let store = try await TestStore.seeded()
        let suiteName = "SettingsSnapshot-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let view = SettingsView(
            store: store,
            autoListPrefs: AutoListPreferences(defaults: defaults),
            listViewPrefs: ListViewPreferences(defaults: defaults),
            calendarPreferences: CalendarPreferences(defaults: defaults),
            reminderDefaults: defaults,
            notificationStatusProvider: { .notDetermined },
            requestNotificationAuthorization: { false }
        )
        .defaultAppStorage(defaults)
        .transaction { $0.disablesAnimations = true }
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = style
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = style
        defer {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            window.isHidden = true
            window.rootViewController = nil
            originalKeyWindow?.makeKeyAndVisible()
        }

        // SnapshotTesting.wait delays before its image strategy mounts the
        // controller. Mount first so the native glass toolbar can settle.
        window.frame.size = try XCTUnwrap(config.size)
        let parent = UIViewController()
        parent.view.backgroundColor = .clear
        parent.view.frame = window.bounds
        parent.addChild(host)
        parent.view.addSubview(host.view)
        host.view.frame = parent.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let traits = config.traits
        host.traitOverrides.forceTouchCapability = traits.forceTouchCapability
        host.traitOverrides.layoutDirection = traits.layoutDirection
        host.traitOverrides.preferredContentSizeCategory = traits.preferredContentSizeCategory
        host.traitOverrides.userInterfaceIdiom = traits.userInterfaceIdiom
        host.traitOverrides.horizontalSizeClass = traits.horizontalSizeClass
        host.traitOverrides.verticalSizeClass = traits.verticalSizeClass
        host.traitOverrides.userInterfaceStyle = style
        host.didMove(toParent: parent)
        window.rootViewController = parent
        window.makeKeyAndVisible()
        parent.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(1500))
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat(for: UITraitCollection(userInterfaceStyle: style))
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        assertSnapshot(of: image, as: .image, file: file, testName: testName, line: line)
    }

    func testSettings_iPhone16_Light() async throws {
        try await assertSettingsSnapshot(on: SnapshotEnvironment.iPhone16Light)
    }

    func testSettings_iPhone16_Dark() async throws {
        try await assertSettingsSnapshot(on: SnapshotEnvironment.iPhone16Light, style: .dark)
    }

    func testSettings_iPhoneSe_Light() async throws {
        try await assertSettingsSnapshot(on: SnapshotEnvironment.iPhoneSeLight)
    }
}
