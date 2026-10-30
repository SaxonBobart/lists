import Foundation

struct ListEditDraft: Equatable {
    var name: String
    var icon: String
    var color: ItemList.ListColor
    var parentId: String?

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hasChanges(from initial: Self) -> Bool {
        trimmedName != initial.trimmedName || icon != initial.icon
            || color != initial.color || parentId != initial.parentId
    }

    func makeList(existing: ItemList?, now: Date = .now, nextPosition: Double) -> ItemList {
        ItemList(
            id: existing?.id ?? Self.newListId(),
            name: trimmedName,
            icon: icon,
            color: color,
            createdAt: existing?.createdAt ?? now,
            modifiedAt: now,
            position: existing?.position ?? nextPosition,
            parentId: parentId,
            deletedAt: existing?.deletedAt,
            lamport: (existing?.lamport ?? 0) + 1,
            sections: existing?.sections ?? []
        )
    }

    private static func newListId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}
