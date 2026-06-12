# Completed & Remaining

## How far it's come
From the first commit (`M0`, 2026-05-09) to today is **~2 weeks and 106 commits** — and in that time Lists
went from scaffold to a **polished, multi-screen, working iOS app** with a custom markdown editor, arbitrary
list nesting, habits with heatmaps, and drag-to-reorder. That's a lot of real product in a short window.

## ✅ Completed & working (verified — see `02-what-works-today.md`)
- **Core model + files-as-truth storage** — one `Item` primitive (task/habit/note), YAML-frontmatter+markdown
  files, list folders, **arbitrary nesting**, sections, sub-items/threads, soft-delete tombstones + cascade,
  legacy-layout migration, deterministic sample data.
- **All the main screens** — sidebar/home, Today, smart lists (Today/Scheduled/Flagged/Urgent/Completed/All),
  list detail, item detail, quick capture, habit detail, search, settings, recently deleted, tags overview, thread.
- **Markdown editor (rebuilt 2026-05-13)** — modular pure-transform design, **live syntax styling**, Live/Raw
  toggle, smart list-continuation, tappable checkboxes, 25-button toolbar, verbatim paste.
- **List nesting (landed 2026-05-19)** — collapsible sidebar tree, reorder mode, drop-to-nest, Move-to… with cycle guard.
- **Tags** — inline `#tag` capture, tags overview with filter chips, **Tags + Assigned smart lists** (latest commit).
- **Habits** — progress ring (tap to increment), cycles, streak, **12-month heatmap**, stats/details modes.
- **Interactions** — drag-to-reorder (items + lists), swipe actions, "linger" on completion, collapsible sections.
- **Clean Swift 6 build**, atomic writes, off-main file I/O.

## 🔧 Built but broken / unfinished (looks done — needs finishing; details in `01-technical-health.md`)
- **Recurring tasks** (`TASK-1`) and **recurring reminders** (`REM-1`) — the UI exists, the engine doesn't.
- **Editor undo** (`ED-1`); **read-path resilience** (`DI-1`); **move-duplicates-item** (`DI-2`);
  **remote-image privacy leak** (`SEC-1`); **VoiceOver usability** (`A11Y-1`); **tests don't compile** (`BUILD-1`).
- **Location** field (present but inert) and **Urgent→alarm** (UI present; real alarms wait on AlarmKit/paid account).

## 📋 Documented "Next Work" (your `docs/CURRENT.md`)
- Render **KaTeX math** and **Mermaid diagrams** in note bodies (WKWebView bridge).
- **Tappable wikilinks** (cross-item navigation when a `[[link]]` resolves).
- Realign the old `shared/format/` wording with the `Item` model (note: `shared/` has since been deleted — see drift note).

## 💤 Deferred by design (your `PRODUCT-SPEC.md` — intentionally NOT active)
Android / Linux / Windows clients · **Lists Sync** · App Store distribution work · **AlarmKit** (needs paid
Apple account) · **agent integrations inside the app** (the agent-lists idea lives here) · shared Rust core ·
web/Electron client.

## 🆕 Surfaced by this audit (not previously planned — recommended additions)
- **Lower the deployment target to iOS 18** so people can actually install it (only 7 cosmetic lines are iOS-26-only).
- **App Intents / widgets / Siri / Shortcuts / Spotlight** — currently none; one App Intent unlocks most.
- **Natural-language quick capture** ("tomorrow 5pm #work") via the system's own `NSDataDetector`.
- **Forgiving habit streaks** (grace day / "never miss twice") to fit the "calm" promise.
- **Sync-readiness groundwork** — field-level merge (union completion logs/tags; last-write-wins scalars) and a
  schema-version field — cheap insurance to add *now*, before sync.
- Later: a **rebuildable SQLite index** (a disposable cache, never the source of truth) for query speed at scale.
