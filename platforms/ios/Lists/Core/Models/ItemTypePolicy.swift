import Foundation

/// App-level availability and editing rules for item types.
///
/// System item types are always available. Core-plugin item types are available
/// only while their owning plugin is enabled, and may choose a full-screen
/// editing path instead of the inline list editor.
public struct ItemTypePolicy: Equatable, Sendable {
    public static let allEnabled = ItemTypePolicy(habitsEnabled: true)
    public static let allDisabled = ItemTypePolicy(habitsEnabled: false)

    public let habitsEnabled: Bool

    public init(habitsEnabled: Bool) {
        self.habitsEnabled = habitsEnabled
    }

    public func isEnabled(_ plugin: CorePlugin) -> Bool {
        switch plugin {
        case .habits:
            habitsEnabled
        }
    }

    public func isAvailable(_ type: Item.ItemType) -> Bool {
        guard let plugin = type.corePlugin else { return true }
        return isEnabled(plugin)
    }

    public func isAvailable(_ item: Item) -> Bool {
        isAvailable(item.type)
    }

    public func effectiveDefaultType(_ type: Item.ItemType) -> Item.ItemType {
        isAvailable(type) ? type : .task
    }

    public func allowsInlineEditing(_ type: Item.ItemType) -> Bool {
        isAvailable(type) && type.supportsInlineEditing
    }

    public func allowsInlineEditing(_ item: Item) -> Bool {
        allowsInlineEditing(item.type)
    }

    public func allowsInlineCreation(_ type: Item.ItemType) -> Bool {
        isAvailable(type) && type.supportsInlineCreation
    }

    public var settingsDefaultTypes: [Item.ItemType] {
        Self.filterAvailable(Item.ItemType.creationPickerOrder, using: self)
    }

    public var quickCaptureTypes: [Item.ItemType] {
        Self.filterAvailable(Item.ItemType.creationPickerOrder, using: self)
    }

    public var compactMenuSystemTypes: [Item.ItemType] {
        Self.filterAvailable(Item.ItemType.compactMenuSystemOrder, using: self)
    }

    public var compactMenuCorePluginTypes: [Item.ItemType] {
        Self.filterAvailable(Item.ItemType.compactMenuCorePluginOrder, using: self)
    }

    private static func filterAvailable(
        _ types: [Item.ItemType],
        using policy: ItemTypePolicy
    ) -> [Item.ItemType] {
        types.filter(policy.isAvailable)
    }
}

extension Item.ItemType {
    public static let systemTypes: [Self] = [.task, .note, .canvas, .event]
    public static let corePluginTypes: [Self] = [.habit]
    public static let creationPickerOrder: [Self] = [.task, .note, .canvas, .event, .habit]
    /// Canvas owns a separate document resource, so it is created explicitly
    /// rather than offered as an in-place conversion of an existing item.
    public static let compactMenuSystemOrder: [Self] = [.event, .note, .task]
    public static let compactMenuCorePluginOrder: [Self] = [.habit]

    public var corePlugin: CorePlugin? {
        switch self {
        case .habit:
            return .habits
        case .task, .note, .event, .canvas:
            return nil
        }
    }

    public var supportsInlineEditing: Bool {
        switch self {
        case .habit, .canvas:
            return false
        case .task, .note, .event:
            return true
        }
    }

    public var supportsInlineCreation: Bool {
        supportsInlineEditing
    }
}
