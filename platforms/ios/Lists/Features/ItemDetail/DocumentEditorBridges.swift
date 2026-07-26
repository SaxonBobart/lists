import SwiftUI
import UIKit

// MARK: - Title field

/// The document title: a plain `UITextView` styled like the previous SwiftUI
/// TextField (title2 semibold, wraps, self-sizing) so it can carry the quick
/// details bar as its keyboard accessory. Return hops into the body editor.
struct DocumentTitleField: UIViewRepresentable {
    @Binding var text: String
    var textColor: UIColor
    /// Render the title in SF Mono when the body is in Raw Markdown mode.
    var monospace: Bool = false
    var placeholder: String
    var quickState: DocumentQuickState
    var onToggleFlag: () -> Void
    var onSetPriority: (Item.Priority) -> Void
    var onSetType: (Item.ItemType) -> Void
    var onOpenDetails: () -> Void
    var onAddTags: () -> Void
    var onBeginEditing: () -> Void = {}
    let bridge: DocumentFocusBridge

    private func titleFont() -> UIFont {
        let base = monospace
            ? UIFont.monospacedSystemFont(ofSize: 22, weight: .semibold)
            : UIFont.systemFont(ofSize: 22, weight: .semibold)
        return UIFontMetrics(forTextStyle: .title2).scaledFont(for: base)
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, bridge: bridge) }

    func makeUIView(context: Context) -> PlaceholderTextView {
        let tv = PlaceholderTextView()
        tv.configureAsInlineField(font: titleFont(), textColor: textColor, placeholder: placeholder)
        tv.text = text
        tv.delegate = context.coordinator
        tv.inputAccessoryView = context.coordinator.quickBar
        tv.returnKeyType = .next
        tv.tintColor = UIColor(ListsTokens.accent)
        tv.adjustsFontForContentSizeCategory = true
        tv.accessibilityIdentifier = "document.title"
        bridge.titleView = tv
        return tv
    }

    func updateUIView(_ uiView: PlaceholderTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.textColor = textColor
        uiView.setPlaceholder(placeholder)
        let wantedFont = titleFont()
        if uiView.font != wantedFont {
            uiView.font = wantedFont
        }
        let bar = context.coordinator.quickBar
        bar.onToggleFlag = onToggleFlag
        bar.onSetPriority = onSetPriority
        bar.onSetType = onSetType
        bar.onOpenDetails = onOpenDetails
        bar.onAddTags = onAddTags
        context.coordinator.onBeginEditing = onBeginEditing
        bar.habitsPluginEnabled = CorePluginPreferences.isEnabled(.habits)
        bar.update(quickState)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PlaceholderTextView, context: Context) -> CGSize? {
        // Width-stable measurement — see InlineTextField for the "phantom
        // extra line" this prevents.
        let proposed = proposal.width ?? 0
        let width: CGFloat
        if proposed > 1 {
            width = proposed
            uiView.lastMeasuredWidth = proposed
        } else if uiView.lastMeasuredWidth > 1 {
            width = uiView.lastMeasuredWidth
        } else {
            return nil
        }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>
        private let bridge: DocumentFocusBridge
        let quickBar = DocumentQuickDetailsBar.make()
        var onBeginEditing: () -> Void = {}

        init(text: Binding<String>, bridge: DocumentFocusBridge) {
            self.text = text
            self.bridge = bridge
        }

        func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
            onBeginEditing()
            return true
        }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText replacement: String) -> Bool {
            // Return in the title hops into the body instead of a newline.
            if replacement == "\n" {
                bridge.focusBody()
                return false
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            (textView as? PlaceholderTextView)?.refreshPlaceholder()
            text.wrappedValue = textView.text
        }
    }
}

// MARK: - Inline document body editor

/// The markdown editor embedded in the document page: the same styler /
/// layout-manager / coordinator stack as `MarkdownTextView`, but
/// **non-scrolling and self-sizing** so the page is one continuous scroll.
/// The editor reports its fitted height through `sizeThatFits`, and the
/// coordinator's `onEditorInteraction` hook keeps the caret visible inside
/// the enclosing SwiftUI scroll view (a non-scrolling text view can't).
struct DocumentBodyEditor: UIViewRepresentable {
    @Binding var text: String
    var mode: MarkdownEditorMode = .live
    var bridge: DocumentFocusBridge? = nil
    var onRequestDocumentLink: ((DocumentLinkEditorSelection) -> Void)? = nil
    var onRequestAttachment: ((DocumentLinkEditorSelection, Data?) -> Void)? = nil
    var onOpenAttachment: ((String) -> Void)? = nil
    var onOpenLink: ((URL) -> Void)? = nil
    var onFormatRequested: ((MarkdownFormatPanelSession) -> Void)? = nil
    var onTableSelectionChanged: ((Bool) -> Void)? = nil
    var onCopySelectionChanged: ((Bool) -> Void)? = nil
    /// Generous floor so an empty body still reads as "tap here and type".
    var minHeight: CGFloat = 220
    /// Body text follows the same document rail as the title: notes are flush
    /// to the page rail, while tasks/events sit after their leading control.
    var leadingInset: CGFloat = 0

    func makeCoordinator() -> EditorCoordinator { EditorCoordinator(text: $text) }

    func makeUIView(context: Context) -> UITextView {
        let storage = MarkdownStyler()
        let layout = MarkdownLayoutManager()
        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        context.coordinator.layoutDelegate.styler = storage
        layout.delegate = context.coordinator.layoutDelegate
        storage.glyphInvalidatable = layout

        let textView = MarkdownInternalTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.indentDelegate = context.coordinator
        textView.markdownPasteDelegate = context.coordinator
        textView.textDropDelegate = context.coordinator
        textView.arrowDelegate = context.coordinator
        textView.commandDelegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.alwaysBounceVertical = false
        textView.textContainerInset = UIEdgeInsets(top: 10, left: leadingInset, bottom: 24, right: 0)
        // Markdown source must be preserved verbatim — see MarkdownTextView.
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no
        textView.adjustsFontForContentSizeCategory = true
        MarkdownTypingStyle.apply(to: textView)
        textView.linkTextAttributes = [
            .foregroundColor: UIColor(ListsTokens.accent),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: UIColor(ListsTokens.accent)
        ]
        textView.accessibilityIdentifier = "document.body"
        // No hide-keyboard button here — the nav-bar tick already dismisses it.
        context.coordinator.onRequestDocumentLink = onRequestDocumentLink
        context.coordinator.onRequestAttachment = onRequestAttachment
        context.coordinator.onOpenAttachment = onOpenAttachment
        context.coordinator.onOpenLink = onOpenLink
        context.coordinator.onTableBandSelectionChanged = onTableSelectionChanged
        context.coordinator.onCopySelectionChanged = onCopySelectionChanged
        textView.inputAccessoryView = MarkdownReminderToolbar(
            coordinator: context.coordinator,
            showsDismiss: false,
            onDocumentLink: { context.coordinator.requestDocumentLink() },
            onAttachment: { context.coordinator.requestAttachment() },
            onFormatRequested: onFormatRequested
        )
        bridge?.bodyView = textView
        bridge?.endTableSelection = { [weak coordinator = context.coordinator] in
            coordinator?.deactivateTableSelections()
        }
        bridge?.focusTableCell = { [weak coordinator = context.coordinator]
            tableLocation, address, range in
            coordinator?.focusTableCell(
                tableLocation: tableLocation,
                address: address,
                range: range
            )
        }
        bridge?.copySelection = { [weak coordinator = context.coordinator] in
            coordinator?.currentCopySelection()
        }

        // Tap-to-toggle for task checkboxes — same wiring as MarkdownTextView
        // (see there for why allowedTouchTypes and require(toFail:) matter).
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(EditorCoordinator.handleCheckboxTap(_:))
        )
        tap.name = "markdown.checkboxTap"
        tap.delegate = context.coordinator
        tap.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.indirect.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        ]
        tap.cancelsTouchesInView = true
        textView.addGestureRecognizer(tap)
        context.coordinator.registerCheckboxTapRecognizer(tap)

        let attachmentTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(EditorCoordinator.handleAttachmentTap(_:))
        )
        attachmentTap.name = "markdown.attachmentTap"
        attachmentTap.delegate = context.coordinator
        attachmentTap.cancelsTouchesInView = true
        textView.addGestureRecognizer(attachmentTap)
        context.coordinator.registerAttachmentTapRecognizer(attachmentTap)

        let linkLongPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(EditorCoordinator.handleLinkLongPress(_:))
        )
        linkLongPress.name = "markdown.linkLongPress"
        linkLongPress.delegate = context.coordinator
        linkLongPress.cancelsTouchesInView = true
        textView.addGestureRecognizer(linkLongPress)
        let linkEditMenu = UIEditMenuInteraction(delegate: nil)
        textView.addInteraction(linkEditMenu)
        context.coordinator.registerLinkLongPressRecognizer(
            linkLongPress,
            editMenuInteraction: linkEditMenu
        )

        for existing in (textView.gestureRecognizers ?? [])
        where existing !== tap && existing !== attachmentTap && existing !== linkLongPress {
            if existing is UITapGestureRecognizer {
                existing.require(toFail: tap)
                existing.require(toFail: attachmentTap)
            } else if existing is UILongPressGestureRecognizer {
                existing.require(toFail: linkLongPress)
            }
        }

        // Hidden UI automation hook exposing the selectedRange (see MarkdownTextView).
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-data")
        let cursorIndicator = UILabel(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        cursorIndicator.isAccessibilityElement = isUITesting
        cursorIndicator.accessibilityElementsHidden = !isUITesting
        cursorIndicator.accessibilityIdentifier = "document.body.cursor"
        cursorIndicator.alpha = 0
        cursorIndicator.accessibilityValue = "0-0"
        textView.addSubview(cursorIndicator)
        context.coordinator.cursorIndicator = cursorIndicator
        context.coordinator.textViewRef = textView
        context.coordinator.installTableControls(in: textView)
        textView.tableControlsLayoutHandler = { [weak coordinator = context.coordinator] _ in
            coordinator?.refreshTableControls()
        }

        if !text.isEmpty {
            storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        }
        storage.mode = mode
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            coordinator?.refreshTableControls()
        }

        context.coordinator.onEditorInteraction = { [weak textView] in
            guard let textView else { return }
            Self.scheduleCaretReveal(for: textView)
        }
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard let storage = uiView.textStorage as? MarkdownStyler else { return }
        if uiView.text != text {
            let diff = TextDiff.minimal(from: storage.string, to: text)
            storage.replaceCharacters(in: diff.range, with: diff.replacement)
        }
        if storage.mode != mode {
            storage.mode = mode
        }
        if abs(uiView.textContainerInset.left - leadingInset) > 0.5 {
            uiView.textContainerInset.left = leadingInset
            uiView.textContainer.lineFragmentPadding = 0
            context.coordinator.refreshTableControls()
        }
        (uiView.inputAccessoryView as? MarkdownReminderToolbar)?
            .updateFormatRequestedHandler(onFormatRequested)
        context.coordinator.onRequestDocumentLink = onRequestDocumentLink
        context.coordinator.onRequestAttachment = onRequestAttachment
        context.coordinator.onOpenAttachment = onOpenAttachment
        context.coordinator.onOpenLink = onOpenLink
        context.coordinator.onTableBandSelectionChanged = onTableSelectionChanged
        context.coordinator.onCopySelectionChanged = onCopySelectionChanged
        bridge?.copySelection = { [weak coordinator = context.coordinator] in
            coordinator?.currentCopySelection()
        }
        context.coordinator.refreshTableControls()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        // Width-stable measurement — trust a real proposed width, remember it,
        // and decline to size before one exists (see InlineItemEditor for the
        // "phantom extra line" this prevents).
        let proposed = proposal.width ?? 0
        let width: CGFloat
        if proposed > 1 {
            width = proposed
            context.coordinator.lastMeasuredWidth = proposed
        } else if context.coordinator.lastMeasuredWidth > 1 {
            width = context.coordinator.lastMeasuredWidth
        } else {
            return nil
        }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(ceil(fitted.height), minHeight))
    }

    /// Scroll the enclosing (SwiftUI) scroll view so the caret stays visible.
    /// Deferred one runloop so the page's self-sizing pass lands first — the
    /// caret's new position only exists after the editor has grown.
    private static func scheduleCaretReveal(for textView: UITextView) {
        DispatchQueue.main.async { [weak textView] in
            guard let textView,
                  textView.isFirstResponder,
                  let scrollView = textView.enclosingDocumentScrollView,
                  let selectedEnd = textView.selectedTextRange?.end else { return }
            var caret = textView.caretRect(for: selectedEnd)
            guard caret.origin.y.isFinite, caret.height > 0 else { return }
            caret = caret.insetBy(dx: 0, dy: -40)
            scrollView.scrollRectToVisible(scrollView.convert(caret, from: textView), animated: false)
        }
    }
}

extension UIView {
    /// Nearest ancestor scroll view — the SwiftUI ScrollView's backing view.
    /// (The text view itself inherits from UIScrollView, so the walk starts
    /// at the superview.)
    var enclosingDocumentScrollView: UIScrollView? {
        var node = superview
        while let current = node {
            if let scroll = current as? UIScrollView { return scroll }
            node = current.superview
        }
        return nil
    }
}
