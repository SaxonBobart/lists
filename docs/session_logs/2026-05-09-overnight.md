# 2026-05-09 — overnight Ralph-loop run

## TL;DR

You went to sleep with M0 done (sample Today screen wired to disk). You woke up to **14 feature iterations + 1 test-fix** on a new branch `feat/m1-screens` that you can review and merge. All on `main`'s parent; no pushes, no merges.

## Branch + how to inspect

```sh
git log --oneline main..feat/m1-screens
git diff main...feat/m1-screens --stat
```

Each commit is one iteration. If something looks wrong: `git branch -D feat/m1-screens` wipes the entire run — `main` is untouched.

## Iterations completed

| # | Slug | What landed |
|---|---|---|
| 1 | sidebar-home | Full Sidebar / Home as the new NavigationStack root: 6 colored smart-list tiles (Today amber, Scheduled orange, Flagged pink, Urgent danger, Completed grey, All sage), "My Lists" inset card with user lists, "System" card with Tags + Recently Deleted. Mirrors `screens-mobile.jsx`. |
| 2 | list-detail-vertical | (Bundled into iter 1) `ListDetailView` with sections, ItemRow reuse, empty state. |
| 3 | item-detail-readonly | Tap item → `ItemDetailSheet` with three cards (title + tag chips + body, Date & Time, Organisation). All read-only. |
| 4 | item-detail-edit | Same sheet rewritten as editable: TextField title / body, DatePicker (with separate include-time toggle), reminder toggle, flag toggle, Priority + List menus, Save (disabled when not dirty), Delete (with confirmation). Adds `ItemStore.{add,update,delete}` + 3 new tests. |
| 5 | quick-capture | The Today FAB is now active. Tap → bottom sheet with auto-focused title field, date toggle + DatePicker, flag toggle, list picker. Honors list's `defaultItemType`. |
| 6 | list-crud | `ListEditSheet` (dual-mode create/edit) with name field, 24-icon SF Symbol grid, 9-color palette, default-item-type picker. Sidebar gets `+` toolbar button + per-row context menu (Edit / Delete). Inbox is undeletable. |
| 7 | recently-deleted | Switched all user-facing deletes to soft-delete. New `RecentlyDeletedView` shows tombstoned items + lists with Restore (sage) and Delete Forever (red, confirmed). Bootstrap auto-purges anything > 30 days old. SmartList predicates and ListDetail / Sidebar counts now filter `deletedAt == nil`. |
| 8 | tags-overview | Sidebar's Tags row now navigates to `TagsOverviewView` (every tag in use, sorted by count desc). Tap a tag → `TaggedItemsView` (reuses ItemRow, sorted by due). |
| 9 | habit-detail | Tapping a habit row opens `HabitDetailView` (instead of the task-shaped sheet). Title + frequency + goal + streak + circular progress ring + +1 button + 12-month heatmap. New `HabitCycle.key(for:on:)` (per spec §3.2.1) and `HabitStats.streak`. `ItemStore.{incrementHabit,setHabitCount}`. |
| 10 | settings-skeleton | Gear toolbar button on Sidebar opens Settings sheet with all six spec Tier 3 sections (Appearance, Sync, Triggers, Notifications, Data, About). Most rows are placeholders with naming to make clear what lands when. |
| 11 | notification-scheduling | New `NotificationScheduler` actor wrapping `UNUserNotificationCenter`. Schedule on add/update/restore, cancel on delete/done. Honours `reminder.early` offset. Settings → "Request" button calls `requestAuthorizationIfNeeded` (first tap shows the system permission alert). AlarmKit deferred per `project_m6_deferred`. |
| 12 | sub-items | `ListDetailView` flattens parent → children → grandchildren depth-first; `ItemRow` gained an `indent` parameter. Parents show a "n/total" subtree progress chip. SampleData adds a "Plan trip to Tasmania" parent + "Book accommodation" + "Pack hiking boots" sub-items so a fresh install demonstrates nesting. |
| 13 | thread-view | `ThreadView` (read-only) flattens an item's hierarchy into one continuous H1/H2/H3 document per spec §2.4. Reachable from a "Thread view" row in `ItemDetailSheet` when the item has children. |
| 14 | search | Sidebar gets `.searchable` (always-visible drawer). `SearchResultsView` filters items by title / body / tag substring, groups results by list. |
| 14b | test fixup | Updated the SampleData and ItemStoreMutation tests to match the new 6-item seed shape from iter 12. |

## What works end to end

Open `platforms/ios/Lists.xcodeproj` → ⌘R. You can:
- Browse the Sidebar, see counts updating live
- Tap any smart-list tile → its screen
- Tap a user list → `ListDetailView` with sub-item nesting
- Tap an item → detail sheet (or `HabitDetailView` for habit-typed items)
- Edit fields, save (changes persist to `Documents/Lists/<list>/<id>.md`)
- Delete an item → soft-deletes → check Recently Deleted to restore
- Tap "+" on the Sidebar → `ListEditSheet` for new list
- Long-press a list row → Edit or Delete
- Tap the FAB on Today → quick capture
- Search items from the Sidebar field
- Tap gear → Settings (most rows show a "coming when" placeholder)
- Open a parent item → "Thread view" row → flat hierarchy

## Test count

23/23 Swift Testing tests passing (was 19 at start of session).

## Things you should know

### Simulator container quirks

The iOS simulator's app container UUID changed multiple times during the session as Xcode reinstalled the app. Old containers' `Documents/Lists/` folders linger on disk and sometimes get inherited by new installs (or older data sticks around). If the Sidebar shows surprising counts, wipe `~/Library/Developer/CoreSimulator/Devices/65D9F3B1-4A19-4820-B6F7-703D4BDF823C/data/Containers/Data/Application/<APP-UUID>/Documents/Lists/` for the latest container. Bootstrap re-seeds 6 sample items (3 top-level tasks + parent + 2 children) on next launch. See `feedback_wipe_sim_data_when_bundle_shared` memory.

### Tap-to-checkbox quirk noticed during M0

Two of the seeded items got marked done at some point during the M0 session without me touching anything I can identify. Couldn't reproduce; might be a SwiftUI nested-Button hit-testing artefact or an actual stray tap on the Simulator window. If you see it again, it's worth investigating with `snapshot_ui` between iterations. Not blocking.

### Ralph loop infrastructure

Set up but not auto-run:
- `BACKLOG.md` (root) — 14 items moved from Next to Done, 0 left
- `docs/AGENT.md` — learning log
- `docs/PROMPT.md` — fresh-Claude prompt template
- `docs/loop_runner.sh` — bash runner with `--max-iterations` cap (chmod +x, NOT started)
- `docs/LOOP.md` — appended every iteration's commit sha
- `docs/ralph_loop.md` — research summary + how this project uses the pattern

If you want to fire a real autonomous bash loop later, `./docs/loop_runner.sh` from repo root. It needs `claude` CLI in PATH.

## What's NOT done (out of scope this run)

- **Inline editing in ThreadView** — currently read-only; clicking back to ItemDetailSheet to edit is the workaround.
- **Sub-item creation UI** — schema works (set `parentId` on the Item), but there's no `+ add sub-item` affordance yet.
- **Edit-history UI for habits** — the model + `ItemStore.setHabitCount` exists; UI is a follow-up.
- **AlarmKit / urgent triggers** — gated on the paid Apple Developer Program per `project_m6_deferred`.
- **Self-managed sync folder, Lists Sync, Triggers settings** — Settings shows them as "Not yet available."
- **Calendar view for Scheduled** (per spec §2.8.1) — Scheduled is currently a flat list.
- **Column / kanban view** for any list — vertical only.
- **Grocery-mode auto-categorisation** — flag exists on `ItemList` (untested visually); the lexicon stub at `shared/lexicons/shopping.en.json` still needs the ~200-entry pass.
- **Format spec realignment** — `shared/format/` still uses old "reminder" naming; the iOS code is on the new `item` primitive. Realign when next touching the format spec.

## Recommended morning moves

1. **Review the branch.** `git log --oneline main..feat/m1-screens` then `git diff main...feat/m1-screens --stat`. Browse a few feature commits to spot anything you'd change.
2. **Wipe the simulator container** (per the note above) and `⌘R` to see a fresh seed with the parent+2 children sub-items rendering.
3. **Tap your way through** every screen to spot UX bugs that didn't surface in unit tests.
4. **Decide what to merge.** All 14 iterations on a single branch — easy to fast-forward with `git checkout main && git merge feat/m1-screens` if you like the lot. If you want to cherry-pick, each iteration is one commit.
5. **Pick the next milestone** from `docs/CURRENT.md`'s "What's next" or add a fresh `BACKLOG.md` for M2 (inline thread editing, sub-item creation UI, calendar view for Scheduled, kanban toggle, grocery auto-categorisation, sync, etc.)
