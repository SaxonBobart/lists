import SwiftUI
import UIKit

extension ListDetailCollectionView.Coordinator {
    // MARK: Context menu

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        if let row = dataSource.itemIdentifier(for: indexPath), case .file(let id) = row,
           let parent, !parent.inSelectMode, !parent.isDestinationModeActive,
           let file = parent.store.standaloneFiles.first(where: { $0.id == id }) {
            return UIContextMenuConfiguration(identifier: id as NSCopying, previewProvider: nil) { [weak self] _ in
                self?.fileMenu(file, from: collectionView)
            }
        }
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
        return UIContextMenuConfiguration(identifier: id.uuidString as NSCopying, previewProvider: nil) { _ in
                ItemActions(item: item, store: parent.store,
                    onOpen: { parent.onShowItemDetail(item) },
                    onDelete: { parent.onSoftDeleteItem(id) },
                    onError: { message in ItemMenuPresentation.error(message, from: collectionView) },
                    onSchedule: { ItemMenuPresentation.schedule(item, store: parent.store, from: collectionView) },
                    onMove: { parent.onBeginMove(item) }, undoManager: collectionView.undoManager).menu()
            }
    }

    // MARK: Swipe actions

    func trailingSwipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let row = dataSource.itemIdentifier(for: indexPath),
              let parent = parent else { return nil }
        if parent.moveSession.isActive || parent.documentLinkSession.isActive { return nil }
        switch row {
        case .file(let id):
            guard let file = parent.store.standaloneFiles.first(where: { $0.id == id }), let view = collectionView else { return nil }
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
                self?.deleteFile(file, from: view); completion(true)
            }
            delete.image = UIImage(systemName: "trash")
            let open = UIContextualAction(style: .normal, title: "Open") { [weak self] _, _, completion in
                self?.openFile(file, from: view); completion(true)
            }
            open.image = UIImage(systemName: "arrow.up.right.square")
            let configuration = UISwipeActionsConfiguration(actions: [delete, open])
            configuration.performsFirstActionWithFullSwipe = false
            return configuration
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
                    do { try await store.toggleFlagged(id) }
                    catch { if let view = self.collectionView { ItemMenuPresentation.error(error.localizedDescription, from: view) } }
                }
                completion(true)
            }
            flag.image = UIImage(systemName: item.flagged ? "flag.slash" : "flag")
            flag.backgroundColor = .systemOrange

            // "Open" reads as "open this as its page" for the document types;
            // All supported types use the document details surface.
            let details = UIContextualAction(
                style: .normal,
                title: "Open"
            ) { _, _, completion in
                onShowItemDetail(item)
                completion(true)
            }
            details.image = UIImage(systemName: "text.document")
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
        if let row = dataSource.itemIdentifier(for: indexPath), case .file(let id) = row,
           let parent, !parent.inSelectMode, !parent.isDestinationModeActive,
           let file = parent.store.standaloneFiles.first(where: { $0.id == id }), let view = collectionView {
            let move = UIContextualAction(style: .normal, title: "Move") { [weak self] _, _, completion in
                self?.moveFile(file, from: view); completion(true)
            }
            move.image = UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            move.backgroundColor = UIColor(ListsTokens.accent)
            let configuration = UISwipeActionsConfiguration(actions: [move])
            configuration.performsFirstActionWithFullSwipe = false
            return configuration
        }
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
    func fileMenu(_ file: StandaloneFile, from view: UIView) -> UIMenu {
        UIMenu(children: [
            UIAction(title: "Open", image: UIImage(systemName: "arrow.up.right.square")) { [weak self] _ in self?.openFile(file, from: view) },
            UIAction(title: "Move", image: UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right")) { [weak self] _ in self?.moveFile(file, from: view) },
            UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.deleteFile(file, from: view) }
        ])
    }

    func openFile(_ file: StandaloneFile, from view: UIView) {
        guard let parent else { return }
        Task {
            do {
                let url = try await parent.store.standaloneFileURL(file)
                ItemMenuPresentation.present(LocalFilePreviewScreen(url: url, title: file.fileName), from: view)
            } catch { ItemMenuPresentation.error(error.localizedDescription, from: view) }
        }
    }

    func moveFile(_ file: StandaloneFile, from view: UIView) {
        guard let parent else { return }
        parent.moveSession.begin(file: file)
    }

    func deleteFile(_ file: StandaloneFile, from view: UIView) {
        guard let parent else { return }
        Task {
            do {
                let deleted = try await parent.store.deleteStandaloneFile(file)
                view.undoManager?.registerUndo(withTarget: parent.store) { store in
                    Task { @MainActor in
                        do { try await store.restoreStandaloneFile(deleted) }
                        catch { ItemMenuPresentation.error(error.localizedDescription, from: view) }
                    }
                }
                view.undoManager?.setActionName("Delete File")
                applySnapshot(animated: true)
            } catch { ItemMenuPresentation.error(error.localizedDescription, from: view) }
        }
    }

}
