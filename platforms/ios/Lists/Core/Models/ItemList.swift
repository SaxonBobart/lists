import Foundation

/// A list — a container holding items. See PRODUCT-SPEC.md §2.6.1.
///
/// Lists can nest (sub-lists shown as folders, not item rollups). A list
/// has a `defaultItemType` that determines what `+` creates by default,
/// and a `groceryMode` flag that auto-categorises items into sections.
public struct ItemList: Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var icon: String
    public var color: ListColor
    public var defaultItemType: Item.ItemType?
    public var groceryMode: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    public var position: Double
    public var deletedAt: Date?
    public var lamport: Int64

    public enum ListColor: String, Codable, Sendable, CaseIterable {
        case sage, blue, teal, green, amber, orange, pink, purple, grey
        case red, indigo, brown
    }

    public static let inboxId = "inbox"

    public static func makeInbox() -> ItemList {
        ItemList(
            id: inboxId,
            name: "Inbox",
            icon: "tray.fill",
            color: .blue,
            defaultItemType: .task,
            groceryMode: false,
            createdAt: .now,
            modifiedAt: .now,
            position: 0,
            deletedAt: nil,
            lamport: 0
        )
    }

    public init(
        id: String,
        name: String,
        icon: String,
        color: ListColor,
        defaultItemType: Item.ItemType? = nil,
        groceryMode: Bool = false,
        createdAt: Date,
        modifiedAt: Date,
        position: Double,
        deletedAt: Date? = nil,
        lamport: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.defaultItemType = defaultItemType
        self.groceryMode = groceryMode
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.position = position
        self.deletedAt = deletedAt
        self.lamport = lamport
    }
}

extension ItemList: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case color
        case defaultItemType = "default_item_type"
        case groceryMode     = "grocery_mode"
        case createdAt       = "created_at"
        case modifiedAt      = "modified_at"
        case position
        case deletedAt       = "deleted_at"
        case lamport
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id              = try c.decode(String.self,    forKey: .id)
        self.name            = try c.decode(String.self,    forKey: .name)
        self.icon            = try c.decodeIfPresent(String.self, forKey: .icon) ?? "tray"
        self.color           = try c.decodeIfPresent(ListColor.self, forKey: .color) ?? .grey
        self.defaultItemType = try c.decodeIfPresent(Item.ItemType.self, forKey: .defaultItemType)
        self.groceryMode     = try c.decodeIfPresent(Bool.self, forKey: .groceryMode) ?? false
        self.createdAt       = try Self.decodeDate(c, .createdAt)
        self.modifiedAt      = try Self.decodeDate(c, .modifiedAt)
        self.position        = try c.decodeIfPresent(Double.self, forKey: .position) ?? 0
        self.deletedAt       = try Self.decodeDateIfPresent(c, .deletedAt)
        self.lamport         = try c.decodeIfPresent(Int64.self, forKey: .lamport) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(icon, forKey: .icon)
        try c.encode(color, forKey: .color)
        try c.encodeIfPresent(defaultItemType, forKey: .defaultItemType)
        if groceryMode { try c.encode(true, forKey: .groceryMode) }
        try c.encode(ISO8601.string(from: createdAt), forKey: .createdAt)
        try c.encode(ISO8601.string(from: modifiedAt), forKey: .modifiedAt)
        try c.encode(position, forKey: .position)
        if let deletedAt {
            try c.encode(ISO8601.string(from: deletedAt), forKey: .deletedAt)
        }
        try c.encode(lamport, forKey: .lamport)
    }

    private static func decodeDate(
        _ c: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) throws -> Date {
        let s = try c.decode(String.self, forKey: key)
        guard let date = ISO8601.date(from: s) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: c,
                debugDescription: "Invalid ISO 8601 date: \(s)"
            )
        }
        return date
    }

    private static func decodeDateIfPresent(
        _ c: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) throws -> Date? {
        guard let s = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
        return ISO8601.date(from: s)
    }
}
