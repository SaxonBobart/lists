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
                               MarkdownArrowDelegate,
                               UIGestureRecognizerDelegate {
    private let textBinding: Binding<String>
    let layoutDelegate = MarkdownLayoutDelegate()
    weak var cursorIndicator: UILabel?
    weak var textViewRef: UITextView?
    /// Document-mode hooks, set only by `DocumentBodyEditor` (the non-scrolling
    /// editor embedded in `ItemDocumentView`'s page). Fired after every text
    /// change, caret move, and programmatic edit so the host can keep the caret
    /// visible inside the *enclosing* scroll view — a non-scrolling text view
    /// can't do it itself. Nil in the full-screen editor, where the text view
    /// scrolls natively.
    var onEditorInteraction: (() -> Void)?
    var onRequestDocumentLink: ((DocumentLinkEditorSelection) -> Void)?
    weak var formatPanelSession: MarkdownFormatPanelSession?
    private var tableOverlayController: MarkdownTableOverlayController?
    private weak var checkboxTapRecognizer: UIGestureRecognizer?
    /// Last width SwiftUI proposed while self-sizing (document mode only) —
    /// reused when a layout pass proposes none, so a transient narrow width
    /// can't wrap the document and lock in a wrong height.
    var lastMeasuredWidth: CGFloat = 0
    private var lastSelectionLocation: Int = 0
    /// True while `applyResult` is pushing an edit through the text input
    /// layer. Lets that re-entrant `shouldChangeTextIn` callback pass straight
    /// through instead of re-running a smart transform on already-transformed
    /// text.
    private var isApplyingResult = false

    init(text: Binding<String>) {
        self.textBinding = text
        super.init()
    }

    func registerCheckboxTapRecognizer(_ recognizer: UIGestureRecognizer) {
        checkboxTapRecognizer = recognizer
    }

    // MARK: shouldChangeTextIn — Return / Backspace / paste interception

    func textView(_ textView: UITextView,
                  shouldChangeTextIn range: NSRange,
                  replacementText text: String) -> Bool {
        // Our own minimal edit (from applyResult) must perform normally, not
        // re-trigger a smart transform on already-transformed text.
        if isApplyingResult { return true }
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

        // Hardware Tab can arrive from Simulator / external keyboards
        // as literal replacement text instead of the UIKeyCommand path.
        // Keep it semantic: indent the current line rather than
        // inserting a tab character into the Markdown source.
        if text == "\t", range.length == 0 {
            let result = EditorIntent.toolbar(.indent)
                .apply(to: storage.string, selection: range)
            applyResult(result, to: textView, storage: storage)
            return false
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

        // Block typing into the marker zone — characters inserted between
        // the bullet/checkbox and its content would either corrupt the
        // marker (`- x[ ] todo` no longer parses as a task) or appear at
        // a visually impossible position. Redirect single-caret inserts
        // to the line's content-start instead.
        if !text.isEmpty, range.length == 0 {
            let ns = storage.string as NSString
            let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
            let raw = ns.substring(with: lineRange)
            let lineContent = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
            if let marker = ListMarker.detect(in: lineContent) {
                let contentStartGlobal = lineRange.location + marker.contentStart
                if range.location < contentStartGlobal {
                    let inserted = ns.replacingCharacters(
                        in: NSRange(location: contentStartGlobal, length: 0),
                        with: text
                    )
                    let newSelection = NSRange(
                        location: contentStartGlobal + (text as NSString).length,
                        length: 0
                    )
                    applyResult((inserted, newSelection), to: textView, storage: storage)
                    return false
                }
            }
        }

        return true
    }

    // MARK: Binding sync

    func textViewDidChange(_ textView: UITextView) {
        textBinding.wrappedValue = textView.text
        updateCursorIndicator(textView.selectedRange)
        // Force-invalidate glyphs + layout for the WHOLE document after
        // every text change. Reason: `MarkdownStyler.applyLiveStyling`
        // re-attributes every line on every edit by mutating `backing`
        // directly (bypassing the textStorage edit-notification path).
        // The framework auto-invalidates only the chars UIKit knows
        // changed (the typed char + maybe surrounding line), so sibling
        // list rows whose marker-char font we JUST switched to zero-
        // width keep stale full-width glyphs in the layout manager's
        // cache — shoving those rows one indent unit too far right.
        // Calling `invalidateGlyphs` from `processEditing` crashes Text
        // Kit ("attempted glyph generation while textStorage is
        // editing"); calling it here, after the whole edit chain
        // settles, is the documented-safe place.
        let full = NSRange(location: 0, length: textView.textStorage.length)
        textView.layoutManager.invalidateGlyphs(forCharacterRange: full,
                                                changeInLength: 0,
                                                actualCharacterRange: nil)
        textView.layoutManager.invalidateLayout(forCharacterRange: full,
                                                actualCharacterRange: nil)
        onEditorInteraction?()
        refreshFormatPanelState()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        // Snap the caret out of phantom marker zones in the direction
        // of motion. UIKit-driven left/right/up/down + taps go through
        // here. Selection ranges (length > 0) are left alone — only
        // bare carets get snapped. Tap-style jumps (across a line
        // boundary) always land on the destination line's content
        // start; arrow-style movement (within one line) uses the
        // forward/backward direction so Left arrow from content start
        // jumps to the previous line.
        if textView.selectedRange.length == 0,
           let storage = textView.textStorage as? MarkdownStyler {
            let original = textView.selectedRange.location
            let movingForward = original >= lastSelectionLocation
            let ns = storage.string as NSString
            let prevLine: NSRange = {
                guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
                let probe = min(lastSelectionLocation, max(0, ns.length - 1))
                return ns.lineRange(for: NSRange(location: probe, length: 0))
            }()
            let newLine: NSRange = {
                guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
                let probe = min(original, max(0, ns.length - 1))
                return ns.lineRange(for: NSRange(location: probe, length: 0))
            }()
            let sameLine = (prevLine.location == newLine.location)
            let snapped = CursorSnapping.snapped(original,
                                                 in: storage.string,
                                                 movingForward: movingForward,
                                                 sameLineMovement: sameLine)
            let tableSnapped = MarkdownTableParser.snappedSelection(
                NSRange(location: snapped, length: 0),
                in: storage.string
            ).location
            if tableSnapped != original {
                textView.selectedRange = NSRange(location: tableSnapped, length: 0)
            }
        }
        lastSelectionLocation = textView.selectedRange.location
        updateCursorIndicator(textView.selectedRange)
        if let storage = textView.textStorage as? MarkdownStyler {
            storage.cursorRange = textView.selectedRange
            syncTypingAttributes(for: textView.selectedRange,
                                 in: textView,
                                 storage: storage)
        }
        onEditorInteraction?()
        refreshFormatPanelState()
    }

    // MARK: Checkbox tap gesture

    /// Slop on each side of the rendered SF Symbol image when hit-
    /// testing a checkbox tap. The image itself is ~17pt wide; with
    /// 8pt slop on both sides the effective target is ~33pt — wide
    /// enough for finger taps and pixel-precise mouse clicks, narrow
    /// enough that taps in a row's CONTENT area still fall through to
    /// cursor placement (matters for nested rows where the parent's
    /// content x overlaps the nested row's checkbox x).
    private static let checkboxHitSlop: CGFloat = 8
    /// SF Symbol "square" / "checkmark.square.fill" render width at
    /// the .body text style. Hard-coded to avoid a UIFont measure
    /// every tap.
    private static let checkboxImageWidth: CGFloat = 17

    /// Resolve the character range of the line containing `touchPoint`
    /// (view coords) using a Y-only line-fragment scan. Avoids
    /// `glyphIndex(for:in:)` because the marker chars `-`, ` `, `[`,
    /// ` `, `]` are all zero-width-fonted and confuse column-aware
    /// glyph lookups. Returns nil if the touch isn't vertically on any
    /// laid-out line.
    private func taskLineRange(for touchPoint: CGPoint,
                               in textView: UITextView,
                               storage: MarkdownStyler) -> (lineRange: NSRange, marker: ListMarker)? {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return nil }
        let layout = textView.layoutManager
        let insetTop = textView.textContainerInset.top
        let containerY = touchPoint.y - insetTop
        // Force layout for the full glyph range so enumerateLineFragments
        // sees a complete picture (lazy generation otherwise skips
        // unrequested ranges).
        let totalGlyphs = layout.numberOfGlyphs
        guard totalGlyphs > 0 else { return nil }
        var hitGlyphRange: NSRange?
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: totalGlyphs)) {
            _, usedRect, _, glyphRange, stop in
            if containerY >= usedRect.minY && containerY < usedRect.maxY {
                hitGlyphRange = glyphRange
                stop.pointee = true
            }
        }
        // Touch below the last line — treat it as the last line so a
        // click in the empty area past a trailing task still toggles.
        let charIndex: Int
        if let r = hitGlyphRange {
            charIndex = layout.characterIndexForGlyph(at: r.location)
        } else if containerY >= 0 {
            charIndex = max(0, ns.length - 1)
        } else {
            return nil
        }
        let lineRange = ns.lineRange(for: NSRange(location: min(charIndex, ns.length - 1), length: 0))
        let raw = ns.substring(with: lineRange)
        let lineContent = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
        guard let marker = ListMarker.detect(in: lineContent),
              case .task = marker.kind else { return nil }
        return (lineRange, marker)
    }

    @objc func handleCheckboxTap(_ recognizer: UITapGestureRecognizer) {
        guard let textView = recognizer.view as? UITextView,
              let storage = textView.textStorage as? MarkdownStyler else { return }
        let location = recognizer.location(in: textView)
        guard let (lineRange, marker) = taskLineRange(for: location, in: textView, storage: storage) else { return }
        // State char (` ` / `x`) sits at `indent + 3` inside `- [ ] `.
        let stateCharIndex = lineRange.location + marker.indent + 3
        let intent = EditorIntent.tapCheckbox(at: stateCharIndex)
        let result = intent.apply(to: storage.string, selection: textView.selectedRange)
        if result.source != storage.string {
            applyResult(result, to: textView, storage: storage)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // Filter: the tap recognizer should ONLY consume taps that land in
    // the checkbox area of a task line. The literal `[ ]` chars are
    // zero-width-fonted and overlaid with an SF Symbol image, so the
    // visible checkbox occupies a region the typesetter doesn't know
    // about. We hit-test geometrically:
    //   1. Find the line by Y (resilient to zero-width-marker columns).
    //   2. Only task lines qualify.
    //   3. Tap-X must be in the leftmost `checkboxHitZoneWidth` of the
    //      view — wider than the rendered symbol so mouse-precise
    //      clicks in the simulator catch reliably.
    // Content taps fall through to UITextView's cursor placement with
    // `CursorSnapping` pushing the caret past the marker.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard let textView = textViewRef,
              let storage = textView.textStorage as? MarkdownStyler else { return false }
        let location = touch.location(in: textView)

        guard let (lineRange, _) = taskLineRange(for: location, in: textView, storage: storage) else { return false }
        // Hit zone is anchored to the rendered SF Symbol image
        // position (which tracks the line's firstLineHeadIndent).
        // This way nested rows get their own zone past the parent's
        // content, and content taps on top-level rows fall through
        // to cursor placement.
        let paraStyle = storage.attribute(.paragraphStyle,
                                          at: lineRange.location,
                                          effectiveRange: nil) as? NSParagraphStyle
        let firstLineIndent = paraStyle?.firstLineHeadIndent ?? 0
        let lfPadding = textView.textContainer.lineFragmentPadding
        let insetLeft = textView.textContainerInset.left
        let imageLeftX = insetLeft + lfPadding + firstLineIndent + MarkdownChecklistMetrics.symbolLeadingOffset
        let zoneLeftX = imageLeftX - Self.checkboxHitSlop
        let zoneRightX = imageLeftX + Self.checkboxImageWidth + Self.checkboxHitSlop
        return location.x >= zoneLeftX && location.x < zoneRightX
    }

    // MARK: Hardware Tab / Shift-Tab (via MarkdownIndentDelegate)

    func markdownTextView(_ textView: UITextView, didRequestIndent outdent: Bool) {
        handleToolbarAction(outdent ? .outdent : .indent)
    }

    // MARK: Hardware Up / Down (via MarkdownArrowDelegate)

    /// Content-column vertical move. UIKit's default Up/Down picks the
    /// destination position by absolute x — which fails for task / list
    /// lines whose marker chars are all collapsed to a 0.01pt font and
    /// therefore share the same x. `CursorSnapping.move` tracks the
    /// column RELATIVE to content-start instead, so "to|do" + Down
    /// lands at "an|other todo" (column 2 of content), not at the
    /// content start of the next row.
    func markdownTextView(_ textView: UITextView, didRequestVerticalMove direction: MoveDirection) {
        guard let storage = textView.textStorage as? MarkdownStyler else { return }
        let result = CursorSnapping.move(direction: direction,
                                         modifiers: [],
                                         in: storage.string,
                                         selection: textView.selectedRange)
        guard result.selection != textView.selectedRange else { return }
        textView.selectedRange = result.selection
        storage.cursorRange = result.selection
        syncTypingAttributes(for: result.selection, in: textView, storage: storage)
        refreshFormatPanelState()
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

    /// Undo / redo drive the text view's own `UndoManager`, the same one ⌘Z /
    /// the shake gesture use, so toolbar undo and system undo stay in step.
    func handleToolbarUndo() { textViewRef?.undoManager?.undo() }
    func handleToolbarRedo() { textViewRef?.undoManager?.redo() }

    func installTableControls(in textView: UITextView) {
        if let markdownTextView = textView as? MarkdownInternalTextView {
            if tableOverlayController?.isAttached(to: markdownTextView) == true {
                tableOverlayController?.refresh()
                return
            }
            tableOverlayController?.detach()
            MarkdownTableOverlayController.removeStaleOverlays(from: markdownTextView)
            tableOverlayController = MarkdownTableOverlayController(
                textView: markdownTextView,
                coordinator: self
            )
            tableOverlayController?.refresh()
        }
    }

    func applyExternalTableEdit(_ result: (source: String, selection: NSRange),
                                keepFirstResponder responder: UIResponder?) {
        guard let textView = textViewRef,
              let storage = textView.textStorage as? MarkdownStyler else { return }
        applyResult(result, to: textView, storage: storage)
        responder?.becomeFirstResponder()
        tableOverlayController?.refresh()
    }

    func selectTableCell(_ address: MarkdownTableCellAddress, in table: MarkdownTable) {
        guard let textView = textViewRef,
              let storage = textView.textStorage as? MarkdownStyler else { return }
        let row: MarkdownTableRow
        if address.row == 0 {
            row = table.header
        } else if !table.bodyRows.isEmpty {
            row = table.bodyRows[min(max(0, address.row - 1), table.bodyRows.count - 1)]
        } else {
            row = table.header
        }
        guard let cell = row.cells.first(where: { $0.column == address.column }) ?? row.cells.first else {
            return
        }
        let selection = NSRange(location: cell.contentRange.location,
                                length: cell.contentRange.length)
        textView.selectedRange = selection
        storage.cursorRange = selection
        syncTypingAttributes(for: selection, in: textView, storage: storage)
        updateCursorIndicator(selection)
        formatPanelSession?.refreshFormatState()
        onEditorInteraction?()
    }

    func requestDocumentLink() {
        guard let onRequestDocumentLink,
              let selection = currentSelectionForDocumentLink() else {
            handleToolbarAction(.link)
            return
        }
        onRequestDocumentLink(
            DocumentLinkEditorSelection(
                range: selection.selection,
                selectedText: selection.selectedText
            )
        )
    }

    func currentSelectionForDocumentLink() -> (selection: NSRange, selectedText: String)? {
        guard let textView = textViewRef,
              let storage = textView.textStorage as? MarkdownStyler else { return nil }
        let selection = textView.selectedRange
        let ns = storage.string as NSString
        guard selection.location != NSNotFound,
              NSMaxRange(selection) <= ns.length else {
            return nil
        }
        let selected = selection.length > 0 ? ns.substring(with: selection) : ""
        return (selection, selected)
    }

    // MARK: Apply a (source, selection) result back to the text view

    private func applyResult(_ result: (source: String, selection: NSRange),
                             to textView: UITextView,
                             storage: NSTextStorage) {
        // Apply the transform as the minimal changed range through the
        // UITextInput surface, so UIKit's tracking + the system UndoManager stay
        // consistent (⌘Z / shake undo a sensible chunk instead of the whole doc).
        let diff = TextDiff.minimal(from: storage.string, to: result.source)
        if let start = textView.position(from: textView.beginningOfDocument, offset: diff.range.location),
           let end = textView.position(from: start, offset: diff.range.length),
           let textRange = textView.textRange(from: start, to: end) {
            isApplyingResult = true
            textView.replace(textRange, withText: diff.replacement)
            isApplyingResult = false
        } else {
            // Fallback only if range mapping fails (should not happen).
            let full = NSRange(location: 0, length: storage.length)
            storage.replaceCharacters(in: full, with: result.source)
        }
        textView.selectedRange = result.selection
        if let storage = storage as? MarkdownStyler {
            storage.cursorRange = result.selection
            syncTypingAttributes(for: result.selection,
                                 in: textView,
                                 storage: storage)
        }
        let updatedFull = NSRange(location: 0, length: storage.length)
        textView.layoutManager.invalidateGlyphs(forCharacterRange: updatedFull,
                                                changeInLength: 0,
                                                actualCharacterRange: nil)
        textView.layoutManager.invalidateLayout(forCharacterRange: updatedFull,
                                                actualCharacterRange: nil)
        textView.setNeedsDisplay()
        textBinding.wrappedValue = result.source
        updateCursorIndicator(result.selection)
        onEditorInteraction?()
        refreshFormatPanelState()
    }

    private func syncTypingAttributes(for selection: NSRange,
                                      in textView: UITextView,
                                      storage: NSTextStorage) {
        guard selection.length == 0, storage.length > 0 else {
            resetTypingAttributes(in: textView)
            return
        }
        let ns = storage.string as NSString
        if selection.location == 0 ||
            (selection.location == storage.length &&
             ns.character(at: storage.length - 1) == 0x0A) {
            resetTypingAttributes(in: textView)
            return
        }
        let probeLocation = min(selection.location, storage.length - 1)
        let paragraph = ns.paragraphRange(for: NSRange(location: probeLocation, length: 0))
        guard paragraph.length > 0 else { return }
        let attributeLocation: Int
        if selection.location < NSMaxRange(paragraph),
           selection.location < storage.length,
           ns.character(at: selection.location) != 0x0A {
            attributeLocation = selection.location
        } else {
            attributeLocation = min(max(selection.location - 1, paragraph.location),
                                    NSMaxRange(paragraph) - 1)
        }
        textView.typingAttributes = sanitizedTypingAttributes(
            storage.attributes(at: attributeLocation, effectiveRange: nil)
        )
    }

    private func sanitizedTypingAttributes(_ attributes: [NSAttributedString.Key: Any])
        -> [NSAttributedString.Key: Any] {
        var sanitized = attributes
        // List markers use kern/SF-Symbol/layout attributes as display
        // scaffolding. If the caret sits just after a marker, UIKit can
        // inherit those onto the active insertion style and visually
        // shove the current row out of alignment.
        sanitized.removeValue(forKey: .kern)
        sanitized.removeValue(forKey: .sfSymbolCheckbox)
        sanitized.removeValue(forKey: .horizontalRule)
        sanitized.removeValue(forKey: .codeBlockBody)
        sanitized.removeValue(forKey: .inlineCodeSpan)
        sanitized.removeValue(forKey: .markdownTableRow)
        return sanitized
    }

    private func resetTypingAttributes(in textView: UITextView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.2
        textView.typingAttributes = [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph
        ]
    }

    private func updateCursorIndicator(_ range: NSRange) {
        cursorIndicator?.accessibilityValue = "\(range.location)-\(range.length)"
    }

    private func refreshFormatPanelState() {
        formatPanelSession?.refreshFormatState()
        refreshTableControls()
    }

    func refreshTableControls() {
        tableOverlayController?.refresh()
    }
}
