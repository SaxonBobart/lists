# Lists App Standard

This is the platform-neutral behavior standard for Lists. The iOS app is the current source of truth; Android and future clients should match these product rules while using native platform UI.

## Product Model

Lists has one durable primitive: `Item`.

An item can be a task, note, habit, or event. These are not separate apps:

- Task: text plus a checkbox.
- Note: text without completion.
- Habit: a first-party module on top of `Item`, with cycle-based completion history.
- Event: text plus a start and end time; it is calendar-shaped from the start.

Items live in lists. Lists can contain items and child lists. Items can contain sub-items. Lists can have sections. Tags are lightweight strings on items.

Invalid list parents are repaired to the sidebar root. A client must not preserve a missing parent, deleted parent for an active list, self-parent, or parent that would put a list under one of its own descendants.

Active items must be visible after load. Missing parents, deleted parents, cross-list parents, and stale section ids are repaired to the nearest valid top-level or parent-inherited state. Active items found inside a deleted list are treated as deleted with that list.

## Local-First Data

Files are the source of truth. Caches, indexes, visible snapshots, and settings screens must be rebuildable from disk.

The live local library is an app-private `Documents/Lists/` folder. Each list is a folder with `.list.yml`; each item is a markdown file with YAML frontmatter and markdown body. Local use must require no account, network, cloud drive, or telemetry.

If a file is corrupt, the app loads the rest of the library and moves the bad file to quarantine. Data loss is worse than visible recovery friction.

## Navigation

The home surface is the sidebar:

- Built-in smart lists at the top.
- User lists as a nested tree.
- Tags and Recently Deleted as system destinations.
- Settings from the overflow menu.
- A floating add button for quick creation.
- Search as a temporary bottom search surface, not a permanent page.

User-list count badges count active items that are not complete and have not rolled off as past calendar events. They use the same completion rules as rows: habits are complete when the current cycle reaches its goal, and non-completable past events are not open work.

Today follows the same smart-list row and visibility rules as other queries. Its only special behavior is membership: due today, overdue actionable items, and non-completable events that overlap today. Its Overdue section is only unfinished actionable items; Show Completed can reveal completed items due today, but it does not relabel completed past work as overdue.

## Rows

Rows are the main interaction surface. The same row rules apply in user lists, query surfaces (Today, other smart lists, tags, search), and pickers unless a picker explicitly makes the row read-only.

Leading control by type:

- Task: checkbox toggles done.
- Completable event: checkbox toggles done.
- Non-completable event: calendar glyph opens time editing; it is never overdue.
- Note: document glyph opens the document page.
- Habit: progress ring increments the current cycle; when at goal, it opens habit detail.

Row text opens the appropriate detail surface, except in user lists where tapping text starts inline editing. The row keeps date, repeat, priority, flag, and tags visible as metadata. Completing a row while completed items are hidden keeps it visible briefly so the transition is understandable.

Swipe actions:

- Trailing: delete, flag or unflag, open/details.
- Leading in user lists: indent, outdent, or start move mode where hierarchy allows it.

Dragging in a user list reorders and can change hierarchy. Smart lists are query results, so they do not reorder the underlying manual order.

Move mode is in-place. A move can start from the Move action in a row/detail surface, or by dragging a user-list row onto the bottom move shelf. The selected item then stays in that persistent shelf. User-list rows become compact destination targets; move mode temporarily reveals collapsed sections and item hierarchies so valid child destinations are not hidden. Tapping `None` at the top of a list makes the item top-level in that list, and tapping another item makes that item the parent. The shelf stays active while navigating between lists. The moving item and its descendants cannot be picked as the new parent. Moving under a parent inherits that parent's section. Moving to another list carries descendants to the same list; moving to another list with no parent clears stale section ids, while choosing `None` inside the same list only removes the parent. Starting move mode clears local editing and selection chrome. While the shelf is active, creation controls, view-option menus, search/settings entry points, list-management gestures/menus, and tag-management context menus stay hidden so the user has one temporary task: choose a destination or cancel.

Query surfaces such as Today, other smart lists, search, and tags may preserve the shelf, but they are not move destinations. While the shelf is active, their result rows should not offer unrelated row actions.

Any screen that changes an item's list or section must keep the stored hierarchy coherent. Children render under their parent, so list and section edits must cascade to descendants even when the edit happens from a detail sheet instead of a list gesture. A child moved to another list without its parent becomes top-level in the destination; a child that stays under a parent inherits that parent's section.

Opening detail from any normal app surface preserves move mode. If the item has a hierarchy parent/control, tapping it starts the in-place move session and bottom shelf. Isolated detail views without a move session hide hierarchy move controls rather than showing an alternate picker.

User-list multi-select is a bulk-edit mode, not item move mode. It can move selected item roots to another list or section, add a tag, flag, or delete. If both a parent and child are selected, the parent move carries the child once. If a selected child moves without its parent to another list, it becomes top-level in that destination. Bulk section moves cascade to descendants just like single-item moves.

## Creating And Editing

The floating add button in a user list creates an inline item immediately. The default item type is an app-wide user preference; it also seeds Quick Capture's starting type from add surfaces. Long-pressing the add button opens full Quick Capture, where the user can still switch type before saving.

Quick Capture is for deliberate creation with type, title, body, tags, date/time, repeat, reminder, priority, flag, section, and list. Habit capture uses the habit module fields (frequency, flexible goal, cycle goal, reminder time, streak visibility) instead of the generic date/repeat form.

Tasks, notes, and events open as a full-screen document page:

- Edits apply live.
- Title sits at the top.
- The fact strip shows the important fields that are already set.
- Body is editable markdown.
- Details live in a sheet opened from the info button or fact strip.
- The keyboard quick bar exposes fast edits.

Habits use their own first-party module screen:

- Overview tab: streak or lifetime count, current-cycle progress, heatmap, recent completions.
- Details tab: title, tags, cadence, flexible goal, goal count, reminder time, streak visibility, flag, priority, section, list, delete.
- Completion log: add, edit, retime, delete, and range backfill.

Habits do not expose or persist a markdown notes body. They share `Item` identity and metadata, but their content surface is the habit module. Habit dates drive reminders; they do not make habits overdue.

## Smart Lists

Smart lists are queries over items, not stored collections.

- Today: due today, overdue actionable items, and non-completable events that overlap today.
- Scheduled: dated future items, excluding habits; overdue actionable items only when the view says to show them.
- All: active non-habit items grouped by list and section.
- Completed: completed tasks, completed habits for the current cycle, and completed completable events.
- Flagged: flagged active items.
- Urgent: active items with urgent trigger enabled.
- Tags: navigates to tag management, not a direct item query.

Completed items are hidden from active views unless the view has Show Completed enabled. Past non-completable events roll off lists after their day unless Show Past Events is enabled. They are not deleted and are not overdue.

Scheduled's Overdue section is only for unfinished actionable items. Past non-completable events shown through Show Past Events, and completed dated items shown through Show Completed, remain grouped by date rather than being labeled overdue.

The sidebar Tags tile, tag chip set, tag chip counts, and tag-scoped item rows are active-work surfaces. They exclude deleted items, completed tasks/habits/completable events, and rolled-off past calendar events, except during the brief row-completion fade.

Search is also an active-work surface: it matches title, body, and tags, but excludes deleted, completed, and rolled-off past calendar items, except during the brief row-completion fade.

## Habits As A First-Party Module

Habits are built-in module behavior, not a separate product. They still persist as `Item` files so cross-platform clients read one model.

The habit module owns:

- Daily, weekly, and monthly cadences in the UI.
- Legacy cadence normalization.
- Timestamped completion events.
- Current-cycle progress.
- Forgiving streaks: one missed cycle is tolerated; two consecutive missed cycles break the streak.
- Heatmap and completion log.
- Repeating local notifications keyed to cadence.

If external plugins ever become real, Habits should still read as an enabled first-party feature/module, not an optional external extension.

## Recurrence

Repeat rules are RRULE strings on items. Clients write repeat end dates as UTC `UNTIL` timestamps, and must read UTC timestamps, floating local datetimes, and bare local dates. User-authored end-repeat behavior is day-granular: ending on a date includes occurrences on that date.

## Settings

Settings is for app-wide preferences, built-in module status, local maintenance, and about information.

Current app-wide preferences:

- Default new-item type for list `+` creation and Quick Capture's starting type.
- Show or hide counts on pinned smart-list tiles.
- Default reminder time for date-only reminders and new habit reminder times.
- Notification permission status, with a request action only while permission is undetermined.

Current module status:

- Habits are a built-in first-party module.
- External plugins are not part of the current app UI.

Current local maintenance tools:

- Export Library: creates a ZIP copy of the app-private Lists folder and opens the system share sheet.
- Rebuild Cache: reloads the in-memory snapshot from disk without seeding sample data.

Disabled rows should be rare and honest about being unavailable. They should not look like working settings unless they perform a real action.

Sync is not part of the current app UI and should not appear as a Settings section until there is actionable local or network behavior to configure.

Urgent is currently a smart-list trigger plus normal reminder scheduling. Alarm-style urgent alarms and location reminders should stay off-screen until they have real controls.

## Deletion And Recovery

Deleting an item or list is soft delete first. Deleting an item also tombstones live descendants, and restoring that item restores descendants deleted by the same operation. Deleting a list also tombstones live items inside that list and descendant lists. Recently Deleted shows deleted items and lists, supports restore, and supports permanent delete with confirmation. Restoring a list restores descendant lists and live items deleted by that list operation; items and sublists that were already deleted before the list deletion stay deleted. Old tombstones auto-purge after the retention window.

Restoring an item whose parent is still deleted detaches it. Restoring an item whose list is still deleted moves it to a live fallback list; descendants restored with that item follow the restored parent's live list and section. Restoring a child list whose parent is still deleted detaches it to the sidebar root.

## Cross-Platform Rule

iOS defines the behavior standard for now. Android should translate the same model and interactions into native Android patterns:

- Same file format.
- Same item/list/tag/habit/event rules.
- Same smart-list visibility.
- Same soft delete and recovery semantics.
- Same habit module behavior.
- Platform-native controls, gestures, typography, and navigation.

Android should not invent a separate product. Differences are allowed only when they are the platform-native way to express the same user outcome.
