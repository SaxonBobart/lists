import Foundation
import Testing
@testable import Lists

@MainActor
struct ListViewPreferencesTests {
    private func freshDefaults() -> (UserDefaults, String) {
        let name = "ListViewPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    @Test func viewModePersistsPerSurface() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let prefs = ListViewPreferences(defaults: defaults)
        prefs.setViewMode(.columns, for: "list-a")
        prefs.setViewMode(.calendar, for: "smart:today")

        let restored = ListViewPreferences(defaults: defaults)
        #expect(restored.viewMode(for: "list-a") == .columns)
        #expect(restored.viewMode(for: "smart:today") == .calendar)
        #expect(restored.viewMode(for: "list-b") == .list)
        #expect(restored.viewMode(for: "global-calendar", default: .calendar) == .calendar)
    }

    @Test func columnsRequireDurableUserListSections() {
        #expect(
            ListViewPreferences.ViewMode.availableForUserList(hasSections: true)
                == [.list, .columns, .calendar]
        )
        #expect(
            ListViewPreferences.ViewMode.availableForUserList(hasSections: false)
                == [.list, .calendar]
        )
        #expect(ListViewPreferences.ViewMode.queryModes == [.list, .calendar])
        #expect(!ListViewPreferences.ViewMode.queryModes.contains(.columns))
    }
}
