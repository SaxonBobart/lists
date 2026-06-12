# Task-management UX — Research

_Research agent R6 (Wave 2). External research + verification against current Lists source. Date: May 2026._

## Bottom line (for a non-technical product owner)
Lists already has the *skeleton* of a serious task app — a real **Inbox**, **smart lists** as live queries (Today/Scheduled/Flagged/Urgent/Completed/All), priority, flags, early reminders, sub-items, sections, nested lists, and inline `#tags`. That's a strong foundation. But three things separate "calm hobby app" from "app people actually run their life in," and Lists is missing all three. (1) **Capture is a form, not a sentence.** The category leaders let you *type* "pay rent every 1st #finance" and parse the date, repeat, and tag automatically; Lists makes you tap through pickers. Users cite this as the single feature they love most (Todoist claims it's ~60% faster; "6–8 taps → 3 seconds"). (2) **Recurring tasks are broken, not just absent.** Lists *captures and stores* a repeat rule (RRULE) but **never acts on it** — completing a repeating task just ticks it off; the next occurrence never appears. That's worse than having no repeat UI, because it silently promises something it doesn't deliver. (3) **Zero system integration** — no widgets, no Siri/Shortcuts, no Spotlight, no Action Button. In 2026 these are table stakes and, on Apple's modern stack, they're *one* mechanism (App Intents), not five. The good news: the highest-value fixes (NL date parsing, making recurrence functional, a basic widget + "Add task" intent) are mostly self-contained and fit the calm/native/single-user ethos.

## What the landscape / best practice looks like (May 2026)

### 1. Natural-language quick capture is the defining feature
This is the feature users single out as essential and the one that most distinguishes the "pro" apps.
- **Todoist**: type `Submit report every 3rd Thursday at 3pm #work p1` into one field and it parses the recurring date, time, project, and priority, highlighting each as it recognises it. Reviewers call it "executed exceptionally well" and report it "parses complex dates like *every other Tuesday at 3pm starting next week* flawlessly." Todoist's own framing: capture "the moment they come to you, with easy-flowing, natural language." ([Todoist Features](https://www.todoist.com/features), [The Sweet Setup](https://thesweetsetup.com/using-natural-language-with-todoist/), [Motion comparison](https://www.usemotion.com/blog/todoist-vs-apple-reminders))
- **Things 3**: natural-language parsing for **When** (start date) and reminders on all platforms; for **Deadlines** only on Mac/iPad-with-keyboard. Accepts shorthand like "Tom", "Sat", "in fou(r days)", "Au(gust 1)", and Quick Entry handles "Write report tomorrow at 3 pm." ([Things: Natural Language](https://culturedcode.com/things/support/articles/9780167/), [Things 3.1 blog](https://culturedcode.com/things/blog/2017/07/things-3-1-repeating-to-dos-date-parsing/))
- **Apple Reminders**: NL works *only via Siri/typing in some surfaces* and is "less consistent — sometimes it works, sometimes you adjust manually." A cited weakness, not a strength. ([Akiflow](https://akiflow.com/blog/apple-reminders-vs-todoist))
- **TickTick**: handles basic NL ("tomorrow 9am") but "isn't as sophisticated" as Todoist. ([ClickUp: TickTick vs Todoist](https://clickup.com/blog/ticktick-vs-todoist/))

The pattern: one always-present text field; recognised tokens are highlighted and stripped from the title; everything else stays as the task name. The win is *speed of capture* — the moment a task is hardest to lose.

### 2. The Inbox → Today → Someday spine (GTD/PARA)
The dominant organising model across all four apps and the GTD methodology:
- **Capture to one Inbox**, process to zero, then file. ([Todoist GTD guide](https://www.todoist.com/productivity-methods/getting-things-done))
- **Today** = what's due/started today (the daily driver). Things splits a **"This Evening"** sub-section.
- **Upcoming/Scheduled** = future-dated, not yet actionable.
- **Anytime** = actionable, no fixed day.
- **Someday/Maybe** = a deliberate holding pen for "not now" — in GTD you create a `Someday/Maybe` list/label + a favourited filter and scan it during the **weekly review**. ([Todoist GTD article](https://www.todoist.com/help/articles/getting-things-done-gtd-with-todoist-e5j2h3))

Things formalises five states — **Today, This Evening, Upcoming, Anytime, Someday** — and this bucket model (not raw dates) is what makes Things feel *calm*. ([Things: Scheduling To-Dos](https://culturedcode.com/things/support/articles/2803579/))

### 3. Scheduling ("when") vs deadline ("must finish by") are two different fields
Things' most-copied idea. **Start date / "When"** = "when can I begin?" (task is dormant in Upcoming, then auto-surfaces in Today on that day). **Deadline** = "the date by which I must *finish*" (stays in Anytime; shows a separate deadline badge and a chronological "Deadlines" list). They are independent — a task can start Monday with a Friday deadline. ([Things: Scheduling](https://culturedcode.com/things/support/articles/2803579/)) Lists collapses both into one `due` field.

### 4. Recurring tasks: the bar is "complete it → next one appears," with two regen modes
- Things: completing a repeating to-do **auto-creates the next instance** in Today when its day comes. Two modes: repeat on a **fixed schedule** *or* repeat **N days/weeks after the previous one is completed**. ([Things: Repeating To-Dos](https://culturedcode.com/things/support/articles/2803564/))
- Todoist: "recurring due dates like no other… unrivalled date recognition," set via NL ("every Monday", "every first workday"). ([Introduction to recurring dates](https://www.todoist.com/help/articles/introduction-to-recurring-dates-YUYVJJAV))
- Common *complaint* even at the top: Things "falls apart by not allowing recurrence rules that consider weekends vs weekdays" (e.g. "last working day of the month"). So even leaders lose users on recurrence edge cases — it's a feature people care about deeply. ([Motion](https://www.usemotion.com/blog/todoist-vs-apple-reminders))

### 5. System integration is one mechanism now: App Intents
Since iOS 16, **App Intents** (pure Swift, replaced SiriKit) is a *single* declaration that lights up **Siri voice, the Shortcuts app, Spotlight, Control Center, the Action Button, Focus filters, and interactive widgets** at once. WWDC25 pushed it further (deeper Spotlight/visual-intelligence/Apple-Intelligence hooks). ([WWDC25: Get to know App Intents](https://developer.apple.com/videos/play/wwdc2025/244/), [GoodRequest](https://www.goodrequest.com/blog/app-intents-how-to-make-your-app-more-accessible-through-siri-spotlight-and-widgets)) **Interactive widgets** (iOS 17+) let users tick a task or log a habit *without opening the app*, driven by the same intents. A to-do app's expected minimum: an "Add Task" intent + a Today/list widget. Users actively file feedback demanding "iOS Shortcuts support, lockscreen widgets." ([ClickUp feedback](https://feedback.clickup.com/new-mobile-app/p/ios-shortcuts-support-lockscreen-widgets))

### 6. Filters / saved searches & calendar view (the "power user" tier)
- **TickTick** wins on filtering: Smart Lists with a *visual* builder (Normal) and a *logical* condition builder (Advanced) — custom views without a query language (paid). ([ClickUp](https://clickup.com/blog/ticktick-vs-todoist/))
- **Todoist** filters use a query syntax; free tier = 3 filters, paid = more. ([Todoist Features](https://www.todoist.com/features))
- **Calendar view**: TickTick has a full native one across all lists; Todoist's is paid + one project at a time; **Things has none**. Not essential for a calm app, but a recurring differentiator. ([ClickUp: TickTick vs Things3](https://clickup.com/blog/ticktick-vs-things3/))
- **Pricing anchors** (for the "is this paid?" question): Things ~one-time purchase per platform; Todoist ~$60/yr; TickTick ~$36/yr. ([rambox](https://rambox.app/blog/ticktick-vs-todoist/))

## Implications for Lists ← most important section

### What Lists already does well (keep)
- **Real Inbox** exists and is the default capture target (`ItemList.inboxId = "inbox"`; `ItemStore.defaultCaptureListId` falls back gracefully). The GTD spine's first node is in place.
- **Smart lists as live queries** (`Core/Queries/SmartList.swift`): Today (due today **or overdue** — good), Scheduled (future-dated, excludes habits), Flagged, Urgent, Completed, All. This is the right architecture and matches how the leaders think.
- **Inline `#tags` parsing on capture** already works (`Tag.extractInline` in `QuickCaptureSheet.add`) — the *seed* of NL capture is present; only dates/repeat are missing.
- **Priority / flag / early-reminder / urgent-trigger / sub-items / sections / nested lists** all modelled. Feature *breadth* is competitive.

### The three highest-leverage gaps (in priority order)

**GAP 1 — Recurring tasks are stored but non-functional. (Highest leverage; correctness bug, not just a feature.)**
`QuickCaptureSheet`/`ItemDetailSheet` compose a full RRULE and save it (`Recurrence(rrule:)`), and `Reminder.swift:74` even notes "recurrence expansion lives elsewhere (out of scope for M0)." But there is **no expansion anywhere** — `ItemStore.toggleDone` (lines 77–91) only flips `done`, sets `completedAt`, and cancels the notification. Completing "Pay rent · Monthly" makes it vanish; next month nothing returns. This silently breaks a promise the UI makes (the Repeat picker implies it works). **Fix:** on completing a task with `recurrence`, compute the next `due` from the RRULE and either roll the same item forward (Reminders-style) or spawn a fresh instance (Things-style). Offer Things' two modes: fixed schedule vs "N after completion." This is a contained, self-funding build — the capture UI and storage already exist; only the engine is missing. **Until it exists, consider hiding the Repeat row** so the app doesn't promise a no-op.

**GAP 2 — Natural-language date parsing on capture. (Biggest perceived-quality win.)**
Today capture is a multi-tap form (`QuickCaptureSheet`: Date toggle → graphical picker → Time wheel → Repeat menu → Early-reminder menu). The leaders let you *type* it. Lists already strips `#tags` from the title; extend that same pass to dates/times/repeat: `dinner with Sam tomorrow 7pm` → title "dinner with Sam", due tomorrow 19:00; `gym every weekday` → daily-weekday repeat. **Native, no third-party libs** (honours the founder's constraint): Apple's `NSDataDetector` catches many date/time phrases out of the box; recurring phrases ("every Monday", "every 2 weeks") map cleanly onto the RRULE presets Lists *already* defines (`RepeatPreset.rrule`). Keep it calm: parse silently, show the inferred date as a removable chip, never block typing. This is the feature users say they love most and it leans directly into the file-as-text identity. (Note: GAP 2 only pays off fully once GAP 1 makes recurrence real.)

**GAP 3 — System integration via App Intents (widgets + "Add Task" + Siri/Spotlight).**
Verified **absent**: zero `AppIntent`/`WidgetKit`/`Shortcut`/`Spotlight`/`NSUserActivity` references in the codebase; `project.yml` declares **one app target** (no widget/extension target). For a "fast, native, daily-driver" app this is the largest *expectation* gap. Sequence by cost:
- **Quick win:** an "Add to Inbox" / "Add Task" **App Intent** → instantly gives Siri, Shortcuts, Spotlight, *and* the Action Button, from one small Swift type. Highest reach-per-effort on Apple's modern stack.
- **Medium:** a **Today/Inbox widget** (read-only first, then **interactive** so a tap ticks a task without opening the app — perfect for the calm ethos).
- These are *additive* and isolated from the core editor work, so they don't risk regressions elsewhere.

### Secondary, lower-priority calls
- **Scheduling vs deadline (Things' "When" vs "Deadline").** Lists has one `due` + `dueAllDay`. Adding a separate deadline is a real model change (new field + new smart list + sync/tombstone implications) — **defer**, but it's the most credible "pro" differentiator after the big three, and it fits a calm app well. If added, mirror Things' independent start/deadline with distinct badges.
- **A "Someday/Later" bucket.** Cheap and very GTD-aligned: either a built-in `Someday` smart list (items with no due + a flag/tag) or a first-class `someday` state. Completes the Inbox→Today→Someday spine. Low effort, high methodology payoff.
- **Saved custom filters (TickTick-style).** Lists' smart lists are *hardcoded* enum cases. A user-defined saved query ("#work + flagged + due this week") is the natural next step and the architecture (live-query `matches`) already supports it. Medium build; do **after** the big three. Keep it calm — a simple builder, not a query language.
- **`Scheduled` smart list excludes overdue + excludes habits** by design; confirm that's intended (overdue future-dated tasks correctly fall into Today instead — that looks right).
- **Calendar view:** a known differentiator but *not* aligned with "calm/minimal." Safe to skip; revisit only if users ask.

### What to avoid
- Don't bolt on a query-language filter syntax or a heavy calendar — both fight the calm/native positioning. TickTick's *visual* builder is the model to copy if/when filters come.
- Don't ship more date/repeat UI before GAP 1 — adding pickers that still don't regenerate compounds the broken promise.
- Don't reach for a third-party NLP library; `NSDataDetector` + the existing RRULE presets cover the 80% case natively (matches the no-third-party-libs rule).

## Open questions / things to validate
- **Is recurrence regeneration genuinely unimplemented, or implemented somewhere I didn't grep?** I checked `ItemStore`, `SmartList`, models, and the two capture sheets; the only RRULE *consumers* are display/parse helpers in the sheets (`parseRecurrence`, `composeRRule`) — no scheduler advance, no occurrence spawning. Confidence high, but a reviewer should confirm there's no expansion in `NotificationScheduler` or a background job.
- **iOS 26.0 deployment target** means the *newest* App Intents/interactive-widget APIs are all available — a genuine upside for GAP 3 (no back-deployment compromises). Worth weighing against the audience-size concern flagged elsewhere (STRAT-1).
- **Single-user, no-account** means assignee/`Assigned` smart list is a placeholder today; fine to leave dormant until/if collaboration is ever scoped.
- Should NL parsing be **on by default or opt-in**? Recommend on, silent, reversible (chip you can tap to remove) — but validate with the founder given the "calm, no surprises" value.

## Sources
- [Things — Using Natural Language Input](https://culturedcode.com/things/support/articles/9780167/)
- [Things — Scheduling To-Dos (When vs Deadline; Today/Upcoming/Anytime/Someday)](https://culturedcode.com/things/support/articles/2803579/)
- [Things — Creating Repeating To-Dos](https://culturedcode.com/things/support/articles/2803564/)
- [Things 3.1 — Repeating To-Dos & Date Parsing (blog)](https://culturedcode.com/things/blog/2017/07/things-3-1-repeating-to-dos-date-parsing/)
- [Todoist — Features](https://www.todoist.com/features)
- [Todoist — Introduction to recurring dates](https://www.todoist.com/help/articles/introduction-to-recurring-dates-YUYVJJAV)
- [Todoist — Getting Things Done (GTD) with Todoist](https://www.todoist.com/help/articles/getting-things-done-gtd-with-todoist-e5j2h3)
- [Todoist — Getting Things Done method overview](https://www.todoist.com/productivity-methods/getting-things-done)
- [The Sweet Setup — Using Natural Language with Todoist](https://thesweetsetup.com/using-natural-language-with-todoist/)
- [Motion — Todoist vs Apple Reminders (NL + recurrence complaints)](https://www.usemotion.com/blog/todoist-vs-apple-reminders)
- [Akiflow — Apple Reminders vs Todoist](https://akiflow.com/blog/apple-reminders-vs-todoist)
- [ClickUp — TickTick vs Todoist (filters, calendar, NL)](https://clickup.com/blog/ticktick-vs-todoist/)
- [ClickUp — TickTick vs Things 3 (calendar view)](https://clickup.com/blog/ticktick-vs-things3/)
- [Rambox — TickTick vs Todoist 2026 (pricing)](https://rambox.app/blog/ticktick-vs-todoist/)
- [Apple Developer — WWDC25: Get to know App Intents](https://developer.apple.com/videos/play/wwdc2025/244/)
- [GoodRequest — App Intents across Siri, Spotlight, Widgets](https://www.goodrequest.com/blog/app-intents-how-to-make-your-app-more-accessible-through-siri-spotlight-and-widgets)
- [ClickUp feedback — iOS Shortcuts support, lockscreen widgets](https://feedback.clickup.com/new-mobile-app/p/ios-shortcuts-support-lockscreen-widgets)
