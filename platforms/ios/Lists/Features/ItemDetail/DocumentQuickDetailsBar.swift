import UIKit

// MARK: - Focus bridge

/// First-responder plumbing between the page's two UIKit text views. SwiftUI
/// focus state can't reach inside representables, so both register here and
/// the page (or the quick bar) drives focus through it.
@MainActor
final class DocumentFocusBridge {
    weak var titleView: UITextView?
    weak var bodyView: UITextView?
    var endTableSelection: (() -> Void)?
    var focusTableCell: ((
        _ tableLocation: Int,
        _ address: MarkdownTableCellAddress,
        _ range: NSRange
    ) -> Void)?

    func focusTitle(range: NSRange? = nil) {
        guard let titleView else { return }
        titleView.becomeFirstResponder()
        if let range {
            titleView.selectedRange = range
        } else {
            let end = titleView.endOfDocument
            titleView.selectedTextRange = titleView.textRange(from: end, to: end)
        }
    }

    /// Return in the title hops into the body, caret at the start.
    func focusBody() {
        guard let bodyView else { return }
        bodyView.becomeFirstResponder()
        let start = bodyView.beginningOfDocument
        bodyView.selectedTextRange = bodyView.textRange(from: start, to: start)
    }

    func focusBody(range: NSRange) {
        guard let bodyView else { return }
        bodyView.becomeFirstResponder()
        bodyView.selectedRange = range
        if let storage = bodyView.textStorage as? MarkdownStyler {
            storage.cursorRange = range
        }
        DispatchQueue.main.async { [weak bodyView] in
            guard let bodyView,
                  let scrollView = bodyView.enclosingDocumentScrollView else { return }
            let visibleRange = NSRange(location: range.location, length: max(range.length, 1))
            bodyView.scrollRangeToVisible(visibleRange)
            if let selectedEnd = bodyView.selectedTextRange?.end {
                var caret = bodyView.caretRect(for: selectedEnd)
                caret = caret.insetBy(dx: 0, dy: -40)
                scrollView.scrollRectToVisible(scrollView.convert(caret, from: bodyView), animated: false)
            }
        }
    }

    func focusEditor(_ target: DocumentEditorFocusTarget) {
        switch target {
        case .body(let range):
            focusBody(range: range)
        case .tableCell(let tableLocation, let address, let range):
            focusTableCell?(tableLocation, address, range)
        }
    }

    func scrollBody(range: NSRange) {
        guard let bodyView,
              let scrollView = bodyView.enclosingDocumentScrollView else { return }
        let visibleRange = NSRange(location: range.location, length: max(range.length, 1))
        bodyView.scrollRangeToVisible(visibleRange)
        let glyphRange = bodyView.layoutManager.glyphRange(
            forCharacterRange: visibleRange,
            actualCharacterRange: nil
        )
        let rect = bodyView.layoutManager.boundingRect(
            forGlyphRange: glyphRange,
            in: bodyView.textContainer
        ).insetBy(dx: 0, dy: -56)
        scrollView.scrollRectToVisible(scrollView.convert(rect, from: bodyView), animated: false)
    }

    func endEditing() {
        endTableSelection?()
        if let storage = bodyView?.textStorage as? MarkdownStyler {
            storage.cursorRange = NSRange(location: NSNotFound, length: 0)
        }
        titleView?.resignFirstResponder()
        bodyView?.endEditing(true)
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
    var habitsPluginEnabled: Bool = true

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

        configureCircularButton(tagsButton, symbol: "number", id: "document.quickbar.tags")
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

        setButtonSymbol(tagsButton, "number")
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
        let currentType = state.type
        let makeAction = { [weak self] (type: Item.ItemType) in
            UIAction(
                title: type.documentDisplayName,
                image: UIImage(systemName: type.documentGlyph),
                state: type == currentType ? .on : .off
            ) { _ in
                self?.onSetType(type)
            }
        }
        let policy = ItemTypePolicy(habitsEnabled: habitsPluginEnabled)
        let systemItems = UIMenu(
            options: .displayInline,
            children: policy.compactMenuSystemTypes.map(makeAction)
        )
        let pluginItems = UIMenu(
            options: .displayInline,
            children: policy.compactMenuCorePluginTypes.map(makeAction)
        )
        return UIMenu(
            children: pluginItems.children.isEmpty ? [systemItems] : [systemItems, pluginItems]
        )
    }

    private static func typeSymbol(_ type: Item.ItemType) -> String {
        type.documentGlyph
    }
}
