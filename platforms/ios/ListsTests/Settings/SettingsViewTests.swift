import Testing
@testable import Lists

struct SettingsViewTests {
    @Test func corePluginsExposeCurrentFirstPartyFeatures() {
        #expect(CorePlugin.allCases == [.habits])
        #expect(CorePlugin.habits.displayName == "Habits")
        #expect(CorePlugin.habits.statusLabel == "Core")
    }

    @Test func notificationPermissionDisplayStates() {
        let request = SettingsView.notificationPermissionDisplay(for: .notDetermined)
        #expect(request.text == "Request")
        #expect(request.canRequest)
        #expect(!request.opensSettings)

        let authorized = SettingsView.notificationPermissionDisplay(for: .enabled)
        #expect(authorized.text == "On")
        #expect(authorized.canRequest == false)
        #expect(!authorized.opensSettings)

        let denied = SettingsView.notificationPermissionDisplay(for: .denied)
        #expect(denied.text == "Off")
        #expect(denied.canRequest == false)
        #expect(denied.opensSettings)

        let quiet = SettingsView.notificationPermissionDisplay(for: .quiet)
        #expect(quiet.text == "Quiet")
        #expect(quiet.opensSettings)

        let summarized = SettingsView.notificationPermissionDisplay(for: .summarized)
        #expect(summarized.text == "Summary")
        #expect(summarized.opensSettings)
    }
}
