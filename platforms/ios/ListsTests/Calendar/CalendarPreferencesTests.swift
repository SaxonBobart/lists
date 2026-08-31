import Foundation
import Testing
@testable import Lists

@MainActor
struct CalendarPreferencesTests {
    @Test func defaultsFavorAQuietUsefulCalendar() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let preferences = CalendarPreferences(defaults: defaults)

        #expect(preferences.recurrenceVisibility == .nextOccurrence)
        #expect(preferences.showTasks)
        #expect(preferences.showEvents)
        #expect(!preferences.showHabits)
        #expect(preferences.showNotes)
        #expect(preferences.showCompletedItems)
        #expect(!preferences.showCompletedHistory)
        #expect(!preferences.showMissedHistory)
        #expect(preferences.showWeekends)
        #expect(!preferences.showWeekNumbers)
    }

    @Test func legacyCalendarSurfaceAndBarsMigrateWithoutOverwritingScheduled() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(
            ["smart:calendar": "week", "smart:scheduled": "month"],
            forKey: "lists.calendar.viewKinds.v1"
        )
        defaults.set(
            ["smart:calendar": "stacked"],
            forKey: "lists.calendar.monthDensities.v1"
        )

        let preferences = CalendarPreferences(defaults: defaults)

        #expect(preferences.viewKind(for: "smart:scheduled") == .month)
        #expect(preferences.monthDensity(for: "smart:scheduled") == .compact)
        #expect(CalendarMonthDensity(rawValue: "stacked") == .compact)
        let storedViews = defaults.dictionary(forKey: "lists.calendar.viewKinds.v1")
        #expect(storedViews?["smart:calendar"] == nil)
    }

    @Test func projectionAndSurfaceChoicesPersist() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let preferences = CalendarPreferences(defaults: defaults)
        preferences.recurrenceVisibility = .visibleRange
        preferences.showNotes = false
        preferences.showCompletedHistory = true
        preferences.setListHidden("private", true)
        preferences.setViewKind(.week, for: "global")
        preferences.setMonthDensity(.compact, for: "global")

        let restored = CalendarPreferences(defaults: defaults)
        #expect(restored.recurrenceVisibility == .visibleRange)
        #expect(!restored.showNotes)
        #expect(restored.showCompletedHistory)
        #expect(restored.hiddenListIds == ["private"])
        #expect(restored.viewKind(for: "global") == .week)
        #expect(restored.monthDensity(for: "global") == .compact)
    }

    private func freshDefaults() -> (UserDefaults, String) {
        let name = "CalendarPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }
}
