# Lists Product Spec

Lists is a local-first app for tasks, habits, and notes. The product should feel calm, native, fast, and private. The active implementation is iOS first.

## Product Shape

- One primitive: `Item`.
- Item types: task, habit, note.
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
