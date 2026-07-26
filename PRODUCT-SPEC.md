# Lists Product Standard

Lists is a local-first app for tasks, habits, notes, and events. The product should feel calm, native, fast, and private. The active implementation is iOS first.

This is the single behavior standard for the app. iOS is the source of truth for now; future Android work should translate these same product outcomes into native Android patterns instead of inventing a separate product.

## Product Shape

- One primitive: `Item`.
- Item types: task, habit, note, event. The types share the same `Item` storage shape but expose different control surfaces: a task is text plus a checkbox, a habit is text plus a cycle counter and completion history, a note is markdown text, and an event is text plus a time span.
- Items live in lists.
- Lists may have sections.
- Items may have one parent item for sub-item hierarchy workflows.
- Lists may nest under other lists (Apple Notes-style hybrid): any list can hold items and child lists.
- Markdown body text is part of the item, not a separate note system.
- Document links use portable, human-readable relative Markdown paths and may
  target headings. Incoming and outgoing links are navigable from the document
  navigator, and app-managed item/list renames rewrite affected paths. Creating
  one uses the normal in-place item browser; items with headings offer a compact
  whole-item or heading choice before insertion. Document links remain inline
  with surrounding text. In Live Markdown they appear as accent-colored,
  underlined words and a tap follows the destination. Moving the caret into a
  link reveals its complete `[label](destination)` source for manual editing;
  moving away hides it again. Raw Markdown always exposes the literal source.
  Ordinary web links use the same inline treatment; only local attachments
  become preview cards.
- Local images, files, and scans are stored as relative `Attachments/`
  references. Library export includes both note text and attachments.
- The document menu can copy either the active body/table-cell text selection
  or the whole Markdown body as Markdown, rich text, or plain text. Selection
  actions stay unavailable without a text selection. Table handles retain
  their table-specific Markdown and CSV copy actions.
- Files are the source of truth; indexes and caches are rebuildable.

Moving an item is an in-place mode, not a modal browser. A move can start from the Move action in a row/detail surface, or by dragging a user-list row onto the bottom move shelf. The moving item sits in that shelf while user-list rows become compact destination targets. Move mode temporarily reveals collapsed sections and item hierarchies so valid destinations are not hidden. `None` means top-level in the current list; tapping another item makes it the parent. The shelf persists while navigating to another list. Moving under a parent inherits that parent's section. A parent item moved to another list carries its descendants with it; moving to another list with no parent clears stale section ids, while choosing `None` inside the same list only removes the parent. Starting move mode clears local editing and selection chrome. While the shelf is active, the app hides creation controls, view-option menus, search/settings entry points, list-management gestures/menus, and tag-management menus so choosing a destination stays the only active task.

Query surfaces, including Today, other smart lists, search, and tags, can preserve the shelf while the user navigates, but destination picking happens in user lists.

List and section edits made from detail screens follow the same subtree rule. Children render under their parent, so storage must move descendants with the edited item instead of leaving invisible stale children behind. A child moved to another list without its parent becomes top-level in the destination; a child that remains under a parent inherits the parent's section.

User lists also support multi-select bulk actions. Bulk moves operate on selected
roots so selecting both a parent and its child moves the parent once and carries
the child with it. Moving a selected child without its parent to another list
makes that child top-level in the destination. Bulk section moves cascade to
descendants, matching single-item moves and detail edits.

## List, Columns, and Calendar Views

User-owned lists can switch between List and Calendar. A list with one or more
durable named sections also offers Columns. Columns are a Kanban-style
presentation of those real sections: every section is one horizontally
scrollable column, empty sections remain visible, and item hierarchy, inline
editing, completion, swipe actions, selection, and reordering retain their
normal list behavior. Lists without sections do not offer Columns.

Smart lists and other query surfaces (Today, Scheduled, Flagged, Alarms,
Completed, All, Tags, and search results) can switch between List and Calendar,
but never Columns. A query's visual grouping is derived and must not be
mistaken for durable list sections.

Calendar is a local projection over the same Markdown documents, not a second
database or an external calendar account. The sidebar Calendar tile combines
all visible lists; a calendar opened from a user list or query keeps that
surface's scope. The planner supports Agenda, Day, 3 Days, Week, Month, and
Year views, month density choices, weekend and week-number display, range
navigation, Today, and a date picker. Per-surface view and density choices are
device-local preferences.

Calendar entries preserve event spans and all-day/multi-day behavior. Timed
entries can be moved or resized in the timeline, and current entries can be
dragged to another day in Month. A long press in a timeline seeds a one-hour
event at that time; the floating add button seeds the current default item type
on the selected day, while its long press seeds an event. Creation still opens
Quick Capture so every normal field remains available. Entries open the same
detail screens, completable entries use the same completion rules, and a
calendar occurrence can be duplicated as a one-off document.

Recurring documents remain one durable Markdown document. The default calendar
shows only the next occurrence; Settings can opt into every recurrence in the
visible range and can independently show completed or missed occurrence
history. Projected occurrences are virtual and never create documents merely
because they are visible. Rescheduling the current recurring occurrence asks
for Only This, This and Future, or Entire Series; Only This detaches a one-off
document and advances the source series. Habit cadence follows the same
next-occurrence versus visible-range setting, while completion history remains
off by default because habits and repeating items already have dedicated
history screens.

Calendar Settings can hide item types, completed items, completion/missed
history, weekends, week numbers, and individual lists from the global
calendar. These choices only change display; they never rewrite item
frontmatter. Lists does not implement shared calendars, invitee responses,
availability, Exchange/CalDAV accounts, or holiday subscriptions as part of
this local planner.

## Storage

The iOS app stores data in its app sandbox:

```text
Documents/Lists/
  <list name>/
    .list.yml
    <item title>.md
    <child list name>/
      .list.yml
      <item title>.md
```

Each item file contains YAML frontmatter and a markdown body.

Important rules:

- List folders are named by sanitized display names; the list's stable id lives inside `.list.yml`. Renaming or reparenting a list physically moves the folder. Filesystem-illegal characters are replaced with `-`; sibling-name collisions auto-suffix `(N)`; the empty name falls back to `Untitled`.
- Nested lists sit as sub-folders alongside the parent's item files. Each nested folder has its own `.list.yml`. Depth is unlimited. Parent linkage is stored as `parent_id: <id>` in the child's `.list.yml`.
- `.list.yml` stores list metadata.
- Item files use sanitized display titles such as `Project notes.md`; the stable
  item id lives in frontmatter. Renaming or moving an item writes the new file
  before removing its previous path. A colliding imported filename is preserved
  and the new file receives a numeric suffix instead of being overwritten.
- A list parent id that is missing, points to a deleted parent for an active list, is self-referential, or points into the list's own descendant subtree is repaired to root rather than creating an invisible or cyclic sidebar tree.
- Active items loaded with missing parents, deleted parents, cross-list parents, or stale section ids are repaired into a visible hierarchy and written back. Active items found inside a tombstoned list are tombstoned with that list.
- Soft-deleted data uses tombstone fields so deletes remain explicit and recoverable. Deleting an item cascades to live descendants, and restoring that item restores descendants deleted by the same operation. Deleting a list cascades to descendant lists and live items inside those lists. Restoring a list restores descendant lists and live items deleted by that list operation. Restoring an item whose parent or list is still tombstoned detaches or moves it to a safe visible place, with restored descendants following that item's live list/section. Restoring a child list whose parent is still tombstoned detaches the child to the sidebar root.
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
- flexible streak (one completion keeps the run alive; reaching the full per-cycle
  goal still completes that cycle)
- completions (timestamped events; the stored source of truth)
- optional reminder time
- show streak

Habit rows use a compact progress ring. Tapping the ring logs a completion for the
current cycle until the goal is met. Tapping the title opens the habit's read-first
detail instead of editing the title inline. At goal, the row shows a filled checkmark
and follows the same completed filtering behavior as tasks.

Streaks are **forgiving**: a single missed cycle does not reset the streak ("never
miss twice" — two consecutive misses break it).

Habit detail opens as one read-first progress surface: title, cadence, exact reminder
schedule and delivery state, current-cycle progress, one primary **Log Completion**
action, secondary Undo/Add with Date actions, an accessible recent-activity chart,
current run and lifetime total, and recent completion history. **Edit** is an explicit
toolbar action because habit setup changes much less often than progress is checked.
Editing exposes habit settings and standard item fields without replacing live
completion history.

Completions are added or corrected through a single sheet: a **Single Date** entry
(date + time, used for both adding and editing one event) or a **Date Range** that
backfills one completion per day across a start–end range. In the full log, each
entry can be retimed, redated, or deleted.

Habit reminders **repeat** on a schedule keyed to the habit's frequency: daily at the
chosen local time, weekly on the chosen weekday, or monthly on a reliable day from
1–28. One repeating request is kept per habit, so reminders do not create duplicate
task instances or a growing queue of notifications. Logging a durable completion
acknowledges the delivered alert without removing the next repeat. The reminder time
is still stored through the existing due/reminder shape until a dedicated field exists;
its source time zone is retained so the wall-clock schedule remains stable. That date
is not an overdue deadline.

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
  crumb opens that ancestor's page. There is no separate tree pill.
- The full controls live in a **Details sheet**, opened from the ⓘ in
  the nav bar or by tapping the fact strip — not inline in the document.
- While editing the title, a keyboard **quick bar** offers the fast edits
  (open Details, flag, priority, type) without leaving the keyboard; Return
  hops into the body.
- During inline row editing, the trailing affordance for these types is a
  **document glyph** ("open as a page"); the open-the-page actions are labeled
  **"Open"** (habits keep "Details").
- **Habits are exempt:** they keep the ⓘ affordance and their dedicated read-first
  progress screen with explicit Edit, and habits have **no notes body** at all.

## Events

An event is a calendar block: it **always has a start (`due`) and an end (`end`)** — there is no point event. When an item becomes an event (or older data arrives without an end), the app seeds sensible defaults (next top-of-the-hour start, +1h end) and won't let the start or end be turned off. Event fields are deliberately calendar-shaped: start, end, all-day, recurrence, and reminders describe time directly instead of encoding event behavior as task metadata.

The defining difference from a task is what *not doing it* means:

- A **non-completable** event (the default) has no failure state. When it passes, it is simply *past* — never overdue, never "completed", no fading or nagging. It appears in Today on its day (or while a multi-day span overlaps today) and then drops out. Rows show a calendar glyph.
- A **completable** event ("pick up the cake, 2–3pm") behaves like a task: checkbox in the row, goes overdue if it passes unticked, hides when done. Completability is opt-in through the Details toggle.

Converting any type into an event makes it a **non-completable** calendar event (the glyph becomes the calendar); any checkbox/done-state is dropped.

Recurring completable events spawn their next occurrence on completion (like tasks), preserving the span's duration. Reminders fire at the start (with the usual early-reminder offset).

On-disk fields: `end` (day-string when the event is all-day, like `due`) and `completable` (written only when true). The file format still tolerates a missing `end` for backward compatibility, but the app backfills one on open. Older builds decode unknown types as task, so an event file degrades gracefully.

### Past events roll off the list (but not the calendar)

The guiding split: **actionable things never auto-hide; things that already happened can.**

- A **past calendar event** (a non-completable event whose end has passed) is not "missed" — there's nothing left to do, it's just over. Once it has ended it **rolls off the list at the end of its day**: events that finished earlier today stay visible through today, then drop out tomorrow. They are never deleted.
- **Actionable** items — overdue tasks, and *completable* events you didn't tick — are unfinished, so they **never roll off**; they persist (overdue styling) until completed, exactly like today.

This is the product split: active item surfaces are "what needs me now + the rest of today," not archives of old events.

A per-view **"Show Past Events"** toggle (default **off**) sits beside "Show Completed" in the overflow menu of user lists and the smart lists (Scheduled / All / Flagged / Alarms). Turning it on surfaces rolled-off past events in that view. It is intentionally **not** on the Today smart list — Today is the current-action query, and dumping last week's finished events there would defeat its purpose.

## Smart Lists

Smart lists are queries over items, not stored collections.

Current smart lists:

- Today
- Calendar
- Scheduled
- Flagged
- Alarms
- Completed
- All

The sidebar also pins a **Tags** tile that opens the tags overview.

Smart-list behavior should stay consistent across regular list views, search, tags, and other clients.

Rules worth preserving: sub-items obey the same visibility rules as top-level items (the All tile count must equal what the view shows); habits are excluded from Scheduled and All; passed non-completable events leave Today without ever reading as overdue or completed; Today's Overdue section is only unfinished actionable items.

In Scheduled, the Overdue section is only for unfinished actionable items. Past non-completable events shown through "Show Past Events", and completed dated items shown through "Show Completed", remain grouped by date rather than being labeled overdue.

## Tags

Tags are plain strings attached to items. Tags may be shown as chips and grouped in a tags overview. Keep tag behavior lightweight until a larger taxonomy is deliberately designed.

Tags are item metadata, edited through tag controls. Literal `#word` text in a title or markdown body remains document text; it does not create or remove item tags.

The sidebar Tags tile, tag chip set, tag chip counts, and tag-scoped rows show active work only: deleted items, completed items, and rolled-off past calendar events do not count, except while a just-completed row is briefly fading out.

Search matches title, body, and tags across active work only. Discoverable
offline filters narrow results to links or backlinks, tables, Markdown tasks,
or images and attachments. Deleted, completed, and rolled-off past calendar
items do not appear in normal search results, except while a just-completed row
is briefly fading out.

## Reminders and Notifications

Non-alarm reminders use standard local notification scheduling.

Alarm currently means an item has the alarm trigger enabled and appears in the Alarms smart list. Reminder delivery still uses normal local notification scheduling.

Date-only reminders use the user's default reminder time.

## Recurrence

Recurrence support should stay small and testable. The supported RRULE subset is the one exercised by the repeat editor and recurrence tests; expand both together when adding a new repeat rule.

Repeat end dates are stored as RRULE `UNTIL` values. The app writes UTC timestamps, and it must also read floating local datetimes and bare local dates so imported or hand-edited rules still end safely instead of repeating forever.

A repeating task or completable event remains one durable Markdown document.
Each scheduled occurrence is lightweight frontmatter metadata with a stable id,
scheduled time, time zone, status, and optional exact completion time.
Completing the current occurrence records one genuine completion, marks crossed
unresolved cadence slots missed, and advances the same item to its next due date.

Completion History is item-scoped. The current occurrence is read-only there;
past completed and missed occurrences can be corrected without changing the
current due date, recurrence rule, or notification schedule. Genuine recurring
completions appear individually in Completed, while missed occurrences do not.
Recurring notification identifiers carry both the stable item id and current
occurrence id so delivered history and the next pending reminder stay distinct.

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
- No sync surface in the current app.

## Out Of Scope

These are not part of the current app contract:

- Android, Linux, Windows, web, or Electron clients.
- Lists Sync.
- External-link previews and remote link metadata fetching. Web links remain
  portable inline Markdown across platforms.
- AlarmKit-style alarms beyond standard local notifications.
- Agent integrations inside the app.
- Shared cross-platform core libraries.

## Documentation Rule

This spec is intentionally compact. Add only product behavior that implementations need to preserve. Do not use it as a changelog, scratchpad, or roadmap.
