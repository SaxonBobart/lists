# Competitive & Market Landscape — Research

## Bottom line (3–5 sentences, plain English, for a non-technical product owner)
The exact combination Lists is going for — **tasks + habits + notes in one, native, local-first, and file-based (plain Markdown you own)** — is essentially **unoccupied**. The closest single competitor is **NotePlan** (markdown files + tasks + calendar, Apple-first), but it leans on a calendar/daily-note workflow, charges ~$99/yr with no free tier, has no real habit tracker, and gets steady complaints about sync bugs. The two camps Lists sits between each have a clear hole: the "calm native" leaders (**Things 3**, **Apple Reminders/Notes**) deliberately omit habits and treat notes as second-class; the "file-based / own-your-data" leaders (**Obsidian, Logseq, Bear**) are notes-first, fiddly on mobile, and bolt tasks/habits on via plugins. Nobody credibly does all three *together*, *natively on iOS*, *with files as the source of truth*, *and privately by default*. That gap is Lists' opening — the risk is execution and discovery, not a crowded niche.

## What the landscape looks like (May 2026)

### The "native + calm" camp (Lists' feel, but missing notes+habits)
- **Things 3 (Cultured Code)** — the gold standard for calm, beautiful, Apple-native task management. One-time pricing (~$50 Mac / $20 iPad / $10 iPhone, ~$80 full suite), free Things Cloud sync that "just works." Beloved for design and simplicity. Deliberate omissions: **no habit tracker, no Pomodoro, no time tracking**, and notes are just a small text field on a task — not a notes app. Apple-only, no collaboration, no web. Cultured Code is famously silent on roadmap; **Things 4 is not even confirmed**, so the product is effectively frozen. ([Calmevo](https://calmevo.com/things-3-review/), [Richard Riviere](https://richardriviere.com/things-3-pricing), [Cultured Code status](https://culturedcode.com/status/))
- **Apple Reminders + Notes (iOS 26)** — free, native, ubiquitous, now with Liquid Glass design and Apple-Intelligence task suggestions. iOS 26.2 added "Urgent" reminders/alarms; 26.5 refined snoozing. **Habits are not a first-class feature** — Apple nudges you toward the *Journal* app for habit-building, and Reminders/Notes/Journal are three separate apps, not one primitive. iCloud-synced (not local-first/file-based; you don't own portable files). This is Lists' real "good enough / free / pre-installed" baseline competitor. ([MacRumors iOS 26 guide](https://www.macrumors.com/guide/ios-26-notes-app-reminders-app/), [9to5Mac 26.2](https://9to5mac.com/2026/01/30/ios-26-2s-new-reminders-feature-is-exactly-what-ive-wanted-for-years/), [Apple: build a journaling habit](https://support.apple.com/guide/iphone/build-a-journaling-habit-iph70107aec2/ios))

### The "file-based / markdown / own-your-data" camp (Lists' data model, but notes-first & fiddly)
- **NotePlan 3** — *the nearest competitor.* Combines notes + tasks + calendar, stores everything as **portable plaintext/Markdown files**, Apple-first (Mac/iPad/iPhone + web). Wins on calendar integration + daily notes + bi-directional linking. **Pricing: ~$8.33/mo billed annually ($99/yr) or $12/mo; no free tier**, only a 3–7 day trial. Weaknesses that map directly to Lists' opportunity: **no real habit tracker**; recurring tasks are limited (no "every 2nd Tuesday"); documented **sync bugs** (old folders/notes reappearing); the workflow is calendar-centric, which not everyone wants. ([NotePlan pricing](https://noteplan.co/pricing), [Capterra](https://www.capterra.com/p/217998/NotePlan-3/), [justuseapp reviews](https://justuseapp.com/en/app/1505432629/noteplan-3/reviews), [Toolradar](https://toolradar.com/tools/noteplan))
- **Obsidian (+ Tasks plugin)** — the local-first PKM heavyweight. Free for personal use; notes are plain Markdown in a local vault, "no vendor lock-in." Tasks/habits exist **only via plugins** (Tasks plugin's 🔁 recurrence, Periodic Notes for reviews, third-party habit-tracker plugins like Kikijiki). Reality: it's **notes-first, desktop-first, and setup-heavy** — assembling a tasks+habits system is a DIY project, and mobile is widely felt as clunky. Great for tinkerers, wrong for someone who wants it to "just work" calmly out of the box. ([Lindy review](https://www.lindy.ai/blog/obsidian-review), [taskforge tasks guide](https://taskforge.md/blog/obsidian-tasks-guide/), [Kikijiki habit plugin](https://www.obsidianstats.com/plugins/kikijiki-habit-tracker))
- **Logseq** — free, open-source, **local plain-Markdown**, outliner with built-in TODO/DOING/DONE and a daily-journal model. Truly own-your-data ("readable in any text editor if Logseq vanished"). But: **inconsistent performance on large graphs, a query language too technical for non-devs**, and an outliner paradigm that's an acquired taste. ([Calmevo Logseq](https://calmevo.com/logseq-review/), [SaaSweep](https://www.saasweep.com/blog/logseq-review))
- **Bear** — beautiful, native (Apple-only), Markdown notes with tag organization; **local storage + iCloud sync, zero-knowledge ("Bear cannot see your data"), per-note encryption.** Cheap: free tier + Pro at **$2.99/mo or $29.99/yr.** But it's a *notes* app: checkboxes exist, yet there's **no task model, no habits, no scheduling**. Closest to Lists on *aesthetic + privacy*, far from it on *tasks/habits*. ([Bear](https://bear.app/), [productivitystack Bear](https://productivitystack.io/tools/bear/))

### The "unified all-in-one" camp (does the combo, but cloud/account-bound, not file-based)
- **TickTick** — the value champion that genuinely bundles **tasks + habits + calendar + Pomodoro + notes** for **~$35.99/yr ($2.99/mo)**. This is the strongest *functional* match for "tasks+habits+notes together." But it's **cloud-account-based (not local-first, not your files)**, habit tracking + calendar sync sit behind the paywall, and reviewers note it "sacrifices the polish of purpose-built apps like Things." ([Calmevo TickTick](https://calmevo.com/ticktick-review/), [productivitystack](https://productivitystack.io/tools/ticktick/), [Android Police](https://www.androidpolice.com/replaced-to-do-list-habit-tracker-planner-with-ticktick/))
- **Todoist** — best-in-class tasks + integrations + cross-platform, cloud/account-based; notes and habits are weak/absent. A tasks specialist, not a unifier.
- **Amplenote** — inline tasks inside notes + Eisenhower-matrix scoring + calendar; free–$25/mo tiers. Functionally close to "tasks+notes," but **cloud-based and widely criticized as "ugly,"** and habits aren't a headline feature. ([Capterra Amplenote](https://www.capterra.com/p/10027015/Amplenote/), [G2](https://www.g2.com/products/amplenote/reviews))
- **Notion / Tana / Capacities / Reflect / Workflowy** — powerful, flexible, **cloud-first databases/outliners**. Notion and Tana ($8–14/mo) can model anything but are heavyweight and not local-first; Tana is now an "agentic AI" system. None are calm, native-iOS, or file-based; all require buy-in to a proprietary store. ([Capacities vs Tana](https://www.sollmannkann.com/project-management-and-notes/capacities-vs-tana/), [Tana review](https://makerstack.co/reviews/tana-review/))
- **Akiflow / Structured / Morgen** — time-blocking/day-planner aggregators that pull tasks from *other* tools onto a calendar. Adjacent, not direct: they assume your tasks live elsewhere.

### Two macro-trends worth knowing
1. **2026's productivity narrative is "integration, not fragmentation"** and **"calm over features"** — reviewers explicitly reward apps that reduce cognitive load over those with the longest feature list. Both trends favor Lists' thesis. ([Briefmatic all-in-one](https://briefmatic.com/blog/the-best-all-in-one-tools-that-combine-notes-tasks-and-calendar-for-remote-teams-2026-guide), [self-manager calm apps](https://self-manager.net/articles/top-10-calm-productivity-apps-in-2026-anti-burnout-low-friction))
2. **"Own your data / local-first / plain Markdown" is now a recognized buying criterion**, with E2EE/zero-knowledge increasingly table stakes for privacy-minded users — but the apps that satisfy it (Obsidian, Logseq, Joplin) are notes-tools, not unified life-organizers. ([Anarlog markdown apps](https://anarlog.so/blog/markdown-note-taking-apps/), [DeepJournal private journaling](https://deepjournal.app/blog/best-private-journaling-apps-in-2026))

## Implications for Lists ← the most important section

**1. The niche is an opening, not a crowd. Lists' four constraints intersect at an empty point.** Map the field on two axes — *(a) does it unify tasks+habits+notes?* and *(b) is it native + local-first + file-based?* — and **no app sits in the "yes/yes" quadrant.** TickTick says yes to (a) but no to (b) (cloud account). NotePlan/Obsidian/Bear say yes to (b) but no to (a) (no habits, notes-first). Things/Reminders say no to both. **This is the single most important strategic finding: Lists isn't entering a war, it's filling a hole.**

**2. Nearest competitor = NotePlan; the wedge against it is habits + free local tier + simplicity.** NotePlan is the only product that genuinely overlaps on "files-as-truth + tasks + notes, Apple-native." Lists should position *directly* against its weak spots: NotePlan has **no habit tracker** (Lists' progress-ring/heatmap habits are a clean differentiator), it's **calendar-centric** (Lists can be list/query-centric and lighter), it has **no free local tier** (Lists is free for local use — a huge wedge), and it has a **reputation for sync bugs** (Lists can win trust by being rock-solid offline first, sync later). Don't out-calendar NotePlan; out-*calm* and out-*habit* it.

**3. Own this one-liner: "Your tasks, habits, and notes in one calm app — as plain files you actually own, private by default."** Sharper variants to test: *"Things 3's calm, Obsidian's plain-text freedom — finally in one app, with habits."* / *"One app for tasks, habits and notes. Your files, your phone, no account, no cloud."* The load-bearing words are **calm + unified + your-files + private**, because each names a specific competitor's gap (calm→TickTick/Notion; unified→Things/Bear; your-files→TickTick/Todoist; private/no-account→all the cloud apps).

**4. Whitespace gaps to plant flags in, in priority order:**
   - **Native iOS + local-first + *real* habits** — the clearest empty space. No native, file-based app treats habits as a first-class primitive with rings/cycles/heatmaps. Lead with this.
   - **Free, fully-functional *local* tier** — every file-based rival either charges with no free tier (NotePlan ~$99/yr) or gates habits/sync behind a paywall (TickTick, Amplenote). Lists can be genuinely free locally and charge only for the eventual "Lists Sync." That's a defensible, generous, trust-building model.
   - **"It just works" calm onboarding** — Obsidian/Logseq lose mass-market users to setup friction and plugin assembly. Lists' single `Item` primitive + smart lists is a chance to deliver the *power* of a configured Obsidian vault with the *zero-setup calm* of Things.
   - **One primitive, not three apps** — Apple's own answer is fragmented (Reminders + Notes + Journal). "One thing that is a task *and* a habit *and* a note, depending on how you use it" is a story none of the incumbents can tell.

**5. Heed the constraints honestly.**
   - **iOS-26-only is a real audience cap but not a crisis.** As of Feb 2026, ~66% of *all* active iPhones (and ~74% of those from the last 4 years) run iOS 26 — roughly on the same curve as iOS 18. So a 26.0 floor excludes a meaningful minority *today* but the addressable base is large and growing, and it lets Lists use the newest TextKit/SwiftUI without legacy debt. Fine for an early/indie launch; revisit the floor only if early-adopter feedback shows demand from holdouts. ([AppleInsider](https://appleinsider.com/articles/26/02/13/ios-26-adoption-rate-isnt-the-crisis-some-analysts-are-portraying), [9to5Mac adoption](https://9to5mac.com/2026/02/13/apple-announces-ios-26-usage-numbers-heres-how-they-compare/))
   - **iOS-only / no-sync-yet repeats Things 3's own "biggest complaint."** Things' #1 frustration is Apple-only + no web. Lists shares this. Acceptable for v1, but the **deferred-but-planned "Lists Sync"** is exactly right, and tombstones-now is the correct groundwork. Frame sync as the premium upgrade, not a missing feature.
   - **Don't drift into Notion/Tana territory.** The whole advantage is *calm + few primitives*. The competitive lesson from 2026 reviews is that feature-creep loses; resist databases, AI agents, and configurability. Lists' edge is restraint.

## Open questions / things to validate
- **Mass-market vs. nerd appeal of "files as source of truth":** Bear/Obsidian users prize plain-text ownership, but does the *Things/Reminders* mainstream care, or just want it to work? Lists may need to *sell* the file-ownership benefit, not assume it's a draw. Worth user-testing the pitch.
- **Is "no habits" truly permanent in Things and Apple Reminders?** Apple is nudging habits via Journal; if Apple ships a first-class habit feature in a future iOS, the "native + habits" gap narrows. Monitor Apple's habit/journal moves each WWDC.
- **NotePlan's habit gap:** confirm NotePlan still lacks a true habit tracker (plugins may exist) — re-check before leaning hard on it as the differentiator.
- **Pricing of "Lists Sync":** validate against NotePlan (~$99/yr), TickTick (~$36/yr), Bear ($30/yr). A calm indie app likely lands nearer Bear/TickTick than NotePlan.
- **Discovery, not the product, is the real risk:** in a hole this empty, the hard part is being found. Validate App Store search terms / positioning that capture "calm tasks habits notes private" intent.

## Sources
- [Things 3 review — Calmevo](https://calmevo.com/things-3-review/)
- [Things 3 pricing — Richard Riviere](https://richardriviere.com/things-3-pricing)
- [Cultured Code status page](https://culturedcode.com/status/)
- [iOS 26 Notes & Reminders guide — MacRumors](https://www.macrumors.com/guide/ios-26-notes-app-reminders-app/)
- [iOS 26.2 Reminders alarms — 9to5Mac](https://9to5mac.com/2026/01/30/ios-26-2s-new-reminders-feature-is-exactly-what-ive-wanted-for-years/)
- [Build a journaling habit with Journal — Apple Support](https://support.apple.com/guide/iphone/build-a-journaling-habit-iph70107aec2/ios)
- [NotePlan pricing](https://noteplan.co/pricing)
- [NotePlan — Capterra](https://www.capterra.com/p/217998/NotePlan-3/)
- [NotePlan reviews — justuseapp](https://justuseapp.com/en/app/1505432629/noteplan-3/reviews)
- [NotePlan — Toolradar](https://toolradar.com/tools/noteplan)
- [Obsidian review — Lindy](https://www.lindy.ai/blog/obsidian-review)
- [Obsidian Tasks plugin guide — taskforge](https://taskforge.md/blog/obsidian-tasks-guide/)
- [Kikijiki Habit Tracker plugin — ObsidianStats](https://www.obsidianstats.com/plugins/kikijiki-habit-tracker)
- [Logseq review — Calmevo](https://calmevo.com/logseq-review/)
- [Logseq review — SaaSweep](https://www.saasweep.com/blog/logseq-review)
- [Bear app site](https://bear.app/)
- [Bear review — Productivity Stack](https://productivitystack.io/tools/bear/)
- [TickTick review — Calmevo](https://calmevo.com/ticktick-review/)
- [TickTick review — Productivity Stack](https://productivitystack.io/tools/ticktick/)
- [Replacing to-do/habit/planner with TickTick — Android Police](https://www.androidpolice.com/replaced-to-do-list-habit-tracker-planner-with-ticktick/)
- [Amplenote — Capterra](https://www.capterra.com/p/10027015/Amplenote/)
- [Amplenote reviews — G2](https://www.g2.com/products/amplenote/reviews)
- [Capacities vs Tana — AppSage](https://www.sollmannkann.com/project-management-and-notes/capacities-vs-tana/)
- [Tana review — MakerStack](https://makerstack.co/reviews/tana-review/)
- [All-in-one tools 2026 — Briefmatic](https://briefmatic.com/blog/the-best-all-in-one-tools-that-combine-notes-tasks-and-calendar-for-remote-teams-2026-guide)
- [Calm productivity apps 2026 — self-manager](https://self-manager.net/articles/top-10-calm-productivity-apps-in-2026-anti-burnout-low-friction)
- [Markdown note-taking apps 2026 — Anarlog](https://anarlog.so/blog/markdown-note-taking-apps/)
- [Best private journaling apps 2026 — DeepJournal](https://deepjournal.app/blog/best-private-journaling-apps-in-2026)
- [iOS 26 adoption not a crisis — AppleInsider](https://appleinsider.com/articles/26/02/13/ios-26-adoption-rate-isnt-the-crisis-some-analysts-are-portraying)
- [iOS 26 adoption numbers — 9to5Mac](https://9to5mac.com/2026/02/13/apple-announces-ios-26-usage-numbers-heres-how-they-compare/)
