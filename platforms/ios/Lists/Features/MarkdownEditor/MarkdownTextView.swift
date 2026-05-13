import SwiftUI
import UIKit

/// `UIViewRepresentable` wrapper around `UITextView` backed by a
/// `MarkdownStyler` (NSTextStorage subclass) and a
/// `MarkdownLayoutDelegate` (handles cursor-aware glyph hiding and
/// substitution).
///
/// Owns three behaviours not in the styler:
/// - Auto-continuation of list / numbered / task markers on Return
/// - Cursor-change → text-view redraw plumbing
/// - Binding sync (push edits out, pull external edits in)
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    var mode: MarkdownEditorMode = .live

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

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
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        textView.autocorrectionType = .yes
        textView.smartDashesType = .yes
        textView.smartQuotesType = .yes
        textView.adjustsFontForContentSizeCategory = true
        textView.accessibilityIdentifier = "markdown.editor"
        textView.inputAccessoryView = makeAccessoryToolbar(for: context.coordinator)

        // Tap-to-toggle for task checkboxes. Recognizer fires ONLY
        // when the tap lands on a `[…]` bracket (filtered in the
        // coordinator's gesture delegate), so other taps fall through
        // to UITextView's default cursor placement.
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCheckboxTap(_:))
        )
        tap.delegate = context.coordinator
        textView.addGestureRecognizer(tap)

        // Hidden accessibility element exposing the current
        // `selectedRange` so XCUITest can assert on cursor position
        // without driving the simulator via screenshots. Format on
        // the wire: "{location}-{length}" (NSRange). The format lives
        // on `accessibilityValue` rather than `.text` so XCUITest's
        // `.value` property returns it — UILabel surfaces `.text` as
        // `accessibilityLabel`, not `accessibilityValue`.
        let cursorIndicator = UILabel(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        cursorIndicator.isAccessibilityElement = true
        cursorIndicator.accessibilityIdentifier = "markdown.editor.cursor"
        cursorIndicator.alpha = 0
        cursorIndicator.accessibilityValue = "0-0"
        textView.addSubview(cursorIndicator)
        context.coordinator.cursorIndicator = cursorIndicator

        if !text.isEmpty {
            storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        }
        storage.mode = mode
        return textView
    }

    /// Builds the keyboard accessory toolbar (Outdent / Indent /
    /// flexible space / Dismiss) so soft-keyboard users can drive
    /// list indent without a hardware Tab key.
    private func makeAccessoryToolbar(for coordinator: Coordinator) -> UIToolbar {
        let toolbar = UIToolbar()
        let outdent = UIBarButtonItem(image: UIImage(systemName: "decrease.indent"),
                                      primaryAction: UIAction { [weak coordinator] _ in
                                          coordinator?.accessoryOutdent()
                                      })
        outdent.accessibilityIdentifier = "markdown.outdent"
        let indent = UIBarButtonItem(image: UIImage(systemName: "increase.indent"),
                                     primaryAction: UIAction { [weak coordinator] _ in
                                         coordinator?.accessoryIndent()
                                     })
        indent.accessibilityIdentifier = "markdown.indent"
        let dismiss = UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"),
                                      primaryAction: UIAction { [weak coordinator] _ in
                                          coordinator?.accessoryDismiss()
                                      })
        dismiss.accessibilityIdentifier = "markdown.dismissKeyboard"
        toolbar.items = [outdent, indent, UIBarButtonItem(systemItem: .flexibleSpace), dismiss]
        toolbar.sizeToFit()
        return toolbar
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard let storage = uiView.textStorage as? MarkdownStyler else { return }
        if uiView.text != text {
            let full = NSRange(location: 0, length: storage.length)
            storage.replaceCharacters(in: full, with: text)
        }
        if storage.mode != mode {
            storage.mode = mode
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, MarkdownIndentDelegate, UIGestureRecognizerDelegate {
        private let textBinding: Binding<String>
        let layoutDelegate = MarkdownLayoutDelegate()
        weak var activeTextView: UITextView?
        weak var cursorIndicator: UILabel?
        private var pendingDefaultInsertionCaret: Int?

        init(text: Binding<String>) { textBinding = text }

        // MARK: Binding sync

        func textViewDidChange(_ textView: UITextView) {
            applyPendingDefaultInsertionCaret(in: textView)
            if textBinding.wrappedValue != textView.text {
                textBinding.wrappedValue = textView.text
            }
        }

        private func applyPendingDefaultInsertionCaret(in textView: UITextView) {
            guard let expected = pendingDefaultInsertionCaret else { return }
            pendingDefaultInsertionCaret = nil

            let current = textView.selectedRange
            guard current.length == 0,
                  expected <= textView.textStorage.length,
                  current.location < expected else { return }
            textView.selectedRange = NSRange(location: expected, length: 0)
        }

        // MARK: Cursor tracking — drives Bear-style show/hide

        func textViewDidBeginEditing(_ textView: UITextView) {
            activeTextView = textView
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let storage = textView.textStorage as? MarkdownStyler else { return }
            if textView.isFirstResponder {
                storage.cursorRange = textView.selectedRange
            } else {
                storage.cursorRange = NSRange(location: NSNotFound, length: 0)
            }
            adjustTypingAttributesForEofCursor(in: textView)
            textView.setNeedsDisplay()
            let sel = textView.selectedRange
            cursorIndicator?.accessibilityValue = "\(sel.location)-\(sel.length)"
        }

        /// When the cursor sits at EOF on the virtual empty line below a
        /// fence closer, iOS uses the previous paragraph's style for the
        /// blinking cursor — which means the closer's `firstLineHeadIndent`
        /// pushes the cursor in to column 4 below the panel. That looks
        /// like a stuck cursor. Override `typingAttributes` to use the
        /// default paragraph style in this specific spot so the cursor
        /// blinks at column 0 like a fresh new line. We also reset it
        /// for the symmetric case after a fence body, where the body's
        /// indent would otherwise leak onto the virtual EOF line.
        private func adjustTypingAttributesForEofCursor(in textView: UITextView) {
            let sel = textView.selectedRange
            let source = textView.text as NSString
            guard sel.length == 0 else { return }

            if isOnEmptyPlainLine(selection: sel, source: source) {
                resetPlainTypingAttributes(in: textView)
                return
            }

            guard sel.location == source.length,
                  source.length > 0,
                  source.character(at: source.length - 1) == 0x0A else { return }
            // Previous-paragraph check: find the line whose `\n` is the
            // last char of the doc. If that line is a fence marker (` ``` `)
            // or fence body (no plain-text paragraph beneath), the typing
            // attributes will inherit its indent. Reset them.
            let lastLine = source.lineRange(for: NSRange(location: source.length - 1, length: 0))
            let lineLen = max(0, lastLine.length - 1)
            let prevLine = lineLen > 0
                ? source.substring(with: NSRange(location: lastLine.location, length: lineLen))
                : ""
            let needsReset = prevLine.hasPrefix("```") || isInsideFenceBody(prevLineRange: lastLine, source: source)
            guard needsReset else { return }
            resetPlainTypingAttributes(in: textView)
        }

        private func isOnEmptyPlainLine(selection: NSRange, source: NSString) -> Bool {
            guard source.length > 0, selection.location <= source.length else { return false }
            let probeLocation = min(selection.location, max(source.length - 1, 0))
            let lineRange = source.lineRange(for: NSRange(location: probeLocation, length: 0))
            let contentLength = lineContentLength(lineRange, source: source)
            guard contentLength == 0 else { return false }
            return !isInsideFenceBody(prevLineRange: lineRange, source: source)
        }

        private func lineContentLength(_ lineRange: NSRange, source: NSString) -> Int {
            guard lineRange.length > 0 else { return 0 }
            let last = lineRange.location + lineRange.length - 1
            if last >= 0, last < source.length, source.character(at: last) == 0x0A {
                return lineRange.length - 1
            }
            return lineRange.length
        }

        private func resetPlainTypingAttributes(in textView: UITextView) {
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = 1.2
            textView.typingAttributes = [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label,
                .paragraphStyle: p
            ]
        }

        /// True if the given line range (already ending in the doc's
        /// trailing `\n`) is between an unmatched opener and EOF — i.e.,
        /// the user typed an opener and is now sitting just past it with
        /// no closer yet.
        private func isInsideFenceBody(prevLineRange: NSRange, source: NSString) -> Bool {
            var inFence = false
            var index = 0
            let end = source.length
            while index < end {
                var lineEnd = 0
                source.getLineStart(nil, end: &lineEnd, contentsEnd: nil,
                                    for: NSRange(location: index, length: 0))
                if lineEnd <= index { break }
                let contentLen = (lineEnd > index && source.character(at: lineEnd - 1) == 0x0A)
                    ? lineEnd - index - 1
                    : lineEnd - index
                if contentLen >= 3 {
                    let prefix = source.substring(with: NSRange(location: index, length: 3))
                    if prefix == "```" { inFence.toggle() }
                }
                index = lineEnd
            }
            return inFence
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            (textView.textStorage as? MarkdownStyler)?.cursorRange =
                NSRange(location: NSNotFound, length: 0)
            textView.setNeedsDisplay()
            if activeTextView === textView { activeTextView = nil }
        }

        // MARK: List indent / outdent (Tab + Shift+Tab + toolbar buttons)

        func markdownTextView(_ textView: UITextView, didRequestIndent outdent: Bool) {
            let source = textView.text as NSString
            guard source.length > 0 || !outdent else { return }
            let cursor = textView.selectedRange.location
            let enclosing = source.lineRange(for: NSRange(location: min(cursor, source.length), length: 0))
            var contentLen = enclosing.length
            if contentLen > 0,
               source.substring(with: NSRange(location: enclosing.location + contentLen - 1, length: 1)) == "\n" {
                contentLen -= 1
            }
            let line = source.substring(with: NSRange(location: enclosing.location, length: contentLen))
            let lineNS = line as NSString
            let lineFull = NSRange(location: 0, length: lineNS.length)

            if let m = Self.quotedAnyListRegex.firstMatch(in: line, range: lineFull),
               m.numberOfRanges >= 3 {
                let quotePrefixLength = m.range(at: 1).length
                let innerWhitespaceLength = m.range(at: 2).length
                if outdent {
                    let stripCount = min(4, innerWhitespaceLength)
                    if stripCount > 0 {
                        textView.textStorage.replaceCharacters(
                            in: NSRange(location: enclosing.location + quotePrefixLength,
                                        length: stripCount),
                            with: ""
                        )
                        let newCursor = max(cursor - stripCount, enclosing.location + quotePrefixLength)
                        textView.selectedRange = NSRange(location: newCursor, length: 0)
                        textBinding.wrappedValue = textView.text
                        return
                    }
                } else {
                    textView.textStorage.replaceCharacters(
                        in: NSRange(location: enclosing.location + quotePrefixLength, length: 0),
                        with: "    "
                    )
                    textView.selectedRange = NSRange(location: cursor + 4, length: 0)
                    textBinding.wrappedValue = textView.text
                    return
                }
            }

            // Callout (blockquote) — Tab deepens (`> ` → `>> `), Shift+Tab
            // shallows. At level 1, Shift+Tab strips `> ` (the marker AND
            // its trailing space) so the user exits cleanly.
            if let m = MarkdownStyler.blockquoteRegex.firstMatch(in: line, range: lineFull),
               m.numberOfRanges >= 2 {
                let level = m.range(at: 1).length
                if outdent {
                    let stripLen = min(level > 1 ? 1 : 2, lineNS.length)
                    guard stripLen > 0 else { return }
                    textView.textStorage.replaceCharacters(
                        in: NSRange(location: enclosing.location, length: stripLen), with: "")
                    let newCursor = max(cursor - stripLen, enclosing.location)
                    textView.selectedRange = NSRange(location: newCursor, length: 0)
                } else {
                    textView.textStorage.replaceCharacters(
                        in: NSRange(location: enclosing.location, length: 0), with: ">")
                    textView.selectedRange = NSRange(location: cursor + 1, length: 0)
                }
                textBinding.wrappedValue = textView.text
                return
            }

            let isList =
                Self.taskRegex.firstMatch(in: line, range: lineFull) != nil ||
                Self.numberedListRegex.firstMatch(in: line, range: lineFull) != nil ||
                Self.bulletRegex.firstMatch(in: line, range: lineFull) != nil

            if !isList {
                if outdent {
                    // Plain-text outdent: strip up to 4 leading spaces
                    // from the line so the line's indent shrinks by one
                    // level — same convention as a code editor.
                    var stripCount = 0
                    for i in 0..<min(4, lineNS.length) {
                        if lineNS.character(at: i) == 0x20 { stripCount += 1 } else { break }
                    }
                    guard stripCount > 0 else { return }
                    textView.textStorage.replaceCharacters(
                        in: NSRange(location: enclosing.location, length: stripCount), with: "")
                    let newCursor = max(cursor - stripCount, enclosing.location)
                    textView.selectedRange = NSRange(location: newCursor, length: 0)
                } else {
                    let r = textView.selectedRange
                    textView.textStorage.replaceCharacters(in: r, with: "    ")
                    textView.selectedRange = NSRange(location: r.location + 4, length: 0)
                }
                textBinding.wrappedValue = textView.text
                return
            }

            if outdent {
                // Strip up to 4 leading spaces (one indent level). Handles
                // legacy 2-space content too.
                var stripCount = 0
                for i in 0..<min(4, lineNS.length) {
                    if lineNS.character(at: i) == 0x20 { stripCount += 1 } else { break }
                }
                guard stripCount > 0 else { return }
                textView.textStorage.replaceCharacters(
                    in: NSRange(location: enclosing.location, length: stripCount), with: "")
                let newCursor = max(cursor - stripCount, enclosing.location)
                textView.selectedRange = NSRange(location: newCursor, length: 0)
            } else {
                textView.textStorage.replaceCharacters(
                    in: NSRange(location: enclosing.location, length: 0), with: "    ")
                textView.selectedRange = NSRange(location: cursor + 4, length: 0)
            }
            textBinding.wrappedValue = textView.text
        }

        // MARK: Keyboard accessory routing

        func accessoryIndent()  {
            guard let tv = activeTextView else { return }
            markdownTextView(tv, didRequestIndent: false)
        }
        func accessoryOutdent() {
            guard let tv = activeTextView else { return }
            markdownTextView(tv, didRequestIndent: true)
        }
        func accessoryDismiss() {
            activeTextView?.resignFirstResponder()
        }

        // MARK: Tap-to-toggle checkboxes (with haptic feedback)

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            MainActor.assumeIsolated {
                guard let textView = touch.view as? UITextView else { return false }
                return checkboxStateRange(in: textView, at: touch.location(in: textView)) != nil
            }
        }

        @objc func handleCheckboxTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? UITextView,
                  let stateRange = checkboxStateRange(in: textView,
                                                      at: gesture.location(in: textView)) else { return }
            let source = textView.text as NSString
            let current = source.substring(with: stateRange)
            let next = (current == "x" || current == "X") ? " " : "x"
            textView.textStorage.replaceCharacters(in: stateRange, with: next)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            textBinding.wrappedValue = textView.text
        }

        /// Absolute range of the state char (the ` ` / `x` between
        /// `[` and `]`) iff the tap lands in the line's marker zone
        /// of a task line; else nil. The marker zone runs from line
        /// start through the regex's full match (i.e., past the
        /// trailing space). After Round 8 collapsed the `[` cell to
        /// 0.01pt, `closestPosition` snaps to the visible chars
        /// flanking it — accepting the whole marker zone lets the
        /// visible SF Symbol image still trigger the toggle.
        private func checkboxStateRange(in textView: UITextView, at point: CGPoint) -> NSRange? {
            guard let pos = textView.closestPosition(to: point) else { return nil }
            let charIdx = textView.offset(from: textView.beginningOfDocument, to: pos)
            let source = textView.text as NSString
            guard charIdx >= 0, charIdx <= source.length else { return nil }
            let probe = NSRange(location: min(charIdx, max(0, source.length - 1)), length: 0)
            let lineRange = source.lineRange(for: probe)
            let line = source.substring(with: lineRange)
            let lineFull = NSRange(location: 0, length: (line as NSString).length)
            if let m = MarkdownStyler.taskRegex.firstMatch(in: line, range: lineFull),
               m.numberOfRanges >= 5 {
                let markerZoneLen = NSMaxRange(m.range(at: 0))
                let absMarkerZone = NSRange(location: lineRange.location, length: markerZoneLen)
                guard NSLocationInRange(charIdx, absMarkerZone) else { return nil }
                let state = m.range(at: 4)
                return NSRange(location: lineRange.location + state.location, length: state.length)
            }

            if let m = Self.quotedTaskRegex.firstMatch(in: line, range: lineFull),
               m.numberOfRanges >= 6 {
                let markerZoneLen = NSMaxRange(m.range(at: 0))
                let absMarkerZone = NSRange(location: lineRange.location, length: markerZoneLen)
                guard NSLocationInRange(charIdx, absMarkerZone) else { return nil }
                let state = m.range(at: 5)
                return NSRange(location: lineRange.location + state.location, length: state.length)
            }
            return nil
        }

        // MARK: List auto-continuation on Return

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            // Smart backspace — when the cursor sits at column N×4 on a
            // line whose entire prefix is spaces, delete 4 chars at
            // once. Matches code-editor convention: an indent typed as
            // 4 spaces should unindent in a single keystroke, not four.
            if text.isEmpty, range.length == 1, range.location > 0 {
                let nsText = textView.text as NSString
                if nsText.character(at: range.location) == 0x0A,
                   (textView.textStorage as? MarkdownStyler)?.mode == .live,
                   range.location + 1 < nsText.length {
                    let nextLineRange = nsText.lineRange(
                        for: NSRange(location: range.location + 1, length: 0)
                    )
                    let nextContentLen = lineContentLength(nextLineRange, source: nsText)
                    let nextLine = nsText.substring(
                        with: NSRange(location: nextLineRange.location, length: nextContentLen)
                    )
                    if let markerRange = leadingMarkerRemovalRange(in: nextLine,
                                                                    lineStart: nextLineRange.location) {
                        return removeMarkerRange(in: textView, range: markerRange)
                    }
                }

                let lineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
                let contentLen = lineContentLength(lineRange, source: nsText)
                let line = nsText.substring(with: NSRange(location: lineRange.location,
                                                          length: contentLen))
                if let markerRange = markerRemovalRange(in: line,
                                                        lineStart: lineRange.location,
                                                        deletionRange: range) {
                    return removeMarkerRange(in: textView, range: markerRange)
                }

                let prefixLen = range.location - lineRange.location
                if prefixLen >= 4, prefixLen % 4 == 0 {
                    let prefixRange = NSRange(location: lineRange.location, length: prefixLen)
                    let prefix = nsText.substring(with: prefixRange)
                    if prefix.allSatisfy({ $0 == " " }) {
                        let delRange = NSRange(location: range.location - 4, length: 4)
                        textView.textStorage.replaceCharacters(in: delRange, with: "")
                        textView.selectedRange = NSRange(location: delRange.location, length: 0)
                        textBinding.wrappedValue = textView.text
                        return false
                    }
                }
            }

            // Code fence autocomplete — typing the third backtick on an
            // otherwise empty line closes itself out: `` ` `` →
            // ```` \n\n``` ```` with the cursor parked on the empty
            // middle line, ready for code. The user sees the panel
            // appear instantly.
            if text == "`", range.length == 0 {
                let sourceTV = textView.text as NSString
                let line = sourceTV.lineRange(for: NSRange(location: range.location, length: 0))
                let beforeLen = range.location - line.location
                let lineBefore = beforeLen > 0
                    ? sourceTV.substring(with: NSRange(location: line.location, length: beforeLen))
                    : ""
                let lineEnd = NSMaxRange(line)
                let lineEndContent: Int = {
                    if lineEnd > line.location && sourceTV.character(at: lineEnd - 1) == 0x0A {
                        return lineEnd - 1
                    }
                    return lineEnd
                }()
                let afterLen = max(0, lineEndContent - range.location)
                if lineBefore == "``" && afterLen == 0 {
                    pendingDefaultInsertionCaret = nil
                    textView.textStorage.replaceCharacters(in: range, with: "`\n\n```")
                    textView.selectedRange = NSRange(location: range.location + 2, length: 0)
                    textBinding.wrappedValue = textView.text
                    return false
                }
            }

            guard text == "\n", range.length == 0 else {
                rememberDefaultInsertionCaret(for: range, replacementText: text)
                return true
            }
            pendingDefaultInsertionCaret = nil
            let source = textView.text as NSString
            let lineEnclosing = source.lineRange(for: NSRange(location: range.location, length: 0))
            let lineStart = lineEnclosing.location
            let lineContentLen = range.location - lineStart
            guard lineContentLen >= 0 else { return true }
            let line = source.substring(with: NSRange(location: lineStart, length: lineContentLen))
            let lineNS = line as NSString
            let lineFull = NSRange(location: 0, length: lineNS.length)

            if let m = Self.quotedTaskRegex.firstMatch(in: line, range: lineFull),
               m.numberOfRanges >= 6 {
                let quotePrefix = lineNS.substring(with: m.range(at: 1))
                let leadingWS = lineNS.substring(with: m.range(at: 2))
                let bulletStr = lineNS.substring(with: m.range(at: 3))
                let contentStart = NSMaxRange(m.range(at: 0))
                let rest = contentStart <= lineNS.length
                    ? lineNS.substring(from: contentStart).trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""

                if rest.isEmpty {
                    return removeMarkerRange(
                        in: textView,
                        range: NSRange(location: lineStart + (quotePrefix as NSString).length,
                                       length: lineContentLen - (quotePrefix as NSString).length)
                    )
                }
                return insert(in: textView,
                              range: range,
                              text: "\n\(quotePrefix)\(leadingWS)\(bulletStr) [ ] ")
            }

            if let m = Self.quotedNumberedListRegex.firstMatch(in: line, range: lineFull),
               m.numberOfRanges >= 4 {
                let quotePrefix = lineNS.substring(with: m.range(at: 1))
                let leadingWS = lineNS.substring(with: m.range(at: 2))
                let markerRange = m.range(at: 3)
                let markerStr = lineNS.substring(with: markerRange)
                let numberStr = String(markerStr.dropLast())
                let contentStart = NSMaxRange(m.range(at: 0))
                let rest = contentStart <= lineNS.length
                    ? lineNS.substring(from: contentStart).trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""

                if rest.isEmpty {
                    return removeMarkerRange(
                        in: textView,
                        range: NSRange(location: lineStart + (quotePrefix as NSString).length,
                                       length: lineContentLen - (quotePrefix as NSString).length)
                    )
                }
                guard let n = Int(numberStr) else { return true }
                return insert(in: textView,
                              range: range,
                              text: "\n\(quotePrefix)\(leadingWS)\(n + 1). ")
            }

            if let m = Self.quotedBulletRegex.firstMatch(in: line, range: lineFull),
               m.numberOfRanges >= 4 {
                let quotePrefix = lineNS.substring(with: m.range(at: 1))
                let leadingWS = lineNS.substring(with: m.range(at: 2))
                let markerRange = m.range(at: 3)
                let markerStr = lineNS.substring(with: markerRange)
                let contentStart = NSMaxRange(m.range(at: 0))
                let rest = contentStart <= lineNS.length
                    ? lineNS.substring(from: contentStart).trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""

                if rest.isEmpty {
                    return removeMarkerRange(
                        in: textView,
                        range: NSRange(location: lineStart + (quotePrefix as NSString).length,
                                       length: lineContentLen - (quotePrefix as NSString).length)
                    )
                }
                return insert(in: textView,
                              range: range,
                              text: "\n\(quotePrefix)\(leadingWS)\(markerStr) ")
            }

            // Task list (group 1: leading WS, 2: bullet, 3: bracket, 4: state).
            if let m = Self.taskRegex.firstMatch(in: line, range: lineFull),
               m.numberOfRanges >= 5 {
                let leadingWS = lineNS.substring(with: m.range(at: 1))
                let bulletStr = lineNS.substring(with: m.range(at: 2))
                let contentStart = NSMaxRange(m.range(at: 0))
                let rest = contentStart <= lineNS.length
                    ? lineNS.substring(from: contentStart).trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""

                if rest.isEmpty {
                    return removeMarker(in: textView,
                                        lineStart: lineStart,
                                        currentLineLength: lineContentLen)
                }
                return insert(in: textView,
                              range: range,
                              text: "\n\(leadingWS)\(bulletStr) [ ] ")
            }

            // Numbered list (group 1: leading WS, 2: marker)
            if let m = Self.numberedListRegex.firstMatch(in: line, range: lineFull),
               m.numberOfRanges >= 3 {
                let leadingWS = lineNS.substring(with: m.range(at: 1))
                let markerRange = m.range(at: 2)
                let markerStr = lineNS.substring(with: markerRange)
                let numberStr = String(markerStr.dropLast())
                let contentStart = NSMaxRange(m.range(at: 0))
                let rest = contentStart <= lineNS.length
                    ? lineNS.substring(from: contentStart).trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""

                if rest.isEmpty {
                    return removeMarker(in: textView,
                                        lineStart: lineStart,
                                        currentLineLength: lineContentLen)
                }
                guard let n = Int(numberStr) else { return true }
                return insert(in: textView,
                              range: range,
                              text: "\n\(leadingWS)\(n + 1). ")
            }

            // Bulleted list (must come after task since task starts with `- `;
            // group 1: leading WS, 2: marker)
            if let m = Self.bulletRegex.firstMatch(in: line, range: lineFull),
               m.numberOfRanges >= 3 {
                let leadingWS = lineNS.substring(with: m.range(at: 1))
                let markerRange = m.range(at: 2)
                let markerStr = lineNS.substring(with: markerRange)
                let contentStart = NSMaxRange(m.range(at: 0))
                let rest = contentStart <= lineNS.length
                    ? lineNS.substring(from: contentStart).trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""

                if rest.isEmpty {
                    return removeMarker(in: textView,
                                        lineStart: lineStart,
                                        currentLineLength: lineContentLen)
                }
                return insert(in: textView,
                              range: range,
                              text: "\n\(leadingWS)\(markerStr) ")
            }

            // Blockquote / callout — group 1: ">+", auto-continue at same
            // level. Empty content → strip the marker (exit blockquote).
            if let m = MarkdownStyler.blockquoteRegex.firstMatch(in: line, range: lineFull),
               m.numberOfRanges >= 2 {
                let markerRange = m.range(at: 1)
                let markers = lineNS.substring(with: markerRange)
                let contentStart = NSMaxRange(markerRange) + 1
                let rest = contentStart <= lineNS.length
                    ? lineNS.substring(from: contentStart).trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""

                if rest.isEmpty {
                    return removeMarker(in: textView,
                                        lineStart: lineStart,
                                        currentLineLength: lineContentLen)
                }
                return insert(in: textView,
                              range: range,
                              text: "\n\(markers) ")
            }

            return true
        }

        private func markerRemovalRange(in line: String,
                                        lineStart: Int,
                                        deletionRange: NSRange) -> NSRange? {
            let lineNS = line as NSString
            let lineFull = NSRange(location: 0, length: lineNS.length)
            let matchAndKeepPrefix: [(NSRegularExpression, Int)] = [
                (Self.quotedTaskRegex, 1),
                (Self.quotedNumberedListRegex, 1),
                (Self.quotedBulletRegex, 1)
            ]
            for (regex, prefixGroup) in matchAndKeepPrefix {
                guard let m = regex.firstMatch(in: line, range: lineFull) else { continue }
                let markerStart = m.range(at: prefixGroup).length
                let markerEnd = NSMaxRange(m.range(at: 0))
                if isDeletingInsideMarkerZone(range: deletionRange,
                                              lineStart: lineStart,
                                              markerStart: markerStart,
                                              markerEnd: markerEnd) {
                    return NSRange(location: lineStart + markerStart,
                                   length: markerEnd - markerStart)
                }
            }

            if let m = Self.taskRegex.firstMatch(in: line, range: lineFull) {
                let markerEnd = NSMaxRange(m.range(at: 0))
                if isDeletingInsideMarkerZone(range: deletionRange,
                                              lineStart: lineStart,
                                              markerStart: 0,
                                              markerEnd: markerEnd) {
                    return NSRange(location: lineStart, length: markerEnd)
                }
            }
            if let m = Self.numberedListRegex.firstMatch(in: line, range: lineFull) {
                let markerEnd = NSMaxRange(m.range(at: 0))
                if isDeletingInsideMarkerZone(range: deletionRange,
                                              lineStart: lineStart,
                                              markerStart: 0,
                                              markerEnd: markerEnd) {
                    return NSRange(location: lineStart, length: markerEnd)
                }
            }
            if let m = Self.bulletRegex.firstMatch(in: line, range: lineFull) {
                let markerEnd = NSMaxRange(m.range(at: 0))
                if isDeletingInsideMarkerZone(range: deletionRange,
                                              lineStart: lineStart,
                                              markerStart: 0,
                                              markerEnd: markerEnd) {
                    return NSRange(location: lineStart, length: markerEnd)
                }
            }
            if let m = MarkdownStyler.blockquoteRegex.firstMatch(in: line, range: lineFull) {
                let markerEnd = NSMaxRange(m.range(at: 0))
                if isDeletingInsideMarkerZone(range: deletionRange,
                                              lineStart: lineStart,
                                              markerStart: 0,
                                              markerEnd: markerEnd) {
                    return NSRange(location: lineStart, length: markerEnd)
                }
            }
            return nil
        }

        private func leadingMarkerRemovalRange(in line: String, lineStart: Int) -> NSRange? {
            let lineNS = line as NSString
            let lineFull = NSRange(location: 0, length: lineNS.length)
            let matchAndKeepPrefix: [(NSRegularExpression, Int)] = [
                (Self.quotedTaskRegex, 1),
                (Self.quotedNumberedListRegex, 1),
                (Self.quotedBulletRegex, 1)
            ]
            for (regex, prefixGroup) in matchAndKeepPrefix {
                guard let m = regex.firstMatch(in: line, range: lineFull) else { continue }
                let markerStart = m.range(at: prefixGroup).length
                let markerEnd = NSMaxRange(m.range(at: 0))
                return NSRange(location: lineStart + markerStart,
                               length: markerEnd - markerStart)
            }

            if let m = Self.taskRegex.firstMatch(in: line, range: lineFull) {
                return NSRange(location: lineStart, length: NSMaxRange(m.range(at: 0)))
            }
            if let m = Self.numberedListRegex.firstMatch(in: line, range: lineFull) {
                return NSRange(location: lineStart, length: NSMaxRange(m.range(at: 0)))
            }
            if let m = Self.bulletRegex.firstMatch(in: line, range: lineFull) {
                return NSRange(location: lineStart, length: NSMaxRange(m.range(at: 0)))
            }
            if let m = MarkdownStyler.blockquoteRegex.firstMatch(in: line, range: lineFull) {
                return NSRange(location: lineStart, length: NSMaxRange(m.range(at: 0)))
            }
            return nil
        }

        private func isDeletingInsideMarkerZone(range: NSRange,
                                                lineStart: Int,
                                                markerStart: Int,
                                                markerEnd: Int) -> Bool {
            let deletionStart = range.location - lineStart
            let deletionEnd = deletionStart + range.length
            return deletionStart >= markerStart && deletionEnd > markerStart && deletionEnd <= markerEnd
        }

        private func rememberDefaultInsertionCaret(for range: NSRange, replacementText text: String) {
            guard range.length == 0, !text.isEmpty, !text.contains("\n") else {
                pendingDefaultInsertionCaret = nil
                return
            }
            pendingDefaultInsertionCaret = range.location + (text as NSString).length
        }

        /// Insert `replacement` at `range`, position cursor at the end of
        /// the inserted text. Returns `false` so UITextView doesn't
        /// double-apply the original change.
        private func insert(in textView: UITextView,
                            range: NSRange,
                            text replacement: String) -> Bool {
            pendingDefaultInsertionCaret = nil
            textView.textStorage.replaceCharacters(in: range, with: replacement)
            let newCursor = range.location + (replacement as NSString).length
            textView.selectedRange = NSRange(location: newCursor, length: 0)
            // Push the new text up to the SwiftUI binding
            textBinding.wrappedValue = textView.text
            return false
        }

        /// Pressed Return on an empty list item — strip the marker so the
        /// user "exits" the list cleanly.
        private func removeMarker(in textView: UITextView,
                                  lineStart: Int,
                                  currentLineLength: Int) -> Bool {
            let removeRange = NSRange(location: lineStart, length: currentLineLength)
            return removeMarkerRange(in: textView, range: removeRange)
        }

        private func removeMarkerRange(in textView: UITextView, range removeRange: NSRange) -> Bool {
            pendingDefaultInsertionCaret = nil
            textView.textStorage.replaceCharacters(in: removeRange, with: "")
            textView.selectedRange = NSRange(location: removeRange.location, length: 0)
            resetPlainTypingAttributes(in: textView)
            (textView.textStorage as? MarkdownStyler)?.cursorRange = textView.selectedRange
            textBinding.wrappedValue = textView.text
            return false
        }

        private static let quotedTaskRegex =
            try! NSRegularExpression(pattern: #"^(>+\s)(\s*)([-*+])\s(\[([ xX])\])(?:\s|$)"#)
        private static let quotedNumberedListRegex =
            try! NSRegularExpression(pattern: #"^(>+\s)(\s*)(\d+\.)(?:\s|$)"#)
        private static let quotedBulletRegex =
            try! NSRegularExpression(pattern: #"^(>+\s)(\s*)([-*+])(?:\s|$)"#)
        private static let quotedAnyListRegex =
            try! NSRegularExpression(pattern: #"^(>+\s)(\s*)(?:(?:[-*+])(?:\s(?:\[[ xX]\](?:\s|$))?|$)|\d+\.(?:\s|$))"#)
        private static let taskRegex =
            try! NSRegularExpression(pattern: #"^(\s*)([-*+])\s(\[([ xX])\])(?:\s|$)"#)
        private static let numberedListRegex =
            try! NSRegularExpression(pattern: #"^(\s*)(\d+\.)(?:\s|$)"#)
        private static let bulletRegex =
            try! NSRegularExpression(pattern: #"^(\s*)([-*+])(?:\s|$)"#)

    }
}
