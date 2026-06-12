# Research Brief — READ THIS FIRST

You are one of several parallel **research** agents for the Lists project. Do real external
research (use **WebSearch** and **WebFetch**) and tie every finding back to Lists. The current
date is **May 2026** — prefer current sources and note when something may have changed.

## The product you're researching for
**Lists** — an iOS-first, **local-first** app for **tasks, habits, and notes** in one. Intended
feel: calm, native, fast, private. Key facts that should shape your analysis:
- **Files are the source of truth.** Each item is a Markdown file with YAML frontmatter; each list
  is a folder. Plain-text, "you own your data." Stored app-private on iOS today (not even Files.app
  / iCloud visible yet).
- **One primitive (`Item`)** unifies task / habit / note. Smart lists are live queries. Tags are
  inline `#tags`. Habits use a progress ring + cycles + heatmap.
- Custom **native** Markdown editor (UITextView/TextKit) — the founder has explicitly ruled out web
  views and third-party editor libraries; native-only on each platform.
- **Sync is deferred but planned** as the likely **paid** feature ("Lists Sync"). Data already
  carries tombstones to make future sync reconciliation possible.
- **No telemetry, no account, no cloud dependency** for local use (privacy is a core promise).
- Built largely solo with AI assistance. iOS-only for now (Android/desktop deferred).
- **Deployment target is iOS 26.0** — a deliberate constraint to dig into (adoption/audience).

## How to deliver — write `audit/research/<NAME>.md` (your prompt gives <NAME>)
```
# <Aspect> — Research
## Bottom line (3–5 sentences, plain English, for a non-technical product owner)
## What the landscape / best practice looks like (May 2026)
Concrete, current, specific. Name names, cite numbers/prices/versions where relevant.
## Implications for Lists  ← the most important section
Specific, actionable. What should Lists do, keep, change, avoid, or prioritise? Tie to the facts above.
## Open questions / things to validate
## Sources
Markdown links to every URL you actually used.
```
Then return to the dispatcher a **≤150-word summary**: the bottom line + the top 2–3 implications
for Lists. Do NOT paste the whole file back.

## Rules
- Be honest and concrete, not generic. "Productivity apps are competitive" is useless; "NotePlan
  charges $X and wins on calendar+markdown, here's the gap Lists could own" is useful.
- Distinguish fact (with a source) from your own recommendation.
- If a search comes up dry, say so and reason from what you do know.
- This is read-only research: do not modify any repo file except your one research file.
