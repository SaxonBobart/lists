# List view: flat background + swipe actions

**Date:** 2026-05-10
**Scope:** iOS — `ListDetailView` chrome change, plus swipe actions on every items view (`ListDetailView`, `TodayView`, `SmartListScreen`, `SearchResultsView`, `TaggedItemsView`).

## Goal

Two changes to how lists of items look and behave:

1. Drop the iOS "card on gray" inset-grouped chrome inside a single list. The list's detail view should be a flat black (dark mode) or flat white (light mode) page.
2. Add row-level swipe actions on every items view, matching iOS conventions: trailing swipe for Details / Flag / Delete, leading swipe for Indent (or Outdent when already nested).

## Behavior changes

### 1. Flat background in `ListDetailView`

| Before | After |
|---|---|
| `Color(.systemGroupedBackground)` background | `Color(.systemBackground)` background |
| `.listStyle(.insetGrouped)` | `.listStyle(.plain)` |
| Section headers render inset with the grouped card | Section headers render flush, with the existing all-caps secondary footnote styling |

The `.scrollContentBackground(.hidden)` modifier stays so our `Color` shows through. Empty-state appearance is unchanged.

`TodayView`, `SmartListScreen`, `SearchResultsView`, and `TaggedItemsView` are not changed in this spec — their backgrounds stay as they are today.

### 2. Trailing swipe (right→left) — every items view

Three actions, in this on-screen order from row body outward to the trailing edge:

1. **Details** (gray / `.gray`)
   - Icon: `info.circle`
   - Action: opens the same detail sheet that tapping the row opens (`ItemDetailSheet`, or `HabitDetailView` for habits). Tapping the row continues to work the same way; the swipe is just an alternate path.
2. **Flag / Unflag** (orange / `.orange`)
   - When `item.flagged == false`: label "Flag", icon `flag`. Tapping toggles `flagged = true`.
   - When `item.flagged == true`: label "Unflag", icon `flag.slash`. Tapping toggles `flagged = false`.
3. **Delete** (red / `.red`, destructive, full-swipe)
   - Icon: `trash`
   - Action: `await store.delete(item.id)` — soft delete, sets `deletedAt`. Item leaves the visible list; recoverable via Trash later (existing behavior).
   - This is the full-swipe action: dragging all the way across the row triggers Delete without needing to release on the button.

### 3. Leading swipe (left→right) — every items view, contextual

A single contextual action depending on the row's current parent state:

- **Indent** (accent / `ListsTokens.accent`)
  - Icon: `increase.indent`
  - Shown only when **there is a valid previous row in the same list**. "Same list" means the row immediately above in the currently rendered flat row sequence has `listId == item.listId`. If the previous row is in a different list (possible in Today / Smart / Search / Tagged), or there is no previous row, no leading swipe action is shown.
  - Action: sets `item.parentId` to the previous row's id, then persists via `store.update(item)`. The item visually becomes a sub-item under the row above.
  - Guard: never set `parentId` to a descendant of `item` (would create a cycle). In practice the previous-row constraint already prevents this, but the implementation must defensively short-circuit if the candidate parent is `item.id` or any descendant.

- **Outdent** (accent / `ListsTokens.accent`)
  - Icon: `decrease.indent`
  - Shown only when `item.parentId != nil` (the row is currently a child).
  - Action: clears `parentId` (`item.parentId = nil`), persists via `store.update(item)`. Item promotes back to top level inside its list.

Indent and Outdent are mutually exclusive — the row shows whichever applies, never both. If neither applies (top-level row, no valid previous-row parent), the leading swipe shows nothing.

## Architecture

### Where the swipe modifier lives

`ItemRow` (`platforms/ios/Lists/Features/Today/ItemRow.swift`) is the shared row view used by every items view. The swipe modifier lives directly on `ItemRow`'s body so all five views inherit it without per-call-site wiring.

`ItemRow` already has `store: ItemStore` and `item: Item`. To support the contextual Indent action, it gains one new optional input:

```swift
var previousSiblingId: UUID? = nil
```

This is the id of the row immediately above in the same visible flat list, or `nil` if this is the first row, or if the previous row is in a different list. Each call site computes this when flattening rows for `ForEach`.

### Computing `previousSiblingId` per view

- **`ListDetailView`**: in `flatten(_:)` (line 151), zip each row with its predecessor in the flattened sequence. The predecessor is always in the same list (since `ListDetailView` filters by `list.id`), so `previousSiblingId` is just the prior row's id, or `nil` for index 0 in the section.
- **`TodayView`, `SmartListScreen`, `SearchResultsView`, `TaggedItemsView`**: each builds a flat array of items for `ForEach`. At the call site, pass `previousSiblingId = previous.listId == current.listId ? previous.id : nil`. For the first row in any section, pass `nil`.

The "same section" question only matters in `ListDetailView` where sections are real groupings. Crossing a section header in `ListDetailView`'s flatten resets the predecessor to `nil` for the first row of the new section. In Today/Smart/Search/Tagged, sections are visual buckets (Overdue / Today / Upcoming, etc.) — for the indent gesture we treat them the same way: the first row of each section block has `previousSiblingId = nil`.

### Swipe action implementation in `ItemRow`

Inside the `ItemRow` body, after the existing `.sheet` modifier:

```swift
.swipeActions(edge: .trailing, allowsFullSwipe: true) {
    Button(role: .destructive) {
        Task { try? await store.delete(item.id) }
    } label: { Label("Delete", systemImage: "trash") }

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

    Button {
        isShowingDetail = true
    } label: { Label("Details", systemImage: "info.circle") }
    .tint(.gray)
}
.swipeActions(edge: .leading, allowsFullSwipe: false) {
    if item.parentId != nil {
        Button {
            Task {
                var copy = item
                copy.parentId = nil
                try? await store.update(copy)
            }
        } label: { Label("Outdent", systemImage: "decrease.indent") }
        .tint(ListsTokens.accent)
    } else if let prevId = previousSiblingId {
        Button {
            Task {
                var copy = item
                copy.parentId = prevId
                try? await store.update(copy)
            }
        } label: { Label("Indent", systemImage: "increase.indent") }
        .tint(ListsTokens.accent)
    }
}
```

Order of buttons in the trailing block reflects iOS rendering: the first button declared sits closest to the trailing edge (Delete, full-swipe-default), with subsequent buttons (Flag, Details) layering inward toward the row body.

### Store calls used

All actions use existing `ItemStore` methods — no new APIs:

- `store.delete(_:)` — soft delete
- `store.update(_:)` — persists toggled `flagged` and changed `parentId`

## Edge cases

- **Indenting an item that already has children:** allowed. The item becomes a child of the row above, and its own children remain its children (the tree depth increases by one). The flatten passes in `ListDetailView` already render up to grandchild depth (lines 151–163); deeper nesting will visually clip at indent level 2 today. That's the existing limitation and not in scope here.
- **Indenting under a row that is itself a child:** allowed. The new parent is whatever row sits directly above visually, regardless of whether that row is top-level or a child.
- **Outdenting a row whose parent has other children:** the row promotes to top level alongside its former parent; the parent's other children are unaffected.
- **Deleting a parent with children:** existing `store.delete` behavior. Children become orphans (their `parentId` still points at a now-soft-deleted parent). This matches today's behavior; not changed by this spec.
- **Flag toggle on a habit:** habits use the same `Item` model and the `flagged` field is valid on them; the swipe works the same.
- **Section drop-targets in `ListDetailView`:** the FAB drag-to-section gesture and row swipe gestures don't conflict — SwiftUI dispatches them based on hit-testing the row vs. dragging from the FAB.

## Out of scope

- Trash UI / restoring deleted items (already exists).
- Visual rendering of indent depth beyond what's already supported (level 0–2).
- Reordering rows by drag (not requested).
- Changing backgrounds in Today / Smart / Search / Tagged.
- New store APIs.

## Test plan

Manual verification on iPhone 17 Pro simulator:

1. Open a list with at least 5 items including one with sub-items.
2. Verify the background is flat black in dark mode and flat white in light mode — no card surround.
3. Trailing-swipe a top-level row partially → see Details / Flag / Delete buttons.
4. Tap Flag → row shows the flag indicator on the right; trailing-swipe again → label is now "Unflag" with `flag.slash` icon.
5. Trailing-swipe full → row deletes (soft).
6. Leading-swipe the second row in a section → Indent appears; tap → row becomes a sub-item under the first row.
7. Leading-swipe that now-indented row → Outdent appears; tap → row promotes back.
8. Leading-swipe the first row of a section → no leading action appears.
9. Open Today view: leading-swipe a row whose predecessor is in a different list → no leading action appears. Trailing swipe still works.
10. Repeat (9) on Smart Lists, Search, Tags.
