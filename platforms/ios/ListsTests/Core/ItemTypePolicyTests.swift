import Foundation
import Testing
@testable import Lists

struct ItemTypePolicyTests {
    @Test func systemTypesStayAvailableWhenCorePluginsAreOff() {
        let policy = ItemTypePolicy.allDisabled

        for type in Item.ItemType.systemTypes {
            #expect(policy.isAvailable(type), "\(type.rawValue) is a system item type")
        }
    }

    @Test func habitAvailabilityFollowsCorePluginToggle() {
        #expect(ItemTypePolicy.allEnabled.isAvailable(.habit))
        #expect(!ItemTypePolicy.allDisabled.isAvailable(.habit))
    }

    @Test func unavailableDefaultTypeFallsBackToTask() {
        let policy = ItemTypePolicy.allDisabled

        #expect(policy.effectiveDefaultType(.habit) == .task)
        #expect(policy.effectiveDefaultType(.event) == .event)
    }

    @Test func pluginBackedHabitUsesFullScreenEditing() {
        let policy = ItemTypePolicy.allEnabled

        #expect(!policy.allowsInlineEditing(.habit))
        #expect(!policy.allowsInlineCreation(.habit))
        #expect(policy.allowsInlineEditing(.task))
        #expect(policy.allowsInlineCreation(.task))
    }

    @Test func compactTypeMenusKeepSystemAndPluginTypesSeparated() {
        let enabled = ItemTypePolicy.allEnabled
        let disabled = ItemTypePolicy.allDisabled

        #expect(enabled.compactMenuSystemTypes == [.event, .note, .task])
        #expect(enabled.compactMenuCorePluginTypes == [.habit])
        #expect(disabled.compactMenuSystemTypes == [.event, .note, .task])
        #expect(disabled.compactMenuCorePluginTypes.isEmpty)
    }

    @Test func preferencesBuildPolicyWithoutChangingStoredKeys() {
        let suiteName = "ItemTypePolicyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(CorePluginPreferences.policy(defaults: defaults).isAvailable(.habit))

        defaults.set(false, forKey: CorePluginPreferences.habitsEnabledKey)

        #expect(!CorePluginPreferences.policy(defaults: defaults).isAvailable(.habit))
    }
}

