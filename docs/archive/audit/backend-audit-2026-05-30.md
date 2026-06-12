# Lists Backend Audit — 2026-05-30

Compiled 2026-05-30. Scope: non-UI backend only. Read-only audit — no code changed.

> **No code was modified in this pass.** Every fix below is a recommendation only. The codebase currently carries uncommitted work (the Habits detail redesign and inline-editing changes) that is pending your UI review. Applying backend fixes now would entangle with that review and make it harder to judge the UI work cleanly, so this pass deliberately stops at "found and prioritized."

---

## 1. TL;DR for Saxon

**Overall backend health: solid foundation, a handful of real correctness gaps — none catastrophic, but four are worth fixing before you lean harder on habits and reminders.**

The big structural risks the May 25 hardening sprint set out to kill are genuinely dead. A single bad file or a stray underscore-named file can no longer brick the whole app on launch (DI-1/2/3, AGENT-1/2), the worst concurrency lost-update loops are fixed (CONC-2), recurrence and reminders no longer crash the load path, and the editor undo and per-cell performance issues are resolved. The save-to-disk machinery (atomic writes, quarantine of bad files) is well built.

What's left falls into three buckets:

1. **Things that go silently wrong with reminders and habits.** The most important: if you accumulate enough habits/reminders, iOS silently stops scheduling some of them with zero warning — a habit you rely on just goes quiet (SCHED-1). And recurring tasks compute their "next time" in whatever timezone your phone is currently in, ignoring the timezone the task was created in, so repeats can drift by an hour or a day after travel or daylight-saving (REC-1).

2. **Things that can quietly lose or corrupt data in edge cases.** A rapid drag-reorder or typing into a brand-new item can, on rare timing, save the *older* value to disk so the change silently reverts on next launch (DI-4 — still open from the prior audit). Migrating very old habits can silently drop their completion history (the Models migration finding). None of these are common today on a single device, but they get more likely the moment sync arrives.

3. **Counts and states that disagree between two screens.** Old "legacy" habits can show as complete in the list but incomplete on the detail screen (and vice versa) because the two screens bucket completions differently. The sidebar "All" tile count is inflated by completed sub-tasks and habit sub-items that don't actually show when you open "All."

### Issue count by severity

| Severity | Meaning | New findings this pass | Known-open carried forward |
|---|---|---|---|
| **P1** | High impact, fix soon | 2 (SCHED-1, REC-1) | 1 (DI-4) |
| **P2** | Real bug, narrower trigger | 7 | — |
| **P3** | Edge-case / latent / robustness | 9 | — |
| **Total new** | | **18** | **1 still-open** |

(Two findings independently surfaced as "REC-1" from two different reviewers; they describe different things — the recurrence-timezone bug and the recurring-task-spawn snapshot/placement issue — and are listed separately below as **REC-1** and **REC-SPAWN-1** to avoid confusion.)

---

## 2. Status of known-open findings

These are the findings the prior audit left open (or that the May 25 sprint did not cover). Verdicts below were confirmed by reading the current working tree.

| ID | Still present? | Where | Severity | Notes |
|---|---|---|---|---|
| **DI-4** | **Yes — still present** | `ItemStore.swift` Task-spawn sites: lines 258, 309, 350, 639, 762; triggered from `ListDetailCollectionView.swift:1983` + `:1992` | **P1** | Five fire-and-forget `Task {}` writes with no shared ordering. Two concrete same-target collisions confirmed (reparent+reorder of one dragged item; addInlineItem then typed-title flush). On-disk value can be the older one; surfaces only on next launch. Errors swallowed by `try?`. |
| **CONC-2** | **Mostly fixed; one residual** | Fixed across all bulk ops (`removeTag` 372, `renameTag` 392, `bulkSetFlagged` 417, `bulkAddTag` 428, `bulkMove` 445/455, `deleteSection` 788, `promoteOthersToSection` 705). **One residual:** `migrateLegacySectionsIfNeeded` (`ItemStore.swift:836`, loop 859–864) | **P3** | The residual writes a pre-loop snapshot instead of re-fetching by id. Runs only at bootstrap before the UI takes input, so realistic blast radius today ≈ zero. Flagged for consistency and because moving it to a user-triggered path later would make it a live lost-update bug. |
| **CONC-4** | **Partially fixed** | Bootstrap double-seed: **fixed** (`isBootstrapping` guard, `ItemStore.swift:28`, 43–47). Fire-and-forget-write half: **not fixed** — same as DI-4 | **P1 (via DI-4)** | The half that remains is the DI-4 ordering hazard above. |
| **AGENT-1** | **Fixed** | `Item.swift:83-86` — `init(from:)` maps any unknown `type:` raw value to `.task` instead of throwing | n/a | Verified by three reviewers. One stray/future `type:` can no longer abort a load. The *HabitFrequency* angle of the same idea (unknown/legacy frequencies still being acted on) resurfaces as **SCHED-2** below. |
| **AGENT-2** | **Fixed** | `FileStore.swift:237-240` filters item files to `.md` AND `!hasPrefix("_")`; `.list.yml` is dot-prefixed and read explicitly; `.quarantine` skipped (`:188`) | n/a | `_status.md` and other underscore aux files are no longer misdecoded as items. Verified. |

---

## 3. New findings

Grouped by subsystem. Each lists severity, file:line, the risk in plain language, and the recommended fix.

### Notifications — `Core/Notifications/NotificationScheduler.swift`

#### SCHED-1 · iOS 64-notification limit is never accounted for; reminders silently overflow — **P1**
- **Where:** `NotificationScheduler.swift:58-66` (schedule loop), `133-140` (weekdays = 5 triggers, weekends = 2 triggers per habit), `154-157`
- **Risk (plain language):** iOS hard-caps an app at 64 pending notifications. Each weekday-style habit eats up to 5 of those slots. With enough habits/reminders the cap is exceeded, iOS refuses the extras, and because every registration uses `try? await center.add(...)` the failure is swallowed with no log and no user notice. A habit the user is relying on simply goes quiet. This is the highest-impact correctness risk in this file because it is invisible and gets worse the more the feature is adopted.
- **Recommended fix:** (1) Collapse weekday/weekend fan-out to a single trigger and/or cap habit reminders, surfacing a one-time notice when the cap is hit; (2) stop swallowing `center.add` failures — log them, ideally bubble a signal so the app can warn the user; (3) enforce a per-habit trigger budget. (Normalizing per SCHED-2/3 already shrinks worst-case fan-out dramatically.)

#### SCHED-2 · `schedule()` switches on RAW frequency, not normalized — legacy/imported habits schedule cadences the UI can't control — **P2** (xref AGENT-1)
- **Where:** `NotificationScheduler.swift:116` (reads `item.frequency` raw), `128-151` (full enum switch incl. hourly/weekdays/weekends/fortnightly/everyThreeMonths/everySixMonths/yearly)
- **Risk:** Habits are locked to daily/weekly/monthly in the UI, but a habit loaded from disk with a legacy/imported raw value (e.g. `hourly`) that's never re-saved is scheduled on that raw cadence. So an old/imported habit can ping the user *every hour* on a schedule the app no longer offers and the user can't turn down without deleting and recreating it — contradicting the file's own "gentle, never spammy" intent.
- **Recommended fix:** Normalize before branching: `let frequency = (item.frequency ?? .daily).normalizedForHabit` at line 116, so the scheduler only ever emits daily/weekly/monthly — matching the model invariant that `HabitCycle`/heatmap already use. Also collapses fan-out (reinforces SCHED-1) and fixes SCHED-3.

#### SCHED-3 · `.custom` habit frequency is persistable but scheduled as plain daily — **P2**
- **Where:** `NotificationScheduler.swift:129-130` (`case .daily, .custom -> daily trigger`)
- **Risk:** A habit can be saved with `frequency == .custom` (from the QuickCapture custom preset), but `.custom` carries no interval data and is lumped in with daily — so a "custom" habit just reminds every day regardless of what the user thought they picked. Wrong quietly rather than failing loudly.
- **Recommended fix:** Either disallow `.custom` for habits at the writer (fold to a supported cadence), or route through `normalizedForHabit` (which already maps `.custom -> .daily`) so behavior is intentional and documented. The SCHED-2 normalization at line 116 resolves this too.

#### SCHED-4 · `Calendar.current` (trigger) vs UTC (cycle key) mismatch — **P3**
- **Where:** `NotificationScheduler.swift:117` (local calendar for time/weekday/day/month), `76-78`
- **Risk:** Triggers fire in device-local time; `HabitCycle.key`/`HabitStats` bucket completions in fixed UTC. For travelers or near UTC-midnight, the reminder can fire on a day the stats engine attributes to the *adjacent* cycle — a habit looks "missed" for that cycle even though the user acted on the reminder.
- **Recommended fix:** Pick one timezone authority for habits and use it for both the trigger and `HabitCycle.key`; document the convention. Lower priority because it only bites around timezone changes / UTC-midnight edges on a single-device app.

#### SCHED-5 · All scheduling failures swallowed by `try?` — no diagnostics for the failures SCHED-1/2 cause — **P3**
- **Where:** `NotificationScheduler.swift:65` (habit add), `84` (task add)
- **Risk:** Every `center.add` is `try?`, discarding the thrown error (including the 64-limit overflow). No log, metric, or user signal that a reminder failed to register. This is what turns SCHED-1 into silent reminder loss.
- **Recommended fix:** Replace `try?` with do/catch that logs the error plus item id + identifier; consider returning success/failure from `schedule()` so `ItemStore` can surface a one-time notice. Pairs with SCHED-1.

### Recurrence — `Core/Recurrence/RecurrenceEngine.swift` + `ItemStore.toggleDone`

#### REC-1 · `dueTimeZone` is ignored when computing the next occurrence; repeats drift across timezones/DST — **P1**
- **Where:** `RecurrenceEngine.swift:19` (defaults to `calendar: .current`); call site `ItemStore.swift:129`
- **Risk:** A task set to repeat "every weekday at 9:00am" in New York will, after the device timezone changes (travel) or a DST transition, spawn its next occurrence using the *new* timezone's wall-clock — re-anchoring 9:00am to 8:00 or 10:00, and shifting the calendar day for month-end/weekly rules. The data model captured `dueTimeZone` specifically to make this stable, but the engine throws that information away.
- **Recommended fix:** Build a `Calendar` pinned to the item's `dueTimeZone` at the spawn site and pass it through: in `toggleDone`, set the calendar's `timeZone` from `item.dueTimeZone` then call `nextOccurrence(after:rrule:calendar:)` with it. The engine already threads `calendar` everywhere, so no engine change is needed beyond the caller passing the right one.

#### REC-2 · Complete → uncomplete → complete spawns a duplicate successor occurrence — **P2**
- **Where:** `ItemStore.swift:104-142` (spawn guarded only by `!wasDone` at 125; the un-complete branch at 139 does not despawn)
- **Risk:** Spawning happens on the completing transition. Un-completing only reschedules the reminder — it does NOT remove the successor the prior completion created, and `add()` has no dedup. So tick → untick → tick again leaves an extra duplicate future occurrence (and duplicate reminders). Easy to hit by ticking the wrong task and correcting it.
- **Recommended fix:** Make spawning idempotent — either remove the previously spawned successor on un-complete (tag spawned items with a series id), or before spawning, guard against an existing non-done sibling with the same rrule + computed nextDue (dedup by series+due). The dedup-on-spawn option is smaller and defends every repeated-completion path.

#### REC-3 · `UNTIL` is compared as a precise instant but authored as a date — last day's occurrence wrongly dropped (or an extra allowed) by up to the UTC offset — **P2**
- **Where:** `RecurrenceEngine.swift:66` (`n > until`), `89-95` (parseUntil); authored at `ItemDetailSheet.swift:583`
- **Risk:** The end-repeat picker yields local-midnight of the chosen day, stored/compared as a precise UTC instant. So "end Dec 31" can exclude the Dec 31 occurrence in the Americas (or slip the other way in UTC-positive zones). The end date the user set is effectively off by up to a day depending on their timezone.
- **Recommended fix:** Compare day-granular: end the series when `calendar.startOfDay(for: n) > calendar.startOfDay(for: until)` (using REC-1's pinned calendar), so "end Dec 31" includes Dec 31 everywhere.

#### REC-4 · Reconstructing a date at a nonexistent DST wall-clock can collapse/drop a spring-forward occurrence — **P3**
- **Where:** `RecurrenceEngine.swift:187-191` (`date(year:month:day:timeFrom:)`), used by 124/161/199/206
- **Risk:** Monthly/yearly/ordinal expanders rebuild candidates from Y/M/D + the anchor's time. On the spring-forward day a chosen time inside the skipped hour doesn't exist, so `Calendar.date(from:)` returns nil/shifted and a month or weekday can be skipped. The weekly+BYDAY path uses `date(byAdding:.day)` and preserves wall-clock, so the two paths diverge for the same notional time.
- **Recommended fix:** Make `date(year:month:day:timeFrom:)` DST-robust (build the day at noon then add the desired time, or use forward-resolving matching), so monthly/yearly behave like the weekly day-add path. Add a DST-gap test fixture.

#### REC-5 · `UNTIL` parser accepts only full UTC datetimes; date-only / floating forms silently fail to end the series — **P3**
- **Where:** `RecurrenceEngine.swift:89-95` (parseUntil)
- **Risk:** App-generated rules always use the full-Z form, so the app's own rules round-trip fine. But an imported/hand-edited RRULE with a date-only `UNTIL=20271231` parses to nil → series treated as never-ending → repeats forever. Latent until external RRULEs enter the system.
- **Recommended fix:** Try multiple formats in `parseUntil` (`yyyyMMddTHHmmssZ`, then `yyyyMMdd` as end-of-day, then a non-Z local form). Pairs with REC-3's day-granular comparison.

#### REC-6 · Successor computed from original due date, not completion time — a long-overdue recurring task spawns a successor still in the past (with no reminder) — **P3**
- **Where:** `ItemStore.swift:125-137` (`base = item.due`); interacts with `NotificationScheduler.swift:73` (`fireDate > .now` guard)
- **Risk:** Completing a task that was overdue for weeks spawns a successor one step after the *original* due — which may also be in the past, and the past successor gets no reminder. The series can quietly go silent.
- **Recommended fix:** Decide the semantics explicitly. If "next from now": loop `nextOccurrence` forward (bounded) until `nextDue > .now` before adding. If "strictly one step": document it and make the UI surface the overdue successor. Add a test for completing a stale recurring task.

#### REC-SPAWN-1 · Recurring-task successor is built from a stale pre-await snapshot and inherits parent/sortIndex — **P3**
- **Where:** `ItemStore.swift:104-142` (spawn block; `item` captured at line 105, used after awaits at 115/117; `next` inherits original `sortIndex`/`section`/`parentId`)
- **Risk:** Two edges: (a) `next` inherits the original's `parentId`/`sortIndex` verbatim — a recurring SUB-task spawns its next instance nested under the same parent with the same sort position, which may not be intended; (b) `next` is built from a snapshot captured before several awaits, so a concurrent edit landing during those awaits is reflected as stale title/body/tags in the *newly created* occurrence. No data loss, but surprising placement/content.
- **Recommended fix:** Build `next` from a re-fetched live copy (`items.first(where:)`) taken after the awaits. Decide intentionally whether a spawned occurrence should reset `parentId`/`sortIndex` (e.g. land at top-level) rather than inheriting the completed instance's placement.

### Stores & persistence — `Core/Stores/ItemStore.swift`, `Core/Storage/FileStore.swift`, `FrontmatterCodec.swift`

#### DI-4 (carried forward, still open) — see Section 2 — **P1**

#### PERSIST-1 · `loadAll` aborts the entire library if any directory listing throws — **P2**
- **Where:** `FileStore.swift:236` (walk), `:268` (walkSubdirsOnly)
- **Risk:** DI-1 made per-FILE parsing resilient, but the directory enumeration itself is bare `try fm.contentsOfDirectory(...)`. One unreadable subfolder (permissions/ACL, dangling symlink, I/O error) throws out of `loadAll` → the user gets an *empty* library with no quarantine entry and no banner, even though most data parses fine. The per-file resilience guarantee doesn't hold at the folder level.
- **Recommended fix:** Wrap each `contentsOfDirectory` in do/catch: on failure, record a quarantine-style issue for that folder and continue walking siblings instead of throwing. So one bad directory degrades to "this folder couldn't be read" rather than an empty library.

#### PERSIST-2 · Hard delete / cross-list move throws (and silently loses the action) when the list folder isn't mapped — **P2**
- **Where:** `FileStore.swift:108` (`deleteItem`→`listDirectory`), `:78` (`writeItem`→`listDirectory`), `299-304` (`listDirectory` throws `fileNoSuchFile`)
- **Risk:** If a list's `.list.yml` was quarantined (so the list isn't in `pathById`) but its item files still parsed into `items`, then deleting such an item throws — and because delete is `async throws`, the in-memory removal never runs, so the item stays visible but its file is never removed ("I deleted it and it came back"). Saving/capturing INTO such a list is silently dropped via the universal `try?` at call sites ("my save vanished"). Narrow trigger, zero feedback.
- **Recommended fix:** Have `listDirectory` reconstruct/create the folder from the in-memory `ItemList` instead of throwing; OR when a list header is quarantined, also skip its item files so orphaned items never reach the live set. And stop swallowing save/delete errors at call sites.

#### CONC-2-RESIDUAL · `migrateLegacySectionsIfNeeded` writes a pre-loop snapshot — **P3** (xref CONC-2) — see Section 2

#### PERSIST-3 / FM-1 · `FrontmatterCodec` splits on the first literal `\n---\n`; relies on YAML never emitting a column-0 `---` in frontmatter — **P3**
- **Where:** `FrontmatterCodec.swift:38-53` (`splitFrontmatter`)
- **Risk:** Benign today — the encoder writes `---\n<yaml>---\n<body>` and Yams uses indented/quoted scalars, so a body's `---` horizontal rule lands after the real delimiter and no column-0 `---` appears inside frontmatter. (Two reviewers independently confirmed they could not construct a corrupting input.) The fragility is forward-looking: a future field or Yams version emitting a column-0 `---` inside frontmatter, or external sync/hand-editing, could mis-split.
- **Recommended fix:** No change required now. If hardening later: anchor the closer to a column-0 line / delimit by line index rather than substring search, and add a round-trip test that a body containing a `---` line survives encode→decode. Keep per-file quarantine as the backstop.

### Models, habit math & migration — `Core/Models/Item.swift`, `HabitCycle.swift`, `HabitCompletion.swift`, `ISO8601.swift`

#### MODEL-HABIT-1 · `isComplete`/`completionLog` use RAW frequency while the habit UI groups by NORMALIZED cadence — legacy habits show inconsistent completion state — **P2**
- **Where:** `Item.swift:65-69` (completionLog), `96-107` (isComplete); writers `ItemStore.swift:161/199/212-215`; readers normalize at `HabitDetailView.swift:45/714`, `HabitHeatmap.swift:21`, `HabitCycle.swift:180-182`
- **Risk:** For any legacy habit whose stored frequency isn't already daily/weekly/monthly (hourly, fortnightly, every_three_months, etc.), the row checkmark/strike-through (`isComplete`) buckets completions on a *different* cycle than the detail screen, which normalizes first. So a habit reads "done" in the list and "not done" on the detail screen (or vice versa) — looks broken, and the +1/goal-cap logic can disagree with the detail screen's current cycle.
- **Recommended fix:** Use one cadence basis everywhere: make `completionLog`/`isComplete` and the `ItemStore` writers all use `(frequency ?? .daily).normalizedForHabit`. Since habits are locked to daily/weekly/monthly going forward, normalizing read+write makes raw-vs-normalized irrelevant and removes the whole mismatch class.

#### MODEL-MIGRATE-1 · Legacy `completion_log` migration silently DROPS completions whose cycle-key doesn't match the current frequency's key format — **P2**
- **Where:** `Item.swift:232-233` (migrate call); `HabitCompletion.swift:62-68`, `74-123` (representativeDate parsing)
- **Risk:** On the one-way legacy→timestamped migration, each legacy key is parsed assuming it was produced by the habit's *current* frequency. If the frequency was ever changed after counts were recorded (e.g. weekly keys `2026-W20` now parsed as daily `yyyy-MM-dd`), the parse fails the guard, returns nil, and the count is silently discarded — no error, no quarantine, and the file is rewritten without the lost counts. Silent, unrecoverable history loss.
- **Recommended fix:** Make migration frequency-agnostic about the key — try parsing each legacy key against ALL known formats (day/week/month/quarter/half/year/hour), best-effort. At minimum, count and surface keys that fail to parse (route to `loadIssues`/a non-fatal warning) so the loss is visible and the original file preserved.

#### MODEL-FORTNIGHT-1 · `fortnightly` cycle key collapses two weeks into one bucket while streak math steps by two weeks — fortnightly stats are wrong — **P3**
- **Where:** `HabitCycle.swift:43-46` (key), `308` (`previousCycleStart .fortnightly = -2 weeks`); raw frequency used at `HabitCycle.swift:105`
- **Risk:** The fortnightly key is per-WEEK (same formula as weekly), but streak/rate math steps back 2 weeks per iteration — so the skipped "off" week's completions are never sampled and two completions in the same fortnight count as two cycles. Legacy fortnightly habits report incorrect streaks/consistency/heatmap counts. Narrow: only stored-fortnightly habits, and the detail view normalizes fortnightly→weekly anyway, so the victim is the RAW-frequency paths.
- **Recommended fix:** Either give `.fortnightly` a real 2-week key, or — consistent with the locked-cadence model — fold `.fortnightly` to `.weekly` everywhere by routing Item/HabitStats habit math through `normalizedForHabit`. The second is less code and matches MODEL-HABIT-1.

#### MODEL-TZKEY-1 · Weekly/fortnightly cycle keys depend on DEVICE timezone, so the same completion instant can change cycle across a timezone change — **P3**
- **Where:** `HabitCycle.swift:34-46` — day/month/year branches use UTC formatters, but the weekly/fortnightly branch uses `Calendar(.iso8601)` with no `timeZone` override (line 35)
- **Risk:** A completion near a week boundary can move to a different week-key after the user travels, while the daily/monthly keys for the same instant stay put — so the heatmap (UTC-day) and the weekly cycle bucket can disagree. Low frequency, but a real internal inconsistency.
- **Recommended fix:** Pin the weekly/fortnightly calendar to UTC (`cal.timeZone = TimeZone(secondsFromGMT: 0)`) to match the day/month/year keys, and update `HabitCompletion.migrate`'s weekly `representativeDate` to the same UTC calendar so the round-trip stays exact.

#### MODEL-ALLDAY-1 · All-day due dates are re-encoded as full UTC timestamps; reload can shift the calendar day — **P3**
- **Where:** `Item.swift:259-261` (encode due), `216` (decode); `ISO8601.swift:28-30` (fallback)
- **Risk:** When `dueAllDay` is true, encode still writes a full date-time with a Z/offset, not a `yyyy-MM-dd` day string. The full parser then succeeds on decode, so the instant is reconstructed in absolute UTC — and an all-day item created at local midnight can render on the wrong calendar day after a timezone change. The format comment says day-only is the intended encoding for all-day, but encode never produces it. Latent off-by-one-day.
- **Recommended fix:** When `dueAllDay` is true, encode `due` as `ISO8601.dayString(from: due)` (UTC `yyyy-MM-dd`) so the decode day-formatter fallback reconstructs deterministically; or normalize all-day `due` to UTC start-of-day before storing.

#### MODEL-TYPEFLIP-1 · `Item.encode` drops habit-only fields whenever `type != .habit`, with no model-level guard against type flips — **P3**
- **Where:** `Item.swift:270-278`
- **Risk:** `frequency`/`goalPerCycle`/`completions`/`showStreak`/`flexibleGoal` are only encoded inside `if type == .habit`. Any future path that sets an item's type to task/note and persists silently strips its entire habit history on the next write. Not reachable today (the only converter blocks habit→task), but the model has no invariant — one future "convert habit to task" feature that forgets to preserve completions would silently delete months of history.
- **Recommended fix:** Either keep encoding `completions` regardless of type (cheap, harmless — decode already tolerates them on any type), or add an explicit guard/assertion at the conversion boundary that habit→non-habit must archive completions first. Preserving unconditionally on encode is safest.

### Queries, preferences & utilities — `Core/Queries/SmartList.swift`, `Core/Preferences/AutoListPreferences.swift`, `Core/Models/ISO8601.swift`

#### SMART-ALL-1 · `SmartList.matches(.all)` returns true for EVERY child item, bypassing the completed-filter and habit-exclusion — inflates the sidebar "All" tile count — **P2**
- **Where:** `SmartList.swift:54` (the `guard ... || self != .all else { return true }` short-circuit, before the `.all` case body at 70-72); only live caller `SidebarView.swift:359` (`tileCount(for:)`)
- **Risk:** For any item with a non-nil `parentId`, when the query is `.all` the guard returns true *unconditionally*, skipping the `.all` rules that exclude completed items and habits. So the "All" tile badge is inflated by every completed sub-task and habit sub-item — the user sees "All 42" but opening it shows far fewer (the list BODY uses a separate, correct filter). Count and body disagree with no way to reconcile.
- **Recommended fix:** Tighten the shortcut so it doesn't skip `.all` visibility rules — either remove line 54 and handle child inclusion inside the `.all` case, or for `.all` enforce `includeCompleted || !item.isComplete` and `item.type != .habit` before letting children through. Add a unit test pinning `matches(childItem, query: .all) == false` for a completed child and a habit child.

#### PREF-1 · `AutoListPreferences.order` is not de-duplicated on read — corrupt UserDefaults yields duplicate SmartList ids in a SwiftUI `ForEach` — **P3**
- **Where:** `AutoListPreferences.swift:50-53`
- **Risk:** `order = parsed + missing` drops unknowns via compactMap but doesn't de-dup. A repeated rawValue in persisted state (corrupt write, future append path) makes a SmartList appear twice; `EditListsSheet` `ForEach` keyed on rawValue then renders undefined rows / mis-handles drag-reorder. Low likelihood today (only writer is `move()`, which can't dupe), but no defensive guard.
- **Recommended fix:** De-dup while preserving first-seen order when constructing `order` (fold through a seen-set, or intersect `defaultOrder` with parsed then append missing) so each SmartList appears exactly once. One line of defense at the persistence boundary.

#### ISO8601-TZ-1 · `ISO8601.date(from:)` date-only fallback parses at UTC midnight — can shift the calendar day used by `SmartList.today`/`scheduled` — **P3**
- **Where:** `ISO8601.swift:15-22`, `29`; consumed at `SmartList.swift:63`, `69`
- **Risk:** A bare `yyyy-MM-dd` is parsed as UTC midnight, but `SmartList.matches` compares via the local calendar. For users far from UTC, a date-only `due` could land in the wrong Today/Scheduled bucket. No impact on app-authored files today (the app always writes full datetimes); becomes relevant if export/sync/manual editing introduces date-only `due` strings.
- **Recommended fix:** Interpret a date-only fallback in the current calendar's timezone (normalize to local start-of-day) rather than UTC midnight; or document that date-only `due` is unsupported on the in-app path and used only for habit day-keys (which are string-compared and unaffected).

---

## 4. Recommended fix order

### Tier 1 — fix first (highest impact, mostly self-contained)

1. **SCHED-2 + SCHED-3 (normalize habit frequency in the scheduler).** One-line change at `NotificationScheduler.swift:116` (`normalizedForHabit`) kills the hourly-spam / uncontrollable-cadence bug AND the `.custom`-becomes-daily bug AND shrinks worst-case notification fan-out (helping SCHED-1).
2. **SCHED-1 (notification limit) + SCHED-5 (stop swallowing `add` failures).** The most invisible, worsens-with-adoption risk. Even just logging failures (SCHED-5) makes the rest diagnosable.
3. **REC-1 (pin recurrence to the item's timezone).** Highest product-relevant correctness gap for recurring tasks. Engine already threads `calendar`; the fix is at the `toggleDone` call site.
4. **REC-2 (duplicate-successor dedup).** Easy to hit (untick/retick), produces silent duplicate tasks and duplicate reminders.

### Tier 2 — fix next (real but narrower, or needs a small product decision)

5. **MODEL-MIGRATE-1 (don't silently drop legacy completions).** Data-loss class — prioritize surfacing the loss even before fully fixing the parser.
6. **MODEL-HABIT-1 (single cadence basis) + MODEL-FORTNIGHT-1 + MODEL-TZKEY-1.** These are one coherent change: route all habit read/write/stats math through `normalizedForHabit` and pin habit calendars to UTC. Fixes the list-vs-detail "done?" mismatch and the fortnightly/timezone key bugs together.
7. **PERSIST-1 + PERSIST-2 (folder-level resilience + quarantined-list writability).** Extends the DI-1 "one bad thing can't brick the load / lose an action" guarantee from files to folders and quarantined lists.
8. **SMART-ALL-1 (correct the "All" tile count).** Visible discrepancy; small, testable fix.
9. **REC-3 + REC-5 (day-granular UNTIL + parser formats).** One coherent change to UNTIL handling.

### Tier 3 — opportunistic / forward-compat (do alongside related work)

10. REC-4 (DST gap), REC-6 (overdue successor — needs a product decision), REC-SPAWN-1 (stale spawn snapshot / sub-task placement), MODEL-ALLDAY-1, MODEL-TYPEFLIP-1, CONC-2-RESIDUAL, PERSIST-3/FM-1, PREF-1, ISO8601-TZ-1, SCHED-4. Mostly latent or edge-case; cheap to fold in when touching the relevant file.

### DI-4 — special handling (carried-forward P1)

11. **DI-4 (serialize fire-and-forget writes).** High severity, but the fix touches the reorder/update write path in `ItemStore` — see entanglement note below.

### Safe-to-apply-independently vs would-tangle-with-the-uncommitted-work

The uncommitted work in the tree is the **Habits detail redesign** and **inline-editing** changes (`InlineItemEditor`, `InlineDateTimePopover`, the Habits feature files), pending your UI review.

**Safe to apply independently (no overlap with the pending UI work):**
- All of the **SCHED-*** fixes — `NotificationScheduler.swift` is not touched by the redesign.
- **REC-1, REC-3, REC-4, REC-5** — pure `RecurrenceEngine.swift` math; REC-1's call-site edit is a small isolated change in `toggleDone`.
- **PERSIST-1, PERSIST-2, PERSIST-3/FM-1** — `FileStore`/`FrontmatterCodec`, persistence layer only.
- **MODEL-MIGRATE-1, MODEL-TZKEY-1, MODEL-ALLDAY-1, MODEL-TYPEFLIP-1** — Codable / migration / cycle-key internals, not UI.
- **SMART-ALL-1, PREF-1, ISO8601-TZ-1** — Queries/Preferences/utilities, independent of the redesign.

**Would tangle with the uncommitted Habits / inline-editing work — defer until after your UI review is merged:**
- **MODEL-HABIT-1 and MODEL-FORTNIGHT-1** (and the habit-math half of normalization) touch `Item.isComplete`/`completionLog`, the `ItemStore` habit writers (`incrementHabit`/`setHabitCount`/`removeLatestCompletion`), and `HabitStats` — exactly the code the Habits detail redesign is exercising. Changing the cadence basis underneath an in-flight UI review would muddy both.
- **REC-2 and REC-SPAWN-1** touch the `toggleDone` spawn block, which interacts with habit completion behavior the redesign also relies on.
- **DI-4 / CONC-2-RESIDUAL** touch the `ItemStore` reorder/update/inline-add write paths (`addInlineItem`, `applyReorderItemsSync`, `applyUpdateSync`) — the same surface the **inline-editing** uncommitted work sits on. Serializing those writes should land *with* or *after* the inline-editing changes, not before, to avoid conflicting edits to the same call sites.

**Reminder:** nothing above was changed in this pass. These recommendations are staged so the independent fixes can proceed immediately while the habit-math and write-path fixes wait for your Habits/inline-editing UI review to merge first.
