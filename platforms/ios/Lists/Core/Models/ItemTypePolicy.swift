import Foundation

/// Active document types. The retired habit enum value is legacy metadata only;
/// its documents are isolated by the decoder instead of entering the library.
public struct ItemTypePolicy: Equatable, Sendable {
    public static let allEnabled = ItemTypePolicy()
    public static let allDisabled = ItemTypePolicy()
    public init() {}
    public init(habitsEnabled: Bool) {}
    public var habitsEnabled: Bool { false }
    public func isAvailable(_ type: Item.ItemType) -> Bool { type != .habit }
    public func isAvailable(_ item: Item) -> Bool { isAvailable(item.type) }
    public func effectiveDefaultType(_ type: Item.ItemType) -> Item.ItemType { isAvailable(type) ? type : .task }
    public func allowsInlineEditing(_ type: Item.ItemType) -> Bool { isAvailable(type) }
    public func allowsInlineEditing(_ item: Item) -> Bool { isAvailable(item) }
    public func allowsInlineCreation(_ type: Item.ItemType) -> Bool { isAvailable(type) }
    public var settingsDefaultTypes: [Item.ItemType] { Item.ItemType.systemTypes }
    public var quickCaptureTypes: [Item.ItemType] { Item.ItemType.systemTypes }
    public var compactMenuSystemTypes: [Item.ItemType] { Item.ItemType.compactMenuSystemOrder }
}
extension Item.ItemType {
    public static let systemTypes: [Self] = [.task, .note, .event]
    public static let creationPickerOrder = systemTypes
    public static let compactMenuSystemOrder: [Self] = [.event, .note, .task]
    public var supportsInlineEditing: Bool { self != .habit }
    public var supportsInlineCreation: Bool { supportsInlineEditing }
}
extension Item {
    public func isAvailable(in policy: ItemTypePolicy) -> Bool { policy.isAvailable(self) }
}
