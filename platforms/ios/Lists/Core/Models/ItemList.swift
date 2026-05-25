import Foundation

/// A list — a container holding items. See PRODUCT-SPEC.md §2.6.1.
///
/// Lists nest arbitrarily deep (Apple Notes-style hybrid): any list can hold
/// its own items *and* have child lists, which are surfaced as a collapsible
/// "Sub-Lists" section in the list detail view. `parentId == nil` means the
/// list lives at the root of the sidebar. A list's `defaultItemType` decides
/// what `+` creates; `groceryMode` auto-categorises items into sections.
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
    public var parentId: String?
    public var deletedAt: Date?
    public var lamport: Int64
    /// Named sub-groups within the list. Items reference their section by
    /// `ListSection.id` via `Item.section`. Empty for lists that have never
    /// had sections defined; old `.list.yml` files decode this as empty.
    public var sections: [ListSection]

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
            parentId: nil,
            deletedAt: nil,
            lamport: 0,
            sections: []
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
        parentId: String? = nil,
        deletedAt: Date? = nil,
        lamport: Int64 = 0,
        sections: [ListSection] = []
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
        self.parentId = parentId
        self.deletedAt = deletedAt
        self.lamport = lamport
        self.sections = sections
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
        case parentId        = "parent_id"
        case deletedAt       = "deleted_at"
        case lamport
        case sections
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
        self.parentId        = try c.decodeIfPresent(String.self, forKey: .parentId)
        self.deletedAt       = try Self.decodeDateIfPresent(c, .deletedAt)
        self.lamport         = try c.decodeIfPresent(Int64.self, forKey: .lamport) ?? 0
        self.sections        = try c.decodeIfPresent([ListSection].self, forKey: .sections) ?? []
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
        try c.encodeIfPresent(parentId, forKey: .parentId)
        if let deletedAt {
            try c.encode(ISO8601.string(from: deletedAt), forKey: .deletedAt)
        }
        try c.encode(lamport, forKey: .lamport)
        if !sections.isEmpty {
            try c.encode(sections, forKey: .sections)
        }
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
        // DI-3: absent → nil, but present-but-invalid must throw (→ DI-1
        // quarantine) rather than silently dropping the value.
        guard let s = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let date = ISO8601.date(from: s) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: c,
                debugDescription: "Invalid ISO 8601 date: \(s)"
            )
        }
        return date
    }
}
