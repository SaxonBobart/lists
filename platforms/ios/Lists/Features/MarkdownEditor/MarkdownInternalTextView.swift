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
    /// The live table overlay is an atomic document block. Location-driven
    /// cursor gestures (including the keyboard's space-bar trackpad) must
    /// never expose positions in its hidden pipe-table source.
    private var atomicTableCaretBoundaryLocation: Int?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) {
            return true
        }
        return subviews.contains { subview in
            guard subview.accessibilityIdentifier?.hasPrefix("markdown.table.") == true else {
                return false
            }
            return subview.point(inside: subview.convert(point, from: self), with: event)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // UITextView resolves touches in its private text-selection hierarchy
        // before ordinary out-of-bounds subviews. Table handles intentionally
        // float beyond the text/table rect, so route table overlays first once
        // `point(inside:)` has admitted that extended region.
        for subview in subviews.reversed()
        where subview.accessibilityIdentifier?.hasPrefix("markdown.table.") == true {
            let tablePoint = subview.convert(point, from: self)
            guard subview.point(inside: tablePoint, with: event) else { continue }
            if let tableHit = subview.hitTest(tablePoint, with: event) {
                return tableHit
            }
        }
        return super.hitTest(point, with: event)
    }

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

    override func closestPosition(to point: CGPoint) -> UITextPosition? {
        guard let proposed = super.closestPosition(to: point) else { return nil }
        return atomicTablePosition(for: proposed, closestTo: point)
    }

    override func closestPosition(
        to point: CGPoint,
        within range: UITextRange
    ) -> UITextPosition? {
        guard let proposed = super.closestPosition(to: point, within: range) else {
            return nil
        }
        return atomicTablePosition(for: proposed, closestTo: point)
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        let location = offset(from: beginningOfDocument, to: position)
        guard location >= 0,
              let storage = textStorage as? MarkdownStyler,
              storage.mode == .live else {
            return rect
        }
        guard let table = MarkdownTableParser.tables(in: storage.string).first(where: {
            location == $0.fullRange.location || location == NSMaxRange($0.fullRange)
        }), let tableRect = tableBlockRect(for: table) else { return rect }
        // A normalized table followed by content owns a genuine empty
        // paragraph. Its sole insertion position is numerically identical to
        // the table's end, so do not replace that paragraph's normal caret
        // with the atomic table boundary caret.
        if location == NSMaxRange(table.fullRange) {
            let ns = storage.string as NSString
            if location < ns.length,
               ns.character(at: location) == 0x0A,
               atomicTableCaretBoundaryLocation != location {
                return rect
            }
        }
        rect.origin.x = location == table.fullRange.location
            ? tableRect.minX
            : tableRect.maxX - max(2, rect.width)
        rect.origin.y = tableRect.minY
        rect.size.height = tableRect.height
        return rect
    }

    private func atomicTablePosition(
        for proposed: UITextPosition,
        closestTo point: CGPoint
    ) -> UITextPosition {
        let location = offset(from: beginningOfDocument, to: proposed)
        guard location >= 0,
              let storage = textStorage as? MarkdownStyler,
              storage.mode == .live,
              let table = MarkdownTableParser.table(
                strictlyContaining: location,
                in: storage.string
              ),
              let tableRect = tableBlockRect(for: table) else {
            atomicTableCaretBoundaryLocation = nil
            return proposed
        }

        let boundary: Int
        if point.y < tableRect.minY {
            boundary = table.fullRange.location
        } else if point.y > tableRect.maxY {
            boundary = NSMaxRange(table.fullRange)
        } else {
            boundary = point.x < tableRect.midX
                ? table.fullRange.location
                : NSMaxRange(table.fullRange)
        }
        atomicTableCaretBoundaryLocation = boundary
        return position(from: beginningOfDocument, offset: boundary) ?? proposed
    }

    private func tableBlockRect(for table: MarkdownTable) -> CGRect? {
        layoutManager.ensureLayout(for: textContainer)
        let glyphs = layoutManager.glyphRange(forCharacterRange: table.header.lineRange,
                                              actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var headerRect: CGRect?
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, _, stop in
            headerRect = lineRect.offsetBy(dx: self.textContainerInset.left,
                                           dy: self.textContainerInset.top)
            stop.pointee = true
        }
        guard let headerRect else { return nil }
        let font = textStorage.attribute(.font,
                                         at: table.header.lineRange.location,
                                         effectiveRange: nil) as? UIFont
            ?? UIFont.preferredFont(forTextStyle: .body)
        let editorWidth = max(
            1,
            (textContainer.size.width - 2 * textContainer.lineFragmentPadding)
                / CGFloat(max(1, table.columnCount))
                - 2 * MarkdownTableVisualMetrics.horizontalCellPadding
        )
        let height = MarkdownTableVisualMetrics.blockHeight(
            for: table,
            font: font,
            editorWidth: editorWidth
        )
        let pad = textContainer.lineFragmentPadding
        return CGRect(
            x: textContainerInset.left + pad,
            y: headerRect.maxY - height,
            width: max(0, textContainer.size.width - 2 * pad),
            height: height
        )
    }
}
