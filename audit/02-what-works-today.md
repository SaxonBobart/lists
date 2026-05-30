# What Actually Works Today

This is a feature-by-feature inventory of Lists as it stands on 2026-05-24. It was produced by
**building the app, running it in the simulator with fresh sample data, and walking the headline
flows** (screenshots in `_screens/`), cross-checked against the code. Each item is tagged:

- ✅ **Works (verified live)** — I saw it working in the running app.
- 🔵 **Built (in code)** — present and wired in the codebase; not every one was visually walked.
- 🟡 **Partial / stubbed** — visible but incomplete, or the UI promises something the engine doesn't do.
- 🔴 **Broken** — present but doesn't function (see the technical findings).

The headline: **this is a real, polished, working app — not a prototype.** It looks and behaves
like a shippable iOS productivity app. The gaps are specific, not structural.

---

## Home & navigation
- ✅ **Sidebar home** with colored smart-list tiles and **live counts** (All 15, Completed, Scheduled 4,
  Flagged 2, Today 4, Urgent 0, Tags 5, Assigned). [`_screens/01-home-sidebar.jpg`]
- ✅ **"My Lists" tree** — Inbox, Work, Personal, Projects — each with a colored icon badge, open-item
  count, and disclosure chevron; nested lists supported (Projects expands). [01]
- ✅ **Recently Deleted** entry, **Reorder Lists** (pencil) and **New List** (+) controls, **FAB** (New Item).
- 🔵 **Search** screen, **Settings**, **Tags overview** (chip filter cloud), **Recently Deleted** view,
  **Move to…/Parent picker**, **Edit List / Edit Sections** sheets — all present in code.

## Tasks
- ✅ **Today** with **Overdue** + **Today** sections, due date/time, inline `#tags` (dusty purple-blue),
  flags, completion checkboxes. [`_screens/02-today.jpg`]
- ✅ **List detail** with **collapsible sections** (incl. an "Others" bucket for uncategorized), **nested
  sub-items** (indent/outdent), body-text previews, multi-tag items, flags. [`_screens/03-list-detail-personal.jpg`]
- ✅ **Item detail** editor — Task/Note type switch, title, tags, expandable notes, Date/Time/Reminder/
  Urgent toggles, **Repeat** row, Flag, Priority, Section. [`_screens/04-item-detail.jpg`]
- ✅ **Quick Capture** (FAB) — **Task/Note/Habit** type picker, auto-focused title, full field set,
  Priority stepper, Section picker. [`_screens/08-quick-capture.jpg`]
- ✅ **Smart lists** as live queries (Today/Scheduled/Flagged/Urgent/Completed/All) — counts confirmed live.
- ✅ **Inline `#tag` capture** (parsed from the title), **flags**, **priority** (`!`/`!!`/`!!!` prefix per design rules).
- 🔵 **Drag-to-reorder** items (with nesting), **swipe actions** (Delete/Flag/Details), **"linger"** on completion.
- 🟡 **Location** field — shown in detail/capture but appears inert (placeholder; no location picker observed).
- 🟡 **Urgent → alarm** — the UI says "mark as urgent to set an alarm," but AlarmKit is deferred (free
  Apple account), so "urgent" can't yet ring like a real alarm.
- 🔴 **Recurring tasks** — the **Repeat** UI saves a rule, but completing a recurring task does **not**
  generate the next occurrence — it just vanishes (`TASK-1`). The feature looks done but is a no-op.

## Habits
- ✅ **Habit rows** with an inline **progress ring** (tap to increment; "Increment habit" a11y label). [03]
- ✅ **Habit detail** — **Stats/Details** tabs, Frequency/Goal/Streak summary, **this-cycle ring + "+1"**,
  and a **12-month heatmap** with a Less→More intensity legend. [`_screens/07-habit-detail.jpg`]
- 🟡 **Streak** — works, but resets to zero on a single miss (no grace/freeze) — punishing for a "calm" app (`HABIT-2`).
- 🔴 **Habit reminders** — scheduled with `repeats: false`, so a recurring habit reminder fires once then stops (`REM-1`).

## Notes & the Markdown editor
- ✅ **Full-screen editor** with a **Live / Raw** mode toggle. [`_screens/05-editor-empty.jpg`]
- ✅ **Live syntax styling** — headings, **bold**, *italic*, `inline code` render with markers hidden;
  verified by typing live. [`_screens/06-editor-live.jpg`]
- ✅ **Smart list-continuation** (Return auto-inserts the next bullet/number/task marker — visible as
  doubled markers in my screenshot only because I typed raw markdown by hand).
- 🔵 **25-button toolbar** (bold/italic/strike/highlight/code/headings/lists/task/quote/indent/link/
  image/code-block/table/hr/wikilink/footnote/math/mermaid), tappable checkboxes, verbatim paste.
- 🟡 **Editor doesn't auto-focus** the text on open (you tap once to start typing) — minor friction.
- 🟡 **KaTeX math, Mermaid diagrams, tappable wikilinks** — on the roadmap (`docs/CURRENT.md` "Next Work"),
  **not implemented yet** (toolbar inserts the syntax; rendering isn't wired).
- 🔴 **Undo** is broken in the editor (full-document replace, no UndoManager — `ED-1`); long-note typing
  lags (`ED-2`).

## Lists structure & storage
- ✅ **Arbitrary list nesting** (sidebar tree + "Sub-Lists" section), **sections within lists**,
  **sub-items/threads**.
- 🔵 **Files-as-truth storage** — each item a Markdown+YAML file, each list a folder, rename/reparent
  moves folders, **soft-delete tombstones + cascade**, legacy-layout migration. (Robust write path;
  the **read path is the weak point** — `DI-1`.)
- 🔵 **Sample-data bootstrap** (deterministic UUIDs; re-seeds on `--ui-testing-reset-data`).
- 🔵 **Export** of the Lists directory (per project notes — the documented way to extract data off-device).

## Platform / system integration
- 🔵 **Local notifications** scheduling (non-recurring — see `REM-1`).
- 🟡 **App Group** entitlement + **`lists://` URL scheme** are declared but **not used yet** (dead hooks;
  relevant to the future agent-lists/share-extension ideas).
- 🔴 **No App Intents / widgets / Siri / Shortcuts / Spotlight** yet (single app target) — the single
  highest-reach integration gap (one App Intent unlocks most of these).
- ⚠️ **iOS 26.0-only** — builds and runs great on the iOS 26 simulator, but **~1/3 of iPhones can't
  install it today** (`STRAT-1`; research recommends lowering to iOS 18).

## Tests & build
- ✅ **App builds clean** — Swift 6 strict concurrency, **zero warnings**.
- 🔴 **`ListsTests` does not currently compile** (`BUILD-1`) — a stale `SettingsView` call; the snapshot
  suite is dark until a one-line fix. `ListsUITests` compiles.

---

### Overall
Verified live: home, Today, list detail (sections + nesting + habit ring), item detail, the markdown
editor (live styling), habit detail (ring + heatmap), and quick capture — **all working and genuinely
polished**. What's *not* done splits cleanly into (a) **deferred-by-design** (alarms, sync, math/mermaid
rendering, other platforms) and (b) **looks-done-but-broken** — the three to know about are recurring
tasks (`TASK-1`), recurring reminders (`REM-1`), and editor undo (`ED-1`). None of these are structural;
they're targeted fixes.
