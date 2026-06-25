import SwiftUI
import UIKit

private extension VerticalAlignment {
    /// Anchors the editor's checkbox + info button to the title's vertical
    /// center, matching `ItemRow` as the title wraps.
    enum TitleCenterID: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }
    static let titleCenter = VerticalAlignment(TitleCenterID.self)
}

/// SwiftUI content for the dedicated inline-editing cell. Lays out the same
/// leading control + text block + trailing affordance as `ItemRow`, while
/// `InlineEditController` owns the UIKit text views, keyboard toolbar, commit,
/// focus, and sub-editor presentation.
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
    let onBeginMove: (Item) -> Void

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
        onShowDetail: @escaping (Item) -> Void,
        onBeginMove: @escaping (Item) -> Void
    ) {
        self.item = item
        self.store = store
        self.listColor = listColor
        self.indent = indent
        self.leadingPadding = leadingPadding
        self.trailingPadding = trailingPadding
        self.onEndEditing = onEndEditing
        self.onShowDetail = onShowDetail
        self.onBeginMove = onBeginMove
        _controller = State(initialValue: InlineEditController(itemId: item.id, store: store))
    }

    var body: some View {
        HStack(alignment: .titleCenter, spacing: ListsSpacing.s3) {
            leadingControl
                .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }

            VStack(alignment: .leading, spacing: 4) {
                InlineTextField(textView: controller.titleView, revision: titleRevision)
                    .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }
                metaLine
                if !liveItem.plainTextBody.isEmpty {
                    Text(liveItem.plainTextBody)
                        .font(ListsTypography.subheadline)
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if liveItem.type != .note {
                Button {
                    controller.requestShowDetail()
                } label: {
                    Image(systemName: liveItem.type == .habit ? "info.circle" : "text.document")
                        .font(.system(size: 22))
                        .foregroundStyle(liveItem.type == .habit ? ListsTokens.accent : ListsTokens.Foreground.tertiary)
                        .frame(width: 28, height: 28, alignment: .trailing)
                        .offset(x: 8)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }
                .accessibilityLabel(item.type == .habit ? "Details" : "Open")
                .accessibilityIdentifier("inline.editor.info")
            }
        }
        .padding(.vertical, ListsDensity.rowPadY)
        .padding(.leading, leadingPadding
                 + CGFloat(min(indent, ListsNesting.maxDisplayDepth)) * ListsNesting.indentStep)
        .padding(.trailing, trailingPadding)
        .onAppear {
            controller.onEndEditing = onEndEditing
            controller.onShowDetail = { [store, id = item.id] in
                if let live = store.item(id) { onShowDetail(live) }
            }
            controller.onBeginMove = { [store, id = item.id] in
                if let live = store.item(id) { onBeginMove(live) }
            }
            controller.onRevealTagField = { tagFieldRevealed = true }
            controller.onContentChange = { titleRevision &+= 1 }
            controller.beginFocus()
        }
    }

    /// Live item from the store (falls back to the captured snapshot), so the
    /// meta line reflects toolbar edits without reloading the cell.
    private var liveItem: Item { store.item(item.id) ?? item }

    private var isOverdue: Bool {
        liveItem.isOverdue()
    }

    /// Date + repeat (read-only) on one line; editable tag field on the line
    /// below. Keeping them separate prevents the tag field's greedy width from
    /// squeezing the date text until it wraps.
    @ViewBuilder
    private var metaLine: some View {
        let hasDateMeta = ItemFactChips.hasFacts(for: liveItem)
        let showTagField = tagFieldRevealed || !liveItem.tags.isEmpty
        if hasDateMeta || showTagField {
            VStack(alignment: .leading, spacing: 2) {
                if hasDateMeta {
                    ItemFactChips(item: liveItem, isOverdue: isOverdue)
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
            Button { controller.requestShowDetail() } label: {
                Image(systemName: "text.document.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(ListsTokens.Foreground.tertiary)
                    .frame(width: 28, height: 28, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .habit:
            Image(systemName: "circle")
                .font(.system(size: 22))
                .foregroundStyle(ListsTokens.Foreground.tertiary)
                .frame(width: 28, height: 28, alignment: .leading)
        }
    }
}
