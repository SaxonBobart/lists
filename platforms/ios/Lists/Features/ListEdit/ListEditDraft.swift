import Foundation

enum ListEditType: Hashable {
    case standard
    case shopping

    var iconName: String {
        switch self {
        case .standard: return "list.bullet"
        case .shopping: return "cart.fill"
        }
    }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .shopping: return "Shopping"
        }
    }

    static func from(_ list: ItemList?) -> ListEditType {
        (list?.groceryMode ?? false) ? .shopping : .standard
    }
}

struct ListEditDraft {
    var name: String
    var icon: String
    var color: ItemList.ListColor
    var listType: ListEditType
    var parentId: String?

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func makeList(existing: ItemList?, now: Date = .now, nextPosition: Double) -> ItemList {
        ItemList(
            id: existing?.id ?? Self.newListId(),
            name: trimmedName,
            icon: icon,
            color: color,
            defaultItemType: existing?.defaultItemType,
            groceryMode: listType == .shopping,
            createdAt: existing?.createdAt ?? now,
            modifiedAt: now,
            position: existing?.position ?? nextPosition,
            parentId: parentId,
            deletedAt: existing?.deletedAt,
            lamport: (existing?.lamport ?? 0) + 1
        )
    }

    private static func newListId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}
