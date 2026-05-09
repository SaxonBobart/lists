# BACKLOG

Single source of truth for "what's next." The Ralph loop reads the top item, does it, then moves it to **Done** with a commit hash.

Format: `- [ ] <slug> — <one-line description>`

## Active milestone: M1 — screens

Goal: bring up the rest of Tier 1 (Sidebar / list detail / item detail / quick capture) plus the major Tier 2 / Tier 3 screens. Branch: `feat/m1-screens`.

## Next (top = next iteration)

## Done

- [x] sidebar-home — `3eee5c8` · iter 1 · NavigationStack root with smart-list tiles + lists + system rows
- [x] list-detail-vertical — `3eee5c8` · iter 1 (bundled) · ListDetailView with sections + ItemRow reuse + empty state
- [x] item-detail-readonly — iter 3 · ItemDetailSheet + SheetRow, three cards, all fields read-only, tap-row presents
- [x] item-detail-edit — iter 4 · TextFields + DatePicker + Menu pickers + Toggles + Save/Cancel/Delete; ItemStore.{add,update,delete}; 22 tests passing
- [x] quick-capture — iter 5 · QuickCaptureSheet (medium/large detents), Today FAB enabled, ItemStore.add wired
- [x] list-crud — iter 6 · ListEditSheet (create+edit), Sidebar + button + context menu, ItemStore.{addList,updateList,deleteList}
- [x] recently-deleted — iter 7 · soft-delete, RecentlyDeletedView, restore + permanent-delete, 30-day auto-purge on bootstrap
- [x] tags-overview — iter 8 · TagsOverviewView (counts, sorted) + TaggedItemsView (per-tag filter)
- [x] habit-detail — iter 9 · HabitDetailView, HabitHeatmap (7×53 grid), HabitCycle key map, HabitStats.streak, +1 ItemStore.incrementHabit
- [x] settings-skeleton — iter 10 · SettingsView with all 6 sections, gear toolbar button on Sidebar, placeholders for sub-screens
- [x] notification-scheduling — iter 11 · NotificationScheduler actor, schedule/cancel hooks in ItemStore CRUD, Settings → Request button
- [x] sub-items — iter 12 · ItemRow indent + flatten() in ListDetailView, "n/total" progress chip on parents, sample data has a parent+2 children
- [x] thread-view — iter 13 · ThreadView (read-only, H1/H2/H3), reachable via "Thread view" row in ItemDetailSheet
- [x] search — iter 14 · SearchResultsView (title/body/tag substring), .searchable on Sidebar, results grouped by list
