# Current Status

## Active Work

The active implementation is the iOS app in `platforms/ios/`.

Work should happen on `dev`. Keep `main` stable.

## Environment: Xcode 27 beta (since 2026-06-10)

Saxon has moved all devices and daily work to the Xcode 27 / OS 27 betas
(no rollback planned). Toolchain verified end-to-end on the Lists app
2026-06-11; background in `docs/research/xcode-27-agentic-testing.md`:

- **UI driving goes through Apple's native agent loop** (`xcrun
  mcpbridge`, the `xcode` MCP): `DeviceInteractionStartSession` →
  `DeviceInteractionInstallAndRun` → `DeviceInteractionSynthesize` →
  `DeviceInteractionEndSession`. Verified working from external agents:
  tap, type, swipe, and capture all pass; every Synthesize call returns
  a screenshot + UI hierarchy (frames, center coordinates, our
  accessibility ids) + the app's cumulative console log. Apple's
  pattern: interactions run in a subagent following the
  `device-interaction` skill (`xcrun mcpbridge run-agent skills export
  --output-dir <absolute path>`). Needs Xcode running with the project
  open; ~5–15 s per Synthesize call.
- **XcodeBuildMCP (v2.6.2)** stays the build driver: build / test /
  install / launch / `screenshot` work. The AXe-based UI tools
  (`snapshot_ui`, `tap`, `swipe`, `gesture`, `type_text`) are broken —
  SimulatorKit.framework moved to `Contents/SharedFrameworks/` and AXe
  hardcodes the old path (getsentry/XcodeBuildMCP#446 closed
  not-planned; AXe v1.7.1 has no fix). A symlink at the old path would
  likely revive AXe but tampers with the signed Xcode bundle — skipped
  while Apple's loop covers the same ground. Re-check releases
  occasionally.
- **Simulators:** only OS-27 runtimes remain; the session default
  (iPhone 17 Pro) already points at an iOS 27.0 device. Simulator.app
  no longer exists — Device Hub is the simulator GUI.
- **Adaptive layout matters on iOS now:** Device Hub adds dynamic
  simulator resizing (foldable-prep). Avoid fixed-size/orientation
  assumptions in new iOS UI; resize-test new screens in Device Hub.
- Gesture XCUITests are frozen smoke coverage only (see AGENTS.md
  "Reality check") — verify interactions via a driven session.

## What Exists

- SwiftUI app project: `platforms/ios/Lists.xcodeproj`
- XcodeGen spec: `platforms/ios/project.yml`
- XcodeBuildMCP defaults: `.xcodebuildmcp/config.yaml`
- Core models, file storage, frontmatter codec, sample data, smart lists, tags, reminders, and notification scheduling
- Item types: task, habit, note, and (since 2026-06-11) **event** — start +
  optional end + completable, calendar-shaped. Events are creatable from the
  quick-capture sheet (Event segment) and editable in the document page
  (Starts / Ends / Checkbox controls). See PRODUCT-SPEC "Events".
- Main screens for sidebar, today, smart lists, list detail, item detail, quick capture, habits, search, settings, recently deleted, tags, and thread view
- Test targets `ListsTests` (XCTest + swift-snapshot-testing, 198 tests; snapshot baselines recorded on the iOS 27 runtime) and `ListsUITests` (XCUITest scaffolding, 8 classes)

## Backend audit — CLOSED 2026-06-11

Every finding from `audit/backend-audit-2026-05-30.md` is now fixed (the
2026-05-30 pass closed 3; this pass closed the rest — reminders, recurrence
edge cases, habit-math consistency, write ordering, unmapped-list recovery,
the inflated "All" count, all-day date drift). Details + verification in
`audit/fixes-applied-2026-06-11.md`.

## Markdown editor — rebuilt 2026-05-13

The full coordinator + editor view was reset on this branch and
rebuilt under TDD. Pre-fix `MarkdownTextView.swift` (920 LOC,
zero unit tests) is preserved verbatim in the
`editor-archive-2026-05-13` worktree at
`/Users/saxon/Developer/Projects/lists-editor-archive`.

The replacement is a glue-only `MarkdownTextView.swift` (~110 LOC)
plus focused pure-transform modules under
`platforms/ios/Lists/Features/MarkdownEditor/`:

- `EditorIntent.swift` — tagged enum + `apply(to:selection:)` dispatch
- `ListContinuation.swift` — smart Return (bullet / numbered / task
  / blockquote / nested-indent continuation; empty-marker exit)
- `IndentHandler.swift` — Tab / Shift-Tab line indent + outdent
- `BackspaceHandler.swift` — smart Backspace (strip marker + join
  with previous line; outdent first when nested)
- `CursorSnapping.swift` — phantom marker-zone snap +
  content-column Up/Down arrow tracking
- `CheckboxToggler.swift` — tap-on-bracket toggles `[ ]` ↔ `[x]`
- `PasteHandler.swift` — source-verbatim paste (CRLF → LF, BOM
  strip, tab → 4 spaces; smart-typography off)
- `ToolbarAction.swift` — 25 Apple-Reminders-style toolbar buttons
  (bold / italic / strike / highlight / code / heading 1..6 /
  paragraph / bullet / numbered / task / blockquote / indent /
  outdent / link / image / code-block / table / hr / wikilink /
  footnote / math-inline / math-display / mermaid)
- `MarkdownReminderToolbar.swift` — the SwiftUI/UIKit accessory
  bar above the keyboard
- `ExtensionParsers.swift` — regex helpers for wikilinks,
  footnotes, math, mermaid

Test infrastructure was rebuilt on 2026-05-21 with a three-layer
stack: snapshot tests for view-layer regression, XCUITest for
gestures and flows, XcodeBuildMCP for in-session exploration. See
AGENTS.md "How to verify iOS work" for details.

## List nesting — landed 2026-05-19

Lists nest arbitrarily deep. Sidebar renders as a collapsible tree
(chevron column on the left, 20pt indent per depth); collapse state
persists across launches. Reorder mode entered via a pencil in the
"My Lists" header — system drag handles, drop-on-row to nest,
drop-between-rows to reorder siblings (parent-aware), swipe + long-press
disabled while active. List detail gains a collapsible "Sub-Lists"
section above its items. Three creation paths (sidebar long-press,
list ••• menu, root + with parent picker). Shared `ParentPickerSheet`
also drives the "Move to…" flow with a cycle guard.

On disk, folder names mirror the sanitized list display name and nest
on the filesystem — `Documents/Lists/Trip planning/Packing/.list.yml`
— so the storage tree reads cleanly on extract. Stable ids continue
to live inside `.list.yml`. Rename and reparent physically move the
folder. Sibling-name collisions auto-suffix `(N)`. `FileStore.loadAll`
silently migrates the legacy `<root>/<listId>/` layout on first launch
after upgrade.

## Document view — landed 2026-06-11

Tasks / notes / events now open as a document-style page
(`Features/ItemDetail/ItemDocumentView.swift`, routed from `ItemDetailSheet`):
title + always-visible one-line fact strip (row-meta style; tappable) + the
markdown body inline. The full control cards live in a **Details pop-up
sheet** (medium/large detents) opened from the nav-bar ⓘ (`document.info`) or
the strip (`document.facts`) — reworked 2026-06-11 from the original
collapsible-inline-block design at Saxon's request (the fold memory
`document.options.expanded.<type>` is gone). The title is a UIKit field
carrying a **quick-details glass bar** (Details / flag / priority / type;
Return hops into the body). Live-apply (debounced keystrokes via
`applyUpdateSync`); `#tag` in the title extracted on close. The body embeds
the editor stack through `DocumentBodyEditor` (non-scrolling, self-sizing,
caret kept visible via `EditorCoordinator.onEditorInteraction`).
The inline-editor trailing (i) became a document glyph for these types
(swipe-action icons too; actions labeled "Open", habits keep "Details").
**Habits keep the (i), the classic form, and have no notes body.** Event UI:
Event segment in quick capture, Starts/Ends/Checkbox controls, task→event
keeps the checkbox.

Same pass (2026-06-11, all per Saxon's feedback batch):
- Leading icons (note doc glyph, event calendar) share the task checkbox's
  geometry + title-line anchor in rows AND on the document page (note-row
  snapshot baseline re-recorded).
- Keyboard accessory bars share one Liquid Glass pill base
  (`Design/Components/KeyboardGlassBar.swift`); the markdown toolbar is now a
  glass pill too (scrollable content, fixed dismiss). Inline bar gained a
  quick **type** button (task/note/event; hidden for habits).
- Inline-edit over-scroll fixed by DELETING the manual keyboard inset/scroll
  code — iOS 26+ UIKit handles keyboard insets + first-responder reveal
  itself; manual insets stacked and caused the jump-to-top (see the
  "deliberately absent" comment in `ListDetailCollectionView`).
- Drag-to-reorder indent is now relative to the grab point (list items +
  sidebar lists), not absolute finger x.
- Driven-session re-verification of the scroll fix + final visual pass are
  PENDING — Saxon is iterating on the look first and will call for the full
  test batch.

Look-iteration round 2 (2026-06-11, per Saxon's second feedback batch):
- The document page now presents **full screen** (`.fullScreenCover`, not a
  `.large` sheet) from every entry point — Today / SmartList / ListDetail /
  ItemRow. Habits (HabitDetailView) ride the same change and are full screen
  too (they already have an `xmark` close).
- **Tree-view pill removed** from the document page's nav title (it now shows a
  plain type label). Replaced by a **"View Breadcrumb"** submenu in the overflow
  ⋯ menu listing the ancestor chain (root → parent); tapping a crumb pushes that
  ancestor's own document page. Driven by a `NavigationPath` owned by
  `ItemDetailSheet` (single `BreadcrumbDestination` registration so jumps work
  from any depth). `ThreadView`/`DetailSheetHeaderTitle` still exist for habits.
- Markdown keyboard toolbar gained **undo / redo** in the fixed (non-scrolling)
  trailing group beside the hide-keyboard button — always tappable; they drive
  the text view's own `UndoManager`.
- Note **body text is flush-left** at the page margin (`leadingInset` 40 → 5),
  no longer indented to line up with the title.
- Tag row: chips and the add-field are vertically centred so a typed `#tag`
  lines up with the placeholder; placeholder reworded "Add tag…" → "Add tags…".
- Still PENDING the same full verification batch above.

Look-iteration round 3 (2026-06-11, third feedback batch):
- Nav bar: **leading back button** leaves the page (`document.back`); the
  trailing **check now dismisses the keyboard**, not the page
  (`navigationBarBackButtonHidden(true)` so the custom back is the only one,
  and it pops a pushed breadcrumb page or closes the cover at the root).
- **Breadcrumb is now a bottom sheet**, not an overflow submenu. The nav title
  is tappable (type label + chevron) for a nested item and opens the ancestor
  path as a `.medium`/`.large` sheet; tapping a crumb pushes that page.
- **Type→Event** now makes a **non-completable** calendar event (glyph flips to
  the calendar) in BOTH the document page (`setType`) and the inline row editor
  (`inlineToolbarSetType`) — fixes "symbol didn't change". Events are also
  **forced to have a start + end**: `ensureEventDates()` seeds defaults on
  conversion + on open (`normalizeEventDates` in `.onAppear`), and the Details
  Date/Ends toggles can't be turned off for an event. (Reverses the old
  task→event=completable rule and the optional-end/point-event model — spec
  updated.)
- **Divider** between the title/fact-strip block and the body.
- Note / plain-event document pages **hide the leading glyph** (only a
  functional checkbox keeps the slot); title + fact strip then sit flush left.
- Still PENDING the same full verification batch (no existing unit test
  asserts the old task→event=completable rule, so nothing breaks from the flip
  change; the batch is for driven-session + visual confirmation).

Look-iteration round 4 (2026-06-11, fourth feedback batch):
- **Confirm ticks are now the accent-filled circle** (the inline editor's
  `.borderedProminent` + `.circle` + `ListsTokens.accent`, white check) — applied
  to the document page (`document.done` hide-keyboard + `document.details.done`),
  habit save, quick-capture add, and the full-screen markdown editor done. They
  read as a distinct, "separated" primary action vs the plain ⓘ/⋯ glyphs.
- **Event date/time editor** rebuilt to the Apple Calendar pattern: **Starts**
  and **Ends** rows each carry a compact date pill (+ a time pill unless All Day
  is on), plus an **All Day** toggle that drops the time. Tasks keep their old
  Date/Time toggle rows. Event start/end stay mandatory.
- **Completable** toggle reworded from "Checkbox / Behaves like a task — can go
  overdue" to just **"Completable"** (no subtext).
- **Breadcrumb shows at the parent too:** the nav title is tappable whenever the
  item has a parent OR children (`hasThread`). The sheet now lists ancestors,
  the current item, and its **direct children**, so you can jump up or down the
  thread.
- Still PENDING the full verification batch.

Look-iteration round 5 (2026-06-11, fifth feedback batch):
- Document-page **tags**: the always-on "Add tags…" field is gone when the item
  has no tags. A **tags button** in the title quick bar (`document.quickbar.tags`,
  `tag`/`tag.fill` with accent when tags exist) reveals + focuses the tag field
  (`TagInputView` gained a `focusToken` that bridges to `becomeFirstResponder`).
  An empty revealed field is dropped again when the keyboard hides.
- Hide-keyboard tick now animates with the liquid-glass toolbar morph (same
  spring as the inline editor) instead of snapping.
- **Raw Markdown** mode now also renders the **title** in SF Mono
  (`DocumentTitleField.monospace`), matching the body.

## Past events roll off the list — landed 2026-06-11

Past **calendar events** (non-completable events whose end has passed) now roll
off list views at the end of their day, instead of lingering forever. Actionable
items never roll off: overdue tasks and *missed completable events* persist
exactly as before. A per-view **"Show Past Events"** toggle (default off) reveals
them, sitting beside "Show Completed" in the overflow menu of **user lists** and
the **Scheduled / All / Flagged / Urgent** smart lists. Deliberately **not on
Today** (Today is right-now + actionable). The calendar view (planned) stays the
permanent archive — nothing is deleted, just hidden from the list.

- Model: `Item.isRolledOffPastEvent(now:calendar:)` — true only for a
  non-completable event with `end ?? due <= startOfToday`.
- Pref: `ListViewPreferences.showPastEvents(for:)` / `setShowPastEvents`, per
  view key, default `false` (mirrors `showOverdue`/`showCompleted`).
- Filter applied at every list filter site (ListDetailView + collection view,
  SmartListScreen flat/All/scheduled paths). In Scheduled it's governed by the
  new toggle, not "Show Overdue" (a past event isn't overdue).
- **Deferred, documented only** (Saxon's request): a future global **Settings**
  toggle to soften the roll-off — default stays end-of-day/instant, optional
  "keep events 1–2 days old" grace window. See PRODUCT-SPEC "Events". Not built.

## Next Work

- Saxon's stated direction: a **calendar view over Scheduled**, and
  **iCal import/export ("calendar sync")** — the event fields are already
  shaped for it.
- Still queued from before: KaTeX math + mermaid rendering in
  `MarkdownBodyView` (WKWebView bridges), tappable wikilinks.
- Android comes after the iOS consolidation. Linux, Windows, sync, and
  AlarmKit stay deferred until explicitly requested.

## Constraints

- Bundle id: `io.github.saxonbobart.lists`
- Apple team: `LM99LGYW87` (Saxon's personal Apple ID, free signing only)
- AlarmKit is deferred until a paid Apple Developer Program account exists
- iOS data stays app-private in `Documents/Lists/`
- Use XcodeBuildMCP for build, test, run, screenshots, logs, and UI snapshots
