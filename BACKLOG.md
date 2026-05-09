# BACKLOG

Single source of truth for "what's next." The Ralph loop reads the top item, does it, then moves it to **Done** with a commit hash.

Format: `- [ ] <slug> — <one-line description>`

## Active milestone: M1 — screens

Goal: bring up the rest of Tier 1 (Sidebar / list detail / item detail / quick capture) plus the major Tier 2 / Tier 3 screens. Branch: `feat/m1-screens`.

## Next (top = next iteration)

- [ ] sidebar-home — Sidebar / Home view: large title "Lists", pinned smart-list tiles (Today / Scheduled / Flagged / All / Completed / Urgent), "My Lists" section, "Tags" + "Recently Deleted" footer. Becomes the NavigationStack root; tap routes to TodayView and other screens (placeholder where not yet built).
- [ ] list-detail-vertical — Single user list view (vertical layout). Section headers + items beneath. Reuses ItemRow. Empty state.
- [ ] item-detail-readonly — Tap item row → modal sheet showing title, body (markdown), due/time, reminder, tags, priority, flag. Read-only.
- [ ] item-detail-edit — Same sheet, editable. Title field, body editor, date+time picker with all-day toggle, reminder toggle + early-reminder picker, tag chip editor, priority picker, flag toggle, delete button. Save through `ItemStore.update(item:)` (new method).
- [ ] quick-capture — Enable the FAB. Tap → bottom sheet with title field, list picker, optional date+time, "Add" button. Adds via `ItemStore.add(item:)` (new method).
- [ ] list-crud — Create / rename / delete user lists. NewListSheet (name + SF Symbol icon picker + color picker) + EditListSheet. Wired to ItemStore.
- [ ] recently-deleted — Soft-deleted items + lists with restore + permanent-delete. Auto-purge after 30 days (per spec §2.8).
- [ ] tags-overview — All tags grouped, items under each tag. Tap a tag → filtered view.
- [ ] habit-detail — Habit detail screen: title, current cycle count + goal, streak counter (when `showStreak`), 12-month heatmap component, "Edit history" button.
- [ ] settings-skeleton — Settings root with sections per spec Tier 3 (Appearance, Sync (disabled placeholder), Triggers, Notifications, Data, About).
- [ ] notification-scheduling — UNUserNotificationCenter wrapper. Schedule on item save, cancel on delete/done. AlarmKit (urgent triggers) stays deferred.
- [ ] sub-items — UI for parent / child nesting in vertical list view (schema already supports it). Indent + sub-item progress badge ("3/5 done") on parent.
- [ ] thread-view — Toggle on item with sub-items. Flatten parent + children + grandchildren into one editable doc with H1/H2/H3 hierarchy.
- [ ] search — Full-text across items. Search field at top of Sidebar. Results screen with grouping by list.

## Done

(Items move here with commit-sha + iteration number as they complete.)
