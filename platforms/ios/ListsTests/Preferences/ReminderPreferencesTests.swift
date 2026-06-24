import Foundation
import Testing
@testable import Lists

struct ReminderPreferencesTests {
    private func freshDefaults() -> (UserDefaults, String) {
        let name = "ReminderPrefsTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    @Test func defaultReminderTimeStartsAtNineAM() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 23))!

        let time = ReminderPreferences.defaultTime(on: date, defaults: defaults)
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)

        #expect(components.hour == 9)
        #expect(components.minute == 0)
    }

    @Test func defaultReminderTimePersistsHourAndMinute() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let calendar = Calendar.current
        let base = calendar.date(from: DateComponents(year: 2026, month: 6, day: 23))!
        let chosen = calendar.date(bySettingHour: 17, minute: 45, second: 0, of: base)!

        ReminderPreferences.setDefaultTime(chosen, defaults: defaults, calendar: calendar)
        let loaded = ReminderPreferences.defaultTime(on: base, defaults: defaults, calendar: calendar)
        let components = calendar.dateComponents([.hour, .minute], from: loaded)

        #expect(components.hour == 17)
        #expect(components.minute == 45)
    }
}
