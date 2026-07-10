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

/// Delegate for paste interception. Returning `true` signals the
/// delegate fully handled the paste (smart pasteboard resolution via
/// `PasteHandler` + URL / image conversions). Returning `false` falls
/// through to UIKit's default paste.
@MainActor
protocol MarkdownPasteDelegate: AnyObject {
    func markdownTextViewDidRequestPaste(_ textView: UITextView) -> Bool
}

/// Receives Up / Down arrow requests so the coordinator can drive
/// content-column tracking (`CursorSnapping.move`) instead of UIKit's
/// default geometric tracker — which can't see through zero-width
/// marker glyphs and lands the caret in the phantom marker zone of
/// the destination line.
@MainActor
protocol MarkdownArrowDelegate: AnyObject {
    func markdownTextView(_ textView: UITextView, didRequestVerticalMove direction: MoveDirection)
}

/// `UITextView` subclass that surfaces Tab and Shift+Tab as key
/// commands so a hardware keyboard (or the simulator's host
/// keyboard) can drive list indent / outdent. Soft-keyboard users
/// reach the same delegate methods via the toolbar buttons wired by
/// `MarkdownTextView`. Also routes `paste(_:)` through
/// `MarkdownPasteDelegate` so the coordinator can normalise
/// pasteboard content via `PasteHandler.normalize`.
final class MarkdownInternalTextView: UITextView {
    weak var indentDelegate: MarkdownIndentDelegate?
    weak var markdownPasteDelegate: MarkdownPasteDelegate?
    weak var arrowDelegate: MarkdownArrowDelegate?
    var tableControlsLayoutHandler: ((MarkdownInternalTextView) -> Void)?
    private var lastStyledContainerWidth: CGFloat = 0

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTab)),
            UIKeyCommand(input: "\t", modifierFlags: [.shift], action: #selector(handleShiftTab)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleUpArrow)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleDownArrow))
        ]
    }

    @objc private func handleTab() {
        indentDelegate?.markdownTextView(self, didRequestIndent: false)
    }

    @objc private func handleShiftTab() {
        indentDelegate?.markdownTextView(self, didRequestIndent: true)
    }

    @objc private func handleUpArrow() {
        arrowDelegate?.markdownTextView(self, didRequestVerticalMove: .up)
    }

    @objc private func handleDownArrow() {
        arrowDelegate?.markdownTextView(self, didRequestVerticalMove: .down)
    }

    override func paste(_ sender: Any?) {
        if markdownPasteDelegate?.markdownTextViewDidRequestPaste(self) == true {
            return
        }
        super.paste(sender)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = textContainer.size.width
        if width > 1, abs(width - lastStyledContainerWidth) > 0.5 {
            lastStyledContainerWidth = width
            (textStorage as? MarkdownStyler)?.invalidateLayoutDependentStyling()
        }
        tableControlsLayoutHandler?(self)
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        let location = offset(from: beginningOfDocument, to: position)
        guard location >= 0,
              let storage = textStorage as? MarkdownStyler,
              storage.mode == .live,
              let table = MarkdownTableParser.table(
                containing: NSRange(location: location, length: 0),
                in: storage.string
              ),
              let row = MarkdownTableParser.row(
                containing: NSRange(location: location, length: 0),
                in: table
              ),
              row.role != .divider,
              let rowRect = tableRowRect(for: row) else {
            return rect
        }

        let font = typingAttributes[.font] as? UIFont
            ?? storage.attribute(.font,
                                 at: min(max(0, location), max(0, storage.length - 1)),
                                 effectiveRange: nil) as? UIFont
            ?? UIFont.preferredFont(forTextStyle: .body)
        let rowHeight = MarkdownTableVisualMetrics.rowHeight(for: font)
        let height = MarkdownTableVisualMetrics.caretHeight(for: font, rowHeight: rowHeight)
        rect.size.height = height
        rect.origin.y = rowRect.midY - height / 2
        return rect
    }

    private func tableRowRect(for row: MarkdownTableRow) -> CGRect? {
        layoutManager.ensureLayout(for: textContainer)
        let glyphs = layoutManager.glyphRange(forCharacterRange: row.lineRange,
                                              actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var rect: CGRect?
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, _, stop in
            rect = lineRect.offsetBy(dx: self.textContainerInset.left,
                                     dy: self.textContainerInset.top)
            stop.pointee = true
        }
        guard var rect else { return nil }
        let font = textStorage.attribute(.font,
                                         at: row.lineRange.location,
                                         effectiveRange: nil) as? UIFont
            ?? UIFont.preferredFont(forTextStyle: .body)
        let rowHeight = MarkdownTableVisualMetrics.rowHeight(for: font)
        if rect.height < rowHeight {
            rect.origin.y -= (rowHeight - rect.height) / 2
            rect.size.height = rowHeight
        }
        return rect
    }
}
