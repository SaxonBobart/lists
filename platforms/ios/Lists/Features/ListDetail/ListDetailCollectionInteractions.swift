import SwiftUI
import UIKit

extension ListDetailCollectionView.Coordinator {
    // MARK: Context menu

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let row = dataSource.itemIdentifier(for: indexPath),
              case .item(let id, _) = row,
              let parent = parent,
              let item = parent.store.item(id) else {
            return nil
        }
        // Suppress context menu while in select mode — the tap is
        // doing selection, so a competing long-press menu would confuse the
        // gesture model.
        if parent.inSelectMode { return nil }
        if parent.moveSession.isActive || parent.documentLinkSession.isActive { return nil }
        return UIContextMenuConfiguration(identifier: id.uuidString as NSCopying, previewProvider: nil) { [weak self] _ in
            let flagAction = UIAction(
                title: item.flagged ? "Unflag" : "Flag",
                image: UIImage(systemName: item.flagged ? "flag.slash" : "flag")
            ) { _ in
                Task { @MainActor in
                    try? await self?.parent?.store.toggleFlagged(id)
                }
            }
            let deleteAction = UIAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self?.parent?.onSoftDeleteItem(id)
            }
            return UIMenu(children: [flagAction, deleteAction])
        }
    }

    // MARK: Swipe actions

    func trailingSwipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let row = dataSource.itemIdentifier(for: indexPath),
              let parent = parent else { return nil }
        if parent.moveSession.isActive || parent.documentLinkSession.isActive { return nil }
        switch row {
        case .item(let id, _):
            guard let item = parent.store.item(id) else { return nil }
            let store = parent.store
            let onShowItemDetail = parent.onShowItemDetail
            let onSoftDeleteItem = parent.onSoftDeleteItem

            let delete = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                onSoftDeleteItem(id)
                completion(true)
            }
            delete.image = UIImage(systemName: "trash")
            delete.backgroundColor = .systemRed

            let flag = UIContextualAction(
                style: .normal,
                title: item.flagged ? "Unflag" : "Flag"
            ) { _, _, completion in
                Task { @MainActor in
                    try? await store.toggleFlagged(id)
                }
                completion(true)
            }
            flag.image = UIImage(systemName: item.flagged ? "flag.slash" : "flag")
            flag.backgroundColor = .systemOrange

            // "Open" reads as "open this as its page" for the document types;
            // habits keep "Details" — their info button leads to habit detail.
            let details = UIContextualAction(
                style: .normal,
                title: item.type.supportsInlineEditing ? "Open" : "Details"
            ) { _, _, completion in
                onShowItemDetail(item)
                completion(true)
            }
            details.image = UIImage(systemName: item.type.supportsInlineEditing ? "text.document" : "info.circle")
            details.backgroundColor = .systemGray

            let config = UISwipeActionsConfiguration(actions: [delete, flag, details])
            config.performsFirstActionWithFullSwipe = true
            return config
        case .sectionHeader(let key):
            guard key != listDetailUncategorizedKey, let sid = UUID(uuidString: key) else { return nil }
            let name = parent.sectionDisplayName(for: key) ?? "section"
            let delete = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                parent.onPromptDeleteSection(sid, name)
                completion(true)
            }
            delete.image = UIImage(systemName: "trash")
            return UISwipeActionsConfiguration(actions: [delete])
        case .subListChild(let id):
            let delete = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                parent.onSoftDeleteSubList(id)
                completion(true)
            }
            delete.image = UIImage(systemName: "trash")
            return UISwipeActionsConfiguration(actions: [delete])
        default:
            return nil
        }
    }

    /// Leading-edge swipe (swipe right) — move mode plus Outdent for sub-items.
    func leadingSwipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let row = dataSource.itemIdentifier(for: indexPath),
              case .item(let id, _) = row,
              let parent = parent,
              let item = parent.store.item(id) else { return nil }
        if parent.moveSession.isActive || parent.documentLinkSession.isActive { return nil }
        let store = parent.store

        let move = UIContextualAction(style: .normal, title: "Move") { [weak self] _, _, completion in
            completion(true)
            self?.parent?.onBeginMove(item)
        }
        move.image = UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right")
        move.backgroundColor = UIColor(ListsTokens.accent)

        if item.parentId != nil {
            let outdent = UIContextualAction(style: .normal, title: "Outdent") { _, _, completion in
                Task { @MainActor in
                    store.applyMoveSync(itemId: item.id, toListId: item.listId, parentId: nil)
                }
                completion(true)
            }
            outdent.image = UIImage(systemName: "decrease.indent")
            outdent.backgroundColor = UIColor(ListsTokens.accent)
            let config = UISwipeActionsConfiguration(actions: [outdent, move])
            config.performsFirstActionWithFullSwipe = false
            return config
        }

        let config = UISwipeActionsConfiguration(actions: [move])
        config.performsFirstActionWithFullSwipe = false
        return config
    }
}
