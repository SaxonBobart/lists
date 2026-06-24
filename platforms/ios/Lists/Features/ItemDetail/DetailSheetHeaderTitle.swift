import SwiftUI

/// Principal toolbar title for a detail sheet, reflecting where the item sits
/// in the hierarchy:
/// - sub-item: parent-title pill; tap starts move mode.
/// - parent item: "Move" pill; tap starts move mode.
/// - standalone item: plain title text, no move control.
struct DetailSheetHeaderTitle: View {
    let item: Item
    let store: ItemStore
    let standaloneLabel: String
    var accessibilityId: String?
    var onBeginMove: ((Item) -> Void)?

    var body: some View {
        if (item.parentId != nil || hasChildren), let onBeginMove {
            Button {
                onBeginMove(item)
            } label: {
                pill(label: pillLabel)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(accessibilityId ?? "detail.parent")
        } else {
            Text(standaloneLabel)
                .font(ListsTypography.headline)
                .foregroundStyle(ListsTokens.Foreground.primary)
        }
    }

    private var pillLabel: String {
        if let parent = parentItem {
            return parent.title.isEmpty ? "Untitled" : parent.title
        }
        return "Move"
    }

    private func pill(label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.indent")
                .imageScale(.small)
            Text(label)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: Capsule())
    }

    private var parentItem: Item? {
        guard let parentId = item.parentId else { return nil }
        return store.items.first { $0.id == parentId && $0.deletedAt == nil }
    }

    private var hasChildren: Bool {
        store.items.contains { $0.parentId == item.id && $0.deletedAt == nil }
    }
}
