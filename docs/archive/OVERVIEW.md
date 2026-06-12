# Lists — Where We Are

*Your plain-English map of the app: what it is, what's built, what isn't, and where it's going. Last updated 2026-05-28. The deep technical detail lives in the `audit/` folder if you ever want it.*

---

## What Lists is

**Tasks, habits, and notes in one calm, native app — built on plain files you own.**

It's three tools in one. A to-do list, a habit tracker, and a notes app, all sharing
the same building block so they live together instead of in three separate apps.
Everything you make is saved as ordinary text files on your phone — no account, no
sign-in, works with no internet, and nothing is sent anywhere. It looks and feels like
a real Apple app, not a flashy startup app.

---

## Where we are right now

You have a **real, working, polished app** — not a fragile prototype.

About a week ago an audit flagged six scary-sounding problems (the worst: a single bad
file could make your whole library look empty). **Those are now fixed.** You've come
out the other side of the "make sure data can't get lost" phase and you're into
"polish it up before showing anyone." In short: the anxiety was bigger than the
evidence, and the evidence keeps getting better.

---

## What the app does today

| Area | What it does | State |
|---|---|---|
| **Lists & nesting** | Make lists, nest them as deep as you want (a list inside a list inside a list), with sections inside each | ✅ Done |
| **Quick capture** | Floating **+** button to add a task, note, or habit fast — with due date, reminder, repeat, priority, flag, tags | ✅ Done |
| **Today & smart lists** | Auto-views that gather things for you: Today, Scheduled, Flagged, Urgent, Completed, All, plus Tags | ✅ Done |
| **Item detail** | Open any task or note to edit everything about it | ✅ Done |
| **Habits** | Streaks, a per-cycle grid (your "heatmap"), an editable history of every time you did it, and flexible goals like "3 times a week" | ✅ Done |
| **Markdown editor** | Write notes with live formatting, a toolbar, tappable checkboxes, and proper undo | ✅ Done |
| **Reminders** | Phone notifications for due dates, and repeating reminders for habits | ✅ Done |
| **Tags** | Add `#tags`, then browse and filter by them | ✅ Done |
| **Search** | Search across every title, note body, and tag | ✅ Done |
| **Recently deleted** | Anything you delete is recoverable for 30 days, then auto-clears | ✅ Done |
| **Drag, swipe, reorder** | Drag to reorder and re-nest, swipe for quick actions, the "linger" fade when you tick something off | ✅ Done |
| **Settings** | The Appearance section works (theme, density, etc.); Sync / Triggers / Data / About are still empty placeholders | 🟡 Partial |
| **Thread view** | See an item together with all its sub-items; you can tick them but not yet edit them in place | 🟡 Read-only |

---

## What we just fixed (the recent push)

This is the "wtf have we done lately" answer. Every scary item from the audit is now
handled:

| The worry | Status |
|---|---|
| One corrupted file could hide your **entire** library | ✅ Fixed — a bad file gets quarantined, the rest still loads |
| Moving an item between lists could **duplicate** it | ✅ Fixed — the old copy is now removed |
| Repeating tasks **silently vanished** when completed | ✅ Fixed — finishing one now creates the next |
| Repeating reminders only fired **once** | ✅ Fixed — they now repeat properly |
| Notes could **secretly fetch images from the internet** (privacy leak) | ✅ Fixed — locked to local images only |
| Editor **undo** misbehaved + long notes lagged | ✅ Fixed — undo works, typing is fast again |
| The **test safety-net** wasn't running | ✅ Fixed — tests compile and run again |
| **VoiceOver** (for blind/low-vision users) | 🟡 Mostly fixed — one piece left (see below) |
| **Habits redesign** | ✅ Done — timestamped history, editable log, forgiving "never miss twice" streaks, flexible weekly/monthly goals |

> Note: the habits redesign and the latest inline-editing work are built and tested on
> the `dev` branch and are waiting on your sign-off before they're locked in — nothing
> is lost, it's just pending your review.

---

## What's not done yet

Nothing here is broken — it's "not started" or "intentionally parked."

| Thing | What it is | Why it's waiting |
|---|---|---|
| **Editor VoiceOver** | The note editor still reads raw `**markdown**` aloud instead of the clean text | Last accessibility piece; real work, not urgent |
| **A couple of test baselines** | Two visual-snapshot tests need re-recording after recent restyling | Minor housekeeping |
| **Math & diagrams in notes** | KaTeX (math) and Mermaid (diagrams) — the buttons insert the text, but it doesn't render yet | Planned next-up polish |
| **Tappable wikilinks** | `[[link]]` jumping you to another item | Planned next-up polish |
| **Habit follow-ups** | "Skip/rest day" marking, and a weekday picker for weekly reminders | Nice-to-have refinements |
| **Lower the iOS requirement (26 → 18)** | Right now ~1 in 3 iPhones are too old to install it; lowering it roughly **doubles** who can | Easy, high-impact — just hasn't been done |
| **App Intents & a widget** | Siri/Shortcuts support and a home-screen widget | Worth adding before launch |
| **Natural-language capture** | Type "tomorrow 5pm #work" and have it understand the date | Future nicety |

---

## The future / the plan

This is the plan *so far* — you drive it, none of it is locked in.

1. **Finish & polish** — wrap up accessibility, render math/diagrams/wikilinks, lower
   the iOS requirement so more people can install, add a widget. *(We're here.)*
2. **Quiet free launch** — put it on the App Store, free, local-only. Soft launch to
   the right communities, not a big ad blitz. Earliest sensible window: **~summer 2026**.
   The angle: *"Tasks, habits & notes in one calm app — plain files you own, private by default."*
3. **Lists Sync (paid)** — optional paid cloud sync across your devices. This is the
   money model: **free app forever, pay only if you want sync** (the same playbook
   Obsidian uses successfully).
4. **Desktop + "agent lists"** — a Mac/desktop version, and the idea of lists that
   outside helpers/automations can read and write.

**The one real blocker for the paid stuff:** sync *and* true alarm-style reminders both
need a **paid Apple Developer account** (~$99/year). The free account you're on now
can't unlock them. Everything in steps 1–2 works without it.

> The golden rule from the audit: **don't charge anyone until sync genuinely works and
> data is rock-solid.** You're already past the hardest part of that.

---

## The honest health check

Straight from a thorough technical review, not flattery:

- ✅ Builds cleanly under Apple's strictest settings, **zero warnings**.
- ✅ **No crash traps** — none of the risky shortcuts that sink amateur apps.
- ✅ **Genuinely private** — no tracking, no analytics, no hidden networking.
- ✅ **Solid foundations** — file work happens safely in the background, saves are
  done in a way that won't corrupt your data.

The review graded it **B+** *before* the recent round of fixes. With those fixes in,
it's stronger than that now.

---

## If you asked me what's next

My suggestion, in order (you decide):

1. **Lower the iOS requirement to 18.** Biggest bang for the buck — roughly doubles
   how many people can install it, very little work.
2. **Finish accessibility + re-record those two tests.** Closes out the last loose
   ends from the audit so the slate is truly clean.
3. **Add one App Intent + a widget.** The kind of polish that makes it feel like a
   "real" App Store app before you show it to anyone.

After that, you're in launch-prep territory.

---

*Want more depth on any line above? The `audit/` folder has the full breakdown with
exact details. This file is just the map.*
