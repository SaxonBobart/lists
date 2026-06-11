import UIKit

/// Keyboard accessory bar for the markdown editor: the same Liquid Glass pill
/// as the inline-edit bar (geometry shared via `KeyboardGlassBar`), holding a
/// horizontally-scrollable row of grouped SF Symbol buttons plus a fixed
/// dismiss button on the trailing edge. Each button calls
/// `coordinator.handleToolbarAction(_:)` which dispatches via
/// `EditorIntent.toolbar(...)` into the pure `ToolbarAction.apply` transform.
///
/// Accessibility identifiers come from `ToolbarAction.accessibilityId`
/// so L3 UI tests can locate every button without hard-coded
/// duplication.
final class MarkdownReminderToolbar: KeyboardGlassBar {
    private weak var coordinator: EditorCoordinator?
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let divider = UIView()
    private let undoButton = UIButton(type: .system)
    private let redoButton = UIButton(type: .system)
    private let dismissButton = UIButton(type: .system)

    convenience init(coordinator: EditorCoordinator) {
        self.init()
        self.coordinator = coordinator
        setupContent()
    }

    private func setupContent() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        pillContent.addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.alignment = .center
        stackView.layoutMargins = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 8)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        // Fixed trailing group — undo / redo / hide-keyboard — separated from
        // the scrolling formatting buttons by a hairline so the scroll content
        // visibly slides "under" it and these three stay tappable at all times.
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        pillContent.addSubview(divider)

        configureFixedButton(undoButton, symbol: "arrow.uturn.backward",
                             id: "markdown.undo") { [weak self] in self?.coordinator?.handleToolbarUndo() }
        configureFixedButton(redoButton, symbol: "arrow.uturn.forward",
                             id: "markdown.redo") { [weak self] in self?.coordinator?.handleToolbarRedo() }
        configureFixedButton(dismissButton, symbol: "keyboard.chevron.compact.down",
                             id: "markdown.dismissKeyboard") { [weak self] in self?.coordinator?.handleToolbarDismiss() }
        pillContent.addSubview(undoButton)
        pillContent.addSubview(redoButton)
        pillContent.addSubview(dismissButton)

        NSLayoutConstraint.activate([
            dismissButton.trailingAnchor.constraint(equalTo: pillContent.trailingAnchor, constant: -10),
            dismissButton.centerYAnchor.constraint(equalTo: pillContent.centerYAnchor),

            redoButton.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -2),
            redoButton.centerYAnchor.constraint(equalTo: pillContent.centerYAnchor),

            undoButton.trailingAnchor.constraint(equalTo: redoButton.leadingAnchor, constant: -2),
            undoButton.centerYAnchor.constraint(equalTo: pillContent.centerYAnchor),

            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 24),
            divider.centerYAnchor.constraint(equalTo: pillContent.centerYAnchor),
            divider.trailingAnchor.constraint(equalTo: undoButton.leadingAnchor, constant: -6),

            scrollView.topAnchor.constraint(equalTo: pillContent.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pillContent.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: pillContent.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: divider.leadingAnchor, constant: -4),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        layoutGroups()
    }

    private func layoutGroups() {
        // Group: Lists
        addButton(.bullet, symbol: "list.bullet")
        addButton(.numbered, symbol: "list.number")
        addButton(.task, symbol: "checklist")
        addButton(.outdent, symbol: "decrease.indent")
        addButton(.indent, symbol: "increase.indent")
        addButton(.blockquote, symbol: "text.quote")
        addDivider()

        // Group: Text formatting
        addButton(.bold, symbol: "bold")
        addButton(.italic, symbol: "italic")
        addButton(.strikethrough, symbol: "strikethrough")
        addButton(.highlight, symbol: "highlighter")
        addDivider()

        // Group: Headings (menu)
        addHeadingMenu()
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
        button.tintColor = .label
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
        button.tintColor = .label
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

    private func configureFixedButton(_ button: UIButton, symbol: String, id: String,
                                      action: @escaping () -> Void) {
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.tintColor = .label
        button.accessibilityIdentifier = id
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    }

    private func addDivider() {
        let divider = UIView()
        divider.backgroundColor = .separator
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stackView.addArrangedSubview(divider)
    }
}
