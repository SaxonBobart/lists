# Lists Product Spec

Lists is a local-first app for tasks, habits, notes, and events. The product should feel calm, native, fast, and private. The active implementation is iOS first.

## Product Shape

- One primitive: `Item`.
- Item types: task, habit, note, event. The types are one thing wearing different control surfaces: a task is a note plus a checkbox, a habit is a note plus a cycle counter, an event is a note plus a time span.
- Items live in lists.
- Lists may have sections.
- Items may have one parent item for thread/sub-item workflows.
- Lists may nest under other lists (Apple Notes-style hybrid): any list can hold items and child lists.
- Markdown body text is part of the item, not a separate note system.
- Files are the source of truth; indexes and caches are rebuildable.

## Storage

The iOS app stores data in its app sandbox:

```text
Documents/Lists/
  <list name>/
    .list.yml
    <item-id>.md
    <child list name>/
      .list.yml
      <item-id>.md
```

Each item file contains YAML frontmatter and a markdown body.

Important rules:

- List folders are named by sanitized display names; the list's stable id lives inside `.list.yml`. Renaming or reparenting a list physically moves the folder. Filesystem-illegal characters are replaced with `-`; sibling-name collisions auto-suffix `(N)`; the empty name falls back to `Untitled`.
- Nested lists sit as sub-folders alongside the parent's item files. Each nested folder has its own `.list.yml`. Depth is unlimited. Parent linkage is stored as `parent_id: <id>` in the child's `.list.yml`.
- `.list.yml` stores list metadata.
- `<item-id>.md` stores item metadata plus markdown body.
- Soft-deleted data uses tombstone fields so future sync can reconcile deletes. Deleting a list cascades to descendants; restoring a child whose parent is still tombstoned detaches the child to the sidebar root.
- iOS storage is not Files.app visible and is not iCloud Drive backed.

## Tasks

Tasks have a checkbox state, optional due date/time, optional early reminder, priority, flag, tag, list, section, and markdown body.

Completion hides tasks from normal active views unless a completed view or show-completed mode is active.

## Habits

Habits track individual, timestamped completion events. Per-cycle counts (and the
completed-state check) are derived by grouping those events into the habit's cycle.

Habit fields:

- frequency — **daily, weekly, or monthly only**, so a habit's streak is always a
  day-, week-, or month-streak. (Any other cadence on older data is folded onto one
  of the three when the habit is edited.)
- goal per cycle
- flexible goal (when set on a weekly/monthly habit, the goal means "N times across
  the cycle" — e.g. "3 times a week" — rather than N on a single day)
- completions (timestamped events; the stored source of truth)
- optional reminder time
- show streak

Habit rows use a compact progress ring. Tapping the ring logs a completion for the
current cycle until the goal is met. At goal, the row shows a filled checkmark and
follows the same completed filtering behavior as tasks.

Streaks are **forgiving**: a single missed cycle does not reset the streak ("never
miss twice" — two consecutive misses break it).

Habit detail has two tabs:

- **Overview** — two stat cards (the streak in the habit's cadence, and this cycle's
  count toward goal with quick +1 / −1 logging), a **per-cycle contribution grid**
  whose shape follows the cadence (the last 30 days, 52 weeks, or 12 months — one
  square per cycle, coloured by that cycle's completion ratio; it fits without
  scrolling), and a "Recent"
  list with a See All push to the full, editable log. Tapping a grid square logs a
  completion in that cycle.
- **Details** — habit settings and standard item fields.

Completions are added or corrected through a single sheet: a **Single Date** entry
(date + time, used for both adding and editing one event) or a **Date Range** that
backfills one completion per day across a start–end range. In the full log, each
entry can be retimed, redated, or deleted.

Habit reminders **repeat** on a schedule keyed to the habit's frequency (e.g. a daily
reminder fires every day; a weekly one matches the chosen weekday). The reminder time
is still stored through the existing due/reminder shape until a dedicated field exists.

## Notes

Notes are markdown-first items without a checkbox. In item rows, notes use a document glyph instead of a task checkbox or habit ring.

## Item Detail (document page)

Tasks, notes, and events open **full screen** as **one scrollable document**:
the title at the top, a one-line **fact strip** beneath it, a divider, and the
markdown body editable inline below. Edits apply live — there is no Save/Discard
step on this page.

Behavior worth preserving:

- Presented full screen (not a card sheet). The **leading back button** leaves
  the page; the nav-bar **check dismisses the keyboard** (it does not close the
  page). The body text sits at the page's **left margin** (Apple Notes style),
  not indented to line up with the title.
- The leading control only appears when it is *functional* — the checkbox of a
  task or a completable event, using the same geometry as a list row's checkbox.
  A note or plain event hides its decorative glyph (the type already shows in
  the nav bar) so the title sits flush at the margin.
- The fact strip shows what's set (date/time, event end, repeat cadence,
  priority, flag) exactly like a row's meta line — the page never hides state.
- A nested item's nav title is tappable and opens its ancestor **breadcrumb**
  path as a sheet from the bottom (root → parent + the current item); tapping a
  crumb opens that ancestor's page. There is no tree/thread pill.
- The full controls live in a **Details pop-up sheet**, opened from the ⓘ in
  the nav bar or by tapping the fact strip — not inline in the document.
- While editing the title, a keyboard **quick bar** offers the fast edits
  (open Details, flag, priority, type) without leaving the keyboard; Return
  hops into the body.
- During inline row editing, the trailing affordance for these types is a
  **document glyph** ("open as a page"); the open-the-page actions are labeled
  **"Open"** (habits keep "Details").
- **Habits are exempt:** they keep the ⓘ affordance and their dedicated
  Overview/Details screen, and habits have **no notes body** at all.

## Events

An event is a calendar block: it **always has a start (`due`) and an end (`end`)** — there is no point event. When an item becomes an event (or older data arrives without an end), the app seeds sensible defaults (next top-of-the-hour start, +1h end) and won't let the start or end be turned off. All fields are deliberately calendar-shaped (start / end / all-day / RRULE recurrence) so a future iCal import/export is a translation, not a migration.

The defining difference from a task is what *not doing it* means:

- A **non-completable** event (the default) has no failure state. When it passes, it is simply *past* — never overdue, never "completed", no fading or nagging. It appears in Today on its day (or while a multi-day span overlaps today) and then drops out. Rows show a calendar glyph.
- A **completable** event ("pick up the cake, 2–3pm") behaves like a task: checkbox in the row, goes overdue if it passes unticked, hides when done. Completability is opt-in through the Details toggle.

Converting any type into an event makes it a **non-completable** calendar event (the glyph becomes the calendar); any checkbox/done-state is dropped.

Recurring completable events spawn their next occurrence on completion (like tasks), preserving the span's duration. Reminders fire at the start (with the usual early-reminder offset).

On-disk fields: `end` (day-string when the event is all-day, like `due`) and `completable` (written only when true). The file format still tolerates a missing `end` for backward compatibility, but the app backfills one on open. Older builds decode unknown types as task, so an event file degrades gracefully.

Planned (not yet built): a calendar view over Scheduled, and iCal import/export/sync.

## Smart Lists

Smart lists are queries over items, not stored collections.

Current smart lists:

- Today
- Scheduled
- Flagged
- Urgent
- Completed
- All

Smart list behavior should stay consistent across regular list views, search, tags, and future platforms.

Rules worth preserving: sub-items obey the same visibility rules as top-level items (the All tile count must equal what the view shows); habits are excluded from Scheduled and All; passed non-completable events leave Today without ever reading as overdue or completed.

## Tags

Tags are plain strings attached to items. Tags may be shown as chips and grouped in a tags overview. Keep tag behavior lightweight until a larger taxonomy is deliberately designed.

## Reminders and Notifications

Non-urgent reminders use standard local notification scheduling.

Urgent alarm behavior is deferred on iOS until a paid Apple Developer Program account unlocks the right capability path. Do not design the core product around AlarmKit until that is unblocked.

Date-only reminders use the user's default reminder time.

## Recurrence

Recurrence support should stay small and testable. The shared recurrence docs define the supported RRULE subset and examples.

## Design

The app should use native iOS patterns and restrained visual design.

Guidelines:

- Prefer system controls and readable density.
- Use the design prototype as a visual reference, not production code.
- Keep typography native: SF Pro and SF Mono.
- Do not ship custom programming fonts on iOS.
- Keep the app calm; avoid marketing-style UI inside the product.

## Privacy

- No telemetry by default.
- No account required for local use.
- No cloud dependency for local use.
- Sync is deferred.

## Deferred

These are not active unless Saxon explicitly asks for them:

- Android, Linux, and Windows clients
- Lists Sync
- App Store distribution work
- AlarmKit
- Agent integrations inside the app
- Shared Rust core
- Web or Electron client

## Documentation Rule

This spec is intentionally compact. Add only product behavior that future implementation needs to preserve. Put temporary status in `docs/CURRENT.md` instead.
