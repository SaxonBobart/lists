# Backend fixes applied — 2026-05-30

Follow-up to `backend-audit-2026-05-30.md`. Three isolated, well-tested backend
fixes were applied, verified (clean build + 107/107 unit tests, zero
regressions), and committed to `main`. **No SwiftUI / UI code was touched.**

## ✅ Applied

| ID | What | Commit | Tests added |
|---|---|---|---|
| **REC-1** | Recurring tasks now compute their next occurrence in the task's stored `dueTimeZone` instead of the device's current zone — so a repeat no longer drifts by an hour/day after travel or a DST change. | `596782c` | 3 engine + 1 DST-crossing integration test |
| **PERSIST-1** | One unreadable *folder* (permissions / I/O) can no longer abort the whole library load and leave it blank — the folder is recorded and its siblings still load. Extends the existing one-bad-*file* safety net (DI-1) up to the folder level. | `b90a94a` | 1 test (unreadable-dir, runs fully on the sim) |
| **PREF-1** | The persisted sidebar tile order is de-duplicated on read, so a corrupt preferences payload can't render the same smart-list tile twice (broken `ForEach` / drag-reorder). | `43ab625` | 3 tests |

Verification: `xcodebuild` Debug build clean (warnings-as-errors enforced),
full unit suite 107/107 green.

## ⏸️ Deliberately deferred (with reasons)

These were NOT applied. Each has a real reason to wait:

### Needs your product decision
- **SCHED-1** (iOS 64-notification limit → reminders can silently overflow). The obvious "fix" (collapsing the weekday/weekend fan-out) **conflicts with behaviour that existing tests intentionally pin** — see below. A real fix is a *budget/cap policy* plus a one-time user notice, which is a product choice (how many habit reminders to allow, what to tell the user). Worth doing before launch; needs you.

### ⚠️ Audit advice that is NOT safe as written
- **SCHED-2 / SCHED-3** (the audit said: "normalize habit frequency in the scheduler"). **Do not apply this verbatim.** `HabitReminderTriggerTests` explicitly asserts the current raw-frequency behaviour (`.weekdays` → 5 triggers, `.weekends` → 2, `.hourly` → minute-only). Normalizing in the scheduler would break those tests — i.e. it would change tested, intended behaviour, not just fix a bug. The audit subagent didn't have these tests in view.

### Touches code you're still iterating (habits / inline-editing)
- **REC-2** (untick→retick spawns a duplicate successor) and **REC-SPAWN-1** (spawned successor inherits parent/sortIndex from a stale snapshot). A clean fix wants a "series id" link on the model — a small data-model decision best made with you.
- **DI-4 / CONC-2-residual** (fire-and-forget reorder / inline-add writes have no shared ordering). These sit on the exact `ItemStore` write paths the inline-editing work uses; they should land *with* that work, not under it.
- **MODEL-HABIT-1 / MODEL-FORTNIGHT-1 / MODEL-MIGRATE-1 / MODEL-TZKEY-1 / MODEL-ALLDAY-1 / MODEL-TYPEFLIP-1** — habit-completion math, cycle keys, and `Item` encode/decode: the surface the habits redesign is exercising. MODEL-MIGRATE-1 (legacy completion history can be silently dropped on migration) is the most valuable of these and a good early follow-up once the habits UI is settled.

### P3 edge-cases with timezone/boundary subtlety (low reward, real risk if mis-done)
- **REC-3 / REC-4 / REC-5** (UNTIL day-granularity, DST-gap date reconstruction, multi-format UNTIL parsing), **SMART-ALL-1** (the "All" tile count is inflated by completed/ habit sub-items — but the fix is a shared predicate also used for display, so it needs care), **ISO8601-TZ-1** (date-only parse zone — no app-path impact today).

## Suggested follow-up order (when you're ready)
1. **SCHED-1** — decide a reminder budget + notice (highest user-visible reliability win).
2. **MODEL-MIGRATE-1** — stop silently dropping legacy habit history (data-loss class) once the habits UI is locked.
3. **SMART-ALL-1** — correct the "All" count after confirming the intended All-view rule for sub-items.
4. The recurrence edge-cases (REC-2/3/4/5) and the write-path ordering (DI-4) alongside related work.
