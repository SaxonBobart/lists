import UIKit

/// Keyboard accessory bar for the markdown editor: a native glass strip with
/// fixed five-item paging. The source transform for every button still lives in
/// `ToolbarAction`; this view owns only ordering, icons, and snap behavior.
final class MarkdownReminderToolbar: KeyboardGlassBar, UIScrollViewDelegate {
    private enum Metrics {
        static let visibleSlots: CGFloat = 5.35
        static let snapSlots = 5
        static let snapAdvanceThreshold: CGFloat = 0.24
        static let flickVelocityThreshold: CGFloat = 0.18
        static let minimumButtonSlotWidth: CGFloat = 50
        static let symbolPointSize: CGFloat = 21
        static let formatPointSize: CGFloat = 20
    }

    private enum ToolbarItem: Equatable {
        case format
        case action(ToolbarAction, symbol: String)

        var accessibilityIdentifier: String {
            switch self {
            case .format:
                return "markdown.toolbar.heading"
            case .action(let action, _):
                return action.accessibilityId
            }
        }
    }

    private static let toolbarItems: [ToolbarItem] = [
        .format,
        .action(.task, symbol: "checkmark.square"),
        .action(.link, symbol: "link"),
        .action(.image, symbol: "photo"),
        .action(.table, symbol: "tablecells"),

        .action(.bold, symbol: "bold"),
        .action(.italic, symbol: "italic"),
        .action(.strikethrough, symbol: "strikethrough"),
        .action(.highlight, symbol: "highlighter"),

        .action(.bullet, symbol: "list.bullet"),
        .action(.numbered, symbol: "list.number"),
        .action(.blockquote, symbol: "quote.bubble"),
        .action(.outdent, symbol: "decrease.indent"),
        .action(.indent, symbol: "increase.indent"),

        .action(.code, symbol: "curlybraces"),
        .action(.codeBlock, symbol: "chevron.left.forwardslash.chevron.right"),
        .action(.horizontalRule, symbol: "minus"),
        .action(.footnote, symbol: "textformat.superscript"),
        .action(.wikilink, symbol: "link.badge.plus"),

        .action(.mathInline, symbol: "x.squareroot"),
        .action(.mathDisplay, symbol: "function"),
        .action(.mermaid, symbol: "chart.bar.doc.horizontal")
    ]

    static let toolbarAccessibilityIdentifiers: [String] =
        toolbarItems.map(\.accessibilityIdentifier)

    static func snapOffset(proposedOffset: CGFloat,
                           slotWidth: CGFloat,
                           itemCount: Int = toolbarItems.count) -> CGFloat {
        snapOffset(currentOffset: proposedOffset,
                   proposedOffset: proposedOffset,
                   velocityX: 0,
                   slotWidth: slotWidth,
                   itemCount: itemCount)
    }

    static func snapOffset(currentOffset: CGFloat,
                           proposedOffset: CGFloat,
                           velocityX: CGFloat,
                           slotWidth: CGFloat,
                           itemCount: Int = toolbarItems.count) -> CGFloat {
        guard slotWidth > 0, itemCount > 0 else { return 0 }
        let stride = slotWidth * CGFloat(Metrics.snapSlots)
        let currentPage = Int((currentOffset / stride).rounded())
        let maxPage = maxPageIndex(itemCount: itemCount)

        let proposedPagePosition = proposedOffset / stride
        let proposedDelta = proposedPagePosition - CGFloat(currentPage)
        let flickDirection: Int
        if abs(velocityX) >= Metrics.flickVelocityThreshold {
            flickDirection = velocityX > 0 ? 1 : -1
        } else {
            flickDirection = 0
        }

        let page: Int
        if flickDirection != 0 {
            page = currentPage + flickDirection
        } else if proposedDelta >= Metrics.snapAdvanceThreshold {
            page = currentPage + 1
        } else if proposedDelta <= -Metrics.snapAdvanceThreshold {
            page = currentPage - 1
        } else {
            page = currentPage
        }

        let clampedPage = min(max(page, 0), maxPage)
        return CGFloat(clampedPage) * stride
    }

    private static func maxPageIndex(itemCount: Int = toolbarItems.count) -> Int {
        max(0, Int(ceil(CGFloat(itemCount) / CGFloat(Metrics.snapSlots))) - 1)
    }

    private weak var coordinator: EditorCoordinator?
    private var onDocumentLink: (() -> Void)?
    private var onAttachment: (() -> Void)?
    private var onFormatRequested: ((MarkdownFormatPanelSession) -> Void)?
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let dismissButton = UIButton(type: .system)
    private var itemWidthConstraints: [NSLayoutConstraint] = []
    private var trailingSpacerWidthConstraint: NSLayoutConstraint?
    private var itemSlotWidth: CGFloat = Metrics.minimumButtonSlotWidth
    private var isEditingTableCell = false

    /// Whether to show the hide-keyboard button. The document page hides it (its
    /// nav-bar tick already dismisses the keyboard); the standalone editor keeps it.
    private var showsDismiss = true

    convenience init(coordinator: EditorCoordinator,
                     showsDismiss: Bool = true,
                     onDocumentLink: (() -> Void)? = nil,
                     onAttachment: (() -> Void)? = nil,
                     onFormatRequested: ((MarkdownFormatPanelSession) -> Void)? = nil) {
        self.init()
        self.coordinator = coordinator
        self.showsDismiss = showsDismiss
        self.onDocumentLink = onDocumentLink
        self.onAttachment = onAttachment
        self.onFormatRequested = onFormatRequested
        setupContent()
    }

    func updateFormatRequestedHandler(_ handler: ((MarkdownFormatPanelSession) -> Void)?) {
        onFormatRequested = handler
    }

    func setEditingTableCell(_ isEditing: Bool) {
        guard isEditingTableCell != isEditing else { return }
        isEditingTableCell = isEditing
        scrollView.setContentOffset(.zero, animated: false)
        buildToolbarItems()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        syncToolbarItemWidths()
        guard !scrollView.isDragging, !scrollView.isDecelerating else { return }
        snapToNearestPage(animated: false)
    }

    private func setupContent() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.clipsToBounds = true
        scrollView.decelerationRate = .fast
        scrollView.delegate = self
        scrollView.accessibilityIdentifier = "markdown.toolbar.strip"
        pillContent.addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.spacing = 0
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        var constraints: [NSLayoutConstraint] = [
            scrollView.topAnchor.constraint(equalTo: pillContent.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pillContent.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: pillContent.leadingAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ]

        if showsDismiss {
            configureFixedButton(dismissButton,
                                 symbol: "keyboard.chevron.compact.down",
                                 id: "markdown.dismissKeyboard") { [weak self] in
                self?.coordinator?.handleToolbarDismiss()
            }
            pillContent.addSubview(dismissButton)
            constraints += [
                dismissButton.trailingAnchor.constraint(equalTo: pillContent.trailingAnchor, constant: -10),
                dismissButton.centerYAnchor.constraint(equalTo: pillContent.centerYAnchor),
                scrollView.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -6)
            ]
        } else {
            constraints.append(scrollView.trailingAnchor.constraint(equalTo: pillContent.trailingAnchor))
        }

        NSLayoutConstraint.activate(constraints)
        buildToolbarItems()
    }

    private func buildToolbarItems() {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        itemWidthConstraints.removeAll()
        trailingSpacerWidthConstraint = nil

        for item in activeToolbarItems {
            switch item {
            case .format:
                stackView.addArrangedSubview(formatButton())
            case .action(let action, let symbol):
                stackView.addArrangedSubview(actionButton(action, symbol: symbol))
            }
        }

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let width = spacer.widthAnchor.constraint(equalToConstant: 0)
        width.isActive = true
        trailingSpacerWidthConstraint = width
        stackView.addArrangedSubview(spacer)
        syncToolbarItemWidths()
    }

    private var activeToolbarItems: [ToolbarItem] {
        guard isEditingTableCell else { return Self.toolbarItems }
        return Self.toolbarItems.filter { item in
            switch item {
            case .format:
                return true
            case .action(let action, _):
                return action.isSupportedInTableCell
            }
        }
    }

    private func formatButton() -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.plain()
        var title = AttributedString("Aa")
        title.font = .systemFont(ofSize: Metrics.formatPointSize, weight: .medium)
        config.attributedTitle = title
        config.baseForegroundColor = .label
        config.contentInsets = .zero
        button.configuration = config
        button.contentHorizontalAlignment = .center
        button.accessibilityIdentifier = "markdown.toolbar.heading"
        constrainToolbarButton(button)
        button.addAction(UIAction { [weak self] _ in
            self?.showFormatPicker()
        }, for: .touchUpInside)
        return button
    }

    private func actionButton(_ action: ToolbarAction, symbol: String) -> UIButton {
        let button = configuredToolbarButton(symbol: symbol, id: action.accessibilityId)
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if action == .link, onDocumentLink != nil {
                coordinator?.requestDocumentLink()
            } else if action == .image, onAttachment != nil {
                coordinator?.requestAttachment()
            } else {
                coordinator?.handleToolbarAction(action)
            }
        }, for: .touchUpInside)
        return button
    }

    private func configuredToolbarButton(symbol: String, id: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: Metrics.symbolPointSize,
            weight: .regular
        )
        config.baseForegroundColor = .label
        config.contentInsets = .zero
        button.configuration = config
        button.accessibilityIdentifier = id
        constrainToolbarButton(button)
        return button
    }

    private func constrainToolbarButton(_ button: UIButton) {
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let width = button.widthAnchor.constraint(equalToConstant: itemSlotWidth)
        width.isActive = true
        itemWidthConstraints.append(width)
    }

    private func syncToolbarItemWidths() {
        let availableWidth = scrollView.bounds.width
        guard availableWidth > 0 else { return }

        let width = max(Metrics.minimumButtonSlotWidth, floor(availableWidth / Metrics.visibleSlots))
        if abs(width - itemSlotWidth) > 0.5 {
            itemSlotWidth = width
            for constraint in itemWidthConstraints {
                constraint.constant = width
            }
        }

        let itemCount = activeToolbarItems.count
        let lastPageStart = CGFloat(Self.maxPageIndex(itemCount: itemCount) * Metrics.snapSlots)
        let itemsOnLastPage = max(0, CGFloat(itemCount) - lastPageStart)
        trailingSpacerWidthConstraint?.constant = max(0, availableWidth - itemsOnLastPage * width)
    }

    private func snapToNearestPage(animated: Bool) {
        let snapped = Self.snapOffset(proposedOffset: scrollView.contentOffset.x,
                                      slotWidth: itemSlotWidth,
                                      itemCount: activeToolbarItems.count)
        guard abs(snapped - scrollView.contentOffset.x) > 0.5 else { return }
        scrollView.setContentOffset(CGPoint(x: snapped, y: 0), animated: animated)
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                   withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        targetContentOffset.pointee.x = Self.snapOffset(currentOffset: scrollView.contentOffset.x,
                                                        proposedOffset: targetContentOffset.pointee.x,
                                                        velocityX: velocity.x,
                                                        slotWidth: itemSlotWidth,
                                                        itemCount: activeToolbarItems.count)
        targetContentOffset.pointee.y = 0
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            snapToNearestPage(animated: true)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        snapToNearestPage(animated: true)
    }

    private func showFormatPicker() {
        guard let coordinator,
              let textView = coordinator.activeFormattingTextView() else { return }
        guard let onFormatRequested else { return }

        let session = MarkdownFormatPanelSession(textView: textView, coordinator: coordinator)
        session.suppressKeyboard()
        onFormatRequested(session)
    }

    private func configureFixedButton(_ button: UIButton, symbol: String, id: String,
                                      action: @escaping () -> Void) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol)
        config.baseForegroundColor = .label
        config.contentInsets = .zero
        button.configuration = config
        button.accessibilityIdentifier = id
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    }
}
