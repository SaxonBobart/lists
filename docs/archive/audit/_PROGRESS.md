# Audit Run Log

Read-only. No source changes. Started 2026-05-24 (overnight autonomous run).

## Plan
- [x] Recon
- [x] Scaffold audit workspace
- [x] **Wave 1 — Technical breadth** (10 domain agents + build) — COMPLETE
- [x] **Wave 2 — External research** (9 aspects) — COMPLETE
- [x] **Wave 3 — Agent-lists** research + feasibility — COMPLETE (2 bg agents)
- [x] **Wave 4 — Product state**: built + ran app, walked 8 headline screens → 02-what-works-today.md + _screens/ — COMPLETE
- [~] **Wave 5+6 — Verify**: skeptic pass to disprove every P0/P1 — DISPATCHED (merged; depth folded into verification)
- [ ] **Wave 7 — Synthesis**: SUMMARY.md + sections 01–05
- [ ] Self-paced deepening loops → PushNotification on completion

## Notes / corrections
- Memory "test targets retired" is STALE — tests exist but `ListsTests` doesn't compile (BUILD-1). Update memory at synthesis.
- AGENTS.md/README/CURRENT reference deleted `shared/`+`research/` dirs — doc drift.
- App Group entitlement + `lists://` URL scheme declared but UNUSED — dead today; hooks for agent-lists.
- Build is Swift 6 language mode + full strict concurrency → memory races are compile errors. Strong.
- **SAFETY (this run):** `~/.claude` `bypassPermissions` + pre-approved `git reset --hard`. Guardrails NOT
  harness-enforced. Audit stays strictly read-only / no state-changing git regardless.

## Consolidated P0/P1 register (authoritative — feeds Verify + Synthesis)
**P0**
- `DI-1` One corrupt/partial file aborts the ENTIRE library load (`FileStore.loadAll`/`walk` bare `try`,
  no per-file isolation; stuck on "Loading…", only console `print`). Corroborated x3. **High.** The `created_at` class.
- `DI-2` Cross-list move duplicates an item on disk (writes new file, never deletes old → zombie reappears
  after deletion). Med-High. **Verify Wave 6.**

**P1**
- `TASK-1`★ Recurring tasks never regenerate: RRULE is saved + UI offers repeat, but `ItemStore.toggleDone`
  (~77–91) doesn't create the next occurrence → completing a recurring task makes it vanish permanently.
  High impact (feels like data loss + silent broken feature). **Verify Wave 6.**
- `REM-1` Reminders fire once: `NotificationScheduler` uses `repeats: false` → "daily" reminders stop after
  day one (habit + task reminders). High.
- `SEC-1` MarkdownUI default image provider fetches remote `![](http…)` images → silent network/IP leak;
  breaks "no network for local use". Fix `.markdownImageProvider(.asset)`. High.
- `DI-3` Malformed `deleted_at` silently un-deletes (tombstone parse).
- `DI-4` Fire-and-forget reorder/update `Task`s — no ordering guarantee; disk can drift from UI after drag.
- `CONC-1` Actor-reentrancy lost-update (read snapshot → `await` write → second action clobbers). Worse with sync.
- `UI-1` `ItemRow` owns its own `.sheet(isPresented:)` inside collection cells; reconfigure resets `@State`
  → can dismiss/interrupt the just-opened detail sheet (linger timer triggers). **Verify live Wave 4.**
- `ED-1` Editor: full-document `replaceCharacters` + NO `UndoManager` → broken undo. (Confirmed by R4.)
- `ED-2` Editor: per-keystroke whole-document re-style + triple full-range invalidation → O(n²) typing,
  lag on long notes. (Confirmed by R4; fix = edited-range styling but invalidate whole list block.)
- `ED-3` `ListMarker.detect` grapheme vs UTF-16 offset mismatch (latent; ASCII-safe today).
- `ED-4` Quoted-task checkboxes render tappable but tapping is a no-op.
- `PERF-1` Smart-list/Today `reconfigureItems(all)` + O(items) `first(where:)` per cell → O(rows×items) per tap.
- `A11Y-1` App not usable end-to-end by VoiceOver: editor reads raw markdown, drawn checkboxes invisible,
  a hidden alpha-0 label is focusable, UIKit swipe actions unannounced, drag-reorder has no accessible
  alternative, ring/heatmap color-only, Reduce Motion never checked.
- `BUILD-1` `ListsTests` doesn't compile (`SettingsView` gained `autoListPrefs:`, test stale; commit 2b224f3). Trivial.
- `SETUP-1` `~/.claude` `bypassPermissions` + pre-approved destructive `git reset` → autonomy guardrails unenforceable. High.

**P2 (selected)**
- `HABIT-2` Streak resets to zero on a single miss (no grace/freeze/“never miss twice”) — punishing, off-brand for "calm".
- repo bloat (.git 57M, ~54M orphaned → `git gc --prune=now`); App Group + `lists://` unused; `main` 100 behind `dev`;
  `QuickCaptureSheet`/`ItemDetailSheet` ~70% duplicate; linger logic copy-pasted ×3; docs reference deleted `shared/`.

**Strategic (product calls, not bugs)**
- `STRAT-1` iOS 26.0 target = ~26–34% of iPhones excluded today (~66% on iOS 26). R9: lower to **iOS 18.0**
  (only 7 cosmetic `.glassEffect` lines are 26-only) → ~doubles installable base. Earliest sensible launch summer 2026.
- `STRAT-2` Niche (native + local-first + tasks+habits+notes unified) is essentially **unoccupied**; nearest = NotePlan.
- `STRAT-3` Model: free local + paid **Lists Sync** (~$2–3/mo or $19–24/yr + lifetime $40–60); Small Business 15%.
  Do NOT charge until DI-1 fixed and sync works. Sync = CloudKit/CKSyncEngine (needs paid Apple acct); keep files+tombstones,
  add **field-level merge** (union `completion_log`/`tags`, LWW scalar fields, text-merge body). No CRDTs needed.
- `STRAT-4` Highest reach-per-effort features: fix recurrence (TASK-1) → natural-language capture (NSDataDetector)
  → one **App Intent** (unlocks Siri/Shortcuts/Spotlight/widgets/Action Button).

## Wave 2 — research takeaways (detail in audit/research/*.md)
- market-competitors · local-first-sync · storage-format · ios-editor-engineering · habit-ux · task-ux ·
  monetization · accessibility-ios · aso-ios26-audience — all written. Storage bet (files-as-truth) validated;
  harden read path + add schema `v:` now, rebuildable SQLite index later. Stay TextKit 1; edited-range styling.

## Agent-lists extra register items (from Wave 3, feed 05 + verify)
- `AGENT-1` `ItemType` Decodable reportedly THROWS on an unknown `type:` (e.g. `question`) → via DI-1 a
  newer/peer file could brick the whole library load on older builds. Make decoding permissive. Verify.
- `AGENT-2` `_status.md` heartbeat file would be mis-read as an item by `FileStore.walk` and fail to decode
  (→ DI-1 brick). `walk` must skip `_`-prefixed files. Verify.
- Convergent verdict: data model fits; external-worker premise needs desktop/sync; claim-lock unsafe over
  iCloud; keep single-writer/local near-term; OpenClaw/Hermes are real but mis-cast (messaging agents).

## Wave 4 — live product verification (DONE)
8 screens captured & confirmed working: home/sidebar, Today, list-detail (sections+nesting+habit ring),
item-detail, editor (empty + live styling), habit-detail (ring+heatmap), quick-capture. App is polished &
shippable-looking. A11Y-1 confirmed live (habit stats are ungrouped VoiceOver fragments). UI-1 sheet opens
on normal tap (dismiss-on-reconfigure not reproduced live — left to code verification). Editor doesn't auto-focus.

## Wave status
- Waves 1–4: COMPLETE → findings/, research/, 02-what-works-today.md, _screens/.
- Wave 5+6: DISPATCHED — verification-data (DI-1/DI-2/DI-3/TASK-1/REM-1/CONC-1) +
  verification-ui (UI-1/ED-1/ED-2/SEC-1/A11Y-1/AGENT-1/AGENT-2). Skeptic pass, CONFIRMED/REFUTED/UNCERTAIN.
- Wave 7 synthesis: COMPLETE → SUMMARY.md + 01,02,03,04,05.
- Wave 8 bonus fix-plan: COMPLETE → 06-fix-plan-data.md, 06-fix-plan-ui.md.
- Memory: corrected stale "tests retired"; added overnight-audit-2026-05-24.

## ✅ AUDIT COMPLETE
Coverage: 10 technical domain audits + clean build + live 8-screen product walk + 9 research aspects +
2 agent-lists deep-dives + 2-agent skeptic verification + 2 fix-plan specs. ~25 agent passes, all read-only.
Zero source files changed; no commits/push/PR/merge. Deliverable: audit/ (start at SUMMARY.md).
Loop stopped intentionally (audit exhaustive; further passes would be padding, not value).
