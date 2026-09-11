import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lists

final class FloatingAddButtonSnapshotTests: XCTestCase {

    @MainActor
    private func subject(tint: Color? = nil) -> some View {
        FloatingAddButton(tint: tint, action: {})
            .padding(20)
            .background(Color(.systemBackground))
    }

    @MainActor
    func testNeutral_Light() {
        assertSnapshot(
            of: subject(),
            as: .image(
                drawHierarchyInKeyWindow: true,
                // Liquid Glass shadow dithering varies by up to two colour levels.
                precision: 0.998,
                layout: .fixed(width: 120, height: 120),
                traits: SnapshotEnvironment.fixedLightTraits
            )
        )
    }

    @MainActor
    func testNeutral_Dark() {
        assertSnapshot(
            of: subject(),
            as: .image(
                drawHierarchyInKeyWindow: true,
                layout: .fixed(width: 120, height: 120),
                traits: SnapshotEnvironment.fixedDarkTraits
            )
        )
    }

    @MainActor
    func testTinted_Light() {
        assertSnapshot(
            of: subject(tint: .blue),
            as: .image(
                drawHierarchyInKeyWindow: true,
                layout: .fixed(width: 120, height: 120),
                traits: SnapshotEnvironment.fixedLightTraits
            )
        )
    }

    @MainActor
    private func bottomRow() -> some View {
        Color(.systemBackground)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BottomControlRow {
                    Image(systemName: "magnifyingglass")
                        .font(.title2).frame(width: 64, height: 64)
                        .glassEffect(.regular, in: Circle())
                    Spacer(minLength: 0)
                    FloatingAddButton(tint: .blue, action: {})
                }
            }
            .safeAreaPadding(.bottom, 34)
    }

    @MainActor
    func testBottomRow_Narrow() {
        assertSnapshot(of: bottomRow(), as: .image(
            drawHierarchyInKeyWindow: true,
            layout: .fixed(width: 320, height: 180),
            traits: SnapshotEnvironment.fixedLightTraits))
    }

    @MainActor
    func testBottomRow_Wide() {
        assertSnapshot(of: bottomRow(), as: .image(
            drawHierarchyInKeyWindow: true,
            layout: .fixed(width: 700, height: 180),
            traits: SnapshotEnvironment.fixedDarkTraits))
    }

    @MainActor
    private func calendarControls(width: CGFloat, overdueCount: Int = 1) -> some View {
        Color(.systemBackground)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CalendarBottomControls(viewKind: .constant(.twoDay), yearLabel: "2026", tint: .blue,
                    overdueCount: overdueCount, onToday: {}, onOverdue: {}, onAdd: {})
            }
            .safeAreaPadding(.bottom, 34)
            .frame(width: width, height: 260)
    }

    @MainActor
    func testCalendarControls_Narrow() {
        assertSnapshot(of: calendarControls(width: 320), as: .image(
            drawHierarchyInKeyWindow: true,
            layout: .fixed(width: 320, height: 260),
            traits: SnapshotEnvironment.fixedLightTraits))
    }

    @MainActor
    func testCalendarControls_Phone() {
        assertSnapshot(of: calendarControls(width: 393), as: .image(
            drawHierarchyInKeyWindow: true,
            layout: .fixed(width: 393, height: 260),
            traits: SnapshotEnvironment.fixedDarkTraits))
    }

    @MainActor
    func testCalendarControls_Wide() {
        assertSnapshot(of: calendarControls(width: 700), as: .image(
            drawHierarchyInKeyWindow: true,
            layout: .fixed(width: 700, height: 260),
            traits: SnapshotEnvironment.fixedDarkTraits))
    }

    @MainActor
    func testCalendarControls_EmptyInbox() {
        assertSnapshot(of: calendarControls(width: 393, overdueCount: 0), as: .image(
            drawHierarchyInKeyWindow: true,
            layout: .fixed(width: 393, height: 260),
            traits: SnapshotEnvironment.fixedDarkTraits))
    }

    @MainActor
    func testCalendarBack_Phone() {
        let name = "CalendarBackSnapshot-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = CalendarPreferences(defaults: defaults)
        let context = CalendarMenuContext(preferences: preferences, surfaceKey: "snapshot",
            viewKind: .twoDay, parentLabel: "September")
        let view = NavigationStack {
            Color(.systemBackground)
                .preference(key: CalendarMenuPreferenceKey.self, value: context)
                .navigationTitle("Scheduled")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(CalendarMenuScope())
        }
        assertSnapshot(of: view, as: .image(
            drawHierarchyInKeyWindow: true,
            layout: .fixed(width: 393, height: 200),
            traits: SnapshotEnvironment.fixedDarkTraits))
    }
}
