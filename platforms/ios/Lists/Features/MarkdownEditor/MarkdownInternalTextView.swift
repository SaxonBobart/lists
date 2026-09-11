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

/// Receives document-level hardware keyboard commands that mirror visible
/// Markdown toolbar actions.
@MainActor
protocol MarkdownCommandDelegate: AnyObject {
    func markdownTextViewDidRequestLink(_ textView: UITextView)
    func markdownTextViewDidRequestTable(_ textView: UITextView)
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
    weak var commandDelegate: MarkdownCommandDelegate?
    var tableControlsLayoutHandler: ((MarkdownInternalTextView) -> Void)?
    private var lastStyledContainerWidth: CGFloat = 0
    /// The live table overlay is an atomic document block. Location-driven
    /// cursor gestures (including the keyboard's space-bar trackpad) must
    /// never expose positions in its hidden pipe-table source.
    private var atomicTableCaretBoundaryLocation: Int?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        registerForPreferredContentSizeChanges()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForPreferredContentSizeChanges()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) {
            return true
        }
        return subviews.contains { subview in
            guard (subview.accessibilityIdentifier?.hasPrefix("markdown.table.") == true || subview.accessibilityIdentifier?.hasPrefix("markdown.media.overlay.") == true) else {
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
        where (subview.accessibilityIdentifier?.hasPrefix("markdown.table.") == true || subview.accessibilityIdentifier?.hasPrefix("markdown.media.overlay.") == true) {
            let tablePoint = subview.convert(point, from: self)
            guard subview.point(inside: tablePoint, with: event) else { continue }
            if let tableHit = subview.hitTest(tablePoint, with: event) {
                return tableHit
            }
        }
        return super.hitTest(point, with: event)
    }

    override var keyCommands: [UIKeyCommand]? {
        var commands = [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTab)),
            UIKeyCommand(input: "\t", modifierFlags: [.shift], action: #selector(handleShiftTab)),
            UIKeyCommand(input: "k", modifierFlags: [.command], action: #selector(handleLinkCommand)),
            UIKeyCommand(input: "t", modifierFlags: [.command, .alternate], action: #selector(handleTableCommand))
        ]
        commands[2].discoverabilityTitle = "Add Link"
        commands[3].discoverabilityTitle = "Insert Table"
        // Only single-line marker transitions need source-column tracking.
        // UIKit must own ordinary prose and wrapped visual-line movement.
        if usesContentColumnNavigation(.up) {
            commands.append(UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleUpArrow)))
        }
        if usesContentColumnNavigation(.down) {
            commands.append(UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleDownArrow)))
        }
        return commands
    }

    private func usesContentColumnNavigation(_ direction: MoveDirection) -> Bool {
        guard selectedRange.length == 0,
              let storage = textStorage as? MarkdownStyler,
              storage.mode == .live,
              !EditorCoordinator.isLiteralBlock(at: selectedRange.location, in: storage) else { return false }
        let source = storage.string as NSString
        guard selectedRange.location <= source.length else { return false }
        let current = source.lineRange(for: selectedRange)
        guard ListMarker.detect(in: MarkdownSyntax.lineContent(in: source, range: current)) != nil else { return false }
        let adjacent: NSRange
        if direction == .up, current.location > 0 {
            adjacent = source.lineRange(for: NSRange(location: current.location - 1, length: 0))
        } else if direction == .down, NSMaxRange(current) < source.length {
            adjacent = source.lineRange(for: NSRange(location: NSMaxRange(current), length: 0))
        } else {
            return false
        }
        guard !EditorCoordinator.isLiteralBlock(at: adjacent.location, in: storage) else { return false }
        layoutManager.ensureLayout(for: textContainer)
        for range in [current, adjacent] {
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var fragments = 0
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, stop in
                fragments += 1
                if fragments > 1 { stop.pointee = true }
            }
            if fragments > 1 { return false }
        }
        return true
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

    @objc private func handleLinkCommand() {
        commandDelegate?.markdownTextViewDidRequestLink(self)
    }

    @objc private func handleTableCommand() {
        commandDelegate?.markdownTextViewDidRequestTable(self)
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

    private func registerForPreferredContentSizeChanges() {
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (self: Self, _: UITraitCollection) in
            MarkdownTypingStyle.apply(to: self)
            (self.textStorage as? MarkdownStyler)?
                .invalidateLayoutDependentStyling()
            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
            self.tableControlsLayoutHandler?(self)
        }
    }

    override func closestPosition(to point: CGPoint) -> UITextPosition? {
        guard let proposed = super.closestPosition(to: point) else { return nil }
        return atomicRenderedPosition(for: atomicTablePosition(for: proposed, closestTo: point), closestTo: point)
    }

    override func closestPosition(
        to point: CGPoint,
        within range: UITextRange
    ) -> UITextPosition? {
        guard let proposed = super.closestPosition(to: point, within: range) else {
            return nil
        }
        return atomicRenderedPosition(for: atomicTablePosition(for: proposed, closestTo: point), closestTo: point)
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        let location = offset(from: beginningOfDocument, to: position)
        guard location >= 0,
              let storage = textStorage as? MarkdownStyler,
              storage.mode == .live else {
            return rect
        }
        let bodyHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
        if rect.height < bodyHeight {
            rect.origin.y -= (bodyHeight - rect.height) / 2
            rect.size.height = bodyHeight
        }
        rect.size.width = max(2, rect.width)
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

    private func atomicRenderedPosition(for proposed: UITextPosition, closestTo point: CGPoint) -> UITextPosition {
        guard let storage = textStorage as? MarkdownStyler, storage.mode == .live else { return proposed }
        let location = offset(from: beginningOfDocument, to: proposed)
        let source = storage.string as NSString
        let ranges = MarkdownRenderedSource.spans(in: storage.string).filter {
            $0.kind != "inline" && storage.renderedImage(at: $0.range.location) != nil
        }.map(\.range) + MarkdownMediaReference.references(in: storage.string).filter {
            storage.mediaHeight(at: $0.range.location) != nil
        }.map(\.range)
        for range in ranges {
            let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                .offsetBy(dx: textContainerInset.left, dy: textContainerInset.top)
            guard NSLocationInRange(location, range) || (point.y >= rect.minY && point.y <= rect.maxY) else { continue }
            let after = NSMaxRange(source.lineRange(for: range))
            let before = range.location > 0 ? range.location - 1 : 0
            let boundary = point.y < rect.midY && range.location > 0 ? before : min(source.length, after)
            return position(from: beginningOfDocument, offset: boundary) ?? proposed
        }
        return proposed
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
