# Future Vision

*You asked me to separate what's **documented** from what I'm **inferring**. I've done exactly that below.
The first section is your own words; the second is the research's recommendations, which are NOT yet your stated
plan; the third is a suggested shape you can take or leave.*

## A. The vision as you've documented it (your words — `PRODUCT-SPEC.md`, `docs/CURRENT.md`)
- **What it is:** "a local-first app for tasks, habits, and notes" that should "feel calm, native, fast, and private."
- **Design philosophy:** one `Item` primitive; files are the source of truth (indexes/caches are rebuildable);
  restrained native iOS design; SF Pro/SF Mono; "avoid marketing-style UI inside the product."
- **Privacy as a principle:** no telemetry, no account required, no cloud dependency for local use.
- **Sync is deferred** — and the spec frames Lists Sync as a future, separate thing (not free-by-default).
- **Explicitly deferred:** other platforms, App Store distribution, AlarmKit, agent integrations, a Rust core, web client.
- **Near-term intent (`CURRENT.md`):** richer note rendering (math, diagrams, wikilinks).

So your documented vision is clear and coherent: **a calm, private, native, file-owned personal organizer**, with
sync and agents as deliberate "later."

## B. What the research suggests (inferred / recommended — *not* your stated plan, decide for yourself)
*(Full detail + sources in `research/`.)*
- **The niche is open.** "Native + local-first + tasks **and** habits **and** notes unified" is essentially
  unoccupied. The closest competitor (NotePlan) has no habits, is calendar-centric, costs ~$99/yr, and has no free
  tier. Your documented vision *is* the differentiator — lean into it.
- **A one-line positioning to own:** *"Tasks, habits & notes in one calm app — plain files you own, private by default."*
- **Monetization that fits the ethos:** keep the **local app free forever** (it's the funnel and costs nothing to run);
  charge for **Lists Sync** (~$2–3/mo or ~$19–24/yr, optional lifetime ~$40–60). This is Obsidian's proven model.
  Don't charge a cent until reliability (`DI-1`) is fixed and sync genuinely works.
- **Sync architecture:** keep files-as-truth + tombstones (right call — no CRDTs needed); add **field-level merge**
  (union completion-logs/tags, last-write-wins scalars, text-merge bodies); build on **CloudKit/CKSyncEngine**
  (free hosting via users' iCloud, native, E2E for users with Advanced Data Protection). *Requires a paid Apple
  Developer account.*
- **Platform reality:** **lower the deployment target to iOS 18** before any release; the earliest sensible public
  launch is **~summer 2026**, riding the iOS 27 release so iOS 26 becomes the safe "−1".
- **Agent-lists** (your new idea) fits best as a **desktop/sync-era differentiator**, after reliability work — see `05-agent-lists.md`.

## C. Where A and B agree, and the one tension
- **Agreement:** privacy-first, local-first, files-you-own, native, calm — the research strongly *validates* your
  documented direction and says it's a real market opening. Your storage bet is the right one.
- **Tension to resolve deliberately:** your spec frames sync as just "deferred," but the research says **sync is also
  your business model** (the paid hook). Worth deciding consciously: is Lists a free gift, or a free-local + paid-sync
  product? (The latter is what funds continued work and fits the ethos.) Also: AlarmKit, CloudKit sync, and agent-lists
  all **need a paid Apple Developer account** — that one purchase unblocks much of the roadmap.

## D. A suggested roadmap shape (a proposal, not a decree)
0. **Reliability first** — `DI-1` read-path, `DI-2` move-dup, `TASK-1`/`REM-1` recurrence. *Nothing ships on a base that can lose data.*
1. **Finish & polish** — editor undo + perf, VoiceOver, forgiving streaks, lower to **iOS 18**, an App Intent + widget.
2. **Quiet public launch (free, local-only)** — App Store, "you own your data" positioning, Product Hunt + local-first communities. (~summer 2026.)
3. **Lists Sync (paid)** — needs the paid Apple account; field-merge + CloudKit; this is the revenue moment.
4. **Desktop client + Agent Lists** — the platform-expansion era, where a real external worker (and BYO agents) finally make sense.

Phases 0–1 are "make the thing you already built trustworthy and installable." Phases 2–4 are "turn it into a product
and a business." You're closer to Phase 0-done than the anxiety suggests.
