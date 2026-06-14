# Changelog

Dated milestone history for the Lists iOS app, newest first.
For current status and next work, see `docs/CURRENT.md`.

---

## 2026-06-12 — Section / event / details batch

- **Sub-item section data-loss bug fixed.** Moving a parent item to another section now cascades the new section to its whole subtree. Before, children kept the old section id and were soft-deleted when that section was deleted.
- **Inline section creation.** "New Section" now creates the section and opens its header inline for renaming — no alert pop-up.
- **Event creation in quick-capture matches the editor.** The Event branch now uses compact Starts/Ends pills + All Day toggle; removed the old wheel picker and Date/Time on-off toggles.
- **Details sheet Cancel (✕).** The document page's Details sheet gained a leading ✕ that restores a snapshot; the accent tick keeps the edits.

## 2026-06-11 — Document view, events, past-events roll-off, audit closed

**Document view (full redesign):**
- Tasks, notes, events open as a full-screen document: title + always-visible fact strip + inline markdown body. Edits apply live.
- Full controls live in a Details pop-up sheet (opened via ⓘ or the fact strip).
- Nav bar: leading back button leaves the page; trailing check dismisses keyboard.
- Breadcrumb navigation: the nav title is tappable for nested items and opens ancestor + children in a bottom sheet.
- Notes and plain events hide the leading glyph; title sits flush left (Apple Notes style).
- Habits are exempt — they keep the ⓘ and their Overview/Details screen, with no notes body.

**Events (new item type):**
- Events always have a start and an end. No point events; the app seeds defaults on conversion or open.
- Non-completable (default): just past when it ends — never overdue or "completed." Rows show a calendar glyph.
- Completable: checkbox in the row; goes overdue if it passes unticked.
- Event creation via the quick-capture Event segment. Compact Starts/Ends pills + All Day toggle (Apple Calendar style).

**Past events roll off the list:**
- Non-completable past events roll off at the end of their day. Nothing deleted — they stay in the calendar view (planned).
- Actionable items (overdue tasks, completable events) never roll off.
- A per-view "Show Past Events" toggle sits beside "Show Completed" in overflow menus. Deliberately absent from Today.

**Backend audit — CLOSED:** all 18 findings from the 2026-05-30 backend audit resolved. Full detail is in git history.

## 2026-05-30 — Habits redesign + backend audit pass 1

- Habits redesign: Overview/Log/Edit tabs, timestamped completions, forgiving "never miss twice" streaks, flexible X/week goals.
- Backend audit pass 1 (3 of 18 findings closed): read-path quarantine, duplicate-on-move, privacy leak in markdown image loading.

## 2026-05-21 — Test infrastructure rebuilt

- Snapshot tests (`ListsTests/SnapshotTests`) for visual regression.
- XCUITest scaffolding (`ListsUITests`) for gesture/flow smoke coverage.
- XcodeBuildMCP configured as the primary build + test driver.

## 2026-05-19 — List nesting

- Lists nest arbitrarily deep. Sidebar renders a collapsible tree.
- Reorder mode with system drag handles; drop-on-row to nest, drop-between-rows to reorder siblings.
- On disk: folder names mirror sanitized list display names, nested as sub-folders.
- Three creation paths: sidebar long-press, list ••• menu, root + parent picker.

## 2026-05-13 — Markdown editor rebuilt

- Full coordinator + editor view rebuilt under TDD. Pre-fix file archived at `editor-archive-2026-05-13`.
- Replacement: glue-only `MarkdownTextView.swift` (~110 LOC) + focused pure-transform modules under `Features/MarkdownEditor/`.
- Apple Reminders–style toolbar (25 actions). Smart Return, Tab/Shift-Tab, smart Backspace, cursor snapping, tappable checkboxes, paste handler, undo/redo.
