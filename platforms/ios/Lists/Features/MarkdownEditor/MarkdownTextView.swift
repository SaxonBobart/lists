import SwiftUI
import UIKit

/// `UIViewRepresentable` glue for the markdown editor. Wires
/// `MarkdownStyler` (NSTextStorage that owns live formatting) to
/// `MarkdownLayoutManager` + `MarkdownLayoutDelegate` (glyph
/// hide/substitution + custom background drawing) inside a
/// `MarkdownInternalTextView` (UITextView subclass that surfaces
/// hardware Tab / Shift-Tab as `UIKeyCommand`).
///
/// This file is **glue only**. Smart Return, smart Backspace, Tab
/// indent, cursor-zone snapping, paste handling, and toolbar actions
/// live in their own focused modules under `Features/MarkdownEditor/`
/// and are dispatched from `EditorCoordinator`. Each behaviour is a
/// pure `(text, range) -> (text, range)` transform — see the modules
/// for the actual logic.
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    var mode: MarkdownEditorMode = .live

    func makeCoordinator() -> EditorCoordinator { EditorCoordinator(text: $text) }

    func makeUIView(context: Context) -> UITextView {
        let storage = MarkdownStyler()
        let layout = MarkdownLayoutManager()
        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        context.coordinator.layoutDelegate.styler = storage
        layout.delegate = context.coordinator.layoutDelegate
        storage.glyphInvalidatable = layout

        let textView = MarkdownInternalTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.indentDelegate = context.coordinator
        textView.markdownPasteDelegate = context.coordinator
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        // Markdown source must be preserved verbatim — smart-dashes /
        // smart-quotes / autocorrect would mutate `--`, `"`, `...`, etc.
        // on both typing and paste, breaking the on-disk format.
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no
        textView.adjustsFontForContentSizeCategory = true
        textView.accessibilityIdentifier = "markdown.editor"
        textView.inputAccessoryView = MarkdownReminderToolbar(coordinator: context.coordinator)

        // Tap-to-toggle for task checkboxes. The coordinator's
        // gesture-delegate filter narrows this to taps on a `[…]`
        // bracket; other taps fall through to UITextView's default
        // cursor placement.
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(EditorCoordinator.handleCheckboxTap(_:))
        )
        tap.delegate = context.coordinator
        textView.addGestureRecognizer(tap)

        // Hidden accessibility element exposing the current
        // `selectedRange` so XCUITest can assert on cursor position
        // without driving the simulator via screenshots. Format on
        // the wire: "{location}-{length}" (NSRange).
        let cursorIndicator = UILabel(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        cursorIndicator.isAccessibilityElement = true
        cursorIndicator.accessibilityIdentifier = "markdown.editor.cursor"
        cursorIndicator.alpha = 0
        cursorIndicator.accessibilityValue = "0-0"
        textView.addSubview(cursorIndicator)
        context.coordinator.cursorIndicator = cursorIndicator
        context.coordinator.textViewRef = textView

        if !text.isEmpty {
            storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        }
        storage.mode = mode
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard let storage = uiView.textStorage as? MarkdownStyler else { return }
        if uiView.text != text {
            let full = NSRange(location: 0, length: storage.length)
            storage.replaceCharacters(in: full, with: text)
        }
        if storage.mode != mode {
            storage.mode = mode
        }
    }

}
