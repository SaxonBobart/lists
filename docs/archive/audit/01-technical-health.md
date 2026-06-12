# Technical Health

*Synthesis of 11 domain audits + a live build/run + a skeptical verification pass. Every P0/P1 below
was re-checked by a second agent trying to disprove it; the verdict (CONFIRMED/PARTIAL) is shown.*

## Bottom line

**Grade: B+ / "solid foundation, a few real bugs to fix before anyone relies on it."**

The engineering quality is genuinely high — higher than typical for an AI-assisted solo build. The app
compiles cleanly under Swift 6's strictest concurrency checking with **zero warnings**, the architecture
is well-layered, there are **no crash-prone patterns**, and file writes are atomic and off the main thread.
You do not have a shaky house. You have a sound house with a handful of specific things to fix — and one
of them (how the app reacts to a single bad file) genuinely matters and should be first.

## What's genuinely solid (not flattery — specifics)

- **Clean Swift 6 build, 0 warnings**, full strict-concurrency on ~19k LOC. No accumulated tech-debt warnings.
- **Crash surface is essentially nil.** Every `try!` is a fixed regex that can't fail; every force-unwrap is
  a hardcoded sample-data UUID; 0 unsafe casts. The classic iOS text-crash zone (emoji/Unicode in the editor)
  is handled in consistent UTF-16 space with clamped ranges.
- **Architecture is disciplined.** A single `@Observable` store fronts a `FileStore` *actor* that owns all
  disk I/O — so file work never blocks the UI and cross-thread memory races are *compile errors*. Zero
  `Features/` files touch the filesystem directly. No retain cycles (every closure/coordinator uses `[weak self]`).
- **Writes are durable** — atomic write-then-rename everywhere, careful soft-delete/cascade, cycle-safe list moves.
- **Privacy mostly holds** — no networking, analytics, or secrets in your own code; the path-sanitizer that
  stops a malicious list name escaping the sandbox is correct (traced on paper: `..`, absolute paths, null
  bytes all blocked).
- The **markdown editor** correctly never mutates the source text while styling it (the right architecture),
  and the known iOS-26 indent-drift bug is fixed everywhere.

## What needs attention — prioritized

### 🔴 P0 — fix before you (or sync, or an agent) rely on the data

**DI-1 · One bad file makes your whole library disappear.** *(CONFIRMED — `FileStore.swift:146,176`;
`ItemStore.swift:25,48`; `ListsApp.swift:19`; `ContentView.swift:7`.)*
Loading reads every file with no per-file safety net. If a single `.md` or `.list.yml` is corrupt, truncated
(e.g. a crash mid-write), or has one unexpected value, the *entire* load aborts — the app sits on "Loading
your lists…" forever, with all your data invisible (only a hidden console message). This is the `created_at`
class you've hit before. **It is also the amplifier behind several other issues** (SEC-1, AGENT-1, AGENT-2 all
become "bricks the whole app" *because* of this). Fix = isolate each file in its own try/catch, quarantine the
bad one, always finish loading the rest, and show a banner instead of a blank screen.

**DI-2 · Moving an item between lists can duplicate it.** *(CONFIRMED — `ItemDetailSheet.swift:1045,1086`;
`HabitDetailView.swift:376,560` → `writeItem`; no delete of the old file; no move-helper exists.)*
Changing an item's list writes a new file in the new folder but never removes the old one. After a reload you
have two copies; deleting one leaves the "zombie" that reappears. Fix = delete the old path on a list change
(a small, well-defined change).

### 🟠 P1 — real bugs / quality gaps, fix soon

- **TASK-1 · Recurring tasks vanish.** *(CONFIRMED — `ItemStore.toggleDone:77–91` never reads recurrence;
  no expansion engine exists anywhere.)* You save a repeat rule and the UI offers it, but completing a recurring
  task doesn't create the next one — it just disappears. **REM-1** (recurring reminders fire once,
  `NotificationScheduler.swift:67` `repeats:false`) is the *same missing engine* seen from the notification side —
  **one fix (a recurrence-expansion step on completion) resolves both.** This is the highest-value functional fix.
- **ED-1 · Editor undo is broken.** *(CONFIRMED — `EditorCoordinator.swift:386–387` full-document replace, no
  `UndoManager`.)* Cmd-Z / shake-to-undo will revert big chunks unexpectedly. Fix = make minimal-range edits via
  the text-input API so the system's own undo works.
- **ED-2 / PERF-1 · Typing lags on long notes; taps lag in big lists.** *(CONFIRMED — `MarkdownStyler.swift:97–124`
  re-styles the whole document every keystroke; smart lists reconfigure every row on every change.)* Fine today;
  noticeable once notes get long or a list has hundreds of items. Same root cause: doing whole-document/whole-list
  work instead of just the part that changed. Fix = restyle only the edited block; add a `[UUID:Item]` index.
- **SEC-1 · Notes silently fetch remote images.** *(CONFIRMED — `MarkdownBodyView.swift:14–18`, no image provider
  set.)* A note containing `![](http…)` will reach out to the internet and leak your IP — contradicting "no cloud
  for local use." One-line fix: restrict the image provider to local assets.
- **UI-1 · A just-opened detail sheet can get dismissed/blanked.** *(CONFIRMED mechanism — `ItemRow.swift:56,67,151`
  owns its own sheet inside reconfiguring cells; an in-repo comment at `ListDetailCollectionView.swift:448` already
  notes reconfigure blanks the row. Not filmed live.)* Route the row tap through the parent's `.sheet(item:)` (the
  swipe "Details" action already does this safely).
- **A11Y-1 · Not usable end-to-end with VoiceOver.** *(CONFIRMED — editor speaks raw markup & its checkboxes are
  silent; a hidden `alpha:0` label is still focusable `MarkdownTextView.swift:97,99`; habit stats are ungrouped
  fragments — observed live.)* The lists/Today views are actually fairly accessible; the gaps are the editor and
  the data-viz. Matters for App Store quality and inclusivity.
- **DI-3 · A corrupted "deleted" date silently un-deletes an item.** *(CONFIRMED — `Item.swift:259–265` maps a bad
  date to nil.)* Edge case, but it resurrects soft-deleted items.
- **BUILD-1 · Your tests don't compile.** *(CONFIRMED.)* A one-line stale call (`SettingsViewSnapshotTests.swift:10`)
  breaks the whole snapshot suite — so your safety net is currently off. Trivial fix + run tests in CI.
- **SETUP-1 · Your safety rails aren't actually enforced.** *(CONFIRMED — `~/.claude/settings.json` `bypassPermissions`
  + a pre-approved `git reset --hard`.)* "Never push/reset without approval" can't be enforced while everything is
  auto-approved. Worth tightening before more autonomous runs (this one stayed strictly read-only regardless).
- **CONC-1 · Rare lost-update if you act on the same item twice in a split second.** *(CONFIRMED mechanism, PARTIAL
  frequency — narrow today, sharpens once sync writes concurrently.)*

### 🟡 P2 / P3 — cleanup, not urgent
Repo bloat (`git gc --prune=now` reclaims ~54 MB); `QuickCaptureSheet`/`ItemDetailSheet` are ~70% duplicated
(extract a shared form); "linger" logic copy-pasted ×3; docs reference a deleted `shared/` folder (an AI-edit
trap); `main` is 100 commits behind `dev`; habit streak is unforgiving (`HABIT-2`); dependency `MarkdownUI` is in
maintenance mode; `SWIFT_TREAT_WARNINGS_AS_ERRORS` is off.

## Recommended fix order
1. **DI-1** (read-path resilience) — protects all your data and unblocks SEC-1/AGENT-1/AGENT-2/sync. *First.*
2. **DI-2** (duplicate-on-move) — second data-integrity P0, small fix.
3. **TASK-1 + REM-1** (recurrence engine) — highest-value *feature* fix; one change.
4. **SEC-1** (image provider) — one line, closes the privacy hole.
5. **BUILD-1** (compile tests) — turn the safety net back on.
6. **ED-1 / ED-2 / PERF-1** (editor undo + scoped restyle + list index) — before notes/lists get large.
7. **UI-1**, **A11Y-1**, then P2 cleanup.

## How this was verified
10 read-only domain agents + a clean build + a live simulator walk of 8 screens + a 2-agent skeptical pass that
re-traced every P0/P1 against exact source. Confidence is high; the few "not filmed live" items (UI-1) are noted.
Raw evidence per finding is in `findings/`.
