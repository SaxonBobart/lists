# Lists — Overnight Audit Summary

*Read this one. Everything else is detail you can dip into. Produced 2026-05-24, read-only, no code changed.*

---

## The bottom line (read this if nothing else)

**Your app is in genuinely good shape. The anxiety isn't matched by the evidence.** You built a real,
polished, working iOS app — not a fragile prototype — and the underlying engineering is *better* than typical
for an AI-assisted solo build. It compiles cleanly under Apple's strictest settings with **zero warnings**, the
structure is sound, and there are **no crash-prone shortcuts**.

There are **a handful of specific, fixable issues** — and I won't soften the important one: **right now, a
single corrupted file can make your entire library appear empty.** That's the thing to fix first. After that,
it's mostly "finish what's started" and "decide the product strategy."

I had ~22 specialist passes read essentially every line, then a skeptic re-checked every serious finding to
make sure none were false alarms. They all held up — but so did all the praise.

---

## The honest health check

**Grade: B+ — solid foundation, a few real bugs.** What's genuinely strong (verified, not flattery):

- ✅ **Clean Swift 6 build, 0 warnings** across ~19,000 lines, with full concurrency safety on.
- ✅ **No crash traps** — every risky-looking shortcut is provably safe; the usual iOS text/emoji crashes don't apply.
- ✅ **Sound architecture** — file work runs off the main thread and can't freeze the UI; writes are atomic; no memory leaks.
- ✅ **Privacy mostly real** — no tracking, no analytics, no secrets, no networking in your own code.
- ✅ **It looks shippable.** I ran it and walked every screen (screenshots in `_screens/`) — Today, lists with
  nesting & sections, the item editor, the live markdown editor, habits with the heatmap, quick capture. All polished.

---

## The 6 things that actually matter (in priority order)

1. 🔴 **A single bad file hides your whole library.** *(P0)* Loading has no per-file safety net, so one corrupt or
   half-written file leaves the app stuck on "Loading…" with everything invisible. This is the `created_at` problem
   you've hit — and it's the root that makes several other issues dangerous. **Fix first.**
2. 🔴 **Moving an item between lists can duplicate it.** *(P0)* The old file isn't deleted, so a copy reappears after
   you delete one. Small, well-defined fix.
3. 🟠 **Recurring tasks silently vanish.** *(P1)* You can set "repeat," but completing a recurring task never creates
   the next one — it just disappears. (Same missing piece makes recurring reminders fire only once.) One fix solves both.
4. 🟠 **Notes secretly fetch remote images** *(P1)* — a note with a web image link reaches the internet and leaks your
   IP, breaking your "no cloud" promise. **One-line fix.**
5. 🟠 **Editor undo is broken & long notes lag** *(P1)* — undo reverts big chunks; typing slows on long notes / big lists.
   Worth fixing before your notes get large.
6. 🟠 **VoiceOver users can't fully use it yet, and your tests don't currently compile** *(P1)* — the test fix is one line;
   accessibility is real work, mostly in the editor.

Full technical detail, with exact file/line references and the recommended fix for each, is in
**`01-technical-health.md`**.

---

## The bigger picture is encouraging

The research (full versions in `research/`, with sources) says your instincts are good:

- 🟢 **Your niche is basically empty.** "Native + local-first + tasks **and** habits **and** notes together" isn't
  occupied. Closest is NotePlan — no habits, calendar-centric, ~$99/yr, no free tier. **You can own this space.**
- 🟢 **A line to own:** *"Tasks, habits & notes in one calm app — plain files you own, private by default."*
- 🟢 **The money model fits:** free local app, **paid sync later** (Obsidian's proven ~$25M/yr playbook). Don't charge
  until the data-safety fix lands.
- ⚠️ **One urgent product call:** you're targeting **iOS 26 only**, so **~1 in 3 iPhones can't install it today.** Only
  *7 cosmetic lines* are iOS-26-specific — **lowering to iOS 18 roughly doubles who can install it.** Easy, high-impact.
- 🗓️ **Earliest sensible public launch: ~summer 2026.**

---

## Your "agent lists" idea

Strong idea, on-trend, and your data model already supports most of it. **But** the core premise — an outside
program reading/writing your files directly — **can't work on iOS as built** (the files are sandboxed), and
"two programs editing the same files" is exactly the fragile spot above. Right path: fix the data-safety issues
first, ship a small **first-party "Agent view"** experiment, and save real external/BYO workers for the **desktop
or sync era**. (Also: "OpenClaw/Hermes" are real but are messaging-app agents, not file workers — keep it
worker-agnostic.) Full feasibility + a phased plan in **`05-agent-lists.md`**.

---

## What I'd do, in order

0. **Make it trustworthy:** fix the read-path (#1), the move-duplicate (#2), recurrence (#3). *Nothing else matters if data can vanish.*
1. **Finish & polish:** image-privacy one-liner (#4), editor undo + speed (#5), accessibility + re-enable tests (#6), **lower to iOS 18**, add one App Intent + a widget.
2. **Launch quietly (free, local):** App Store, "you own your data" angle, Product Hunt + local-first communities.
3. **Lists Sync (paid):** needs a **paid Apple Developer account** (which also unblocks alarms and agent-lists).
4. **Desktop + Agent Lists:** the platform-expansion era.

You are closer to "step 0 done" than the anxiety suggests.

---

## Two housekeeping notes

- 🔒 **Your Claude Code safety rails aren't actually enforced.** Your global setting is `bypassPermissions` with a
  destructive `git reset` pre-approved — so "never push/reset without asking" can't be enforced by the tool. Worth
  tightening before more autonomous runs. *(This run stayed strictly read-only regardless — nothing was changed,
  committed, or pushed.)*
- 🗂️ **This `audit/` folder is the only thing I created.** It's not committed. Keep it, or delete it any time with
  `rm -rf audit/`.

## Where to read more
| File | What's in it |
|---|---|
| `01-technical-health.md` | Every bug, prioritized, with file:line + fixes |
| `02-what-works-today.md` | Feature-by-feature inventory (I ran the app) + `_screens/` |
| `03-completed-and-remaining.md` | Done / unfinished / deferred ledger |
| `04-future-vision.md` | Vision — **your documented words vs my inferred suggestions**, kept separate |
| `05-agent-lists.md` | Agent-lists feasibility + phased plan |
| `06-fix-plan-data.md` · `06-fix-plan-ui.md` | Ready-to-implement fix specs (locations + before/after code) |
| `research/` | Market, sync, storage, editor, habits, monetization, accessibility, App Store — with sources |
| `findings/` | Raw evidence behind `01` (incl. the skeptic verification) |
| `_PROGRESS.md` | How this audit was run, and the master finding register |
