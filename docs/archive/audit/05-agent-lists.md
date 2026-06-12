# Agent Lists — Feasibility & Recommendation

*Synthesis of external prior-art research + a code-grounded feasibility analysis + verification of two
schema landmines. Your sketch is in `research/_agent-lists-handoff.md`; full detail in
`research/agent-lists-prior-art.md` and `research/agent-lists-feasibility.md`. You said "don't treat it
like a Bible" — good, because the core instinct is right but one premise needs reworking.*

## Bottom line
The **idea is strong and on-trend**, and your data model already supports most of it almost for free.
But the headline mechanism — *an external program (OpenClaw/Hermes) reading and writing the list's files
directly* — **does not work on iOS as built**, and "two programs editing the same files" is exactly the
fragile spot this audit already flagged. The right move: treat agent-lists as a **desktop/sync-era feature**,
and ship a small **first-party, read-mostly "Agent view"** experiment first. It's correctly already on your
Deferred list.

## What fits Lists almost for free
- The **one-`Item` primitive + tolerant frontmatter + live smart-list queries** is a great substrate. The four
  sections (Needs Attention / Working / Scheduled / Completed) are just smart-list queries over a `status` field.
- `created_by`, `parent`, and tombstones **already exist** — they support agent provenance, the "question" as a
  child of a task, and run history.
- The **`question` item type** maps cleanly onto the existing model (a new type + a few frontmatter fields).
- Recurring agent jobs **reusing habits** is elegant — *but depends on recurrence, which is currently broken
  (`TASK-1`). That must be fixed first* or recurring jobs would silently never fire.

## The blocker: the iOS sandbox
An external process **cannot read or write an iOS app's `Documents/`**. Your storage is deliberately app-private
(not even Files.app). So a "files-only worker" needs one of:
- **(a) A desktop/macOS client** pointed at a user-chosen folder — the *cleanest* fit, but the desktop client is deferred.
- **(b) The future sync layer** — the worker operates on a server/desktop copy and changes sync back — but sync is deferred.
- **(c) An iOS App Group + app extension** — works, but that's *your own first-party code*, not an arbitrary BYO worker.
- **(d) Files.app / File Provider exposure** — a deliberate non-goal for you.

You already declare an App Group + a `lists://` URL scheme (both currently unused) — real hooks, but they don't
change the conclusion: **a true external worker is gated on the desktop client or sync.** Near-term iOS can only
do a *first-party* version.

## The hard part: two writers on the same files
This is the real risk, and it's the same weakness the audit found:
- A plain `claimed_by`/`claimed_at` field is **a lease without a fence** — racy on a normal disk, and **genuinely
  unsafe over iCloud**, where there's no atomic compare-and-set, propagation lags, and conflicts get silently
  resolved by *destroying the losing version* and renaming copies to "… 2" (which would orphan an item out of its
  list). Lock files over sync are known to jam.
- Two writers also turn today's **rare** bugs into **routine** ones: `DI-1` (one bad file bricks the library) and
  `CONC-1` (lost updates) would fire constantly.
- **Verdict:** keep agent-lists **single-writer, local-only, atomic-rename**, with an optimistic `modified_at`/seq
  check before each write (you already store `modified_at`). Do **not** attempt multi-writer-over-iCloud.

## Schema landmines (verified) — and why `DI-1` must come first
- **AGENT-1 (CONFIRMED, `Item.swift:58,174`)** — the item-type decoder **throws on an unknown `type:`**. So the
  moment a `type: question` file exists, any build that doesn't know that type would fail to decode it — and via
  `DI-1`, that **bricks the entire library load**. Make type decoding permissive (unknown → a safe fallback) *before* adding types.
- **AGENT-2 (CONFIRMED, `FileStore.swift:174`)** — a `_status.md` heartbeat file would be **mistaken for an item**,
  fail to decode, and (via `DI-1`) brick the load. The loader must skip `_`-prefixed/non-item files.
Both reinforce: **fix `DI-1` (and make decoding forgiving) before any agent-list work.**

## The human-in-the-loop UX (this part is well-solved elsewhere — copy it)
- Model the `question` flow on **LangChain's "Agent Inbox"** (Accept / Edit / Respond / Ignore). Your inline
  tick/cross/chips/"other" maps onto this nicely.
- Use `risk: low|high` to **gate friction, not create noise.** The #1 documented failure of approval UIs is
  *approval fatigue* (people rubber-stamp). Default most questions to one-tap low-risk; reserve high-risk friction
  for irreversible/external effects; batch low-risk in Needs Attention.

## "OpenClaw / Hermes" reality check
Both are **real but mis-cast** — they're messaging-app agents, not list-file workers. Drop the brand names from the
design and position the protocol as **worker-agnostic**, validated against the actual BYO workers a user would point
at a folder: **Claude Code (headless), Aider, OpenHands.**

## Phased recommendation
1. **Prerequisites (you'd want these anyway):** fix `DI-1` (+ permissive type decoding, skip `_` files) and
   `TASK-1` (recurrence). Without these, agent-lists is actively dangerous.
2. **Smallest experiment (iOS, first-party, low risk):** a read-mostly **"Agent view"** — the 4 status sections, the
   `_status.md` status bubble, and the `question` type with the Agent-Inbox interaction — with the *writer stubbed
   or simulated*. Proves the UX and the file protocol without opening a multi-writer can of worms.
3. **Real workers:** arrive with the **desktop client** (local folder + a proper file lock) or the **sync layer**
   (worker as another sync peer). That's where "BYO agent works your list" genuinely belongs.
4. **Never:** multi-writer coordination over iCloud with a plain `claimed_by` flag.

## Risks to keep in view
- **Positioning drift.** Lists is "calm, private, personal." An agent-orchestration surface is powerful and unique
  (no one offers "your files, worked by your agents, with a human-in-the-loop inbox") — but it's a different product
  energy. Decide deliberately whether it's a headline or a power-user mode.
- **Scope.** This is a *platform* feature (desktop + sync + protocol spec). Treat it as a future milestone, not a quick add.
