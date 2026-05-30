import XCTest
@testable import Lists

/// PREF-1: the persisted auto-list order is de-duplicated on read, so a corrupt
/// UserDefaults payload with a repeated id can't make a SmartList appear twice
/// (which yields undefined rows / broken drag-reorder in the Edit-Lists screen).
final class AutoListPreferencesTests: XCTestCase {

    private func freshDefaults() -> (UserDefaults, String) {
        let name = "AutoListPrefsTest-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return (d, name)
    }

    func testDuplicateOrderEntriesAreDeduplicated() {
        let (d, name) = freshDefaults()
        defer { d.removePersistentDomain(forName: name) }
        d.set(["today", "scheduled", "today", "flagged", "scheduled"],
              forKey: "lists.autolists.order.v1")

        let prefs = AutoListPreferences(defaults: d)

        XCTAssertEqual(prefs.order.count, Set(prefs.order).count, "no SmartList appears twice")
        XCTAssertEqual(Set(prefs.order), Set(SmartList.allCases), "every smart list present exactly once")
        XCTAssertEqual(Array(prefs.order.prefix(3)), [.today, .scheduled, .flagged],
                       "first-seen order of the stored prefix is preserved")
    }

    func testUnknownOrderEntriesAreDroppedNotDuplicated() {
        let (d, name) = freshDefaults()
        defer { d.removePersistentDomain(forName: name) }
        d.set(["bogus", "today", "garbage"], forKey: "lists.autolists.order.v1")

        let prefs = AutoListPreferences(defaults: d)

        XCTAssertEqual(prefs.order.first, .today, "known ids survive; unknown ids are dropped")
        XCTAssertEqual(Set(prefs.order), Set(SmartList.allCases))
        XCTAssertEqual(prefs.order.count, SmartList.allCases.count)
    }

    func testEmptyOrderFallsBackToDefault() {
        let (d, name) = freshDefaults()
        defer { d.removePersistentDomain(forName: name) }
        let prefs = AutoListPreferences(defaults: d)
        XCTAssertEqual(prefs.order, AutoListPreferences.defaultOrder)
    }
}
