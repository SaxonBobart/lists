import SwiftUI
import UIKit

private extension VerticalAlignment {
    /// Anchors the editor's checkbox + ⓘ to the title's vertical center, the
    /// same way `ItemRow` does, so they sit at an identical height in both the
    /// static row and the inline editor.
    enum TitleCenterID: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }
    static let titleCenter = VerticalAlignment(TitleCenterID.self)
}

/// SwiftUI content for the dedicated inline-editing cell. Lays out the same
/// leading control + text block + trailing affordance as `ItemRow`, but the
/// title and notes are live `UITextView`s (plain text) driven by
/// `InlineEditController`, and a blue ⓘ button opens the full details screen.
///
/// The text views own the keyboard `inputAccessoryView` (`InlineEditToolbar`)
/// and first responder; the controller mediates commit, focus, and the
/// toolbar's sub-editors. See `ListDetailCollectionView` for why the editing
/// row gets its own diffable identity (`.editingItem`) — it keeps live typing
/// from triggering the cell reload that would tear down the keyboard.
struct InlineItemEditor: View {
    let item: Item
    let store: ItemStore
    let listColor: Color
    let indent: Int
    let leadingPadding: CGFloat
    let trailingPadding: CGFloat
    /// Called when editing truly ends (no inline text view is first responder).
    /// Passes the item id so the host only clears `editingItemId` if it still
    /// points at this row.
    let onEndEditing: (UUID) -> Void
    let onShowDetail: (Item) -> Void

    @State private var controller: InlineEditController
    /// Set true once the user taps the # button, so the otherwise-hidden tag
    /// field appears and can take focus. Resets each edit session (new view).
    @State private var tagFieldRevealed = false
    /// Incremented on each title edit so SwiftUI re-measures the title field's
    /// height (the text lives in UIKit, invisible to SwiftUI otherwise).
    @State private var titleRevision = 0

    init(
        item: Item,
        store: ItemStore,
        listColor: Color,
        indent: Int,
        leadingPadding: CGFloat = ListsDensity.rowPadX,
        trailingPadding: CGFloat = ListsDensity.rowPadX,
        onEndEditing: @escaping (UUID) -> Void,
        onShowDetail: @escaping (Item) -> Void
    ) {
        self.item = item
        self.store = store
        self.listColor = listColor
        self.indent = indent
        self.leadingPadding = leadingPadding
        self.trailingPadding = trailingPadding
        self.onEndEditing = onEndEditing
        self.onShowDetail = onShowDetail
        _controller = State(initialValue: InlineEditController(itemId: item.id, store: store))
    }

    var body: some View {
        // Mirror ItemRow's alignment exactly: the title field carries the
        // `.titleCenter` guide at its own vertical center (below), so the
        // checkbox + trailing glyph sit at the title's center whether it's one
        // line or wrapped to two — and don't jump when entering/leaving edit.
        HStack(alignment: .titleCenter, spacing: ListsSpacing.s3) {
            leadingControl
                .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }

            VStack(alignment: .leading, spacing: 4) {
                InlineTextField(textView: controller.titleView,
                                revision: titleRevision)
                    .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }
                metaLine
                if !liveItem.plainTextBody.isEmpty {
                    Text(liveItem.plainTextBody)
                        .font(ListsTypography.subheadline)
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                        .lineLimit(2)
                }
            }
            // Fill the row's width (up to the trailing glyphs) so SwiftUI
            // proposes the real column width to the title field in a single
            // layout pass — it then wraps to a second line by growing taller
            // (see `InlineTextField`). Replaces a greedy `Spacer`, which had
            // handed the title its intrinsic one-line width so it never wrapped.
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                controller.requestShowDetail()
            } label: {
                // Habits keep the classic ⓘ (their detail is the dedicated
                // habit screen); tasks / notes / events show a document glyph —
                // "open this as its page".
                Image(systemName: liveItem.type == .habit ? "info.circle" : "text.document")
                    .font(.system(size: 22))
                    .foregroundStyle(ListsTokens.accent)
                    // Trailing-aligned in the 28pt slot to match the static
                    // row's collapse chevron (and the section chevron) — the
                    // swap on entering edit stays put.
                    .frame(width: 28, height: 28, alignment: .trailing)
                    // Both glyphs carry more optical side-bearing than the
                    // thin chevron, so a trailing-aligned frame still leaves
                    // the visual edge a few pt short. Nudge the glyph out so
                    // its right edge lines up with the chevrons' right edge.
                    .offset(x: 8)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }
            .accessibilityLabel(item.type == .habit ? "Details" : "Open")
            .accessibilityIdentifier("inline.editor.info")
        }
        .padding(.vertical, ListsDensity.rowPadY)
        .padding(.leading, leadingPadding + CGFloat(min(indent, 8)) * 24)
        .padding(.trailing, trailingPadding)
        .onAppear {
            controller.onEndEditing = onEndEditing
            controller.onShowDetail = { [store, id = item.id] in
                if let live = store.item(id) { onShowDetail(live) }
            }
            controller.onRevealTagField = { tagFieldRevealed = true }
            controller.onContentChange = { titleRevision &+= 1 }
            controller.beginFocus()
        }
    }

    /// Live item from the store (falls back to the captured snapshot), so the
    /// meta line reflects toolbar edits without reloading the cell.
    private var liveItem: Item { store.item(item.id) ?? item }

    private var inlinePriorityText: String {
        switch liveItem.priority {
        case .high:   return "!!!"
        case .medium: return "!!"
        case .low:    return "!"
        case .none:   return ""
        }
    }

    private var inlinePriorityColor: Color {
        switch liveItem.priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .yellow
        case .none:   return .clear
        }
    }

    private var isOverdue: Bool {
        guard let due = liveItem.due else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    /// Date + repeat (read-only) on one line; editable tag field on the line
    /// below. Keeping them separate prevents the tag field's greedy width from
    /// squeezing the date text until it wraps.
    @ViewBuilder
    private var metaLine: some View {
        let hasDateMeta = ItemMetaLine.dateString(for: liveItem) != nil
            || liveItem.recurrence?.rrule != nil
            || liveItem.priority != .none
            || liveItem.flagged
        let showTagField = tagFieldRevealed || !liveItem.tags.isEmpty
        if hasDateMeta || showTagField {
            VStack(alignment: .leading, spacing: 2) {
                if hasDateMeta {
                    HStack(spacing: 6) {
                        if let date = ItemMetaLine.dateString(for: liveItem) {
                            Text(date)
                                .foregroundStyle(isOverdue
                                                 ? ListsTokens.Semantic.danger
                                                 : ListsTokens.Foreground.secondary)
                        }
                        if let rrule = liveItem.recurrence?.rrule {
                            HStack(spacing: 3) {
                                Image(systemName: "repeat")
                                Text(RepeatPreset.summary(forRRule: rrule))
                            }
                            .foregroundStyle(ListsTokens.Foreground.secondary)
                        }
                        if liveItem.priority != .none {
                            Text(inlinePriorityText)
                                .foregroundStyle(inlinePriorityColor)
                        }
                        if liveItem.flagged {
                            Image(systemName: "flag.fill")
                                .foregroundStyle(ListsTokens.Semantic.warning)
                        }
                    }
                    .font(ListsTypography.footnote)
                }
                if showTagField {
                    InlineTextField(textView: controller.tagsView)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Reads `liveItem` (not the captured snapshot) so a quick type flip from
    /// the toolbar swaps the glyph immediately, without reloading the cell.
    @ViewBuilder
    private var leadingControl: some View {
        switch liveItem.type {
        case .event where !liveItem.completable:
            Image(systemName: "calendar")
                .font(.system(size: 22))
                .foregroundStyle(ListsTokens.Foreground.tertiary)
                .frame(width: 28, height: 28, alignment: .leading)
        case .task, .event:
            Button {
                Task { try? await store.toggleDone(item.id) }
            } label: {
                Image(systemName: (store.item(item.id)?.done ?? false) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle((store.item(item.id)?.done ?? false)
                                     ? ListsTokens.accent : ListsTokens.Foreground.tertiary)
                    .frame(width: 28, height: 28, alignment: .leading)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        case .note:
            Image(systemName: "text.document.fill")
                .font(.system(size: 22))
                .foregroundStyle(ListsTokens.Foreground.tertiary)
                .frame(width: 28, height: 28, alignment: .leading)
        case .habit:
            Image(systemName: "circle")
                .font(.system(size: 22))
                .foregroundStyle(ListsTokens.Foreground.tertiary)
                .frame(width: 28, height: 28, alignment: .leading)
        }
    }
}

// MARK: - Representable text field

/// Mounts ONE of the controller's text views (title or tags) and reports its
/// height via `UITextView.sizeThatFits` — the reliable height API for a
/// non-scrolling text view. (Sizing the fields as one `UIStackView` via
/// `systemLayoutSizeFitting` over-reported the height, dropping the meta line.)
/// SwiftUI's VStack lays the fields out, so spacing matches `ItemRow`.
private struct InlineTextField: UIViewRepresentable {
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
        // Measure at a *stable* width: trust a real finite proposed width (and
        // remember it), reuse the last good one when a pass proposes none or
        // infinity, and decline to size (return nil) until we've had a real
        // width — so SwiftUI never guesses a width that might wrap wrong. With
        // the enclosing `.frame(maxWidth: .infinity)`, the first real pass
        // proposes the full column width, so the title wraps in one pass.
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
        // True content height: includes every line, so the field grows to fit a
        // wrapped title rather than clipping it; no trailing overhead, so no jump.
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

        // Blue caret + selection, matching the ⓘ accent.
        let caret = UIColor(ListsTokens.accent)
        titleView.tintColor = caret

        titleView.configureAsInlineField(
            font: .preferredFont(forTextStyle: .body),
            textColor: .label,
            placeholder: "Title"
        )
        titleView.text = item?.title ?? ""
        titleView.delegate = self
        titleView.inputAccessoryView = toolbar
        // No notes field to advance into anymore — Return commits the edit.
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
    /// item is soft-deleted instead (Reminders-style: a titleless reminder you
    /// dismiss is discarded — covers "tap +, type nothing, dismiss").
    private func flush(discardIfEmpty: Bool) {
        guard var item = store.item(itemId) else { return }
        let trimmedTitle = titleView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if discardIfEmpty && trimmedTitle.isEmpty {
            Task { try? await store.softDelete(itemId) }
            return
        }
        item.title = titleView.text
        // The body is never edited inline (notes are a read-only preview here),
        // so it's left untouched — full note editing lives on the detail page.
        item.tags = parsedTags()
        store.applyUpdateSync(item)
    }

    private func endEditing() {
        guard !hasEnded else { return }
        hasEnded = true
        flush(discardIfEmpty: true)
        onEndEditing?(itemId)
    }

    func requestShowDetail() {
        // Resign FIRST, while `editingItemId` still points at this row.
        // Resigning animates the keyboard away, which synchronously re-enters
        // the list's `applySnapshot`; if `editingItemId` were already cleared by
        // then, that pass would delete this still-first-responder cell and UIKit
        // would abort ("the first responder contained inside of a deleted item
        // refused to resign"). With the id still set, the editing cell survives
        // the resign — we clear it on the next pass, once focus is gone.
        titleView.resignFirstResponder()
        tagsView.resignFirstResponder()
        // End the session WITHOUT discarding an empty title — the detail screen
        // can fill it in. Mark ended so the deferred end-editing fired by the
        // resignations above doesn't re-run `endEditing` (whose discard-if-empty
        // would delete the item we're about to open).
        if !hasEnded {
            hasEnded = true
            flush(discardIfEmpty: false)
            onEndEditing?(itemId)
        }
        onShowDetail?()
    }

    // MARK: UITextViewDelegate

    func textView(_ textView: UITextView,
                  shouldChangeTextIn range: NSRange,
                  replacementText text: String) -> Bool {
        // Return in the (single-line) title commits the edit — there's no notes
        // field to advance into.
        if textView === titleView, text == "\n" {
            titleView.resignFirstResponder()
            return false
        }
        // Return in the single-line tag field ends editing rather than adding a
        // newline.
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
        // Tell SwiftUI the text changed so it re-measures the field height — the
        // text lives in this UIKit view, so SwiftUI has no other signal that a
        // title just wrapped to a second line and needs a taller frame.
        onContentChange?()
        // Then apply that new height to the self-sizing cell immediately and
        // without animation, so the row grows in place rather than the cell's
        // top overshooting upward for a few frames (the "jump/wiggle up").
        guard let cv = textView.enclosingCollectionView else { return }
        UIView.performWithoutAnimation {
            cv.performBatchUpdates(nil)
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if let tv = textView as? PlaceholderTextView { tv.refreshPlaceholder() }
        // Defer: moving focus title→notes briefly leaves neither as first
        // responder. Only treat editing as ended if, next runloop, no inline
        // field holds focus and we aren't mid-sub-sheet.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isPresentingSubSheet { return }
            if self.titleView.isFirstResponder
                || self.tagsView.isFirstResponder { return }
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
        (store.item(itemId)?.type ?? .task) != .habit
    }

    func inlineToolbarCurrentType() -> Item.ItemType {
        store.item(itemId)?.type ?? .task
    }

    /// Same flip rules as the document page: switching to Event makes a plain
    /// (non-completable) calendar event — the row's glyph becomes the calendar —
    /// with a guaranteed start + end. Flips that lose the checkbox clear the
    /// done state so it can't linger invisibly. Habits never flip from here.
    func inlineToolbarSetType(_ newType: Item.ItemType) {
        guard var item = store.item(itemId), item.type != .habit,
              newType != item.type, newType != .habit else { return }
        item.type = newType
        if newType == .event {
            item.completable = false
            ensureEventDates(&item)
        }
        let keepsDone = newType == .task || (newType == .event && item.completable)
        if !keepsDone {
            item.done = false
            item.completedAt = nil
        }
        store.applyUpdateSync(item)
    }

    /// An event must always have a start and an end (mirrors the document page).
    private func ensureEventDates(_ item: inout Item) {
        let cal = Calendar.current
        if item.due == nil {
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: Date())
            let flooredHour = cal.date(from: comps) ?? Date()
            item.due = cal.date(byAdding: .hour, value: 1, to: flooredHour) ?? Date()
            item.dueAllDay = false
        }
        if item.end == nil, let start = item.due {
            item.end = item.dueAllDay
                ? (cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))
                : start.addingTimeInterval(3_600)
        }
    }

    func inlineToolbarHasParent() -> Bool {
        store.item(itemId)?.parentId != nil
    }

    func inlineToolbarDidTapMoveToParent() {
        guard let item = store.item(itemId) else { return }
        presentEditor(MoveToParentPicker(item: item, store: store))
    }

    func inlineToolbarDidTapTags() {
        // The tag field is hidden until needed, so first ask the view to mount
        // it, then drop in a "#" and focus it (retrying until it's on screen).
        onRevealTagField?()
        let current = tagsView.text ?? ""
        let needsSpace = !current.isEmpty && !current.hasSuffix(" ")
        tagsView.text = current + (needsSpace ? " #" : "#")
        focusTags()
    }

    /// Focus the tag field once it's in a window (it may have just been
    /// revealed this runloop), caret at the end. Mirrors `focusIfNeeded`.
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

    /// Present a toolbar sub-editor (date / tags) over the editing text view's
    /// own window, suspending the "editing ended" commit while it's up, and
    /// re-focusing the title when it disappears. `onDisappear` is used (not the
    /// presentation-controller delegate) so it fires for BOTH swipe-to-dismiss
    /// and the sheet's own Done/Cancel programmatic dismiss.
    private func presentEditor<V: View>(_ view: V) {
        guard let presenter = topPresentedController() else { return }
        isPresentingSubSheet = true
        let restore: () -> Void = { [weak self] in
            guard let self, self.isPresentingSubSheet else { return }
            self.isPresentingSubSheet = false
            self.titleView.becomeFirstResponder()
            self.toolbar.refresh()
        }
        let host = UIHostingController(rootView: view.onDisappear(perform: restore))
        if let sheet = host.sheetPresentationController {
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
