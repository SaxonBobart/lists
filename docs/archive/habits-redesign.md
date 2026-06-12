# Habits redesign — plan & notes

Living notes for the habit-row / completion work. Behavioural-science
background (forgiving streaks, flexible cadences, reminder correctness) lives
in `audit/research/habit-ux.md` — this file is the build plan.

## Done

- **Row binding fix** (shared with all item rows): the UIKit list now reloads a
  row when its underlying `Item` changes content, not just on insert/remove/move.
  Fixes "edits don't show until you leave", and ticking / un-ticking with
  "Show Completed" on. (`ListDetailCollectionView.applySnapshot`.)
- **Completed-habit tick**: custom symbol `habit.completed` (in the asset
  catalog) — `checkmark.circle.fill` combined with `badge.clock` via the SF
  Symbols app. Rendered in palette mode `(secondary, accent)` → blue checkmark
  (matches a done task), muted-grey clock badge. The clock signals the count is
  reviewable; tapping is non-destructive (no longer silently undoes a
  multi-per-cycle goal). (`ItemRow.habitRing`.)
- **Incomplete habit ring** restyled to match a task's open checkbox (thin grey
  `circle`) with the count + a blue progress arc on top.
- **Removed** the trailing repeat glyph — the ring's count already reads as a
  habit, and a trailing repeat icon looked like a recurring *task*.
- **Completed title greys** for both tasks and habits (keyed off `isComplete`,
  not `done`) to the same `secondary` tone as the notes/meta subtext. The icon
  stays bright; only the text dims.
- **Tapping a completed habit opens the detail view** (`HabitDetailView`) — the
  ring is no longer disabled at goal, so a tap reviews instead of doing nothing.

## Shipped: detail-screen redesign + editable log

The detail screen was rebuilt around a real, editable completion history, and the
brittle parts of the habit model were fixed at the same time. See
`PRODUCT-SPEC.md` §Habits for the behaviour and `HabitStatsTests` /
`HabitCompletionMigrationTests` for the contracts.

- **Timestamped completions.** `Item.completionLog: [String: Int]` is now a
  *computed* getter over a stored `completions: [HabitCompletion]` (each a `{id, at}`
  event). Per-cycle counts are derived by grouping events through `HabitCycle.key`.
  Legacy `completion_log` files migrate on decode (one-way; the old key is dropped on
  the next save). This is what lets the Log edit the *time* of an entry, not just a count.
- **Two tabs: Overview · Details** (revised from the first cut's three). Overview =
  two stat cards (streak in the cadence + this-cycle count with **+1 / −1**), a
  per-cycle contribution grid, and a "Recent" list with a See All push to the full,
  editable log (day-grouped, swipe-to-delete, tap-to-edit, add-a-past-entry). Details =
  the form plus the flexible-goal toggle.
- **Frequency locked to daily / weekly / monthly.** `HabitFrequency.habitCadences`
  drives both pickers; `normalizedForHabit` folds any legacy cadence onto the three
  (healed on the next save). Tasks keep the full RRULE range — untouched.
- **Per-cycle grid.** `HabitHeatmap` switches on the cadence — the last 30 days (10×3),
  52 weeks (13×4), or 12 months (one labelled row) via `HabitStats.recentCycles` — one
  square per cycle, coloured by that cycle's `count / goal`. The grid fits the card
  without scrolling (flexible columns, square cells). Tapping a square logs a completion
  in that cycle.
- **Single Date / Date Range add.** The completion sheet adds one event (date + time)
  or backfills a whole range (one per day) via `ItemStore.addCompletions(_:on:)`.
- **Forgiving streaks.** `HabitStats.streak` is "never miss twice"; the Overview leads
  with the streak card (in the habit's cadence). The calm `consistency(...)` stat
  still exists in `HabitStats` but is no longer shown on the screen.
- **Flexible "X times per week/month".** `Item.flexibleGoal` re-reads `goalPerCycle`
  as a per-cycle target; the heatmap counts real per-day activity so a weekly habit
  still shows which days it happened.
- **Repeating reminders (REM-1 fixed).** `NotificationScheduler.habitTriggers` builds
  repeating `UNCalendarNotificationTrigger`s per frequency (weekday cadences fan out
  into per-day requests; `cancel` clears them all).

Store methods behind the Log: `addCompletion`, `deleteCompletion`, `updateCompletion`,
`removeLatestCompletion` (the −1); `incrementHabit`/`setHabitCount` reimplemented on events.

### Deferred / follow-ups
- Rest-day / explicit "skip" marking (the `scheduledCycle` extension point in `HabitStats`).
- A weekday picker in Edit for weekly reminders (today the weekly reminder uses the
  weekday the reminder time was set on).
- Re-record the pre-existing `ItemRowSnapshotTests`/`SettingsViewSnapshotTests`
  references (they drifted from the earlier row restyle, not this work).

## Shipped: custom habit badge symbol (replaces the `?`)

The completed-habit tick now uses a real custom SF Symbol instead of the
`?`-badge stand-in. There is **no off-the-shelf** `checkmark.circle.badge.clock`
system symbol, so we built one.

- **What we use:** `habit.completed.symbolset` in the asset catalog —
  `checkmark.circle.fill` combined with `badge.clock` in the SF Symbols app
  ("Combine Symbol with Component"), exported as the Xcode symbol template. The
  badge sits on its own layer, so palette mode colours the tick and badge
  independently. Referenced as `Image("habit.completed")`, palette
  `(secondary, accent)` → grey clock badge, blue checkmark.
- **Why `badge.clock`, not the repeat arrows:** the "Combine with Component"
  feature only offers Apple's preset badge glyphs (no repeat). We tried hand-
  assembling a `clock.arrow.trianglehead…path.dotted` badge from two exported
  templates — it worked technically but read as busy/ugly at row size, so we
  dropped it for the clean preset clock.
- **Habit type glyph** (new-item sheet, habit detail, item detail) uses
  `checkmark.arrow.trianglehead.clockwise` — distinct from the completed-tick
  badge, reads as "recurring done".
- **No trailing row marker.** Briefly added a trailing habit glyph beside the
  flag; removed again — same reason as before, it muddies the row.
