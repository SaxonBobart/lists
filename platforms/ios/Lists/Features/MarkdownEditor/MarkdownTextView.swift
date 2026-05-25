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
        textView.arrowDelegate = context.coordinator
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
        // gesture-delegate filter narrows this to taps on the
        // checkbox area of a task line; other taps fall through to
        // UITextView's default cursor placement.
        //
        // Two requirements that aren't the default:
        //   1. `allowedTouchTypes` must explicitly include
        //      `.indirectPointer` so mouse clicks on the macOS
        //      Simulator (and trackpad clicks on iPad) reach the
        //      recognizer — otherwise UITextView's internal
        //      cursor-placement recognizer wins the race silently
        //      on indirect touches.
        //   2. UITextView's own UITapGestureRecognizers must
        //      `require(toFail:)` ours so our toggle recognizer
        //      gets first crack at any tap. Without this, the
        //      caret placement fires before our recognizer settles
        //      and the cursor visibly jumps under the checkbox.
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(EditorCoordinator.handleCheckboxTap(_:))
        )
        tap.delegate = context.coordinator
        tap.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.indirect.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        ]
        tap.cancelsTouchesInView = true
        textView.addGestureRecognizer(tap)
        for existing in (textView.gestureRecognizers ?? []) where existing !== tap {
            if existing is UITapGestureRecognizer {
                existing.require(toFail: tap)
            }
        }

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
            // ED-1: apply an external binding change as the minimal changed
            // range, not a whole-document wipe.
            let diff = TextDiff.minimal(from: storage.string, to: text)
            storage.replaceCharacters(in: diff.range, with: diff.replacement)
        }
        if storage.mode != mode {
            storage.mode = mode
        }
    }

}
