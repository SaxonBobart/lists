# iOS Design Rules

In-flight UI rules that govern iOS work. Read this before changing any visible UI in `platforms/ios/Lists/`. When a rule becomes self-evident in the codebase it can be removed from here.

## Calendar

Keep list navigation above a neutral month navigator (leading back chevron) and a native view-symbol menu. Keep named choices and the active view accessibility label in the menu. Both use matching native glass buttons; a noninteractive month/year heading is plain text. The full-width week strip uses compact dates, a tight selected-date circle, and a joined capsule for multi-day ranges. Day view has no extra gray halo. Today retains the list accent; another selected date uses a neutral high-contrast circle. Bottom controls align right: Add nearest the edge, then Today, Overdue and the layout picker. The overdue tray remains available with its badge hidden at zero.

Use compact all-day capsules, single-line day headings, short secondary hour labels centered on thin gridlines, and 18 points before midnight. Events have soft list-colored fills and bright edges; deadlines remain compact markers.

Current time uses white digits in a small red gutter capsule, with a thin red line through today's column and a faint continuation across other columns. Hide a colliding hour label and update at each minute boundary.

Selected events shade their day column and show small white circular handles with colored borders at the top-right and bottom-left. Handles and edges follow raw finger motion; the time label previews quarter-hours and the event snaps only on release. Keep the all-day band's height stable during manipulation so paging cannot shift the timeline beneath the finger.

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

Use a custom `VerticalAlignment.itemTitleCenter` declared at file scope. The outer HStack uses `.itemTitleCenter`; both the checkbox AND `decoratedTitle` set their `.itemTitleCenter` alignmentGuide to their own `VerticalAlignment.center`:

```swift
private extension VerticalAlignment {
    enum ItemTitleCenterID: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }
    static let itemTitleCenter = VerticalAlignment(ItemTitleCenterID.self)
}

HStack(alignment: .itemTitleCenter, spacing: ListsSpacing.s3) {
    checkbox
        .alignmentGuide(.itemTitleCenter) { d in d[VerticalAlignment.center] }
    Button { ... } label: { rowContent }
}

decoratedTitle
    .alignmentGuide(.itemTitleCenter) { d in d[VerticalAlignment.center] }
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

### Document navigation

The document header uses its current compact title/back behavior and persistent
Attachments/More actions. Related Items opens hierarchy navigation through the
document menu. The old centered move-pill detail header is retired; item moves
use the existing shelf.

## Sidebar list tree

Sidebar `My Lists` renders user lists as a collapsible tree. Each row carries a leading 18×30pt chevron column; `SidebarRow`'s `indent` parameter adds 20pt of leading padding per depth level. Leaf rows reserve the same chevron column with an empty spacer so they align with sibling parents.

Collapse state persists across launches via `UserDefaults.standard.stringArray(forKey: "sidebar.collapsed.v1")`. Default is expanded.

### Reordering

There is no sidebar edit/reorder mode. User lists reorder with the normal long-press drag gesture directly on a row. Drag onto a row nests under it, and drag between rows reorders at the chosen hierarchy depth. The same long-press can dwell into the context menu, so the source row is only hidden after the drag actually moves.

The `+` button in the "My Lists" header stays a creation control. It is hidden while item move mode is active, because the sidebar becomes a destination-navigation surface instead of a list-management surface.

## List hierarchy reveal

List, Columns and Calendar expose Browse sub-lists beside the overflow menu.
The shared hierarchy reveal sits above the entire navigation container, reuses
Home rows and persisted collapse state, and keeps the mounted list in place.
A deliberate pull from the top or the toolbar opens it; Done, the toolbar or
keyboard editing closes it. Do not restore the old embedded Sub-Lists section.

List rows, section headers, inline editing and drop cues retain the shared
leading inset aligned with the navigation title.

## Columns (list detail)

Columns remain full-height drop targets even when empty, but their surfaces
should recede into the app background rather than fill most of the screen with
opaque grouped grey. Use a near-background translucent semantic fill plus a
hairline separator border to preserve the column boundary in both appearances.

Column item rows use a compact 3pt vertical inset with a 44pt minimum touch
height. The ordinary full-width List presentation keeps its normal 10pt row
inset; compacting Columns must not change List density.

The board, large list title, column surfaces, and section headers do not move
vertically. Only the clipped item area below the touched column header scrolls;
each column keeps its own vertical position. Horizontal scrolling and gentle
column snapping remain shared by the board.

When a column has a positive retained vertical offset, its fixed section header
shows a one-device-pixel hairline along its bottom edge using the adaptive system
separator color. The divider belongs to that column—not the navigation title—and
is absent when the column is at its top.

Columns always keep a springy vertical rubber-band interaction, including when
their items fit inside the viewport. Rubber-band displacement belongs only to
the touched column and must never move or collapse the fixed list title or
section header.

Sub-list navigation is a compact toolbar control beside the ellipsis in List,
Columns and Calendar. The hierarchy is tucked above the whole navigation
container, including its title; reveal pushes the primary screen downward.
Reuse Home SidebarListCellContent rows and independent collapse/expand controls.
Only a deliberate pull from the top reveals during list scrolling; explicit
the toolbar control remains available in every view. A thin separator divides
the revealed hierarchy from the main screen. The revealed Sub-lists Done button uses native Liquid Glass. Closing retains
the mounted content.
Honor Reduce Motion, safe areas, keyboard editing and existing Calendar gestures.
Columns and Calendar use compact, fixed navigation titles.

## Item move mode (list detail)

Moving an item is an in-place list mode, not a modal picker. It starts only from an explicit Move action such as the row leading swipe, a menu or toolbar action, the inline editor parent button, or the detail hierarchy title. Ordinary List and Columns drags remain local reorder/nesting gestures and do not reveal the shelf. Starting move mode:

- hides the moving item and its descendants from destination rows;
- shows a `None` row at the top of the current list, meaning "top-level in this list";
- turns every valid item row into a compact parent pick target;
- temporarily shows collapsed sections and the full item hierarchy instead of honoring collapsed section/item state;
- disables row swipe/context/drag affordances and hides floating add buttons, view-option menus, sidebar search/settings controls, and tag-management context menus;
- parks the moving item in the bottom shelf owned by `SidebarView`, so it remains active while navigating to another list.

Picking a row sets that item as the parent and inherits the parent's section. Picking `None` clears the parent in the current list. If that list is unchanged, the item keeps its current section; cross-list moves with no parent clear list-scoped section ids. Cross-list moves under a destination parent inherit that destination parent's section. All moves cascade the resulting list/section to descendants through `ItemStore.applyMoveSync`. A child moved to another list without its parent becomes top-level in the destination. The moving item and its descendants must never be valid parent targets.

Document pages keep their breadcrumb title for navigation. The overflow Organization menu exposes Parent / Move so this remains reachable without structural metadata in the document body.

## Colors

When matching an iOS color, first try a semantic system color (`.secondaryLabel`, `.systemGrayN`, `.systemFill`, `.tertiarySystemBackground`, etc). Only fall back to a custom hex if no semantic fits — the semantic colors adapt correctly to light/dark mode and dynamic type for free.

## Confirm ticks

The primary "done / save / confirm" action in a toolbar is a **filled accent circle** with a white checkmark: `.buttonStyle(.borderedProminent)` + `.buttonBorderShape(.circle)` + `.tint(ListsTokens.accent)`, white semibold `checkmark`. It reads as a distinct, "separated" primary action next to the plain glyph buttons (ⓘ, ⋯, back). Used by the inline editor done (`inline.editor.done`), the document page (`document.done` hide-keyboard), quick-capture add, and the markdown editor done. Plain accent-tinted checkmarks stay only as *selection* indicators inside pickers — those are not buttons.

The document page's `document.done` (hide-keyboard) tick only appears while a field on the page holds the keyboard — hidden when nothing is focused, like the inline editor's Done on the list screens (driven by keyboard show/hide observation, no inset handling).

## Event date/time editor

An event's schedule uses the Apple Calendar pattern, not the task Date/Time toggles: **Starts** and **Ends** rows each show a compact date pill, plus a time pill unless **All Day** is on; the All Day toggle drops the time component (`displayedComponents` `[.date]` vs `[.date, .hourAndMinute]`). Start and end are mandatory for events; shared defaults and loaded-data repair belong in `EventDefaults.normalize`.

Event creation and editing both expose start and end. Inline document scheduling (`DocumentScheduleProperties`) and quick capture (`QuickCaptureEventScheduleRows`) use the same event defaults and range rules. Selecting Event always seeds a start and end; its scheduling controls do not use task-style Date/Time on-off switches.

## Sections

### Creating a section — inline, no alert

"New Section" (list overflow → Manage Sections) does **not** pop a text-field alert. It creates the section with a placeholder name and drops straight into renaming its header **in place** — a focused text field with the keyboard up (placeholder shows the seeded "New Section"; an empty commit just keeps it). Implemented as a dedicated `.editingSectionHeader` diffable row (mirrors the `.editingItem` inline-item pattern) driven by `editingSectionKey`. The same `CVSectionHeaderRow` still supports tap-to-rename on a static header.

### A child's section always equals its parent's

Sub-items render under their parent regardless of their own `section`, so the invariant is **child.section == parent.section**. Inheritance is set at creation (nest-into) and maintained on every move-to-section / move-under-parent path: moving a parent cascades the new section to its whole subtree (`ItemStore.applyMoveSync` or `ItemStore.applySectionCascadeSync`). A direct detail edit that would put a child in a different list from its parent clears the parent instead of storing a cross-list hierarchy. Skipping the cascade is a data-loss bug — descendants keep the OLD section id and get soft-deleted when that section is deleted, even though they visually moved. Covered by `CrossListMoveTests.testMoveParentBetweenSectionsCarriesSubtreeAndSurvivesOldSectionDelete`.

## Document properties

The document has one fixed, icon-only rail beneath its title/tags: Date & time,
Flag, Priority, Tags, Move, Type, plus. Use 44-point targets. On narrow layouts,
Move/Type go in More; the rail never scrolls or clips controls. Scheduling is
blue when configured; Flag is neutral when off and orange when on. Priority
is neutral when unset and yellow/orange/red for low/medium/high. Keep labels
and values available to accessibility. Retain the body's Markdown accessory.

Saved tags use plain text and reveal an editor on request. Empty tags collapse
when editing ends; removing the last tag while typing keeps the editor focused.

Plus opens one compact creation sheet directly. Property names, type symbols
and values align in plain rows. Text/number/URL edit inline, checkboxes toggle
inline, and date/select/multi-select use one contextual selector with live
changes. Preserve invalid or failed input beside its Retry action. Table cells
use the same controls and retain drafts while scrolled out of view.

Table uses task checkboxes, event symbols and plain document titles. Header
symbols identify each property type. Its native scroll container disables
bouncing on both axes; columns and rows remain scrollable within content bounds.
Keep hierarchy disclosure separate from the leading item control.

Search uses the native SwiftUI search field, clear/cancel controls and explicit
system dictation. Keep focused search at the top with
`.navigationBarDrawer(displayMode: .always)` and scoped native navigation-item
placement that disables toolbar integration. Let the system determine symbol sizes, font and spacing;
verify the actual navigation/keyboard context against the supplied Siri images.

### Document editor completion

The top bar leaves its title empty at the top of a document; there is no generic
“Note” label. Once the document title scrolls away, show a leading, single-line,
truncating title beside Back. Reserve room for Attachments, More, and the editing
checkmark at all widths. Local media stays in the body flow with stable cards;
web/document links remain inline text. Blank source paragraphs use compact
spacing in Live mode without changing the established table handle lane.
Recording controls must remain visible inside document sheets as well as on
the library root.

## Calendar item editing

Use one clipped rounded shape for event fill and accent strip, with a flat inner
strip edge and an inset selection stroke. Never extend the event frame beyond its
time bounds. Timed tasks use a minimum 44-point tinted row with a completion circle
and exact time; scale the row with accessibility text. Shared native item menus use
a medium three-action Details / Flag / Delete header. The timeline uses the native
compact edit bar and system overflow; menu dismissal must not deselect its handles.

Collection files and items share the 28pt glyph column with 44pt hit areas and title-center alignment. Attachment rows use the same file row content in a full-screen browser. Horizontal action rails use colored capsules with labels beneath and a centered rounded row background; both row types retain their existing actions.
