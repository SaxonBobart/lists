import UIKit

/// Receives Tab / Shift+Tab requests from `MarkdownInternalTextView`.
/// The coordinator in `MarkdownTextView` adopts this to indent or
/// outdent the line under the cursor. `@MainActor` because every
/// implementation touches UIKit state (`UITextView.selectedRange`,
/// `textStorage`).
@MainActor
protocol MarkdownIndentDelegate: AnyObject {
    func markdownTextView(_ textView: UITextView, didRequestIndent outdent: Bool)
}

/// `UITextView` subclass that surfaces Tab and Shift+Tab as key
/// commands so a hardware keyboard (or the simulator's host
/// keyboard) can drive list indent / outdent. Soft-keyboard users
/// reach the same delegate methods via the toolbar buttons wired by
/// `MarkdownTextView`.
final class MarkdownInternalTextView: UITextView {
    weak var indentDelegate: MarkdownIndentDelegate?

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTab)),
            UIKeyCommand(input: "\t", modifierFlags: [.shift], action: #selector(handleShiftTab))
        ]
    }

    @objc private func handleTab() {
        indentDelegate?.markdownTextView(self, didRequestIndent: false)
    }

    @objc private func handleShiftTab() {
        indentDelegate?.markdownTextView(self, didRequestIndent: true)
    }
}
