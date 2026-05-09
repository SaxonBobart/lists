# CURRENT.md — you are here

Single-page status pointer. Updated each session.

## Active milestone

**M1 — screens ✅ DONE on `feat/m1-screens` (awaiting review & merge)**

14 iterations + 1 test fixup landed overnight via the Ralph loop pattern. See `docs/session_logs/2026-05-09-overnight.md` for the full hand-off.

## What's next

After merging `feat/m1-screens`, sensible follow-ups:

1. **Inline thread-view editing** — currently read-only. Per-position TextField management is the work.
2. **Sub-item creation UI** — schema supports `parentId` already; needs a `+ Add sub-item` affordance in detail sheet / list view.
3. **Habit edit-history UI** — `ItemStore.setHabitCount(_:count:on:)` is in place; just needs the screen.
4. **Calendar view for Scheduled** (spec §2.8.1) — Month / Week / Day variants with drag-to-reschedule.
5. **Column / kanban toggle per list** (spec §2.6.3).
6. **Grocery-mode auto-categorisation** (spec §2.6.2). Lexicon at `shared/lexicons/shopping.en.json` still stub.
7. **Sync** — Lists Sync v1 architecture decision + transport. Out of v1.
8. **AlarmKit** — gated on paid Developer Program (per `project_m6_deferred`).
9. **`shared/format/` realignment** — uses old "reminder" naming; iOS code is on `item` primitive.
10. **Linux / Windows / Android implementation** — placeholders + research already in tree under `platforms/{linux,windows,android}/`.

## What exists right now

- Repo skeleton + cross-platform foundations (M0)
- iOS Xcode project (Swift 6.2, iOS 26, sage tokens)
- Data layer: Item / ItemList / FrontmatterCodec / FileStore / ItemStore / SmartList / SampleData / HabitCycle / HabitStats
- NotificationScheduler (UNUserNotificationCenter wrapper)
- Screens (M1 — currently on `feat/m1-screens`):
  - SidebarView (NavigationStack root + search + settings + new-list)
  - TodayView, SmartListScreen
  - ListDetailView (with sub-item tree)
  - ItemDetailSheet (editable) + HabitDetailView + ThreadView
  - QuickCaptureSheet + ListEditSheet
  - RecentlyDeletedView + TagsOverviewView + TaggedItemsView
  - SettingsView + SearchResultsView
- 23 Swift Testing tests (all green)
- Ralph loop infrastructure: BACKLOG.md, AGENT.md, PROMPT.md, LOOP.md, loop_runner.sh, ralph_loop.md

## Known follow-ups + open questions

(Same as 2026-05-09 morning; updated post-overnight-run.)

- **`shared/format/` uses old "reminder" naming** — needs realignment with the new "item" primitive.
- **Tier 1 screen mockups not yet exported as PNGs** — the prototype HTML is the visual reference.
- **`shared/lexicons/shopping.en.json`** is a 20-entry skeleton; needs ~200 entries before grocery mode ships.
- **`LICENSE.app-store-exception`** drafting — needed when App Store is in scope (post paid Developer Program).
- **Old simulator data conflict** — see `feedback_wipe_sim_data_when_bundle_shared` memory.
- **Stray-tap quirk** — two seeded items got marked done at some point during M0 without a known cause. Watch for it.
- **No `tap` UI automation** in this XcodeBuildMCP install — manual checkbox interaction not scripted.

## Don't forget

- Bundle id `io.github.saxonbobart.lists`, team `899XX9P8T4` (Personal — AlarmKit deferred until paid)
- Drive the simulator (build_run_sim + screenshot) before claiming iOS work done
- Conventional Commits, never push without explicit go
- Saxon is non-technical — frame technical decisions as product effects
