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
        // Half the title line height — the title's vertical center, used as the
        // `.titleCenter` anchor. Captured as a value so the (Sendable) alignment
        // closure doesn't reach back into this main-actor view.
        let titleHalf = UIFont.preferredFont(forTextStyle: .body).lineHeight / 2
        // Mirror ItemRow exactly: center the checkbox + ⓘ on the title line
        // (not the top of the block) so tapping into edit doesn't nudge them.
        return HStack(alignment: .titleCenter, spacing: ListsSpacing.s3) {
            leadingControl
                .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }

            VStack(alignment: .leading, spacing: 4) {
                InlineTextField(textView: controller.titleView)
                InlineTextField(textView: controller.notesView)
                // Meta line: date / repeat stay read-only (edited via the date
                // toolbar button), but tags are an inline editable field right
                // where they render — keeps the row's height + layout on edit.
                metaLine
            }
            // The title is the VStack's first line; its center is the row's
            // titleCenter anchor.
            .alignmentGuide(.titleCenter) { d in d[.top] + titleHalf }

            // Greedy spacer pins the trailing ⓘ to the row's edge — exactly like
            // ItemRow's `Spacer(minLength: 0)`. A `.frame(maxWidth: .infinity)`
            // on the VStack does NOT expand reliably here: its children are
            // `UITextView` representables, so the frame collapsed to the text's
            // intrinsic width and the ⓘ floated mid-row right after the text.
            Spacer(minLength: 0)

            // Flag stays visible while editing (reads live, so toggling it
            // from the toolbar shows immediately), matching the static row.
            if liveItem.flagged {
                Image(systemName: "flag.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ListsTokens.Semantic.warning)
                    .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }
            }

            Button {
                controller.requestShowDetail()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(ListsTokens.accent)
                    // Trailing-aligned in the 28pt slot to match the static
                    // row's collapse chevron (and the section chevron) — the
                    // swap on entering edit stays put.
                    .frame(width: 28, height: 28, alignment: .trailing)
                    // info.circle carries more optical side-bearing than the
                    // thin chevron, so a trailing-aligned frame still leaves its
                    // visual edge a few pt short. Nudge the circle out so its
                    // right edge lines up with the chevrons' right edge.
                    .offset(x: 8)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }
            .accessibilityLabel("Details")
            .accessibilityIdentifier("inline.editor.info")
        }
        .padding(.vertical, ListsDensity.rowPadY)
        .padding(.leading, leadingPadding + CGFloat(indent) * 24)
        .padding(.trailing, trailingPadding)
        .onAppear {
            controller.onEndEditing = onEndEditing
            controller.onShowDetail = { [store, id = item.id] in
                if let live = store.item(id) { onShowDetail(live) }
            }
            controller.onRevealTagField = { tagFieldRevealed = true }
            controller.beginFocus()
        }
    }

    /// Live item from the store (falls back to the captured snapshot), so the
    /// meta line / flag reflect toolbar edits without reloading the cell.
    private var liveItem: Item { store.item(item.id) ?? item }

    private var isOverdue: Bool {
        guard let due = liveItem.due else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    /// The meta line is only worth a row when it has something in it: a date, a
    /// repeat rule, existing tags, or the tag field the user just revealed via
    /// the # button. Otherwise it's omitted so a tagless/dateless item doesn't
    /// reserve a blank line under the notes while editing.
    private var showsMetaLine: Bool {
        tagFieldRevealed
            || ItemMetaLine.dateString(for: liveItem) != nil
            || liveItem.recurrence?.rrule != nil
            || !liveItem.tags.isEmpty
    }

    /// Date + repeat (read-only) followed by the inline editable tag field —
    /// laid out like ItemRow's meta line so the row holds still on edit.
    @ViewBuilder
    private var metaLine: some View {
        if showsMetaLine {
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
                InlineTextField(textView: controller.tagsView)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(ListsTypography.footnote)
        }
    }

    @ViewBuilder
    private var leadingControl: some View {
        switch item.type {
        case .task:
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

/// Mounts ONE of the controller's text views (title or notes) and reports its
/// height via `UITextView.sizeThatFits` — the reliable height API for a
/// non-scrolling text view. (Sizing the title+notes as one `UIStackView` via
/// `systemLayoutSizeFitting` over-reported the height, dropping the meta line.)
/// SwiftUI's VStack lays the two fields out, so spacing matches `ItemRow`.
private struct InlineTextField: UIViewRepresentable {
    let textView: PlaceholderTextView

    func makeUIView(context: Context) -> PlaceholderTextView { textView }

    func updateUIView(_ uiView: PlaceholderTextView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PlaceholderTextView, context: Context) -> CGSize? {
        // Measure at a *stable* width. A transient narrow width — an early
        // layout pass, or a stale `bounds` — wraps a one-line field to two and
        // that taller height sticks, which is the "phantom extra line" that
        // shows up in notes and throws the row's spacing off. So: trust a real
        // proposed width (and remember it); reuse the last good width when a
        // pass proposes none; and if we've never had one, decline to size
        // (return nil) so SwiftUI falls back to intrinsic sizing instead of
        // guessing a width that might wrap.
        let proposed = proposal.width ?? 0
        let width: CGFloat
        if proposed > 1 {
            width = proposed
            uiView.lastMeasuredWidth = proposed
        } else if uiView.lastMeasuredWidth > 1 {
            width = uiView.lastMeasuredWidth
        } else {
            return nil
        }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
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

    let titleView = PlaceholderTextView()
    let notesView = PlaceholderTextView()
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
        notesView.tintColor = caret

        titleView.configureAsInlineField(
            font: .preferredFont(forTextStyle: .body),
            textColor: .label,
            placeholder: "Title"
        )
        titleView.text = item?.title ?? ""
        titleView.delegate = self
        titleView.inputAccessoryView = toolbar
        titleView.returnKeyType = .next
        titleView.accessibilityIdentifier = "inline.editor.title"

        notesView.configureAsInlineField(
            font: .preferredFont(forTextStyle: .subheadline),
            textColor: .secondaryLabel,
            placeholder: "Notes"
        )
        // Trim to match the static row, which displays
        // `body.trimmingCharacters(in: .whitespacesAndNewlines)`. Without this a
        // stored trailing newline renders as a real blank line in the editor —
        // the row looks taller the moment you tap into it.
        notesView.text = (item?.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        notesView.delegate = self
        notesView.inputAccessoryView = toolbar
        notesView.accessibilityIdentifier = "inline.editor.notes"

        tagsView.configureAsInlineField(
            font: .preferredFont(forTextStyle: .footnote),
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

        applyPriorityPrefix()
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

    /// Mirror the item's priority as a coloured prefix on the title field, so
    /// the title text sits at the same x as the row's "!!! Title" and entering
    /// edit doesn't shift it. Re-run when priority changes via the toolbar.
    private func applyPriorityPrefix() {
        switch store.item(itemId)?.priority ?? .none {
        case .high:   titleView.setPriorityPrefix("!!!", color: UIColor(.red))
        case .medium: titleView.setPriorityPrefix("!!", color: UIColor(.orange))
        case .low:    titleView.setPriorityPrefix("!", color: UIColor(.yellow))
        case .none:   titleView.setPriorityPrefix(nil, color: nil)
        }
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
        item.body = notesView.text
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
        notesView.resignFirstResponder()
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
        // Return in the title hops to notes instead of inserting a newline.
        if textView === titleView, text == "\n" {
            notesView.becomeFirstResponder()
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
        // A newline grows the (non-scrolling) text view, which grows the
        // self-sizing cell. Left to UICollectionView's automatic self-sizing,
        // that height change animates — the cell's top overshoots upward for a
        // few frames before settling, the "jump/wiggle up" when pressing return
        // in notes. Force an immediate, non-animated re-measure so the row just
        // grows in place.
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
                || self.notesView.isFirstResponder
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
        applyPriorityPrefix()
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

// MARK: - Placeholder text view

/// A plain `UITextView` styled to sit flush in the inline editor, with a
/// lightweight placeholder shown while empty.
final class PlaceholderTextView: UITextView {
    private let placeholderLabel = UILabel()
    /// Non-editable coloured priority prefix ("!" / "!!" / "!!!") shown ahead
    /// of the editable text, matching how `ItemRow` renders priority.
    private let prefixLabel = UILabel()
    /// Leading constraints for the placeholder + prefix, shifted by the prefix
    /// width so the editable text and placeholder begin after the prefix.
    private var placeholderLeading: NSLayoutConstraint?
    private var prefixFont: UIFont = .preferredFont(forTextStyle: .body)
    /// Last width SwiftUI proposed for self-sizing. Reused when a later layout
    /// pass proposes none, so a transient narrow width can't wrap a one-line
    /// field to two. See `InlineTextField.sizeThatFits`.
    var lastMeasuredWidth: CGFloat = 0

    func configureAsInlineField(font: UIFont, textColor: UIColor, placeholder: String) {
        self.font = font
        self.textColor = textColor
        self.prefixFont = font
        self.backgroundColor = .clear
        self.isScrollEnabled = false
        // Flush insets so the editable text lands at the same baseline as the
        // row's plain Text — any top inset would drop the title a point on edit.
        self.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        self.textContainer.lineFragmentPadding = 0
        self.setContentHuggingPriority(.defaultHigh, for: .vertical)
        self.setContentCompressionResistancePriority(.required, for: .vertical)

        prefixLabel.font = font
        prefixLabel.numberOfLines = 1
        prefixLabel.isHidden = true
        prefixLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(prefixLabel)

        placeholderLabel.text = placeholder
        placeholderLabel.font = font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 1
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)

        let phLeading = placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor)
        placeholderLeading = phLeading
        NSLayoutConstraint.activate([
            prefixLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            prefixLabel.topAnchor.constraint(equalTo: topAnchor),
            phLeading,
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor)
        ])
        refreshPlaceholder()
    }

    /// Show a coloured priority prefix and inset the editable text so typing
    /// begins after it (keeps the title word at the same x as the row's
    /// "!!! Title"). `nil` clears it.
    func setPriorityPrefix(_ text: String?, color: UIColor?) {
        guard let text, let color else {
            prefixLabel.isHidden = true
            prefixLabel.text = nil
            setLeftInset(0)
            return
        }
        prefixLabel.text = text
        prefixLabel.textColor = color
        prefixLabel.isHidden = false
        // Width of "prefix + space" so the editable text lands exactly where
        // the row renders the title word after the prefix.
        let width = ((text + " ") as NSString)
            .size(withAttributes: [.font: prefixFont]).width
        setLeftInset(width)
    }

    private func setLeftInset(_ left: CGFloat) {
        var inset = textContainerInset
        inset.left = left
        textContainerInset = inset
        placeholderLeading?.constant = left
    }

    func refreshPlaceholder() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    override var text: String! {
        didSet { refreshPlaceholder() }
    }
}
