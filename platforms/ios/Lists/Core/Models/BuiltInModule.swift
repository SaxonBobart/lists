import Foundation

/// First-party plugins that ship as part of Lists.
///
/// This is deliberately not an external plugin API. It gives app surfaces a
/// shared product vocabulary for built-in plugins while persistence stays in
/// the normal local-first `Item` model.
enum BuiltInModule: String, CaseIterable, Identifiable, Sendable {
    case habits

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .habits: return "Habits"
        }
    }

    var statusLabel: String {
        switch self {
        case .habits: return "System"
        }
    }

    var settingsSummary: String {
        switch self {
        case .habits: return "Habit tracking, schedules, streaks, and completion history."
        }
    }
}

enum BuiltInModulePreferences {
    static let habitsEnabledKey = "plugins.habits.enabled"

    static func isEnabled(_ module: BuiltInModule, defaults: UserDefaults = .standard) -> Bool {
        switch module {
        case .habits:
            defaults.object(forKey: habitsEnabledKey) == nil
                ? true
                : defaults.bool(forKey: habitsEnabledKey)
        }
    }

    static func isItemTypeAvailable(_ type: Item.ItemType, habitsEnabled: Bool) -> Bool {
        switch type {
        case .habit:
            habitsEnabled
        case .task, .note, .event:
            true
        }
    }

    static func effectiveItemType(_ type: Item.ItemType, habitsEnabled: Bool) -> Item.ItemType {
        isItemTypeAvailable(type, habitsEnabled: habitsEnabled) ? type : .task
    }
}

extension Item {
    func isAvailable(habitsEnabled: Bool) -> Bool {
        BuiltInModulePreferences.isItemTypeAvailable(type, habitsEnabled: habitsEnabled)
    }
}
