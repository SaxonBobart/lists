# Lists Product Spec

Lists is a local-first app for tasks, habits, and notes. The product should feel calm, native, fast, and private. The active implementation is iOS first.

## Product Shape

- One primitive: `Item`.
- Item types: task, habit, note.
- Items live in lists.
- Lists may have sections.
- Items may have one parent item for thread/sub-item workflows.
- Markdown body text is part of the item, not a separate note system.
- Files are the source of truth; indexes and caches are rebuildable.

## Storage

The iOS app stores data in its app sandbox:

```text
Documents/Lists/
  <list-id>/
    .list.yml
    <item-id>.md
```

Each item file contains YAML frontmatter and a markdown body.

Important rules:

- List folders are named by stable ids, not human-readable names.
- `.list.yml` stores list metadata.
- `<item-id>.md` stores item metadata plus markdown body.
- Soft-deleted data uses tombstone fields so future sync can reconcile deletes.
- iOS storage is not Files.app visible and is not iCloud Drive backed.

## Tasks

Tasks have a checkbox state, optional due date/time, optional early reminder, priority, flag, tag, list, section, and markdown body.

Completion hides tasks from normal active views unless a completed view or show-completed mode is active.

## Habits

Habits track completion counts by cycle.

Habit fields:

- frequency
- goal per cycle
- completion log
- optional reminder time
- show streak

Habit rows use a compact progress ring. Tapping the ring increments the current cycle until the goal is met. At goal, the row shows a filled checkmark and follows the same completed filtering behavior as tasks.

Habit detail has:

- stats mode with progress, streak, and heatmap
- details mode for editing habit settings and standard item fields

Until a dedicated habit reminder field exists, the habit reminder time is stored through the existing due/reminder shape.

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
