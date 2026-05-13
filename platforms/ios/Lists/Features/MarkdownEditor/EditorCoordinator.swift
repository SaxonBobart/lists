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
final class EditorCoordinator: NSObject, UITextViewDelegate, MarkdownIndentDelegate {
    private let textBinding: Binding<String>
    let layoutDelegate = MarkdownLayoutDelegate()
    weak var cursorIndicator: UILabel?
    weak var textViewRef: UITextView?

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
        updateCursorIndicator(textView.selectedRange)
        if let storage = textView.textStorage as? MarkdownStyler {
            storage.cursorRange = textView.selectedRange
        }
    }

    // MARK: Hardware Tab / Shift-Tab (via MarkdownIndentDelegate)

    func markdownTextView(_ textView: UITextView, didRequestIndent outdent: Bool) {
        applyIndentChange(outdent: outdent, to: textView)
    }

    // MARK: Accessory toolbar actions

    func handleToolbarIndent() {
        guard let textView = textViewRef else { return }
        applyIndentChange(outdent: false, to: textView)
    }

    func handleToolbarOutdent() {
        guard let textView = textViewRef else { return }
        applyIndentChange(outdent: true, to: textView)
    }

    func handleToolbarDismiss() { textViewRef?.resignFirstResponder() }

    private func applyIndentChange(outdent: Bool, to textView: UITextView) {
        guard let storage = textView.textStorage as? MarkdownStyler else { return }
        let intent: EditorIntent = outdent ? .shiftTab : .tab
        let result = intent.apply(to: storage.string, selection: textView.selectedRange)
        applyResult(result, to: textView, storage: storage)
    }

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
