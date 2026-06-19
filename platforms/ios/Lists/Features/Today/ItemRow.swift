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
    /// chevron — no meta line, no notes preview. The Move-to picker uses this:
    /// item rows there are compact pick targets, and the rich detail (whose
    /// tags/meta have no line limit) would crowd and, at deep indent, collapse
    /// into a one-character-per-line sliver.
    var showMetadata: Bool = true
    /// When the parent view is in "Select Reminders" mode, the row swaps
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
    /// UI-1: when the host is a reconfiguring collection-view cell, it provides
    /// this so the detail sheet is owned by the *parent* (above the cell) and
    /// survives the linger timer / any store change reconfiguring the cell. When
    /// nil (plain-`List` hosts like Search/Tags, whose cells aren't destructively
    /// reconfigured), the row falls back to its own internal sheet.
    var onShowDetail: ((Item) -> Void)? = nil
    /// When provided (hierarchical list-detail host), tapping the row's text
    /// enters inline edit instead of opening the detail sheet. Detail is then
    /// reachable via the editor's blue ⓘ and the "Details" swipe action.
    /// `nil` for plain-`List` hosts (Search / Tags), which keep tap-to-detail.
    var onBeginInlineEdit: ((UUID) -> Void)? = nil
    /// When set, the row is a read-only **pick** target (the Move-to picker):
    /// the whole row taps to `onPick(item)`, and the leading control's own taps
    /// plus the swipe actions are neutralized. `nil` = a normal interactive row.
    var onPick: ((Item) -> Void)? = nil

    @State private var isShowingDetail = false
    /// Drives the event time-editor sheet opened by tapping a (non-completable)
    /// event's calendar glyph.
    @State private var isEditingTime = false

    /// Opens the detail surface — via the parent-owned sheet when wired, else
    /// the row's internal sheet.
    private func showDetail() {
        if let onShowDetail {
            onShowDetail(item)
        } else {
            isShowingDetail = true
        }
    }

    var body: some View {
        if let onPick {
            // Pick mode (Move-to picker): the whole row is one tap-to-select
            // target. The leading control's own taps (toggle / open-note /
            // open-time / habit) are hit-disabled and swipe actions suppressed,
            // so the row reads like the real list but only ever selects.
            Button { onPick(item) } label: { rowStack }
                .buttonStyle(.plain)
                .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).pick")
        } else {
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
                    if item.parentId != nil {
                        Button {
                            Task {
                                var copy = item
                                copy.parentId = nil
                                try? await store.update(copy)
                            }
                        } label: {
                            Label("Outdent", systemImage: "decrease.indent")
                        }
                        .tint(ListsTokens.accent)
                        .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).swipe.outdent")
                    } else if let prevId = previousSiblingId {
                        Button {
                            Task {
                                var copy = item
                                // When the previous row is itself a sub-item, become
                                // its sibling at the same indent level rather than a
                                // child of it (one indent makes it a child of the
                                // previous row's parent; a second indent then nests
                                // further if the user wants).
                                copy.parentId = previousSiblingParentId ?? prevId
                                try? await store.update(copy)
                            }
                        } label: {
                            Label("Indent", systemImage: "increase.indent")
                        }
                        .tint(ListsTokens.accent)
                        .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).swipe.indent")
                    }
                }
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
    }

    /// The row's visual content — leading control + label + trailing glyphs.
    /// In pick mode the leading control is hit-disabled and the label is not its
    /// own button, so the enclosing pick Button owns every tap.
    private var rowStack: some View {
        HStack(alignment: .titleCenter,
               spacing: ListsSpacing.s3) {
            leadingControl
                .allowsHitTesting(onPick == nil)

            if onPick == nil {
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
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString)")
            } else {
                rowContent
            }

            if inSelectMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? ListsTokens.accent : ListsTokens.Foreground.tertiary)
                    .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }
                    .accessibilityLabel(isSelected ? "Selected" : "Not selected")
                    .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).select")
                    .onTapGesture { onSelectToggle() }
            }
        }
        .padding(.vertical, ListsDensity.rowPadY)
        .padding(.leading, leadingPadding
                 + CGFloat(min(indent, ListsNesting.maxDisplayDepth)) * ListsNesting.indentStep)
        .padding(.trailing, trailingPadding)
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
                .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).collapse")
            }
        }
    }

    /// Title with a leading `!`/`!!`/`!!!` priority prefix. The prefix uses
    /// a fixed per-level color (traffic-light: yellow / orange / red) so it
    /// stays consistent across every list, independent of the list's tint.
    /// Returns a single `Text` so the prefix wraps with the title rather
    /// than sitting on its own line.
    private var decoratedTitle: Text {
        let completed = liveItem.isComplete
        let titleColor: Color = completed
            ? ListsTokens.Foreground.secondary
            : ListsTokens.Foreground.primary
        return Text(item.title).foregroundColor(titleColor)
    }

    /// True when this item has any non-deleted children — used to render
    /// the small "has sub-items" indicator on the trailing edge of the row.
    private var hasSubItems: Bool {
        store.items.contains { $0.parentId == item.id && $0.deletedAt == nil }
    }

    /// The leading control varies by item type:
    /// - `.task`  → tappable circle / filled checkmark (toggles done)
    /// - `.event` → checkbox when completable, else a calendar glyph that opens
    ///              the time editor (start / end / all-day)
    /// - `.note`  → document glyph that opens the full document view
    /// - `.habit` → tappable progress ring with the current cycle count
    /// All of them anchor to the title's vertical center — the icon sits on
    /// the title line exactly where a task's checkbox does, even when body /
    /// meta lines stack below.
    @ViewBuilder
    private var leadingControl: some View {
        switch item.type {
        case .task:
            checkbox
                .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }
        case .event where item.completable:
            checkbox
                .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }
        case .event:
            eventIcon
        case .note:
            noteIcon
        case .habit:
            habitRing
                .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }
        }
    }

    private var checkbox: some View {
        Button(action: onToggle) {
            Group {
                if item.done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(ListsTokens.accent)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(ListsTokens.Foreground.tertiary)
                }
            }
            .frame(width: 28, height: 28, alignment: .leading)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.done ? "Mark not done" : "Mark done")
        .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).checkbox")
    }

    /// A note's glyph opens its full document view — the note's "page".
    private var noteIcon: some View {
        Button { showDetail() } label: {
            Image(systemName: "text.document.fill")
                .font(.system(size: 22))
                .foregroundStyle(ListsTokens.Foreground.tertiary)
                .frame(width: 28, height: 28, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open note")
        .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).opennote")
    }

    /// Non-completable events: no checkbox — there is nothing to fail at. The
    /// calendar glyph instead opens the time editor (start / end / all-day).
    private var eventIcon: some View {
        Button { isEditingTime = true } label: {
            Image(systemName: "calendar")
                .font(.system(size: 22))
                .foregroundStyle(ListsTokens.Foreground.tertiary)
                .frame(width: 28, height: 28, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit event time")
        .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).eventtime")
    }

    /// When the cycle's count reaches `goalPerCycle`, the ring transitions
    /// into a filled checkmark in the list's accent — the habit can't be
    /// "ticked" any further until the next cycle resets the count.
    private var habitRing: some View {
        Button {
            // Below goal: a tap adds one. At goal: a tap opens the detail
            // view to review/adjust rather than being inert or destructively
            // undoing a multi-per-cycle goal.
            if isAtGoal {
                showDetail()
            } else {
                onIncrementHabit()
            }
        } label: {
            Group {
                if isAtGoal {
                    // Completed habit: the checkmark uses the same blue as a
                    // done task; the badge is a muted-grey clock that reads as
                    // "recurring", signalling the count is reviewable/adjustable
                    // (tapping opens the rich completion view — wired up
                    // separately). Custom symbol (`habit.completed.symbolset`):
                    // checkmark.circle.fill combined with `badge.clock`. Palette
                    // layer order puts the badge first, the checkmark circle
                    // second — hence (secondary, accent).
                    Image("habit.completed")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(ListsTokens.Foreground.secondary, ListsTokens.accent)
                } else {
                    // Base ring is the *same* `circle` glyph as a task's open
                    // checkbox — so diameter, stroke and padding match exactly.
                    // The blue progress is a round-capped arc overlaid on that
                    // ring, sized off the glyph's own rendered frame so it
                    // tracks the ring. The count sits in the middle.
                    ZStack {
                        Image(systemName: "circle")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(ListsTokens.Foreground.tertiary)
                        // Blue progress arc drawn at the `circle` glyph's
                        // measured geometry — 20pt centerline, 1.67pt stroke —
                        // so it overlays the base ring exactly and its round
                        // caps (~0.8pt) are proportional to the ring rather than
                        // overshooting the start/end.
                        Circle()
                            .trim(from: 0, to: cycleProgress)
                            .stroke(
                                ListsTokens.accent,
                                style: StrokeStyle(lineWidth: 1.67, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 20, height: 20)
                        Text("\(currentCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ListsTokens.Foreground.secondary)
                    }
                }
            }
            .frame(width: 28, height: 28, alignment: .leading)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isAtGoal ? "Review habit" : "Increment habit")
        .accessibilityValue("\(currentCount) of \(liveItem.goalPerCycle)")   // A11Y-1(c)
        .accessibilityIdentifier("item.row.\(item.type.rawValue).\(item.id.uuidString).checkbox")
    }

    /// The live item resolved from the observed store, falling back to the
    /// captured snapshot. The collection-view cell only re-reads `item` when
    /// the row appears/disappears, so habit progress must read live state to
    /// reflect intermediate +1s within a cycle.
    private var liveItem: Item {
        store.item(item.id) ?? item   // PERF-1: O(1) lookup
    }

    private var currentCount: Int {
        let live = liveItem
        let key = HabitCycle.key(for: (live.frequency ?? .daily).normalizedForHabit, on: .now)  // MODEL-HABIT-1
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

/// The footnote meta line beneath an item's title — due date (red when
/// overdue), repeat cadence, and tags. Shared by `ItemRow` and the inline
/// editor (`InlineItemEditor`) so an item's date/tags stay visible and pixel-
/// identical while editing in place. Renders nothing when there's no meta.
struct ItemMetaLine: View {
    let item: Item
    let isOverdue: Bool

    var body: some View {
        let hasDateMeta = metaText != nil || Self.endString(for: item) != nil
            || item.recurrence != nil || item.priority != .none || item.flagged
        let hasTags = !item.tags.isEmpty
        if hasDateMeta || hasTags {
            VStack(alignment: .leading, spacing: 2) {
                if hasDateMeta {
                    // One line when it fits; otherwise date+end+repeat on top and
                    // priority/flag below. Each chip stays on one line so a label
                    // like "Every 2 weeks" never wraps mid-word.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            dateChip; endChip; repeatChip; priorityChip; flagChip
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) { dateChip; endChip; repeatChip }
                            HStack(spacing: 6) { priorityChip; flagChip }
                        }
                    }
                    .font(ListsTypography.footnote)
                }
                if hasTags {
                    Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(ListsTypography.subheadline)
                        .foregroundStyle(ListsTokens.tagAccent)
                }
            }
        }
    }

    // MARK: Meta chips — each pinned to one line (`.fixedSize`) so they report
    // their full intrinsic width to `ViewThatFits` and never wrap mid-word.

    @ViewBuilder private var dateChip: some View {
        if let metaText {
            Text(metaText)
                .lineLimit(1).fixedSize()
                .foregroundStyle(isOverdue
                                 ? ListsTokens.Semantic.danger
                                 : ListsTokens.Foreground.secondary)
        }
    }

    @ViewBuilder private var endChip: some View {
        if let end = Self.endString(for: item) {
            Text("→ \(end)")
                .lineLimit(1).fixedSize()
                .foregroundStyle(ListsTokens.Foreground.secondary)
        }
    }

    @ViewBuilder private var repeatChip: some View {
        if let rrule = item.recurrence?.rrule {
            HStack(spacing: 3) {
                Image(systemName: "repeat")
                Text(RepeatPreset.summary(forRRule: rrule)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(ListsTokens.Foreground.secondary)
        }
    }

    @ViewBuilder private var priorityChip: some View {
        if item.priority != .none {
            Text(priorityText)
                .lineLimit(1).fixedSize()
                .foregroundStyle(priorityColor)
        }
    }

    @ViewBuilder private var flagChip: some View {
        if item.flagged {
            Image(systemName: "flag.fill")
                .foregroundStyle(ListsTokens.Semantic.warning)
        }
    }

    /// Apple-Reminders-style date string: relative names for today /
    /// yesterday / tomorrow; short weekday within ±6 days; M/D/YY for
    /// anything else. Appends the time of day when the item isn't all-day.
    /// "Overdue" is signalled by colour (red) at the call site — not here.
    private var metaText: String? { Self.dateString(for: item) }

    private var priorityText: String {
        switch item.priority {
        case .high:   return "!!!"
        case .medium: return "!!"
        case .low:    return "!"
        case .none:   return ""
        }
    }

    private var priorityColor: Color {
        switch item.priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .yellow
        case .none:   return .clear
        }
    }

    /// The date portion of the meta line (no tags). Exposed so the inline
    /// editor can render the same date string beside its editable tag field.
    static func dateString(for item: Item) -> String? {
        guard let due = item.due else { return nil }

        let datePart = shortDate(due)
        if item.dueAllDay {
            return datePart
        }
        let timePart = due.formatted(date: .omitted, time: .shortened)
        return "\(datePart), \(timePart)"
    }

    /// The end-of-span string for an event's meta line — time-only when the
    /// event ends the same day it starts (timed), otherwise a short date.
    /// Mirrors the document view's fact strip. `nil` for non-events or events
    /// without an end. Exposed so the inline editor and document view share one
    /// end formatter.
    static func endString(for item: Item) -> String? {
        guard item.type == .event, let end = item.end else { return nil }
        if let due = item.due,
           Calendar.current.isDate(end, inSameDayAs: due), !item.dueAllDay {
            return end.formatted(date: .omitted, time: .shortened)
        }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: end)
    }

    private static func shortDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInTomorrow(date)  { return "Tomorrow" }
        if cal.isDateInYesterday(date) { return "Yesterday" }

        let startToday = cal.startOfDay(for: .now)
        let startDate  = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: startToday, to: startDate).day ?? 0

        let f = DateFormatter()
        f.locale = Locale.current
        if (-6...6).contains(days) {
            f.dateFormat = "EEE"   // short weekday, e.g. "Mon"
        } else {
            f.dateStyle = .short   // locale-aware M/D/YY
            f.timeStyle = .none
        }
        return f.string(from: date)
    }
}
