import Foundation

struct ListEditDraft {
    var name: String
    var icon: String
    var color: ItemList.ListColor
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
