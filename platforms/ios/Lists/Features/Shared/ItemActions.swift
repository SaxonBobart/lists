import SwiftUI
import UIKit

/// Shared action vocabulary. UIKit collections and SwiftUI rows render the
/// same actions, with the native menu owning its layout and overflow.
@MainActor struct ItemActions {
    struct Action: Identifiable {
        let id: String
        let title: String
        let symbol: String
        var destructive = false
        let run: () -> Void
    }
    let item: Item
    let store: ItemStore
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onError: (String) -> Void
    var onSchedule: (() -> Void)?
    var onMove: (() -> Void)?
    var undoManager: UndoManager?
    var destination: ItemPasteDestination?
    var onCut: (() -> Void)?
    var onCopy: (() -> Void)?
    var onPaste: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onToggle: (() -> Void)?
    var onFlag: (() -> Void)?
    var onPriority: ((Item.Priority) -> Void)?
    var allowsCompletion = true

    private var pasteDestination: ItemPasteDestination {
        destination ?? .init(listId: item.listId, section: item.section, parentId: item.parentId, afterId: item.id)
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do { try await operation() }
            catch { onError(error.localizedDescription) }
        }
    }

    var primary: [Action] {
        [Action(id: "details", title: "Details", symbol: "info.circle", run: onOpen),
         Action(id: "flag", title: item.flagged ? "Unflag" : "Flag", symbol: item.flagged ? "flag.slash" : "flag") {
             if let onFlag { onFlag() }
             else { perform { try await store.toggleFlagged(item.id) } }
         },
         Action(id: "delete", title: "Delete", symbol: "trash", destructive: true, run: onDelete)]
    }
    var editing: [Action] {
        var actions = [
            Action(id: "cut", title: "Cut", symbol: "scissors", run: onCut ?? {
                perform { try await ItemClipboard.shared.cut(item, store: store, undoManager: undoManager) }
            }),
            Action(id: "copy", title: "Copy", symbol: "doc.on.doc", run: onCopy ?? {
                perform { try await ItemClipboard.shared.copy(item, store: store) }
            }),
            Action(id: "duplicate", title: "Duplicate", symbol: "plus.square.on.square", run: onDuplicate ?? {
                perform {
                    let payload = try await ItemClipboard.shared.prepare(item, store: store)
                    try await ItemClipboard.shared.paste(payload, into: pasteDestination, store: store)
                }
            })
        ]
        if ItemClipboard.shared.canPaste {
            actions.append(Action(id: "paste", title: "Paste", symbol: "doc.on.clipboard", run: onPaste ?? {
                perform { try await ItemClipboard.shared.paste(into: pasteDestination, store: store) }
            }))
        }
        if ItemClipboard.shared.canUndoCut {
            actions.append(Action(id: "undo.cut", title: "Undo Cut", symbol: "arrow.uturn.backward") {
                perform { try await ItemClipboard.shared.undoCut() }
            })
        }
        return actions
    }
    var secondary: [Action] {
        var actions: [Action] = []
        if allowsCompletion && (item.type == .task || (item.type == .event && item.completable)) {
            actions.append(Action(id: "complete", title: item.done ? "Mark Incomplete" : "Mark as Completed", symbol: "checkmark.circle", run: onToggle ?? {
                perform { try await store.toggleDone(item.id) }
            }))
        }
        if let onSchedule { actions.append(Action(id: "schedule", title: "Date and Time", symbol: "calendar", run: onSchedule)) }
        if let onMove { actions.append(Action(id: "move", title: "Move", symbol: "folder", run: onMove)) }
        return actions
    }
    var priorities: [Action] {
        Item.Priority.allCases.map { priority in
            Action(id: "priority.\(priority.rawValue)", title: priority.rawValue.capitalized,
                   symbol: item.priority == priority ? "checkmark" : "") {
                if let onPriority { onPriority(priority) }
                else {
                    perform {
                        guard var current = store.item(item.id) else { return }
                        current.priority = priority
                        try await store.update(current)
                    }
                }
            }
        }
    }
    func menu(compact: Bool = false) -> UIMenu {
        func ui(_ action: Action) -> UIAction {
            UIAction(title: action.title, image: UIImage(systemName: action.symbol),
                     identifier: .init("item.menu.\(action.id)"), attributes: action.destructive ? .destructive : []) { _ in action.run() }
        }
        let priority = UIMenu(title: "Priority", image: UIImage(systemName: "exclamationmark"), children: priorities.map(ui))
        if compact {
            let edits = editing
            let ordered = [edits.first(where: { $0.id == "cut" }), edits.first(where: { $0.id == "copy" }), primary.last,
                           edits.first(where: { $0.id == "duplicate" }), edits.first(where: { $0.id == "paste" })].compactMap { $0 }
            return UIMenu(children: ordered.map(ui) + edits.filter { $0.id == "undo.cut" }.map(ui) + primary.prefix(2).map(ui) + secondary.map(ui) + [priority])
        }
        let header = UIMenu(options: .displayInline, children: primary.map(ui))
        header.preferredElementSize = .medium
        return UIMenu(children: [header, UIMenu(options: .displayInline, children: secondary.map(ui) + [priority]),
                                UIMenu(options: .displayInline, children: editing.map(ui))])
    }
}

struct ItemActionsMenu: View {
    let actions: ItemActions
    var body: some View {
        ControlGroup { ForEach(actions.primary) { action in actionButton(action) } }
        ForEach(actions.secondary) { action in actionButton(action) }
        Menu("Priority", systemImage: "exclamationmark") {
            ForEach(actions.priorities) { action in actionButton(action) }
        }
        .accessibilityIdentifier("item.menu.priority")
        Divider()
        ForEach(actions.editing) { action in actionButton(action) }
    }
    private func actionButton(_ action: ItemActions.Action) -> some View {
        Button(role: action.destructive ? .destructive : nil, action: action.run) {
            Label(action.title, systemImage: action.symbol)
        }
        .accessibilityIdentifier("item.menu.\(action.id)")
    }
}

struct ItemActionsModifier: ViewModifier {
    let item: Item
    let store: ItemStore
    let onOpen: () -> Void
    var onDelete: (() -> Void)?
    var onMove: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCut: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onToggle: (() -> Void)?
    var destination: ItemPasteDestination?
    @Environment(\.undoManager) private var undoManager
    @State private var error: String?
    @State private var schedule = false
    @State private var pasteDraft = false

    func body(content: Content) -> some View {
        content.contextMenu {
            ItemActionsMenu(actions: ItemActions(item: store.item(item.id) ?? item, store: store, onOpen: onOpen,
                onDelete: onDelete ?? {
                    Task {
                        do { try await store.softDelete(item.id) }
                        catch { self.error = error.localizedDescription }
                    }
                }, onError: { error = $0 }, onSchedule: { schedule = true }, onMove: onMove,
                undoManager: undoManager, destination: destination, onCut: onCut, onCopy: onCopy,
                onPaste: { pasteDraft = true }, onDuplicate: onDuplicate, onToggle: onToggle))
        }
        .sheet(isPresented: $pasteDraft) { QuickCaptureSheet(store: store, defaultListId: item.listId, pasteOnOpen: true) }
        .sheet(isPresented: $schedule) { InlineDateTimePopover(item: store.item(item.id) ?? item, store: store) }
        .alert("Couldn’t Update Item", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

@MainActor enum ItemMenuPresentation {
    private static func presenter(from view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
    static func schedule(_ item: Item, store: ItemStore, from view: UIView) {
        presenter(from: view)?.present(UIHostingController(rootView: InlineDateTimePopover(item: item, store: store)), animated: true)
    }
    static func paste(store: ItemStore, listId: String, from view: UIView) {
        presenter(from: view)?.present(UIHostingController(rootView: QuickCaptureSheet(store: store, defaultListId: listId, pasteOnOpen: true)), animated: true)
    }
    static func error(_ message: String, from view: UIView) {
        let alert = UIAlertController(title: "Couldn’t Update Item", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter(from: view)?.present(alert, animated: true)
    }
}

/// Also available with an empty list, so an immediate Cut can always be undone.
struct ClipboardUndoButton: View {
    @State private var error: String?
    var body: some View {
        if ItemClipboard.shared.canUndoCut {
            Button("Undo Cut", systemImage: "arrow.uturn.backward") {
                Task {
                    do { try await ItemClipboard.shared.undoCut() }
                    catch { self.error = error.localizedDescription }
                }
            }
            .accessibilityIdentifier("item.menu.undo.cut")
            .itemMutationErrorAlert($error)
        }
    }
}
