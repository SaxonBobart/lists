import Foundation
import Testing
@testable import Lists

/// Persisted auto-list order is de-duplicated on read so corrupt UserDefaults
/// cannot make a SmartList appear twice in the Edit Pinned Lists screen.
@MainActor
struct AutoListPreferencesTests {

    private func freshDefaults() -> (UserDefaults, String) {
        let name = "AutoListPrefsTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    @Test func duplicateOrderEntriesAreDeduplicated() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["today", "scheduled", "today", "flagged", "scheduled"],
                     forKey: "lists.autolists.order.v1")

        let prefs = AutoListPreferences(defaults: defaults)

        #expect(prefs.order.count == Set(prefs.order).count, "no SmartList appears twice")
        #expect(Set(prefs.order) == Set(AutoListPreferences.defaultOrder),
                "every active smart list is present exactly once")
        #expect(Array(prefs.order.prefix(3)) == [.today, .scheduled, .flagged],
                "first-seen order of the stored prefix is preserved")
    }

    @Test func unknownOrderEntriesAreDroppedNotDuplicated() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["bogus", "today", "garbage"], forKey: "lists.autolists.order.v1")

        let prefs = AutoListPreferences(defaults: defaults)

        #expect(prefs.order.first == .today, "known ids survive; unknown ids are dropped")
        #expect(Set(prefs.order) == Set(AutoListPreferences.defaultOrder))
        #expect(prefs.order.count == AutoListPreferences.defaultOrder.count)
    }

    @Test func emptyOrderFallsBackToDefault() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let prefs = AutoListPreferences(defaults: defaults)

        #expect(prefs.order == AutoListPreferences.defaultOrder)
    }

    @Test func defaultNewItemTypePersists() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let prefs = AutoListPreferences(defaults: defaults)
        prefs.defaultNewItemType = .habit

        #expect(AutoListPreferences(defaults: defaults).defaultNewItemType == .habit)
    }

    @Test func invalidDefaultNewItemTypeFallsBackToTask() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("bookmark", forKey: "lists.newitem.defaultType.v1")

        let prefs = AutoListPreferences(defaults: defaults)

        #expect(prefs.defaultNewItemType == .task)
    }

    @Test func oldAssignedTileRawValueIsDroppedFromStoredPreferences() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["today", "assigned", "scheduled"], forKey: "lists.autolists.order.v1")
        defaults.set(["assigned"], forKey: "lists.autolists.hidden.v1")

        let prefs = AutoListPreferences(defaults: defaults)

        #expect(!prefs.order.map(\.rawValue).contains("assigned"))
        #expect(!prefs.visible.map(\.rawValue).contains("assigned"))
        #expect(prefs.hidden.isEmpty)
    }

    @Test func oldUrgentTileRawValueMigratesToAlarms() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["today", "urgent", "scheduled"], forKey: "lists.autolists.order.v1")
        defaults.set(["urgent"], forKey: "lists.autolists.hidden.v1")

        let prefs = AutoListPreferences(defaults: defaults)

        #expect(Array(prefs.order.prefix(3)) == [.today, .alarms, .scheduled])
        #expect(prefs.hidden == [.alarms])
        #expect(!prefs.visible.contains(.alarms))
    }
}
