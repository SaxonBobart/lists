import Foundation

/// A named section inside a user list. Sections are first-class on the list
/// (`ItemList.sections`) so they can exist empty, be reordered, and be renamed
/// without rewriting every item. Items reference their section by `id` —
/// `Item.section` holds the UUID string.
public struct ListSection: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Manual ordering within the list. Same pattern as `ItemList.position`.
    public var position: Double

    public init(id: UUID = UUID(), name: String, position: Double) {
        self.id = id
        self.name = name
        self.position = position
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, position
    }
}
