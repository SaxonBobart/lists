import SwiftUI

private extension VerticalAlignment {
    /// Anchors the row's checkbox to the title's vertical center, even when
    /// body / meta / tag content stacks below the title.
    enum TitleCenterID: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }
    static let titleCenter = VerticalAlignment(TitleCenterID.self)
}

/// One row in a list of items. See design `ListRow` in screens-mobile.jsx.
struct ItemRow: View {
    let item: Item
    let isOverdue: Bool
    let store: ItemStore
    let onToggle: () -> Void
    /// Tapping a habit's ring fires this. Parent views pair it with the
    /// linger pattern so the row hangs briefly before fading out when its
    /// final +1 completes the cycle and "Show Completed" is off.
    var onIncrementHabit: () -> Void = {}
    var indent: Int = 0
    /// The id of the row immediately above this one in the visible flat
    /// sequence, when that row is in the same list as `item`. Used to scope
    /// the leading-swipe Indent action — `nil` means no valid parent above
    /// and the Indent action is hidden.
    var previousSiblingId: UUID? = nil
    /// The `parentId` of the previous row, when present. When that row is
    /// itself a sub-item, indenting this row makes it a sibling at the same
    /// level (parent = previous row's parent) instead of diving one deeper.
    var previousSiblingParentId: UUID? = nil
    /// When true (the default), shows a small "has sub-items" glyph on
    /// parent rows. ListDetailView passes `false` because it renders the
    /// children inline directly beneath the parent — the indicator is for
    /// flat / date-grouped views where children might not be in the same
    /// frame as the parent.
    var showSubItemIndicator: Bool = true
    /// When false, the row shows only its title + leading control + collapse
    /// chevron — no meta line, no notes preview. Move-destination rows use
    /// this so pick targets stay compact; rich metadata would crowd and, at
    /// deep indent, collapse into a one-character-per-line sliver.
    var showMetadata: Bool = true
    /// When the parent view is in multi-select mode, the row swaps
    /// its tap gesture from "open detail" to "toggle selection" and shows
    /// a trailing selection circle. Drag handles are supplied by SwiftUI
    /// via the `.editMode` environment value the parent sets.
    var inSelectMode: Bool = false
    var isSelected: Bool = false
    var onSelectToggle: () -> Void = {}
    /// When true, rows that have sub-items show a tappable trailing chevron
    /// that collapses/expands their children. Off by default; only the
    /// hierarchical list-detail view wires this up.
    var showCollapseControl: Bool = false
    /// Whether this item's sub-items are currently shown. Drives the chevron
    /// rotation. Ignored unless `showCollapseControl` is true.
    var isExpanded: Bool = true
    var onToggleCollapse: () -> Void = {}
    var leadingPadding: CGFloat = ListsDensity.rowPadX
    var trailingPadding: CGFloat = ListsDensity.rowPadX
    /// Parent-owned detail routing. Real app screens provide this so a detail
    /// surface can start shared move mode after dismissing itself. When nil
    /// (previews or isolated row usage), the row falls back to its own sheet.
    var onShowDetail: ((Item) -> Void)? = nil
    /// When provided (hierarchical list-detail host), tapping the row's text
    /// enters inline edit instead of opening the detail sheet. Detail is then
    /// reachable via the editor's blue ⓘ and the "Details" swipe action.
    /// `nil` for plain-`List` hosts (Search / Tags), which keep tap-to-detail.
    var onBeginInlineEdit: ((UUID) -> Void)? = nil
    /// When set, the row is a read-only pick target: the whole row taps to
    /// `onPick(item)`, and the leading control's own taps plus the swipe
    /// actions are neutralized. `nil` = a normal interactive row.
    var onPick: ((Item) -> Void)? = nil
    /// UIKit collection-view hosts provide their own swipe actions. Plain
    /// SwiftUI hosts keep the row's native SwiftUI swipe actions enabled.
    var enablesSwipeActions: Bool = true
    /// Only user-list rows should mutate hierarchy from a leading swipe.
    /// Query surfaces such as Search and Tags keep trailing actions only.
    var enablesHierarchySwipeActions: Bool = true
    /// Query surfaces use this while item move mode is active. The shelf is
    /// still visible, but rows stop opening, toggling, or showing actions until
    /// the user chooses a real destination list or cancels the move.
    var isReadOnly: Bool = false

    @State private var isShowingDetail = false
    /// Drives the event time-editor sheet opened by tapping a (non-completable)
    /// event's calendar glyph.
    @State private var isEditingTime = false

    /// Opens the detail surface — via the parent-owned sheet when wired, else
    /// the row's internal sheet.
    private func showDetail() {
        guard !isReadOnly else { return }
        if let onShowDetail {
            onShowDetail(item)
        } else {
            isShowingDetail = true
        }
    }

    var body: some View {
        if let onPick {
            // Pick mode: the whole row is one tap-to-select target. The leading
            // control's own taps (toggle / open-note / open-time / habit) are
            // hit-disabled and swipe actions suppressed, so the row reads like
            // the real list but only ever selects.
            Button { onPick(item) } label: { rowStack }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).pick")
        } else {
            normalRow
        }
    }

    @ViewBuilder
    private var normalRow: some View {
        rowWithOptionalSwipeActions
            .fullScreenCover(isPresented: $isShowingDetail) {
                if item.type == .habit {
                    HabitDetailView(item: item, store: store)
                } else {
                    ItemDetailSheet(item: item, store: store)
                }
            }
            .sheet(isPresented: $isEditingTime) {
                InlineDateTimePopover(item: item, store: store)
            }
    }

    @ViewBuilder
    private var rowWithOptionalSwipeActions: some View {
        if enablesSwipeActions && !isReadOnly {
            rowStack
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { try? await store.softDelete(item.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                    .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).swipe.delete")

                    Button {
                        Task {
                            var copy = item
                            copy.flagged.toggle()
                            try? await store.update(copy)
                        }
                    } label: {
                        Label(item.flagged ? "Unflag" : "Flag",
                              systemImage: item.flagged ? "flag.slash" : "flag")
                    }
                    .tint(.orange)
                    .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).swipe.flag")

                    Button {
                        showDetail()
                    } label: {
                        Label(item.type == .habit ? "Details" : "Open",
                              systemImage: item.type == .habit ? "info.circle" : "text.document")
                    }
                    .tint(.gray)
                    .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).swipe.details")
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if enablesHierarchySwipeActions, item.parentId != nil {
                        Button {
                            Task {
                                await MainActor.run {
                                    store.applyMoveSync(itemId: item.id, toListId: item.listId, parentId: nil)
                                }
                            }
                        } label: {
                            Label("Outdent", systemImage: "decrease.indent")
                        }
                        .tint(ListsTokens.accent)
                        .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).swipe.outdent")
                    } else if enablesHierarchySwipeActions, let prevId = previousSiblingId {
                        Button {
                            Task {
                                await MainActor.run {
                                    // When the previous row is itself a sub-item, become
                                    // its sibling at the same indent level rather than a
                                    // child of it (one indent makes it a child of the
                                    // previous row's parent; a second indent then nests
                                    // further if the user wants).
                                    store.applyMoveSync(
                                        itemId: item.id,
                                        toListId: item.listId,
                                        parentId: previousSiblingParentId ?? prevId
                                    )
                                }
                            }
                        } label: {
                            Label("Indent", systemImage: "increase.indent")
                        }
                        .tint(ListsTokens.accent)
                        .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).swipe.indent")
                    }
                }
        } else {
            rowStack
        }
    }

    /// The row's visual content — leading control + label + trailing glyphs.
    /// In pick mode the leading control is hit-disabled and the label is not its
    /// own button, so the enclosing pick Button owns every tap.
    private var rowStack: some View {
        HStack(alignment: .titleCenter,
               spacing: ListsSpacing.s3) {
            ItemRowLeadingControl(
                item: item,
                currentCount: currentCount,
                goalPerCycle: liveItem.goalPerCycle,
                cycleProgress: cycleProgress,
                isAtGoal: isAtGoal,
                onToggle: onToggle,
                onShowDetail: showDetail,
                onIncrementHabit: onIncrementHabit,
                onEditEventTime: { isEditingTime = true }
            )
                .allowsHitTesting(onPick == nil && !isReadOnly)
                .accessibilityHidden(onPick != nil)
                .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }

            if onPick == nil {
                if isReadOnly {
                    rowContent
                        .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString)")
                } else {
                    Button(action: {
                        if inSelectMode {
                            onSelectToggle()
                        } else if let onBeginInlineEdit {
                            onBeginInlineEdit(item.id)
                        } else {
                            showDetail()
                        }
                    }) {
                        rowContent
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString)")
                }
            } else {
                rowContent
            }

            if inSelectMode {
                Button(action: onSelectToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? ListsTokens.accent : ListsTokens.Foreground.tertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }
                .accessibilityLabel(isSelected ? "Selected" : "Not selected")
                .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).select")
            }
        }
        .padding(.vertical, ListsDensity.rowPadY)
        .padding(.leading, leadingPadding
                 + CGFloat(min(indent, ListsNesting.maxDisplayDepth)) * ListsNesting.indentStep)
        .padding(.trailing, trailingPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var rowContent: some View {
        HStack(alignment: .titleCenter, spacing: ListsSpacing.s3) {
            VStack(alignment: .leading, spacing: 4) {
                decoratedTitle
                    .font(ListsTypography.body)
                    .lineLimit(showMetadata ? 2 : 1)
                    .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }

                if showMetadata {
                    ItemMetaLine(item: item, isOverdue: isOverdue)

                    if !item.plainTextBody.isEmpty {
                        Text(item.plainTextBody)
                            .font(ListsTypography.subheadline)
                            .foregroundStyle(ListsTokens.Foreground.secondary)
                            .lineLimit(2)
                    }
                }
            }
            // Fill the row's width (up to the trailing glyphs) so the title
            // wraps across the full width instead of truncating at its ideal
            // one-line width, and the note preview runs all the way to the
            // right. Replaces a greedy `Spacer`, which had sized the text block
            // to the title's natural width and squeezed everything narrow.
            .frame(maxWidth: .infinity, alignment: .leading)

            if showSubItemIndicator, hasSubItems {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ListsTokens.Foreground.tertiary)
                    .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }
                    .accessibilityHidden(true)
            }

            // Collapse chevron sits on the far right — right of the flag — in
            // the same 28×28 trailing slot the inline editor's ⓘ occupies, so
            // entering edit just swaps the chevron for the ⓘ without shifting.
            // Glyph is trailing-aligned in the slot so its right edge lands at
            // rowPadX — the same x as the section-header chevron above it.
            if showCollapseControl, hasSubItems {
                Button(action: onToggleCollapse) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 28, height: 28, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }
                .accessibilityLabel(isExpanded ? "Collapse sub-items" : "Expand sub-items")
                .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).collapse")
            }
        }
    }

    /// Plain row title. Priority lives in the metadata/fact strip so the title
    /// text stays stable across list, smart-list, search, and picker surfaces.
    private var decoratedTitle: Text {
        let completed = liveItem.isComplete
        let titleColor: Color = completed
            ? ListsTokens.Foreground.secondary
            : ListsTokens.Foreground.primary
        return Text(item.title).foregroundStyle(titleColor)
    }

    /// True when this item has any non-deleted children — used to render
    /// the small "has sub-items" indicator on the trailing edge of the row.
    private var hasSubItems: Bool {
        store.items.contains { $0.parentId == item.id && $0.deletedAt == nil }
    }

    /// The live item resolved from the observed store, falling back to the
    /// captured snapshot. The collection-view cell only re-reads `item` when
    /// the row appears/disappears, so habit progress must read live state to
    /// reflect intermediate +1s within a cycle.
    private var liveItem: Item {
        store.item(item.id) ?? item
    }

    private var currentCount: Int {
        let live = liveItem
        let key = HabitCycle.key(for: (live.frequency ?? .daily).normalizedForHabit, on: .now)
        return live.completionLog[key] ?? 0
    }

    private var cycleProgress: Double {
        let goal = liveItem.goalPerCycle
        guard goal > 0 else { return 0 }
        return min(1.0, Double(currentCount) / Double(goal))
    }

    private var isAtGoal: Bool {
        currentCount >= liveItem.goalPerCycle
    }

}
