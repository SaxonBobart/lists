import UIKit

// MARK: - Focus bridge

/// First-responder plumbing between the page's two UIKit text views. SwiftUI
/// focus state can't reach inside representables, so both register here and
/// the page (or the quick bar) drives focus through it.
@MainActor
final class DocumentFocusBridge {
    weak var titleView: UITextView?
    weak var bodyView: UITextView?

    /// Return in the title hops into the body, caret at the start.
    func focusBody() {
        guard let bodyView else { return }
        bodyView.becomeFirstResponder()
        let start = bodyView.beginningOfDocument
        bodyView.selectedTextRange = bodyView.textRange(from: start, to: start)
    }

    func endEditing() {
        titleView?.resignFirstResponder()
        bodyView?.resignFirstResponder()
    }
}

// MARK: - Quick details bar

/// Snapshot of the item state the quick bar displays.
struct DocumentQuickState: Equatable {
    var flagged: Bool
    var priority: Item.Priority
    var type: Item.ItemType
    var tagCount: Int
}

/// The title's keyboard accessory: the same Liquid Glass pill as the inline
/// editor's bar, carrying the fast metadata edits — open Details, flag,
/// priority, type — so a quick flag doesn't force a trip into the sheet.
final class DocumentQuickDetailsBar: KeyboardGlassBar {
    var onOpenDetails: () -> Void = {}
    var onToggleFlag: () -> Void = {}
    var onSetPriority: (Item.Priority) -> Void = { _ in }
    var onSetType: (Item.ItemType) -> Void = { _ in }
    var onAddTags: () -> Void = {}

    private let stackView = UIStackView()
    private let detailsButton = UIButton(type: .system)
    private let flagButton = UIButton(type: .system)
    private let priorityButton = UIButton(type: .system)
    private let tagsButton = UIButton(type: .system)
    private let typeButton = UIButton(type: .system)
    private var state = DocumentQuickState(flagged: false, priority: .none, type: .task, tagCount: 0)

    static func make() -> DocumentQuickDetailsBar {
        let bar = DocumentQuickDetailsBar()
        bar.setupContent()
        return bar
    }

    private func setupContent() {
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        pillContent.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: pillContent.leadingAnchor, constant: Self.buttonRowInset),
            stackView.trailingAnchor.constraint(equalTo: pillContent.trailingAnchor, constant: -Self.buttonRowInset),
            stackView.centerYAnchor.constraint(equalTo: pillContent.centerYAnchor)
        ])

        configureCircularButton(detailsButton, symbol: "calendar.badge.clock", id: "document.quickbar.date")
        detailsButton.addAction(UIAction { [weak self] _ in
            self?.onOpenDetails()
        }, for: .touchUpInside)
        stackView.addArrangedSubview(detailsButton)

        configureCircularButton(flagButton, symbol: "flag", id: "document.quickbar.flag")
        flagButton.addAction(UIAction { [weak self] _ in
            self?.onToggleFlag()
        }, for: .touchUpInside)
        stackView.addArrangedSubview(flagButton)

        configureCircularButton(priorityButton, symbol: "exclamationmark.circle", id: "document.quickbar.priority")
        priorityButton.showsMenuAsPrimaryAction = true
        stackView.addArrangedSubview(priorityButton)

        configureCircularButton(tagsButton, symbol: "tag", id: "document.quickbar.tags")
        tagsButton.addAction(UIAction { [weak self] _ in
            self?.onAddTags()
        }, for: .touchUpInside)
        stackView.addArrangedSubview(tagsButton)

        configureCircularButton(typeButton, symbol: "circle", id: "document.quickbar.type")
        typeButton.showsMenuAsPrimaryAction = true
        stackView.addArrangedSubview(typeButton)

        refresh()
    }

    /// Re-derive button appearance from the page's draft (pushed in from
    /// `DocumentTitleField.updateUIView` whenever the draft changes).
    func update(_ newState: DocumentQuickState) {
        state = newState
        refresh()
    }

    private func refresh() {
        setButtonSymbol(flagButton, state.flagged ? "flag.fill" : "flag")
        setActive(flagButton, state.flagged)

        priorityButton.menu = makePriorityMenu()
        setActive(priorityButton, state.priority != .none)

        setButtonSymbol(tagsButton, state.tagCount > 0 ? "tag.fill" : "tag")
        setActive(tagsButton, state.tagCount > 0)

        typeButton.menu = makeTypeMenu()
        setButtonSymbol(typeButton, Self.typeSymbol(state.type))
        setActive(typeButton, false)
        setActive(detailsButton, false)
    }

    private func makePriorityMenu() -> UIMenu {
        let options: [(String, Item.Priority)] = [
            ("None", .none), ("Low", .low), ("Medium", .medium), ("High", .high)
        ]
        let actions = options.map { (title, priority) in
            UIAction(
                title: title,
                state: priority == state.priority ? .on : .off
            ) { [weak self] _ in
                self?.onSetPriority(priority)
            }
        }
        return UIMenu(title: "Priority", children: actions)
    }

    private func makeTypeMenu() -> UIMenu {
        let options: [(String, String, Item.ItemType)] = [
            ("Task", "circle", .task),
            ("Habit", "checkmark.arrow.trianglehead.clockwise", .habit),
            ("Note", "text.document", .note),
            ("Event", "calendar", .event)
        ]
        let actions = options.map { (title, symbol, type) in
            UIAction(
                title: title,
                image: UIImage(systemName: symbol),
                state: type == state.type ? .on : .off
            ) { [weak self] _ in
                self?.onSetType(type)
            }
        }
        return UIMenu(title: "Type", children: actions)
    }

    private static func typeSymbol(_ type: Item.ItemType) -> String {
        switch type {
        case .task:  return "circle"
        case .note:  return "text.document"
        case .event: return "calendar"
        case .habit: return "checkmark.arrow.trianglehead.clockwise"
        }
    }
}
