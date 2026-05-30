import UIKit

/// Actions raised by the inline-edit keyboard accessory bar. Implemented by
/// `InlineEditController` (the editing cell's coordinator), which holds the
/// item + store and either mutates the store directly (flag, priority) or
/// presents a sub-editor (date, tags) over the editing text view's window.
@MainActor
protocol InlineEditToolbarDelegate: AnyObject {
    func inlineToolbarDidTapDate()
    func inlineToolbarHasDate() -> Bool
    func inlineToolbarToggleFlag()
    func inlineToolbarIsFlagged() -> Bool
    func inlineToolbarCurrentPriority() -> Item.Priority
    func inlineToolbarSetPriority(_ priority: Item.Priority)
    func inlineToolbarDidTapTags()
}

/// Apple Reminders-style keyboard accessory bar shown while editing an item
/// inline: a single rounded "pill" floating above the keyboard with a spread
/// row of SF Symbol buttons — date/time, flag, priority, tags, assign
/// (placeholder). Buttons whose attribute is set (date, flag, priority) render
/// as a filled blue circle with a white glyph; the rest are plain glyphs.
///
/// There is no keyboard-dismiss button here — committing the edit is done by
/// the blue ✓ that pops into the navigation bar while editing.
///
/// Distinct from `MarkdownReminderToolbar`: that one performs pure text
/// transforms on the markdown editor; this one edits item metadata and can
/// open sub-editors. Lightweight pickers (priority, assign) are native
/// `UIMenu`s; the heavier date and tag editors are presented by the delegate.
final class InlineEditToolbar: UIView {
    private weak var delegate: InlineEditToolbarDelegate?
    /// Liquid Glass pill (iOS 26). Buttons live in `pill.contentView`.
    private let pill = UIVisualEffectView(effect: UIGlassEffect())
    private let stackView = UIStackView()
    private var pillBottomConstraint: NSLayoutConstraint?
    private let dateButton = UIButton(type: .system)
    private let flagButton = UIButton(type: .system)
    private let priorityButton = UIButton(type: .system)
    private let tagButton = UIButton(type: .system)
    private let assignButton = UIButton(type: .system)

    private static let pillHeight: CGFloat = 44
    private static let buttonSize: CGFloat = 38
    private static let edgeInset: CGFloat = 16
    private static let keyboardVerticalInset: CGFloat = 8
    private static let dockedBottomInset: CGFloat = 16

    init(delegate: InlineEditToolbarDelegate) {
        self.delegate = delegate
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.pillHeight + Self.keyboardVerticalInset * 2))
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = .clear
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setup() {
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.layer.cornerRadius = Self.pillHeight / 2
        pill.layer.cornerCurve = .continuous
        pill.clipsToBounds = true
        addSubview(pill)

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        pill.contentView.addSubview(stackView)

        // Pin to the safe area so the pill clears the home indicator when the
        // bar docks at the screen edge (keyboard dismissed / hardware kbd). This
        // yields to the fixed height + top constraints: if the input system
        // doesn't re-query our grown intrinsic height in time, the bar falls
        // back to a slight clip rather than crushing the pill to fit.
        let pillBottom = pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomInset)
        pillBottom.priority = .required - 1
        pillBottomConstraint = pillBottom

        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.edgeInset),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.edgeInset),
            pill.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: Self.keyboardVerticalInset),
            pillBottom,
            pill.heightAnchor.constraint(equalToConstant: Self.pillHeight),

            stackView.leadingAnchor.constraint(equalTo: pill.contentView.leadingAnchor, constant: 14),
            stackView.trailingAnchor.constraint(equalTo: pill.contentView.trailingAnchor, constant: -14),
            stackView.centerYAnchor.constraint(equalTo: pill.contentView.centerYAnchor)
        ])

        layoutButtons()
    }

    // An input accessory view doesn't auto-inset for the home indicator, so it
    // gets clipped when docked at the bottom with no keyboard. Grow the bar's
    // intrinsic height by the bottom safe-area inset (0 while the keyboard is up,
    // since the keyboard then covers that zone) and lay the pill out against the
    // safe area, so the pill always sits fully above the indicator.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric,
               height: preferredHeight)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: preferredHeight)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        syncHeightWithSafeArea()
        invalidateIntrinsicContentSize()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncHeightWithSafeArea()
    }

    private var preferredHeight: CGFloat {
        Self.pillHeight + Self.keyboardVerticalInset + bottomInset
    }

    private var bottomInset: CGFloat {
        safeAreaInsets.bottom > 0 ? Self.dockedBottomInset : Self.keyboardVerticalInset
    }

    private func syncHeightWithSafeArea() {
        pillBottomConstraint?.constant = -bottomInset
        let height = preferredHeight
        guard frame.height != height else { return }
        frame.size.height = height
        superview?.setNeedsLayout()
    }

    private func layoutButtons() {
        // Date / time / repeat / early reminder — opens a sub-editor.
        configure(dateButton, symbol: "calendar.badge.clock", id: "inline.toolbar.date")
        dateButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.inlineToolbarDidTapDate()
        }, for: .touchUpInside)
        stackView.addArrangedSubview(dateButton)

        // Flag — instant toggle.
        configure(flagButton, symbol: "flag", id: "inline.toolbar.flag")
        flagButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.inlineToolbarToggleFlag()
            self?.refresh()
        }, for: .touchUpInside)
        stackView.addArrangedSubview(flagButton)

        // Priority — native menu.
        configure(priorityButton, symbol: "exclamationmark.circle", id: "inline.toolbar.priority")
        priorityButton.showsMenuAsPrimaryAction = true
        priorityButton.menu = makePriorityMenu()
        stackView.addArrangedSubview(priorityButton)

        // Tags — opens the inline tag editor.
        configure(tagButton, symbol: "number", id: "inline.toolbar.tags")
        tagButton.addAction(UIAction { [weak self] _ in
            self?.delegate?.inlineToolbarDidTapTags()
        }, for: .touchUpInside)
        stackView.addArrangedSubview(tagButton)

        // Assign — placeholder template, no model yet.
        configure(assignButton, symbol: "person", id: "inline.toolbar.assign")
        assignButton.showsMenuAsPrimaryAction = true
        assignButton.menu = makeAssignPlaceholderMenu()
        stackView.addArrangedSubview(assignButton)

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
        flagButton.setImage(UIImage(systemName: flagged ? "flag.fill" : "flag"), for: .normal)
        setActive(flagButton, flagged)

        priorityButton.menu = makePriorityMenu()
        let priority = delegate?.inlineToolbarCurrentPriority() ?? .none
        setActive(priorityButton, priority != .none)

        setActive(tagButton, false)
        setActive(assignButton, false)
    }

    /// Toggle a button's filled-circle "active" treatment.
    private func setActive(_ button: UIButton, _ active: Bool) {
        button.backgroundColor = active ? .systemBlue : .clear
        button.tintColor = active ? .white : .label
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

    private func makeAssignPlaceholderMenu() -> UIMenu {
        // PLACEHOLDER: assignment has no data model yet (Phase 4). The single
        // disabled row signals the feature is coming without doing anything.
        let coming = UIAction(title: "Assign to… (coming soon)", attributes: .disabled) { _ in }
        return UIMenu(title: "Assign", children: [coming])
    }

    private func configure(_ button: UIButton, symbol: String, id: String) {
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.accessibilityIdentifier = id
        button.layer.cornerRadius = Self.buttonSize / 2
        button.layer.cornerCurve = .continuous
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            button.heightAnchor.constraint(equalToConstant: Self.buttonSize)
        ])
    }
}
