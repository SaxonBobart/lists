import SwiftUI
import UIKit

/// Receives `UITextViewDelegate` callbacks and dispatches them to
/// behaviour modules (`ListContinuation`, `IndentHandler`,
/// `BackspaceHandler`, `CursorSnapping`, `CheckboxToggler`,
/// `PasteHandler`, `ToolbarAction`).
///
/// The coordinator itself owns **no business logic** — every actual
/// edit goes through a pure `apply(to: source, selection:)` transform
/// whose tests live alongside the module. The coordinator's job is
/// only:
///   1. Translate a delegate callback into an `EditorIntent`.
///   2. Call `intent.apply(...)`.
///   3. Apply the returned `(text, selection)` back to the text view.
///   4. Sync the binding.
///
/// Modules land progressively under TDD. The coordinator delegates
/// to UIKit's default behaviour when no smart override applies.
final class EditorCoordinator: NSObject,
                               UITextViewDelegate,
                               MarkdownIndentDelegate,
                               MarkdownPasteDelegate,
                               UIGestureRecognizerDelegate {
    private let textBinding: Binding<String>
    let layoutDelegate = MarkdownLayoutDelegate()
    weak var cursorIndicator: UILabel?
    weak var textViewRef: UITextView?
    private var lastSelectionLocation: Int = 0

    init(text: Binding<String>) {
        self.textBinding = text
        super.init()
    }

    // MARK: shouldChangeTextIn — Return / Backspace / paste interception

    func textView(_ textView: UITextView,
                  shouldChangeTextIn range: NSRange,
                  replacementText text: String) -> Bool {
        guard let storage = textView.textStorage as? MarkdownStyler else { return true }

        // Smart Return: plain `\n` at caret on a list-marker line.
        if text == "\n", range.length == 0 {
            let ns = storage.string as NSString
            let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
            let raw = ns.substring(with: lineRange)
            let lineContent = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
            if ListMarker.detect(in: lineContent) != nil {
                let result = EditorIntent.enter.apply(to: storage.string, selection: range)
                applyResult(result, to: textView, storage: storage)
                return false
            }
        }

        // Smart Backspace: single-char deletion immediately before the
        // caret, current line is a list item, caret at content start.
        if text.isEmpty, range.length == 1,
           range.location + 1 == textView.selectedRange.location {
            let caretBefore = textView.selectedRange.location
            let ns = storage.string as NSString
            let lineRange = ns.lineRange(for: NSRange(location: caretBefore, length: 0))
            let raw = ns.substring(with: lineRange)
            let lineContent = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
            if let marker = ListMarker.detect(in: lineContent),
               caretBefore == lineRange.location + marker.contentStart {
                let selection = NSRange(location: caretBefore, length: 0)
                let result = EditorIntent.backspace.apply(to: storage.string,
                                                          selection: selection)
                applyResult(result, to: textView, storage: storage)
                return false
            }
        }

        return true
    }

    // MARK: Binding sync

    func textViewDidChange(_ textView: UITextView) {
        textBinding.wrappedValue = textView.text
        updateCursorIndicator(textView.selectedRange)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        // Snap the caret out of phantom marker zones in the direction
        // of motion. UIKit-driven left/right/up/down + taps go through
        // here. Selection ranges (length > 0) are left alone — only
        // bare carets get snapped.
        if textView.selectedRange.length == 0,
           let storage = textView.textStorage as? MarkdownStyler {
            let original = textView.selectedRange.location
            let movingForward = original >= lastSelectionLocation
            let snapped = CursorSnapping.snapped(original,
                                                 in: storage.string,
                                                 movingForward: movingForward)
            if snapped != original {
                textView.selectedRange = NSRange(location: snapped, length: 0)
            }
        }
        lastSelectionLocation = textView.selectedRange.location
        updateCursorIndicator(textView.selectedRange)
        if let storage = textView.textStorage as? MarkdownStyler {
            storage.cursorRange = textView.selectedRange
        }
    }

    // MARK: Checkbox tap gesture

    @objc func handleCheckboxTap(_ recognizer: UITapGestureRecognizer) {
        guard let textView = recognizer.view as? UITextView,
              let storage = textView.textStorage as? MarkdownStyler else { return }
        let location = recognizer.location(in: textView)
        let layout = textView.layoutManager
        let glyphIndex = layout.glyphIndex(for: location, in: textView.textContainer)
        let charIndex = layout.characterIndexForGlyph(at: glyphIndex)
        let intent = EditorIntent.tapCheckbox(at: charIndex)
        let result = intent.apply(to: storage.string, selection: textView.selectedRange)
        if result.source != storage.string {
            applyResult(result, to: textView, storage: storage)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // Filter: the tap recognizer should ONLY consume taps that land on a
    // task-checkbox bracket. Other taps fall through to UITextView's
    // default cursor placement.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard let textView = textViewRef,
              let storage = textView.textStorage as? MarkdownStyler else { return false }
        let location = touch.location(in: textView)
        let layout = textView.layoutManager
        let glyphIndex = layout.glyphIndex(for: location, in: textView.textContainer)
        let charIndex = layout.characterIndexForGlyph(at: glyphIndex)
        let ns = storage.string as NSString
        guard charIndex < ns.length else { return false }
        let lineRange = ns.lineRange(for: NSRange(location: charIndex, length: 0))
        let raw = ns.substring(with: lineRange)
        let lineContent = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
        guard let marker = ListMarker.detect(in: lineContent),
              case .task = marker.kind else { return false }
        let lineOffset = charIndex - lineRange.location
        let bracketOpen = marker.indent + 2
        let bracketClose = marker.indent + 4
        return lineOffset >= bracketOpen && lineOffset <= bracketClose
    }

    // MARK: Hardware Tab / Shift-Tab (via MarkdownIndentDelegate)

    func markdownTextView(_ textView: UITextView, didRequestIndent outdent: Bool) {
        handleToolbarAction(outdent ? .outdent : .indent)
    }

    // MARK: Paste interception (via MarkdownPasteDelegate)

    func markdownTextViewDidRequestPaste(_ textView: UITextView) -> Bool {
        guard let storage = textView.textStorage as? MarkdownStyler else { return false }
        let pasteboard = UIPasteboard.general

        // URL: wrap selection as `[text](url)` (or `<url>` autolink if
        // no selection). Checked before plain-string fallback so a
        // pasted Safari URL becomes a link, not just its display text.
        if let url = pasteboard.url {
            let urlString = url.absoluteString
            let selection = textView.selectedRange
            let payload: String
            if selection.length > 0 {
                let inner = (storage.string as NSString).substring(with: selection)
                payload = "[\(inner)](\(urlString))"
            } else {
                payload = "<\(urlString)>"
            }
            let result = EditorIntent.paste(payload)
                .apply(to: storage.string, selection: selection)
            applyResult(result, to: textView, storage: storage)
            return true
        }

        // Plain string (the common path)
        if let string = pasteboard.string {
            let result = EditorIntent.paste(string)
                .apply(to: storage.string, selection: textView.selectedRange)
            applyResult(result, to: textView, storage: storage)
            return true
        }

        // Image pasteboard — defer to v2 once the Attachments/<uuid>
        // pipeline lands.
        return false
    }

    // MARK: Accessory toolbar actions

    /// Dispatch a single toolbar action through the `EditorIntent.toolbar`
    /// path. The accessory bar (`MarkdownReminderToolbar`) calls this
    /// for every button tap.
    func handleToolbarAction(_ action: ToolbarAction) {
        guard let textView = textViewRef,
              let storage = textView.textStorage as? MarkdownStyler else { return }
        let intent: EditorIntent = .toolbar(action)
        let result = intent.apply(to: storage.string, selection: textView.selectedRange)
        applyResult(result, to: textView, storage: storage)
    }

    /// Legacy hooks retained for the bare indent / outdent / dismiss
    /// surface used by the prior minimal accessory toolbar and (still)
    /// by hardware key commands.
    func handleToolbarIndent() { handleToolbarAction(.indent) }
    func handleToolbarOutdent() { handleToolbarAction(.outdent) }
    func handleToolbarDismiss() { textViewRef?.resignFirstResponder() }

    // MARK: Apply a (source, selection) result back to the text view

    private func applyResult(_ result: (source: String, selection: NSRange),
                             to textView: UITextView,
                             storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        storage.replaceCharacters(in: full, with: result.source)
        textView.selectedRange = result.selection
        textBinding.wrappedValue = result.source
        updateCursorIndicator(result.selection)
    }

    private func updateCursorIndicator(_ range: NSRange) {
        cursorIndicator?.accessibilityValue = "\(range.location)-\(range.length)"
    }
}
