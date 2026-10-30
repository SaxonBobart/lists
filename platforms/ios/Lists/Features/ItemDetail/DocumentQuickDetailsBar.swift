import UIKit
import Observation

// MARK: - Focus bridge

/// First-responder plumbing between the page's two UIKit text views. SwiftUI
/// focus state can't reach inside representables, so both register here and
/// the page drives focus through it.
@MainActor
@Observable
final class DocumentFocusBridge {
    @ObservationIgnored weak var titleView: UITextView?
    @ObservationIgnored weak var bodyView: UITextView?
    var endTableSelection: (() -> Void)?
    var focusTableCell: ((
        _ tableLocation: Int,
        _ address: MarkdownTableCellAddress,
        _ range: NSRange
    ) -> Void)?
    var copySelection: (() -> String?)?
    var replaceSource: ((String) -> Void)?
    var requestAttachment: (() -> Void)?
    @ObservationIgnored var attachmentMenu: (() -> UIMenu)?
    var canUndo = false
    var canRedo = false

    func replaceBody(_ source: String) { replaceSource?(source) }
    func undo() { bodyView?.undoManager?.undo(); refreshHistory() }
    func redo() { bodyView?.undoManager?.redo(); refreshHistory() }
    func refreshHistory() {
        canUndo = bodyView?.undoManager?.canUndo == true
        canRedo = bodyView?.undoManager?.canRedo == true
    }

    func focusTitle(range: NSRange? = nil) {
        guard let titleView else { return }
        titleView.becomeFirstResponder()
        if let range {
            titleView.selectedRange = range
        } else {
            let end = titleView.endOfDocument
            titleView.selectedTextRange = titleView.textRange(from: end, to: end)
        }
    }

    /// Return in the title hops into the body, caret at the start.
    func focusBody() {
        guard let bodyView else { return }
        bodyView.becomeFirstResponder()
        let start = bodyView.beginningOfDocument
        bodyView.selectedTextRange = bodyView.textRange(from: start, to: start)
    }

    func focusBody(range: NSRange) {
        guard let bodyView else { return }
        bodyView.becomeFirstResponder()
        bodyView.selectedRange = range
        if let storage = bodyView.textStorage as? MarkdownStyler {
            storage.cursorRange = range
        }
        DispatchQueue.main.async { [weak bodyView] in
            bodyView?.revealDocumentSelection()
        }
    }

    func revealFocusedSelection() {
        focusedEditor?.revealDocumentSelection()
    }

    func reloadFocusedInputViews() {
        focusedEditor?.reloadInputViews()
    }

    private var focusedEditor: UITextView? {
        func focusedTextView(in view: UIView) -> UITextView? {
            if let textView = view as? UITextView, textView.isFirstResponder { return textView }
            return view.subviews.lazy.compactMap { focusedTextView(in: $0) }.first
        }
        for view in [titleView, bodyView].compactMap({ $0 }) {
            if let editor = focusedTextView(in: view) { return editor }
        }
        return nil
    }

    func focusEditor(_ target: DocumentEditorFocusTarget) {
        switch target {
        case .body(let range):
            focusBody(range: range)
        case .tableCell(let tableLocation, let address, let range):
            focusTableCell?(tableLocation, address, range)
        }
    }

    func currentCopySelection() -> String? {
        copySelection?()
    }

    func scrollBody(range: NSRange) {
        guard let bodyView,
              let scrollView = bodyView.enclosingDocumentScrollView else { return }
        let visibleRange = NSRange(location: range.location, length: max(range.length, 1))
        bodyView.scrollRangeToVisible(visibleRange)
        let glyphRange = bodyView.layoutManager.glyphRange(
            forCharacterRange: visibleRange,
            actualCharacterRange: nil
        )
        let rect = bodyView.layoutManager.boundingRect(
            forGlyphRange: glyphRange,
            in: bodyView.textContainer
        ).insetBy(dx: 0, dy: -56)
        scrollView.scrollRectToVisible(scrollView.convert(rect, from: bodyView), animated: false)
    }

    func endEditing() {
        // Tags and native property inputs share this document's window but
        // are not the title/body text views tracked by the editor bridge.
        let documentWindow = titleView?.window ?? bodyView?.window
        endTableSelection?()
        if let storage = bodyView?.textStorage as? MarkdownStyler {
            storage.cursorRange = NSRange(location: NSNotFound, length: 0)
        }
        titleView?.resignFirstResponder()
        bodyView?.endEditing(true)
        bodyView?.resignFirstResponder()
        documentWindow?.endEditing(true)
    }
}
