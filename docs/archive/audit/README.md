# Lists — Overnight Audit (2026-05-24)

This folder is a **read-only audit** of the Lists project, produced overnight by Claude Code.
**No source code was changed to produce it.** It is safe to delete: `rm -rf audit/`.

## Start here
- **`SUMMARY.md`** — the one to read first. Plain-English state of the project: health, what's
  solid, what needs attention, what's done vs not, the forward vision, and how Lists compares
  to the world. Written for a product owner, not an engineer.

## The rest
- `01-technical-health.md` — synthesized code/quality/data-safety audit.
- `02-what-works-today.md` — verified feature-by-feature inventory (built + observed running).
- `03-completed-and-remaining.md` — done / not-done ledger and milestone history.
- `04-future-vision.md` — the product vision & roadmap (documented vs inferred, clearly marked).
- `05-agent-lists.md` — research + feasibility for the "agent list" idea.
- `06-fix-plan-data.md` / `06-fix-plan-ui.md` — **bonus:** concrete, ready-to-implement fix specs for the
  priority bugs (exact locations, before/after code, tests). Hand these to an implementer directly.
- `research/*.md` — external research per aspect (market, sync, storage, editor, habits,
  monetization, accessibility, App Store…), each tied to *implications for Lists*, with sources.
- `findings/*.md` — raw technical evidence per domain (the detail behind 01).
- `_screens/` — screenshots captured while the app was running.
- `_CONTEXT.md` / `_PROGRESS.md` — internal briefing + the run log (how this was produced).

## Trust notes
- Severity is ranked P0 (could lose your data / crash / leak) → P3 (cosmetic).
- High-severity findings get a second skeptical pass to weed out false alarms before they reach
  `SUMMARY.md`. Anything still uncertain is labelled as such.
- Where the roadmap/vision is *inferred* rather than written down, it says so.
