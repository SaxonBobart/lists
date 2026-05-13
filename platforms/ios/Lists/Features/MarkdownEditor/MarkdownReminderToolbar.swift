import UIKit

/// Apple Reminders-style keyboard accessory bar for the markdown
/// editor.
///
/// A horizontally-scrollable single row of grouped SF Symbol buttons
/// plus a right-aligned dismiss button. Each button calls
/// `coordinator.handleToolbarAction(_:)` which dispatches via
/// `EditorIntent.toolbar(...)` into the pure `ToolbarAction.apply`
/// transform.
///
/// Accessibility identifiers come from `ToolbarAction.accessibilityId`
/// so L3 UI tests can locate every button without hard-coded
/// duplication.
final class MarkdownReminderToolbar: UIView {
    private weak var coordinator: EditorCoordinator?
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let dismissContainer = UIStackView()
    private let dismissButton = UIButton(type: .system)

    init(coordinator: EditorCoordinator) {
        self.coordinator = coordinator
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        autoresizingMask = .flexibleWidth
        backgroundColor = UIColor.secondarySystemBackground
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setup() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.alignment = .center
        stackView.layoutMargins = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        // Right-side fixed dismiss group, separate from the scrolling area.
        dismissContainer.axis = .horizontal
        dismissContainer.alignment = .center
        dismissContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dismissContainer)

        configureDismissButton()
        dismissContainer.addArrangedSubview(dismissButton)

        NSLayoutConstraint.activate([
            dismissContainer.topAnchor.constraint(equalTo: topAnchor),
            dismissContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            dismissContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: dismissContainer.leadingAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        layoutGroups()
    }

    private func layoutGroups() {
        // Group: Text formatting
        addButton(.bold, symbol: "bold")
        addButton(.italic, symbol: "italic")
        addButton(.strikethrough, symbol: "strikethrough")
        addButton(.highlight, symbol: "highlighter")
        addDivider()

        // Group: Headings (menu)
        addHeadingMenu()
        addDivider()

        // Group: Lists
        addButton(.bullet, symbol: "list.bullet")
        addButton(.numbered, symbol: "list.number")
        addButton(.task, symbol: "checklist")
        addButton(.blockquote, symbol: "text.quote")
        addDivider()

        // Group: Indent
        addButton(.outdent, symbol: "decrease.indent")
        addButton(.indent, symbol: "increase.indent")
        addDivider()

        // Group: Inline
        addButton(.link, symbol: "link")
        addButton(.code, symbol: "chevron.left.forwardslash.chevron.right")
        addDivider()

        // Group: Blocks
        addButton(.codeBlock, symbol: "curlybraces")
        addButton(.horizontalRule, symbol: "minus")
        addButton(.image, symbol: "photo")
        addButton(.table, symbol: "tablecells")
        addDivider()

        // Group: Extensions (deferred constructs)
        addButton(.wikilink, symbol: "link.badge.plus")
        addButton(.footnote, symbol: "textformat.superscript")
        addButton(.mathInline, symbol: "x.squareroot")
        addButton(.mathDisplay, symbol: "function")
        addButton(.mermaid, symbol: "chart.bar.doc.horizontal")
    }

    private func addButton(_ action: ToolbarAction, symbol: String) {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.accessibilityIdentifier = action.accessibilityId
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        button.addAction(UIAction { [weak self] _ in
            self?.coordinator?.handleToolbarAction(action)
        }, for: .touchUpInside)
        stackView.addArrangedSubview(button)
    }

    private func addHeadingMenu() {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "textformat"), for: .normal)
        button.accessibilityIdentifier = "markdown.toolbar.heading"
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        button.showsMenuAsPrimaryAction = true
        let actions: [(String, String, ToolbarAction)] = [
            ("Paragraph", "text.alignleft", .paragraph),
            ("Title (H1)", "textformat.size.larger", .heading(1)),
            ("Heading (H2)", "textformat.size", .heading(2)),
            ("Subheading (H3)", "textformat.size.smaller", .heading(3)),
            ("H4", "4.square", .heading(4)),
            ("H5", "5.square", .heading(5)),
            ("H6", "6.square", .heading(6))
        ]
        button.menu = UIMenu(title: "Heading", children: actions.map { (title, symbol, action) in
            UIAction(title: title, image: UIImage(systemName: symbol)) { [weak self] _ in
                self?.coordinator?.handleToolbarAction(action)
            }
        })
        stackView.addArrangedSubview(button)
    }

    private func configureDismissButton() {
        dismissButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down"),
                               for: .normal)
        dismissButton.accessibilityIdentifier = "markdown.dismissKeyboard"
        dismissButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        dismissButton.addAction(UIAction { [weak self] _ in
            self?.coordinator?.handleToolbarDismiss()
        }, for: .touchUpInside)
    }

    private func addDivider() {
        let divider = UIView()
        divider.backgroundColor = .separator
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stackView.addArrangedSubview(divider)
    }
}
