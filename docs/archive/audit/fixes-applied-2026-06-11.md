# Backend fixes applied — 2026-06-11

Follow-up to `backend-audit-2026-05-30.md` and `fixes-applied-2026-05-30.md`.
This pass closes **every remaining finding** from the 2026-05-30 audit. The two
blockers that deferred them in May are gone: the habits/inline-editing UI work
is committed, and Saxon delegated the product calls ("fix all that bug stuff,
whatever you think is best", 2026-06-11).

Verification: full unit suite green (198 tests) on the iOS 27.0 simulator
under Xcode 27 beta 1, plus a clean `build_run_sim` launch. Zero warnings
(warnings-as-errors enforced).

## ✅ Applied (audit IDs → what changed)

| IDs | What |
|---|---|
| SCHED-2, SCHED-3 | The scheduler now builds habit reminders from the **normalized** cadence (daily/weekly/monthly) — a legacy `hourly`/`weekdays`/`custom` value can no longer drive a cadence the UI can't edit. One trigger per habit (weekday fan-out removed). `HabitReminderTriggerTests` deliberately re-pinned to the new behavior. |
| SCHED-1, SCHED-5 | `center.add` failures are logged (os.Logger, `notifications` category), and the scheduler warns when pending notifications reach iOS's 64 cap. Normalization shrinks worst-case usage 5×. A user-facing "reminders over budget" notice is UI work, deferred to the redesign. |
| SCHED-4 | Documented convention: triggers fire at local wall-clock; cycle keys are UTC. |
| REC-2 | Tick → untick → tick no longer spawns a duplicate successor (dedup-on-spawn by list + title + rule + computed due). |
| REC-3, REC-5 | `UNTIL` is compared day-granular in the series' calendar ("end Dec 31" includes Dec 31 everywhere), and date-only / floating `UNTIL` forms parse instead of silently making the series infinite. |
| REC-4 | Monthly/yearly occurrences landing in a DST spring-forward gap roll forward instead of being dropped. |
| REC-6 | Completing a long-overdue recurring task rolls the successor forward to the **future** (anchored to the original cadence) instead of spawning an already-overdue ghost with no reminder. |
| REC-SPAWN-1 | The successor is built from a re-fetched live copy after the awaits (no stale title/body resurrection); placement inheritance is now deliberate and documented. |
| DI-4, CONC-4 (write half) | Every disk write flows through one FIFO chain in `ItemStore` — a deferred (fire-and-forget) write can never land after a newer write and silently revert it on relaunch. Deferred-write failures are logged, not swallowed. `flushPendingWrites()` added for tests. |
| CONC-2-residual | `migrateLegacySectionsIfNeeded` re-fetches live values inside its loop. |
| PERSIST-2 | Saves/deletes to an unmapped list id no longer throw or silently vanish: writes fall back to the file's actual folder or materialize a visible "Recovered …" list; deletes find the file wherever it lives. |
| PERSIST-3 / FM-1 | No code change needed (confirmed); a round-trip regression test pins that a `---` line in a body survives. |
| MODEL-HABIT-1, MODEL-FORTNIGHT-1 | One cadence basis everywhere: `completionLog`/`isComplete`, the ItemStore habit writers, `HabitStats`, and the four row/screen count lookups all use `normalizedForHabit`. The list row and detail screen can no longer disagree. |
| MODEL-MIGRATE-1 | Legacy `completion_log` keys migrate by **shape** (day/hour/week/month/quarter/half/year), so history recorded under an older frequency is never silently dropped. |
| MODEL-TZKEY-1 | `HabitCycle.key` is pinned to UTC for every cadence (was: weekly keys used device timezone). Migration's representative dates match. |
| MODEL-ALLDAY-1, ISO8601-TZ-1 | All-day dates are calendar days: encoded as local `yyyy-MM-dd`, decoded at local start-of-day — no more off-by-one-day drift on reload/travel. (Also a prerequisite for clean iCal sync later.) |
| MODEL-TYPEFLIP-1 | `completions` are encoded for any item type, so a future habit→task conversion can't strip history. |
| SMART-ALL-1 | Sub-items obey the same `.all` visibility rules as top-level items — the sidebar "All" count now matches what the view shows. |

Also in this pass (not audit findings):

- **Xcode 27 test-suite revival:** the habit-detail render smoke test now hosts
  the view in a window (`ImageRenderer` teardown asserts and kills the whole
  suite on the OS 27 beta), and all 49 snapshot baselines were re-recorded on
  the iOS 27 runtime (every reference was captured on iOS 26 and mismatched
  wholesale).
- **Event item type** (see PRODUCT-SPEC.md "Events"): start + optional end +
  completable, calendar-shaped; non-completable events have no overdue state.
