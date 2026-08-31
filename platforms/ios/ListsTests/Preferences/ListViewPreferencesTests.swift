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

    @Test func legacyCalendarSurfaceMigratesOnlyIntoUnsetScheduledPreferences() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(
            ["smart:calendar": "calendar", "smart:scheduled": "list"],
            forKey: "lists.listview.viewMode.v1"
        )
        defaults.set(
            ["smart:calendar": false],
            forKey: "lists.listview.showOverdue.v1"
        )

        let prefs = ListViewPreferences(defaults: defaults)

        #expect(prefs.viewMode(for: "smart:scheduled") == .list)
        #expect(!prefs.showOverdue(for: "smart:scheduled"))
        let stored = defaults.dictionary(forKey: "lists.listview.viewMode.v1")
        #expect(stored?["smart:calendar"] == nil)
    }
}
