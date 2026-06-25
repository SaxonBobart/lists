import SwiftUI
import UIKit

// MARK: - Representable text field

/// Mounts ONE of the controller's text views (title or tags) and reports its
/// height via `UITextView.sizeThatFits` — the reliable height API for a
/// non-scrolling text view. (Sizing the fields as one `UIStackView` via
/// `systemLayoutSizeFitting` over-reported the height, dropping the meta line.)
/// SwiftUI's VStack lays the fields out, so spacing matches `ItemRow`.
struct InlineTextField: UIViewRepresentable {
    let textView: PlaceholderTextView
    /// Bumped by the controller on every text change. The text lives in the
    /// UIKit view, not in SwiftUI state, so without a value that changes on each
    /// keystroke SwiftUI wouldn't know to re-run `sizeThatFits` — and the field
    /// would keep its old (now-too-short) height when a title wraps, clipping
    /// the new line. Threading the revision through forces the re-measure.
    var revision: Int = 0

    func makeUIView(context: Context) -> PlaceholderTextView { textView }

    func updateUIView(_ uiView: PlaceholderTextView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PlaceholderTextView, context: Context) -> CGSize? {
        // Measure at a stable width: trust a real finite proposed width (and
        // remember it), reuse the last good one when a pass proposes none or
        // infinity, and decline to size until we've had a real width.
        let proposed = proposal.width ?? 0
        let width: CGFloat
        if proposed > 1, proposed.isFinite {
            width = proposed
            uiView.lastMeasuredWidth = proposed
        } else if uiView.lastMeasuredWidth > 1 {
            width = uiView.lastMeasuredWidth
        } else {
            return nil
        }
        let height = uiView.contentHeight(forWidth: width,
                                          displayScale: context.environment.displayScale)
        return CGSize(width: width, height: height)
    }
}

// MARK: - Controller

/// Owns the inline editor's UITextViews, keyboard toolbar, and first-responder
/// lifecycle. Persists edits to `ItemStore` and presents the toolbar's date /
/// tag sub-editors over the editing text view's own window.
@MainActor
final class InlineEditController: NSObject, UITextViewDelegate, InlineEditToolbarDelegate {
    private let itemId: UUID
    private let store: ItemStore

    var onEndEditing: ((UUID) -> Void)?
    var onShowDetail: (() -> Void)?
    var onBeginMove: (() -> Void)?
    /// Asks the view to mount the (otherwise hidden) tag field so it can focus.
    var onRevealTagField: (() -> Void)?
    /// Fired on every text change so the view can force SwiftUI to re-measure
    /// the field heights (the text lives in UIKit, invisible to SwiftUI).
    var onContentChange: (() -> Void)?

    let titleView = PlaceholderTextView()
    /// Editable tags, rendered inline in the meta line where the row already
    /// shows "#tag" chips. Focused by the toolbar's # button.
    let tagsView = PlaceholderTextView()
    private lazy var toolbar = InlineEditToolbar(delegate: self)

    /// True while a toolbar sub-editor (date / tags) is presented — suppresses
    /// the "editing ended" commit so the session survives the modal.
    private var isPresentingSubSheet = false
    /// Guards against a double commit when both text views report end-editing.
    private var hasEnded = false
    private var didFocus = false

    init(itemId: UUID, store: ItemStore) {
        self.itemId = itemId
        self.store = store
        super.init()
        configure()
    }

    private func configure() {
        let item = store.item(itemId)

        // Blue caret + selection, matching the info accent.
        let caret = UIColor(ListsTokens.accent)
        titleView.tintColor = caret

        titleView.configureAsInlineField(
            font: .preferredFont(forTextStyle: .body),
            textColor: .label,
            placeholder: (item?.type ?? .task).titlePlaceholder
        )
        titleView.text = item?.title ?? ""
        titleView.delegate = self
        titleView.inputAccessoryView = toolbar
        titleView.returnKeyType = .done
        titleView.accessibilityIdentifier = "inline.editor.title"

        tagsView.configureAsInlineField(
            font: .preferredFont(forTextStyle: .subheadline),
            textColor: UIColor(ListsTokens.tagAccent),
            placeholder: ""
        )
        tagsView.tintColor = caret
        tagsView.text = (item?.tags ?? []).map { "#\($0)" }.joined(separator: " ")
        tagsView.delegate = self
        tagsView.inputAccessoryView = toolbar
        tagsView.returnKeyType = .done
        tagsView.autocapitalizationType = .none
        tagsView.autocorrectionType = .no
        tagsView.accessibilityIdentifier = "inline.editor.tags"
    }

    /// Parse the tag field into a deduped tag list. Accepts space/comma
    /// separated entries, with or without a leading "#".
    private func parsedTags() -> [String] {
        let raw = tagsView.text ?? ""
        var seen = Set<String>()
        var result: [String] = []
        for token in raw.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }) {
            var tag = String(token)
            if tag.hasPrefix("#") { tag.removeFirst() }
            tag = tag.trimmingCharacters(in: .whitespaces)
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { continue }
            result.append(tag)
        }
        return result
    }

    /// Focus the title field once the editing cell is on screen. Called from
    /// the editor's `onAppear`; retries until the view is in a window.
    func beginFocus() {
        focusIfNeeded()
    }

    private func focusIfNeeded(attempt: Int = 0) {
        guard !didFocus else { return }
        // becomeFirstResponder only works once the view is in a window; the
        // hosting cell may not be attached on the first runloop. Retry briefly.
        guard titleView.window != nil else {
            guard attempt < 12 else { return }
            DispatchQueue.main.async { [weak self] in self?.focusIfNeeded(attempt: attempt + 1) }
            return
        }
        didFocus = true
        titleView.becomeFirstResponder()
        let end = titleView.endOfDocument
        titleView.selectedTextRange = titleView.textRange(from: end, to: end)
    }

    // MARK: Commit

    /// Persist current text. When `discardIfEmpty` and the title is blank, the
    /// item is soft-deleted instead. Returns whether a live item remains.
    @discardableResult
    private func flush(discardIfEmpty: Bool) -> Bool {
        guard var item = store.item(itemId) else { return false }
        let trimmedTitle = titleView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if discardIfEmpty && trimmedTitle.isEmpty {
            store.applySoftDeleteSync(itemId)
            return false
        }
        item.title = titleView.text
        // The body is never edited inline; full note editing lives on the detail page.
        item.tags = parsedTags()
        store.applyUpdateSync(item)
        return true
    }

    @discardableResult
    private func finishEditing(discardIfEmpty: Bool) -> Bool {
        guard !hasEnded else {
            guard let item = store.item(itemId), item.deletedAt == nil else { return false }
            return item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        hasEnded = true
        let keptItem = flush(discardIfEmpty: discardIfEmpty)
        onEndEditing?(itemId)
        return keptItem
    }

    private func endEditing() {
        _ = finishEditing(discardIfEmpty: true)
    }

    func requestShowDetail() {
        // Resign FIRST while the list still knows this row is editing, so the
        // keyboard dismissal cannot delete the first responder out from under UIKit.
        titleView.resignFirstResponder()
        tagsView.resignFirstResponder()
        guard finishEditing(discardIfEmpty: true) else { return }
        onShowDetail?()
    }

    func requestBeginMove() {
        titleView.resignFirstResponder()
        tagsView.resignFirstResponder()
        guard finishEditing(discardIfEmpty: true) else { return }
        onBeginMove?()
    }

    // MARK: UITextViewDelegate

    func textView(_ textView: UITextView,
                  shouldChangeTextIn range: NSRange,
                  replacementText text: String) -> Bool {
        if textView === titleView, text == "\n" {
            titleView.resignFirstResponder()
            return false
        }
        if textView === tagsView, text == "\n" {
            tagsView.resignFirstResponder()
            return false
        }
        // Typing a space in the tag field: if the word just typed has no "#",
        // prepend one so every tag stays "#tag".
        if textView === tagsView, text == " ", range.length == 0 {
            let ns = (textView.text ?? "") as NSString
            let cursor = range.location
            var start = cursor
            while start > 0, ns.character(at: start - 1) != unichar(32) {
                start -= 1
            }
            let token = ns.substring(with: NSRange(location: start, length: cursor - start))
            if !token.isEmpty, !token.hasPrefix("#") {
                let withSpace = ns.replacingCharacters(in: NSRange(location: cursor, length: 0), with: " ")
                let withHash = (withSpace as NSString)
                    .replacingCharacters(in: NSRange(location: start, length: 0), with: "#")
                textView.text = withHash
                if let pos = textView.position(from: textView.beginningOfDocument, offset: cursor + 2) {
                    textView.selectedTextRange = textView.textRange(from: pos, to: pos)
                }
                return false
            }
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        if let tv = textView as? PlaceholderTextView { tv.refreshPlaceholder() }
        onContentChange?()
        guard let cv = textView.enclosingCollectionView else { return }
        UIView.performWithoutAnimation {
            cv.performBatchUpdates(nil)
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if let tv = textView as? PlaceholderTextView { tv.refreshPlaceholder() }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isPresentingSubSheet { return }
            if self.titleView.isFirstResponder || self.tagsView.isFirstResponder { return }
            self.endEditing()
        }
    }

    // MARK: InlineEditToolbarDelegate

    func inlineToolbarDidTapDate() {
        guard let item = store.item(itemId) else { return }
        presentEditor(InlineDateTimePopover(item: item, store: store))
    }

    func inlineToolbarHasDate() -> Bool { store.item(itemId)?.due != nil }

    func inlineToolbarToggleFlag() {
        guard var item = store.item(itemId) else { return }
        item.flagged.toggle()
        store.applyUpdateSync(item)
    }

    func inlineToolbarIsFlagged() -> Bool { store.item(itemId)?.flagged ?? false }

    func inlineToolbarCurrentPriority() -> Item.Priority { store.item(itemId)?.priority ?? .none }

    func inlineToolbarSetPriority(_ priority: Item.Priority) {
        guard var item = store.item(itemId) else { return }
        item.priority = priority
        store.applyUpdateSync(item)
    }

    func inlineToolbarCanChangeType() -> Bool {
        true
    }

    func inlineToolbarHabitsPluginEnabled() -> Bool {
        CorePluginPreferences.isEnabled(.habits)
    }

    func inlineToolbarCurrentType() -> Item.ItemType {
        store.item(itemId)?.type ?? .task
    }

    /// Same flip rules as the document page: switching to Event makes a plain
    /// non-completable calendar event with a guaranteed start + end. Switching
    /// to Habit clears the notes body and starts with a normal daily goal.
    func inlineToolbarSetType(_ newType: Item.ItemType) {
        guard var item = store.item(itemId), newType != item.type else { return }
        let itemTypePolicy = ItemTypePolicy(habitsEnabled: inlineToolbarHabitsPluginEnabled())
        guard itemTypePolicy.isAvailable(newType) else { return }
        item.type = newType
        titleView.setPlaceholder(newType.titlePlaceholder)
        if newType == .event {
            item.completable = false
            EventDefaults.normalize(&item)
        } else if newType == .habit {
            item.body = ""
            item.frequency = item.frequency?.normalizedForHabit ?? .daily
            item.goalPerCycle = max(1, item.goalPerCycle)
            item.completions = []
            item.completable = false
            item.end = nil
        }
        let keepsDone = newType == .task || (newType == .event && item.completable)
        if !keepsDone {
            item.done = false
            item.completedAt = nil
        }
        store.applyUpdateSync(item)
        if newType == .habit {
            requestShowDetail()
        }
    }

    func inlineToolbarHasParent() -> Bool {
        store.item(itemId)?.parentId != nil
    }

    func inlineToolbarDidTapMove() {
        requestBeginMove()
    }

    func inlineToolbarDidTapTags() {
        onRevealTagField?()
        let current = tagsView.text ?? ""
        let needsSpace = !current.isEmpty && !current.hasSuffix(" ")
        tagsView.text = current + (needsSpace ? " #" : "#")
        focusTags()
    }

    private func focusTags(attempt: Int = 0) {
        guard tagsView.window != nil else {
            guard attempt < 12 else { return }
            DispatchQueue.main.async { [weak self] in self?.focusTags(attempt: attempt + 1) }
            return
        }
        tagsView.becomeFirstResponder()
        let end = tagsView.endOfDocument
        tagsView.selectedTextRange = tagsView.textRange(from: end, to: end)
    }

    // MARK: Sub-editor presentation

    private func presentEditor<V: View>(_ view: V) {
        presentSubEditor(view, fullScreen: false)
    }

    private func presentSubEditor<V: View>(_ view: V, fullScreen: Bool) {
        guard let presenter = topPresentedController() else { return }
        isPresentingSubSheet = true
        let restore: () -> Void = { [weak self] in
            guard let self, self.isPresentingSubSheet else { return }
            self.isPresentingSubSheet = false
            self.titleView.becomeFirstResponder()
            self.toolbar.refresh()
        }
        let host = UIHostingController(rootView: view.onDisappear(perform: restore))
        if fullScreen {
            host.modalPresentationStyle = .fullScreen
        } else if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.present(host, animated: true)
    }

    private func topPresentedController() -> UIViewController? {
        guard var top = titleView.window?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

private extension UIView {
    /// Nearest ancestor collection view, walking the superview chain.
    var enclosingCollectionView: UICollectionView? {
        var node = superview
        while let current = node {
            if let cv = current as? UICollectionView { return cv }
            node = current.superview
        }
        return nil
    }
}
