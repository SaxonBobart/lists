# iOS Design Rules

In-flight UI rules that govern iOS work. Read this before changing any visible UI in `platforms/ios/Lists/`. When a rule becomes self-evident in the codebase it can be removed from here.

## Item rows (`platforms/ios/Lists/Features/Today/ItemRow.swift`)

### Priority in the meta line

Priority renders in the row's metadata/fact strip as `!`/`!!`/`!!!`, not as a title prefix, toolbar icon, badge, or coloured pip. This keeps the title text stable while still making priority visible beside date, repeat, flag, and tags.

| Level  | Glyph | Color    |
|--------|-------|----------|
| low    | `!`   | `.yellow` |
| medium | `!!`  | `.orange` |
| high   | `!!!` | `.red`    |

The colour is **fixed per level across all lists** — do not use the parent `.tint` / `.accentColor`. When `priority == .none`, render nothing — no spacer, no placeholder.

Implementation: `ItemFactChips.priorityChip` owns the glyph and colour. Row titles stay plain except for completed-item colour.

### Checkbox alignment — title-centered

The checkbox is vertically centered with the **title only**, not the full row (which stacks body, meta, and tag chips beneath).

Use a custom `VerticalAlignment.titleCenter` declared at file scope. The outer HStack uses `.titleCenter`; both the checkbox AND `decoratedTitle` set their `.titleCenter` alignmentGuide to their own `VerticalAlignment.center`:

```swift
private extension VerticalAlignment {
    enum TitleCenterID: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }
    static let titleCenter = VerticalAlignment(TitleCenterID.self)
}

HStack(alignment: .titleCenter, spacing: ListsSpacing.s3) {
    checkbox
        .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }
    Button { ... } label: { rowContent }
}

decoratedTitle
    .alignmentGuide(.titleCenter) { d in d[VerticalAlignment.center] }
```

`.firstTextBaseline` does NOT work — it anchors to the title's descender, not its visual center. `.center` on the outer HStack re-anchors to whole-row content. `.top` puts the checkbox above the title's midpoint.

### Completed-item styling

Done items render as **muted secondary title text + filled blue checkbox — no strikethrough**. This deliberately differs from Apple Reminders because strikethrough reads as visually noisy in Lists.

Do not add `.strikethrough(item.done, ...)` anywhere a done item is rendered.

### Completion Linger

When **Show Completed is off** and the user checks an item, the row stays visible ~1.5s then fades away (0.4s ease-in-out). The code calls this `Linger`; the behavior gives the user a beat to see what just happened.

Implementation: `lingeringIds: Set<UUID>` state + `toggleAndLinger(_:)` method on the list view. Apply this pattern to any new checkable list view that filters out done items (Today, smart lists, search results) — completion shouldn't feel like the row got yanked.

## Tags

### Inline display (item rows, detail sheet) — plain text

```swift
Text(item.tags.map { "#\($0)" }.joined(separator: " "))
    .foregroundStyle(ListsTokens.tagAccent)
```

No capsule, no padding, no background. `ListsTokens.tagAccent` is the dusty purple-blue `#6A84B8` — also the hue of the Tags pseudo-list icon, so inline tags read as the same "tag" thing.

### Chip-style — only in `TagsOverviewView`

Chips (capsule with background) appear **only** in the Tags overview's filter cloud, because there they're interactive filter pills (tap to select / multi-select intersection). Nowhere else.

### Input

Tags are metadata, not title or Markdown syntax. Add and remove them through the tag field / tag toolbar button, which writes `item.tags` directly. A literal `#word` in a title or document body stays user text and does not affect the Tags smart list, tag counts, or future custom smart-list predicates.

## Sheet headers — plain glyphs, no `.circle.fill`

For modal sheet headers (New Item, New List, Edit List, Edit Lists, etc.), use plain `xmark` (dismiss) and `checkmark` (commit) SF Symbols. iOS 26's toolbar renders a Liquid-Glass pill behind each ToolbarItem button — using `.circle.fill` variants creates a double-circle effect.

```swift
.toolbar {
    ToolbarItem(placement: .topBarLeading) {
        Button { dismiss() } label: {
            Image(systemName: "xmark").accessibilityLabel("Cancel")
        }
    }
    ToolbarItem(placement: .topBarTrailing) {
        Button { save() } label: {
            Image(systemName: "checkmark").accessibilityLabel(existing == nil ? "Add" : "Save")
        }
        .disabled(...)
    }
}
```

Rules:
- New sheet → leading `xmark`, trailing `checkmark`.
- Dismiss-only sheet (live-apply) → trailing `checkmark` alone.
- Don't use `+` (`plus`) on a commit button — `checkmark` is the universal commit glyph.
- Don't substitute text labels ("Cancel" / "Save" / "Done") — the icon is the button.
- No `.font(.title2)`, `.foregroundStyle(.secondary)`, `.buttonStyle(.plain)`, etc. — let SwiftUI defaults handle styling.
- Overflow / menu buttons: plain `ellipsis`, never `ellipsis.circle`.

### Detail-sheet principal title — move pill only when in a hierarchy

The principal (center) title of a detail/edit sheet reflects where the item sits in the item hierarchy. Three states, shared by item and habit detail via `DetailSheetHeaderTitle`:

- **sub-item** (has a parent) → glass-capsule pill with the parent title; tap starts item move mode when the screen has a move shelf available.
- **parent** (has children) → glass-capsule pill `Move`; tap starts item move mode when the screen has a move shelf available.
- **standalone** (no parent, no children) → plain title text (`Edit Item` / `Edit Habit`) — **no capsule, no icon**. Use the nav-title style (`ListsTypography.headline` + `ListsTokens.Foreground.primary`).

The capsule is reserved for the hierarchy/move affordance; a standalone item has nowhere to move from, so it must not render a pill. Screens outside the shared move-session navigation hide hierarchy move controls rather than showing a separate picker.

## Sidebar list tree

Sidebar `My Lists` renders user lists as a collapsible tree. Each row carries a leading 18×30pt chevron column; `SidebarRow`'s `indent` parameter adds 20pt of leading padding per depth level. Leaf rows reserve the same chevron column with an empty spacer so they align with sibling parents.

Collapse state persists across launches via `UserDefaults.standard.stringArray(forKey: "sidebar.collapsed.v1")`. Default is expanded.

### Reordering

There is no sidebar edit/reorder mode. User lists reorder with the normal long-press drag gesture directly on a row. Drag onto a row nests under it, and drag between rows reorders at the chosen hierarchy depth. The same long-press can dwell into the context menu, so the source row is only hidden after the drag actually moves.

The `+` button in the "My Lists" header stays a creation control. It is hidden while item move mode is active, because the sidebar becomes a destination-navigation surface instead of a list-management surface.

## Sub-Lists section (list detail)

When a list has children, list detail renders a collapsible `Sub-Lists` section above its items. Header is footnote/secondary with a leading chevron (`chevron.down` expanded / `chevron.right` collapsed). Default state is expanded; per-list-view state, not persisted. Empty-state only triggers when both items and child lists are empty.

Child row: circular `IconBadge` · list name · open-item count in `ListsTypography.mono`/secondary · the implicit `NavigationLink` chevron. Trailing swipe: Delete only.

List-detail body content aligns to the large navigation title leading edge. Section headers, Sub-Lists rows, item rows, inline editor rows, and drag/drop placement cues share the same list-detail leading inset.

## Item move mode (list detail)

Moving an item is an in-place list mode, not a modal picker. It can start from the row leading swipe Move action, the inline editor parent button, the detail/habit hierarchy title, or by dragging a user-list row onto the bottom move shelf. Starting move mode:

- hides the moving item and its descendants from destination rows;
- shows a `None` row at the top of the current list, meaning "top-level in this list";
- turns every valid item row into a compact parent pick target;
- temporarily shows collapsed sections and the full item hierarchy instead of honoring collapsed section/item state;
- disables row swipe/context/drag affordances and hides floating add buttons, view-option menus, sidebar search/settings controls, and tag-management context menus;
- parks the moving item in the bottom shelf owned by `SidebarView`, so it remains active while navigating to another list.

Picking a row sets that item as the parent and inherits the parent's section. Picking `None` clears the parent in the current list. If that list is unchanged, the item keeps its current section; cross-list moves with no parent clear list-scoped section ids. Cross-list moves under a destination parent inherit that destination parent's section. All moves cascade the resulting list/section to descendants through `ItemStore.applyMoveSync`. A child moved to another list without its parent becomes top-level in the destination. The moving item and its descendants must never be valid parent targets.

Document pages keep their breadcrumb title for navigation. Their Details sheet still uses the move-aware header when possible, and also exposes a normal `Parent` row in the Details card for the same action so the move path is reachable as a standard control.

## Colors

When matching an iOS color, first try a semantic system color (`.secondaryLabel`, `.systemGrayN`, `.systemFill`, `.tertiarySystemBackground`, etc). Only fall back to a custom hex if no semantic fits — the semantic colors adapt correctly to light/dark mode and dynamic type for free.

## Confirm ticks

The primary "done / save / confirm" action in a toolbar is a **filled accent circle** with a white checkmark: `.buttonStyle(.borderedProminent)` + `.buttonBorderShape(.circle)` + `.tint(ListsTokens.accent)`, white semibold `checkmark`. It reads as a distinct, "separated" primary action next to the plain glyph buttons (ⓘ, ⋯, back). Used by the inline editor done (`inline.editor.done`), the document page (`document.done` hide-keyboard + `document.details.done`), habit save, quick-capture add, and the markdown editor done. Plain accent-tinted checkmarks stay only as *selection* indicators inside pickers — those are not buttons.

The document page's `document.done` (hide-keyboard) tick only appears while a field on the page holds the keyboard — hidden when nothing is focused, like the inline editor's Done on the list screens (driven by keyboard show/hide observation, no inset handling).

## Event date/time editor

An event's schedule uses the Apple Calendar pattern, not the task Date/Time toggles: **Starts** and **Ends** rows each show a compact date pill, plus a time pill unless **All Day** is on; the All Day toggle drops the time component (`displayedComponents` `[.date]` vs `[.date, .hourAndMinute]`). Start and end are mandatory for events; shared defaults and loaded-data repair belong in `EventDefaults.normalize`.

This is identical in **both** places an event is scheduled: the document Details sheet (`DocumentScheduleCard`) and the quick-capture / New Item sheet (`QuickCaptureEventScheduleRows`) both use the shared `EventDateRows`. Quick-capture's event branch deliberately drops the task-style Date/Time on-off toggles, the wheel picker, and the Time Zone row — selecting Event always seeds a start + end. Keep the two in sync: event creation and event editing must look the same.

## Sections

### Creating a section — inline, no alert

"New Section" (list overflow → Manage Sections) does **not** pop a text-field alert. It creates the section with a placeholder name and drops straight into renaming its header **in place** — a focused text field with the keyboard up (placeholder shows the seeded "New Section"; an empty commit just keeps it). Implemented as a dedicated `.editingSectionHeader` diffable row (mirrors the `.editingItem` inline-item pattern) driven by `editingSectionKey`. The same `CVSectionHeaderRow` still supports tap-to-rename on a static header.

### A child's section always equals its parent's

Sub-items render under their parent regardless of their own `section`, so the invariant is **child.section == parent.section**. Inheritance is set at creation (nest-into) and maintained on every move-to-section / move-under-parent path: moving a parent cascades the new section to its whole subtree (`ItemStore.applyMoveSync` or `ItemStore.applySectionCascadeSync`). A direct detail edit that would put a child in a different list from its parent clears the parent instead of storing a cross-list hierarchy. Skipping the cascade is a data-loss bug — descendants keep the OLD section id and get soft-deleted when that section is deleted, even though they visually moved. Covered by `CrossListMoveTests.testMoveParentBetweenSectionsCarriesSubtreeAndSurvivesOldSectionDelete`.

## Live-apply detail sheets — Cancel restores, tick keeps

The document page's **Details** sheet live-applies edits as you change them (no separate save step). So it carries a leading **✕ Cancel** that restores a snapshot captured when the sheet opened (`detailsSnapshot`), and a trailing accent-tick that keeps the edits. Any sheet that live-applies onto a `draft` should follow this snapshot-on-open / restore-on-cancel pattern rather than leaving the user no way back.
