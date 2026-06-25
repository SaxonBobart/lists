import Foundation

/// First-party plugins that ship as part of Lists.
///
/// This is deliberately not an external plugin API. It gives app surfaces a
/// shared product vocabulary for built-in plugins while persistence stays in
/// the normal local-first `Item` model.
public enum CorePlugin: String, CaseIterable, Identifiable, Sendable {
    case habits

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .habits: return "Habits"
        }
    }

    public var statusLabel: String {
        switch self {
        case .habits: return "Core"
        }
    }

    public var settingsSummary: String {
        switch self {
        case .habits: return "Habit tracking, schedules, streaks, and completion history."
        }
    }
}

public enum CorePluginPreferences {
    public static let habitsEnabledKey = "plugins.habits.enabled"

    public static func policy(defaults: UserDefaults = .standard) -> ItemTypePolicy {
        ItemTypePolicy(habitsEnabled: isEnabled(.habits, defaults: defaults))
    }

    public static func isEnabled(_ module: CorePlugin, defaults: UserDefaults = .standard) -> Bool {
        switch module {
        case .habits:
            defaults.object(forKey: habitsEnabledKey) == nil
                ? true
                : defaults.bool(forKey: habitsEnabledKey)
        }
    }

    public static func isItemTypeAvailable(_ type: Item.ItemType, habitsEnabled: Bool) -> Bool {
        ItemTypePolicy(habitsEnabled: habitsEnabled).isAvailable(type)
    }

    public static func effectiveItemType(_ type: Item.ItemType, habitsEnabled: Bool) -> Item.ItemType {
        ItemTypePolicy(habitsEnabled: habitsEnabled).effectiveDefaultType(type)
    }
}

extension Item {
    public func isAvailable(in policy: ItemTypePolicy) -> Bool {
        policy.isAvailable(self)
    }
}
