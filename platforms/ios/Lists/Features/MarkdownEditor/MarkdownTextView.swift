import SwiftUI
import UIKit

@MainActor
enum MarkdownTypingStyle {
    static var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.2
        return [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph
        ]
    }

    static func apply(to textView: UITextView) {
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textColor = .label
        textView.typingAttributes = attributes
    }

    static func isEmptyParagraph(in source: NSString, at location: Int) -> Bool {
        guard source.length > 0 else { return true }
        let clamped = min(max(0, location), source.length)
        if clamped == source.length {
            return source.character(at: source.length - 1) == 0x0A
        }
        let paragraph = source.paragraphRange(
            for: NSRange(location: clamped, length: 0)
        )
        let raw = source.substring(with: paragraph)
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

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
    var onFormatRequested: ((MarkdownFormatPanelSession) -> Void)? = nil

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
        MarkdownTypingStyle.apply(to: textView)
        textView.accessibilityIdentifier = "markdown.editor"
        textView.inputAccessoryView = MarkdownReminderToolbar(
            coordinator: context.coordinator,
            onFormatRequested: onFormatRequested
        )

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

        for existing in (textView.gestureRecognizers ?? []) where existing !== tap {
            if existing is UITapGestureRecognizer {
                existing.require(toFail: tap)
            }
        }

        // Hidden accessibility element exposing the current
        // `selectedRange` so UI automation can assert on cursor position
        // without driving the simulator via screenshots. Format on
        // the wire: "{location}-{length}" (NSRange).
        // A11Y-1(b): this 1×1 alpha-0 label exists only as a UI automation hook for
        // cursor position. Keeping it an accessibility element put an empty stop
        // in the VoiceOver order for real users. Expose it as an element *only*
        // under UI testing; in production it's hidden from VoiceOver entirely.
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-data")
        let cursorIndicator = UILabel(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        cursorIndicator.isAccessibilityElement = isUITesting
        cursorIndicator.accessibilityElementsHidden = !isUITesting
        cursorIndicator.accessibilityIdentifier = "markdown.editor.cursor"
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
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard let storage = uiView.textStorage as? MarkdownStyler else { return }
        if uiView.text != text {
            // Apply an external binding change as the minimal changed range,
            // not a whole-document wipe.
            let diff = TextDiff.minimal(from: storage.string, to: text)
            storage.replaceCharacters(in: diff.range, with: diff.replacement)
        }
        if storage.mode != mode {
            storage.mode = mode
        }
        context.coordinator.refreshTableControls()
        (uiView.inputAccessoryView as? MarkdownReminderToolbar)?
            .updateFormatRequestedHandler(onFormatRequested)
    }

}
