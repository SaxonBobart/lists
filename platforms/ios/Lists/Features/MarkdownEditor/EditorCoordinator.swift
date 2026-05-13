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
///   2. Call the right module's `apply` function.
///   3. Apply the returned `(text, selection)` back to the text view.
///   4. Sync the binding.
///
/// Modules and intents land progressively under TDD. Until each
/// module exists, the coordinator falls through to UITextView's
/// default behaviour (which is what made the previous 920-LOC
/// version so hard to maintain — every interception had to be
/// reasoned about against every other interception).
final class EditorCoordinator: NSObject, UITextViewDelegate, MarkdownIndentDelegate {
    private let textBinding: Binding<String>
    let layoutDelegate = MarkdownLayoutDelegate()
    weak var cursorIndicator: UILabel?
    weak var textViewRef: UITextView?

    init(text: Binding<String>) {
        self.textBinding = text
        super.init()
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
        // Wires up to `IndentHandler` once that module lands in P3.
        _ = textView
        _ = outdent
    }

    // MARK: Accessory toolbar actions

    func handleToolbarIndent() {
        // Wires up to `IndentHandler` in P3.
    }

    func handleToolbarOutdent() {
        // Wires up to `IndentHandler` in P3.
    }

    func handleToolbarDismiss() {
        textViewRef?.resignFirstResponder()
    }

    // MARK: Cursor indicator (accessibility surface for XCTest)

    private func updateCursorIndicator(_ range: NSRange) {
        cursorIndicator?.accessibilityValue = "\(range.location)-\(range.length)"
    }
}
