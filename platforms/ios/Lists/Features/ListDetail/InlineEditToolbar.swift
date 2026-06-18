import UIKit

/// Actions raised by the inline-edit keyboard accessory bar. Implemented by
/// `InlineEditController` (the editing cell's coordinator), which holds the
/// item + store and either mutates the store directly (flag, priority, type)
/// or presents a sub-editor (date, tags) over the editing text view's window.
@MainActor
protocol InlineEditToolbarDelegate: AnyObject {
    func inlineToolbarDidTapDate()
    func inlineToolbarHasDate() -> Bool
    func inlineToolbarToggleFlag()
    func inlineToolbarIsFlagged() -> Bool
    func inlineToolbarCurrentPriority() -> Item.Priority
    func inlineToolbarSetPriority(_ priority: Item.Priority)
    func inlineToolbarDidTapTags()
    /// Quick type flip (task / note / event). `canChangeType` is false for
    /// habits — habit semantics don't survive a casual flip, so their button
    /// is hidden and type stays editable only through the habit screen.
    func inlineToolbarCanChangeType() -> Bool
    func inlineToolbarCurrentType() -> Item.ItemType
    func inlineToolbarSetType(_ type: Item.ItemType)
    /// True when the item currently has a parent — button glows blue.
    func inlineToolbarHasParent() -> Bool
    /// Open the Move-to-Parent picker sheet.
    func inlineToolbarDidTapMoveToParent()
}

/// Apple Reminders-style keyboard accessory bar shown while editing an item
/// inline: a Liquid Glass pill (geometry shared via `KeyboardGlassBar`) with a
/// spread row of SF Symbol buttons — date/time, flag, priority, tags, type,
/// assign (placeholder). Buttons whose attribute is set (date, flag, priority)
/// render as a filled blue circle with a white glyph; the rest are plain
/// glyphs. Deliberately compact: every button fits, nothing scrolls.
///
/// There is no keyboard-dismiss button here — committing the edit is done by
/// the blue ✓ that pops into the navigation bar while editing.
///
/// Distinct from `MarkdownReminderToolbar`: that one performs pure text
/// transforms on the markdown editor; this one edits item metadata and can
/// open sub-editors. Lightweight pickers (priority, type, assign) are native
/// `UIMenu`s; the heavier date and tag editors are presented by the delegate.
final class InlineEditToolbar: KeyboardGlassBar {
    private weak var delegate: InlineEditToolbarDelegate?
    private let stackView = UIStackView()
    private let dateButton = UIButton(type: .system)
    private let flagButton = UIButton(type: .system)
    private let priorityButton = UIButton(type: .system)
    private let tagButton = UIButton(type: .system)
    private let typeButton = UIButton(type: .system)
    private let assignButton = UIButton(type: .system)
    private let parentButton = UIButton(type: .system)

    /// Seven buttons share this bar, so each is a touch narrower than the shared
    /// 50pt default. The extra slack becomes wider gaps (≈9pt) between buttons —
    /// so adjacent active (blue) fills read as distinct rather than running
    /// together — while `.equalSpacing` keeps the end buttons pinned at the 4pt
    /// concentric inset, so they still fill the pill's rounded corners exactly.
    private static let iconButtonWidth: CGFloat = 44

    convenience init(delegate: InlineEditToolbarDelegate) {
        self.init()
        self.delegate = delegate
        setupContent()
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

        layoutButtons()
    }

    private func layoutButtons() {
        // Date / time / repeat / early reminder — opens a sub-editor.
        configureCircularButton(dateButton, symbol: "calendar.badge.clock", id: "inline.toolbar.date", width: Self.iconButtonWidth)
        dateButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.inlineToolbarDidTapDate()
        }, for: .touchUpInside)
        stackView.addArrangedSubview(dateButton)

        // Flag — instant toggle.
        configureCircularButton(flagButton, symbol: "flag", id: "inline.toolbar.flag", width: Self.iconButtonWidth)
        flagButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.inlineToolbarToggleFlag()
            self?.refresh()
        }, for: .touchUpInside)
        stackView.addArrangedSubview(flagButton)

        // Priority — native menu.
        configureCircularButton(priorityButton, symbol: "exclamationmark.circle", id: "inline.toolbar.priority", width: Self.iconButtonWidth)
        priorityButton.showsMenuAsPrimaryAction = true
        priorityButton.menu = makePriorityMenu()
        stackView.addArrangedSubview(priorityButton)

        // Tags — opens the inline tag editor.
        configureCircularButton(tagButton, symbol: "number", id: "inline.toolbar.tags", width: Self.iconButtonWidth)
        tagButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.inlineToolbarDidTapTags()
        }, for: .touchUpInside)
        stackView.addArrangedSubview(tagButton)

        // Type — quick task / note / event flip. The glyph mirrors the row's
        // current leading-control grammar, so it reads as "what this is".
        configureCircularButton(typeButton, symbol: "circle", id: "inline.toolbar.type", width: Self.iconButtonWidth)
        typeButton.showsMenuAsPrimaryAction = true
        typeButton.menu = makeTypeMenu()
        stackView.addArrangedSubview(typeButton)

        // Assign — placeholder template, no model yet.
        configureCircularButton(assignButton, symbol: "person", id: "inline.toolbar.assign", width: Self.iconButtonWidth)
        assignButton.showsMenuAsPrimaryAction = true
        assignButton.menu = makeAssignPlaceholderMenu()
        stackView.addArrangedSubview(assignButton)

        // Parent picker — opens MoveToParentPicker to choose/change parent item.
        configureCircularButton(parentButton, symbol: "list.bullet.indent", id: "inline.toolbar.parent", width: Self.iconButtonWidth)
        parentButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.inlineToolbarDidTapMoveToParent()
        }, for: .touchUpInside)
        stackView.addArrangedSubview(parentButton)

        refresh()
    }

    /// Re-derive each button's appearance from the live item state. A button
    /// whose attribute is set fills with a blue circle + white glyph (date /
    /// flag / priority); the others stay plain. Called after a toggle and
    /// whenever the bar reappears.
    func refresh() {
        let hasDate = delegate?.inlineToolbarHasDate() ?? false
        setActive(dateButton, hasDate)

        let flagged = delegate?.inlineToolbarIsFlagged() ?? false
        setButtonSymbol(flagButton, flagged ? "flag.fill" : "flag")
        setActive(flagButton, flagged)

        priorityButton.menu = makePriorityMenu()
        let priority = delegate?.inlineToolbarCurrentPriority() ?? .none
        setActive(priorityButton, priority != .none)

        typeButton.isHidden = !(delegate?.inlineToolbarCanChangeType() ?? false)
        typeButton.menu = makeTypeMenu()
        let type = delegate?.inlineToolbarCurrentType() ?? .task
        setButtonSymbol(typeButton, Self.typeSymbol(type))
        setActive(typeButton, false)

        // The date button reads as an event glyph when the item is an event —
        // matching the type menu and the row's leading control — otherwise it's
        // the task due-date glyph (calendar + clock badge). The symbol swap
        // preserves the active (blue) fill applied above.
        setButtonSymbol(dateButton, type == .event ? "calendar" : "calendar.badge.clock")

        setActive(tagButton, false)
        setActive(assignButton, false)

        let hasParent = delegate?.inlineToolbarHasParent() ?? false
        setActive(parentButton, hasParent)
    }

    private func makePriorityMenu() -> UIMenu {
        let current = delegate?.inlineToolbarCurrentPriority() ?? .none
        let options: [(String, Item.Priority)] = [
            ("None", .none), ("Low", .low), ("Medium", .medium), ("High", .high)
        ]
        let actions = options.map { (title, priority) in
            UIAction(
                title: title,
                state: priority == current ? .on : .off
            ) { [weak self] _ in
                self?.delegate?.inlineToolbarSetPriority(priority)
                self?.refresh()
            }
        }
        return UIMenu(title: "Priority", children: actions)
    }

    private func makeTypeMenu() -> UIMenu {
        let current = delegate?.inlineToolbarCurrentType() ?? .task
        let options: [(String, String, Item.ItemType)] = [
            ("Task", "circle", .task),
            ("Note", "text.document", .note),
            ("Event", "calendar", .event)
        ]
        let actions = options.map { (title, symbol, type) in
            UIAction(
                title: title,
                image: UIImage(systemName: symbol),
                state: type == current ? .on : .off
            ) { [weak self] _ in
                self?.delegate?.inlineToolbarSetType(type)
                self?.refresh()
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

    private func makeAssignPlaceholderMenu() -> UIMenu {
        // PLACEHOLDER: assignment has no data model yet (Phase 4). The single
        // disabled row signals the feature is coming without doing anything.
        let coming = UIAction(title: "Assign to… (coming soon)", attributes: .disabled) { _ in }
        return UIMenu(title: "Assign", children: [coming])
    }
}
