# Verification — Data Integrity, Concurrency & Task-UX findings

Skeptic pass. READ-ONLY review of the exact code paths. Each finding gets a verdict, a `file:line` citation, and a one-line plain-English "what the owner should believe."

---

## DI-1 — One bad file makes the WHOLE library unloadable
**Verdict: CONFIRMED.**

The read path is all-or-nothing exactly as claimed.
- `FileStore.walk` decodes items with a bare `try` and no per-file catch: `let items = try itemFiles.map { try readItem(at: $0) }` (`Core/Storage/FileStore.swift:176`); the list itself is `let list = try readList(at: listFile)` (`:146`). Any throw propagates straight out of `walk` → `loadAll` (`:130-137`).
- `readItem` → `FrontmatterCodec.decode` throws on a missing `---` (`Core/Storage/FrontmatterCodec.swift:41,50`); `Item.init(from:)` throws on a missing/invalid required key — `keyNotFound` for `id`/`type`/`title`/`list` (`Core/Models/Item.swift:173-177`) or a bad `created_at`/`modified_at` (`decodeDate`, `:245-257`). Any one of these aborts the whole load.
- `bootstrap()` awaits `loadAll()` at `Core/Stores/ItemStore.swift:25`; a throw there exits before `self.isLoaded = true` (`:48`).
- The throw is caught only by the `.task` in `App/ListsApp.swift:14-20`, whose sole action is `print(...)` (`:19`). `isLoaded` stays `false`.
- `ContentView` shows `SidebarView` only when `store.isLoaded` is true, else `BootstrapPlaceholder` ("Loading your lists…") forever (`App/ContentView.swift:7-11`, `:23`).

No file-level isolation exists anywhere in `walk`. The `do/catch` at `:163-170` is only around the legacy folder-*rename* migration (`moveItem`), not around `readItem`/`readList` — and on failure it keeps loading, so it does NOT protect decode. This is the exact "manually wipe the container" failure class in `feedback_wipe_sim_data_when_bundle_shared` memory.

**Owner should believe:** Real and serious — a single damaged or truncated note file leaves the whole app stuck on "Loading…" with no data and no error, and the user has no way out. Top priority.

---

## DI-2 — Cross-list move duplicates the item on disk (old `.md` never deleted)
**Verdict: CONFIRMED.**

- `FileStore.writeItem` derives the path purely from `item.listId` and writes `<newList>/<id>.md`; the basename is the stable item UUID, so it never overwrites the old-folder copy (`Core/Storage/FileStore.swift:77-83`).
- The detail-sheet save sets `item.listId = listId` (`Features/ItemDetail/ItemDetailSheet.swift:1045`) and `save()` calls only `store.update(toSave)` (`:1086-1090`). The list-picker that changes `listId` is at `:702`.
- The habit editor does the same: `draft.listId = list.id` (`Features/Habits/HabitDetailView.swift:376`) and `save()` calls only `store.update(toSave)` (`:560-575`).
- `ItemStore.update` only writes the new file: `try await store.writeItem(updated)` (`Core/Stores/ItemStore.swift:185-195`). No `listId`-change detection, no delete of the old file.
- `store.deleteItem` is invoked from exactly two places — `delete` (`:260`) and `purgeExpiredTombstones` (`:599`) — never from `update` or any move path. Grep confirms no `moveItem(_,fromListId:)` for items and no `oldListId` tracking exists.

Result: after a cross-list move, the next `loadAll` reads both copies (`walk` at `:176` loads every `.md` in each folder). The stale copy carries the old `listId`, so the item shows in both lists and resurrects after deleting one. Real, routine-action corruption.

**Owner should believe:** Real. Moving a task/habit to a different list leaves a ghost copy in the old list that comes back after relaunch. Confirmed by code; a 30-second sim repro would demonstrate it.

---

## DI-3 — Malformed `deleted_at` silently un-deletes
**Verdict: CONFIRMED (with the same logic affecting `completed_at` / `due`).**

- `deleted_at` decodes via `decodeDateIfPresent`, which maps a present-but-unparseable string to `nil` rather than throwing: `guard let s = try c.decodeIfPresent(...) else { return nil }; return ISO8601.date(from: s)` (`Core/Models/Item.swift:259-265`, used for `deletedAt` at `:198`). Same code in `ItemList` (`Core/Models/ItemList.swift:153-159`, used at `:113`).
- `ISO8601.date(from:)` returns `nil` when both the datetime and day formatters fail (`Core/Models/ISO8601.swift:28-30`) — no throw.
- Contrast the required dates, which DO throw on a bad value (`decodeDate`, `Item.swift:245-257`).

So a mangled `deleted_at` → `nil` → item decodes as live again. The same `decodeDateIfPresent` also silently drops a corrupt `completed_at` (`:185`) and `due` (`:186`).

**Owner should believe:** Real but narrow today. A deleted item can silently come back (and a due/completed date can silently vanish) if its date text gets corrupted. Low frequency on a single device; the risk rises once export round-trips or sync can mangle a file. Correctly rated P1.

---

## TASK-1 — Completing a recurring task never generates the next occurrence
**Verdict: CONFIRMED.**

- `toggleDone` only flips `done`, stamps `completedAt`, bumps `modifiedAt`, persists, and cancels/reschedules the notification — it never reads `item.recurrence` (`Core/Stores/ItemStore.swift:77-91`).
- Whole-app grep for where recurrence/RRULE is READ: the only consumers are UI compose/parse/display helpers in the two capture sheets — `composeRRule`/`parseRecurrence`/`CustomRRule.parse`/`displayName` (`Features/ItemDetail/ItemDetailSheet.swift:1025-1075,1119-1145`; `Features/QuickCapture/QuickCaptureSheet.swift:1006-1011,1230-1244`; `Features/QuickCapture/RepeatCustomSheet.swift:99-150`). It is otherwise only written/encoded (`Item.swift:192,226`).
- The model comment confirms intent: "recurrence expansion lives elsewhere (out of scope for M0)" (`Core/Models/Reminder.swift:74-75`) — but no "elsewhere" exists. No `nextOccurrence`/`advance`/`regenerate`/expansion anywhere, including `NotificationScheduler`.

Recurrence is stored and round-tripped through the editor, but never consumed on completion. Completing "Pay rent · Monthly" ticks it off and nothing returns.

**Owner should believe:** Real. The Repeat picker stores a rule that nothing acts on — completing a repeating task makes it vanish permanently. The UI silently promises a feature the engine doesn't deliver.

---

## REM-1 — Recurring reminders fire once (`repeats: false`)
**Verdict: CONFIRMED — but it is a direct consequence of TASK-1, not an independent second bug.**

- The trigger is built with `repeats: false`: `UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)` from the item's single `due` date components (`Core/Notifications/NotificationScheduler.swift:65-67`).

So a notification fires once for the one stored `due` and is never re-armed. Important nuance for severity: this is the *same* missing-engine gap as TASK-1, viewed from the notification side. Because there is no recurrence expansion, there is no future `due` to schedule a repeat against, so `repeats: false` is arguably the only correct choice today — a `repeats: true` calendar trigger would misfire (e.g. fire monthly off `.day`/`.hour` components regardless of the actual RRULE). The fix is the same one engine (advance the occurrence on completion / expansion), after which scheduling re-arms naturally.

**Owner should believe:** Real symptom, but don't count it as a separate defect — it's the reminder-side face of the missing recurrence engine (TASK-1). Fixing recurrence fixes this; "just flip repeats to true" would not.

---

## CONC-1 — Actor-reentrancy "lost update" across the `await` in `ItemStore` mutators
**Verdict: CONFIRMED (mechanism real) / PARTIAL on real-world frequency.**

The read-modify-await-write shape is exactly present:
- `toggleDone` (`Core/Stores/ItemStore.swift:77-91`): read `items.first(where:)` → mutate copy → `try await store.writeItem(item)` (`:82`, suspends the main actor) → `items[idx] = item` (`:83-85`).
- Same shape in `incrementHabit` (`:95-107`), `setHabitCount` (`:110-124`), `update` (`:185-195`), `softDelete` (`:267-276`), `restore` (`:279-288`).

`ItemStore` is `@MainActor` (`:6`), so these serialize except across each `await`. A second mutator for the same id that runs during the suspension reads the pre-mutation snapshot from `items` and, on resume, both do `items[idx] = copy` — last writer wins, and the on-disk file matches whichever `writeItem` completed last. The interleaving is genuinely possible.

Why PARTIAL on impact: the in-memory read at step 1 reads from the shared `items` array, so the *second* mutator to start (after the first's in-memory assignment lands) sees the updated value — the lost-update window is specifically when two actions for the same item are *both* in flight and the second starts before the first's post-await assignment. The single-action-at-a-time UI makes this rare today; it sharpens with fast double-actions and especially once concurrent sync writers exist. Note the build is in Swift 6 language mode (per `concurrency.md`), so this is a *logical* race the compiler cannot catch, not a memory race.

**Owner should believe:** Real race, low odds on today's single-device tap-one-thing-at-a-time usage, rising sharply before/when sync ships. Worth tightening (apply the in-memory change before the await, or serialize per-item) but not an emergency.

---

## Summary of changes vs. the original findings
- **CONFIRMED as written:** DI-1 (P0), DI-2 (P0), DI-3 (P1), TASK-1 (highest-leverage), CONC-1 (mechanism).
- **Severity adjustment — REM-1:** confirmed as a *symptom* but it is the reminder-side face of TASK-1's missing recurrence engine, not an independent bug. `repeats: false` is defensible until expansion exists; the single fix (recurrence engine) resolves both. Don't double-count it or "just flip the flag."
- **Scope narrowing — CONC-1:** mechanism confirmed and unambiguous, but the lost-update window is genuinely narrow on the current single-device build (PARTIAL on frequency, High on existence). Tighten before sync; not urgent now.
- **No findings refuted.** All six describe real code behavior. The two P0s (DI-1, DI-2) are the ones to act on first; they are confirmed by exact source, not inference.
