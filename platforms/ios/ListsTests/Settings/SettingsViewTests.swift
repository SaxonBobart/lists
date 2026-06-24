import Testing
import UserNotifications
@testable import Lists

struct SettingsViewTests {
    @Test func builtInModulesExposeCurrentFirstPartyFeatures() {
        #expect(BuiltInModule.allCases == [.habits])
        #expect(BuiltInModule.habits.displayName == "Habits")
        #expect(BuiltInModule.habits.statusLabel == "Built-in")
    }

    @Test func notificationPermissionDisplayStates() {
        let request = SettingsView.notificationPermissionDisplay(for: .notDetermined)
        #expect(request.text == "Request")
        #expect(request.canRequest)

        let authorized = SettingsView.notificationPermissionDisplay(for: .authorized)
        #expect(authorized.text == "On")
        #expect(authorized.canRequest == false)

        let denied = SettingsView.notificationPermissionDisplay(for: .denied)
        #expect(denied.text == "Denied")
        #expect(denied.canRequest == false)
    }
}
