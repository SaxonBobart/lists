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
            if snapped != original {
                textView.selectedRange = NSRange(location: snapped, length: 0)
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
    // task-checkbox glyph. The literal `[ ]` chars are collapsed to a
    // zero-width font and overlaid with an SF Symbol image, so the
    // checkbox occupies a visible region the typesetter doesn't know
    // about. We use a geometric hit instead of character-index hit:
    // any tap on a task line whose x falls before the content column
    // (`headIndent` from the paragraph style) is a checkbox tap. Taps
    // on the content text fall through to UITextView's default cursor
    // placement, with `CursorSnapping` keeping the caret out of the
    // marker zone.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard let textView = textViewRef,
              let storage = textView.textStorage as? MarkdownStyler else { return false }
        let location = touch.location(in: textView)
        let layout = textView.layoutManager
        let container = textView.textContainer
        let ns = storage.string as NSString
        guard ns.length > 0 else { return false }
        let glyphIndex = layout.glyphIndex(for: location, in: container)
        let charIndex = layout.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < ns.length else { return false }
        let lineRange = ns.lineRange(for: NSRange(location: charIndex, length: 0))
        let raw = ns.substring(with: lineRange)
        let lineContent = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
        guard let marker = ListMarker.detect(in: lineContent),
              case .task = marker.kind else { return false }
        let paraStyle = storage.attribute(.paragraphStyle,
                                          at: lineRange.location,
                                          effectiveRange: nil) as? NSParagraphStyle
        let contentColumn = paraStyle?.headIndent ?? 0
        let lfPadding = container.lineFragmentPadding
        let insetLeft = textView.textContainerInset.left
        let contentStartX = insetLeft + lfPadding + contentColumn
        let firstLineIndent = paraStyle?.firstLineHeadIndent ?? 0
        let markerStartX = insetLeft + lfPadding + firstLineIndent - 8  // small slop for fat fingers
        return location.x >= markerStartX && location.x < contentStartX
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
}
