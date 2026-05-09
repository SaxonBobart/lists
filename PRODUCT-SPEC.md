# Lists — Product Specification v2

> **Status**: Working spec, captured from full design conversation.
> **Last updated**: 8 May 2026
> **Supersedes**: v1 (2026-05-08)
>
> **How to use this document**:
> Paste at the top of any Claude or Claude Code session for project work. Keep as `PRODUCT-SPEC.md` in the repo root. Reference from `AGENTS.md` / `CLAUDE.md`. Use it to evaluate new features ("does this fit the spec?"). Update deliberately with changelog entries at the bottom.

---

## 0. Identity

### 0.1 Name

The product is called **Lists**. The repo and project files may be tagged `OpenReminders` for SEO / discovery, but the public-facing name is Lists.

### 0.2 One-sentence pitch

Lists is a beautiful, local-first markdown app with rich reminders, habits, and notes — your data lives in plain files you own, with optional paid sync that makes everything feel alive across devices.

### 0.3 Three-word identity

**Calm. Honest. Yours.**

### 0.4 Elevator pitch

Lists treats reminders, habits, and notes as one thing — items in markdown files with YAML frontmatter on disk. You can edit them in any text editor, sync them with Lists Sync (paid), point them at a Syncthing folder, or just use them on one device forever. It looks beautiful, runs natively on iOS, macOS, Android, Windows, and Linux, and never holds your data hostage. Agents you connect to it (Claude Code, opencode, Codex) appear as another collaborator alongside you.

### 0.5 What Lists is not

- Not a notes app (notes are an item type, not the primary mode).
- Not a project manager (no Gantt charts, dependencies, or resource allocation).
- Not a team collaboration tool in v1 (single-user multi-device first).
- Not a habit tracker (habits are an item type, not the primary mode).
- Not an LLM chat interface (agent integration is presence and queueing, not chat).
- Not a sync service (sync is the paid product; the app is a markdown reminders app).

### 0.6 Inspirations

- Apple Reminders for visual restraint and information density.
- Things 3 for polish and animation craft.
- Bear and Drafts for markdown editing.
- Obsidian for "your data is yours, in plain files" ethos.
- iA Writer for the principle that calm software earns trust.
- Apple Reminders' grocery auto-categorization specifically (worth replicating).

### 0.7 The "why does this exist" answer

Apple Reminders is beautiful but proprietary, Apple-only, and conflates dates with notifications. Todoist and TickTick are powerful but not local-first, not open-source, and treat your data as theirs. Obsidian is great for notes but isn't a reminders app. Nothing combines beautiful native UI on every platform with markdown-files-as-truth and decoupled date/reminder semantics. Lists fills that gap.

### 0.8 License

**AGPL-3.0-or-later.** Both the client app and the sync server are AGPL. Self-hostable sync is a deliberate release valve for users who don't want to pay or trust a hosted service.

---

## 1. Audience and use cases

### 1.1 Primary persona

A technically-curious individual aged 18–45 who values privacy, dislikes lock-in, and wants their data on their own terms. Uses multiple devices across at least two operating systems (e.g., iPhone + Linux laptop, or iPad + Windows desktop). Has tried Apple Reminders and found it too closed, and tried Obsidian or Logseq and found them too note-focused. Wants a beautiful, fast, native app that respects their intelligence and their data.

### 1.2 Secondary personas

- **Power users who self-host:** want self-hostable sync, file access, scriptability.
- **Obsidian users:** want a reminders app that doesn't fight their existing markdown vaults.
- **Apple ecosystem users tired of iCloud sync flakiness:** want something better that still feels native on iOS.
- **Developers using Claude Code or similar agents:** want a calm queue/dashboard for their AI-driven work.

### 1.3 Anti-persona

Teams of 3+ people doing structured project management with task assignment, dependency graphs, and resource planning. They should use Linear, Asana, or ClickUp.

### 1.4 Accessibility commitment

WCAG AA compliance from launch. Full VoiceOver / TalkBack / NVDA support. Dynamic type / system text scaling. High contrast modes. Reduce-motion compliance. Keyboard navigation on every desktop platform.

---

## 2. Core mental model

### 2.1 The single primitive: item

Every piece of content in Lists is an **item**. Items have a `type` field that determines behavior:

- **`task`** — has a checkbox. Can be completed.
- **`habit`** — recurring nudge with goal-per-cycle tracking. Cannot have sub-items.
- **`note`** — same item shape with the checkbox stripped. Pure markdown content with frontmatter.

Items share all other capabilities: title, markdown body, frontmatter, tags, dates, reminders, sub-items (where allowed), location, priority, flagging, and any future fields.

A list can mix all three types. A "Project Apollo" list might contain tasks ("file paperwork"), habits ("daily standup check-in"), and notes ("meeting transcript from May 3") sitting side by side.

### 2.2 Decoupling: dates and reminders are independent

The Apple Reminders mistake — setting a date forces a notification — is fixed.

A task can have:
- A date and a reminder (Apple-default behavior).
- A date with no reminder (visible in date-based views, no notification).
- A reminder with no date (rare but possible — a generic reminder without temporal context).
- Neither (a task you'll get to eventually).

UI: standard date+time picker. The "remind me" toggle defaults on but is one tap to disable. A bell-with-strikethrough icon visually marks dated-but-silent tasks.

### 2.3 Sub-items, not subtasks

Sub-items are first-class items nested inside other items. They have all the same capabilities as parents — frontmatter, type, markdown body, tags, dates, reminders, their own sub-items.

**Rules:**
- Tasks and notes can have sub-items.
- Habits cannot have sub-items (a habit is a recurring counter, not a container).
- Sub-items appear in views (Today, Scheduled, etc.) independently of their parent's state.
- Sub-item depth in **thread view** is capped at H3 (parent → child → grandchild). Deeper trees require tapping into a grandchild to view its tree.

A sub-item is a separate file on disk with a `parent:` UUID reference in its frontmatter. They are not markdown checkboxes embedded in the body.

### 2.4 Thread view

Any item with sub-items has a thread-view toggle. Thread view flattens the tree into one continuous editable document:

- Parent's title (H1) and body, then
- Sub-item 1's title (H2), body, then sub-item 1's children (H3), then
- Sub-item 2's title (H2), body, then sub-item 2's children (H3), etc.

New sub-items can be added inline by hitting enter at the end of a section.

Thread view is read-write. Changes propagate to the underlying files. The visual hierarchy uses H1/H2/H3 styling (large, medium, small headings) to distinguish levels.

### 2.5 Completion semantics

**Parent and children are fully independent.** Completing a parent does not cascade to children. Completing all children does not auto-complete the parent. Each item has its own checkbox state.

Parent items show a **subtree progress badge**: "3/5 done" or similar. Possible states:

- ☐ with 0/5 — fully undone
- ☐ with 5/5 — children done, parent itself not yet ticked
- ✓ with 3/5 — parent ticked, children mixed
- ✓ with 5/5 — fully done

**Visibility rule when "show completed" is off:** an item is hidden only when its own checkbox is ticked **and** its subtree is fully done (or empty). A ticked parent with incomplete children stays visible — there's still loose ends.

This rule applies identically across Today, Scheduled, smart lists, search results, tag overview, and any other view. One rule everywhere.

### 2.6 Lists, sub-lists, and views

#### 2.6.1 Lists are containers

Lists hold items. Lists can nest inside other lists for organization (semi-file-tree). **Opening a parent list shows its sub-lists as folders, not their items rolled up.** Click into a sub-list to see its contents.

A list has its own metadata: name, icon, color, default item type (e.g., a habit list creates habits by default when "+" is tapped), and a grocery-mode flag.

#### 2.6.2 Sections

Sections are user-defined groupings within a list. A section is a labeled divider. Items in a list can belong to a section.

**Sections behavior:**
- A normal user list lets the user create, rename, reorder, and delete sections freely.
- A grocery-mode list auto-creates sections by item category (Produce, Dairy, Bakery, Meat & Seafood, Pantry, Frozen, Beverages, Other). Auto-categorization happens on item creation; user can manually move items between sections.
- AI-section lists (under the AI tab) auto-create sections by agent status: Working, Questions, Scheduled, Done.

Items can belong to one section or no section ("Uncategorized" / shown above the first section header).

#### 2.6.3 Column view

Any list can be toggled between **vertical** layout (sections as headers, items below each header) and **column** layout (sections as kanban columns, items as cards within each column).

This is a per-list preference. The user picks per list, the choice persists. Column view is most useful for kanban-style flows (To Do / Doing / Done, or per-area columns).

### 2.7 Tags

Flat strings, applied to items. Cross-cutting — a tag can be on items in any list. There is a **Tags overview** view in the sidebar showing all items with a given tag, grouped by tag.

**Rules:**
- Lowercase. (Stored normalized; user-entered case is converted on save.)
- No spaces. Hyphens (`work-projecta`) and underscores (`work_projecta`) allowed.
- No hierarchical tags. Power users can fake hierarchy with naming conventions.

Inline tag editor: tags can be added by typing `#tag` in the title or via a tag chip at the bottom of the new-item editor.

### 2.8 Smart lists

Smart lists are saved filter views over items. They share the data model with regular items — same files, different lens.

**Built-in smart lists (always present):**

| Smart list | Filter |
|---|---|
| Today | Items with a date of today, plus all overdue items. |
| Scheduled | Items with a future date, sorted by date. Has calendar view toggle. |
| All | All items, all lists. Sorted by recently modified. |
| Completed | Items with `done: true`, sorted by completion timestamp. |
| Flagged | Items with `flagged: true`. |
| Urgent | Items with the urgent trigger active. |

**System lists:**

- Tags overview — all items grouped by tag.
- Recently Deleted — soft-deleted items, auto-purged after 30 days.

**User-created smart lists:** deferred to v2. v1 ships only the built-in set.

#### 2.8.1 Calendar view (Scheduled only)

The Scheduled smart list has a unique calendar view toggle. Three sub-views:

- **Month** — calendar grid, items shown as small chips on each day.
- **Week** — vertical week with items per day.
- **Day** — single day with items by time.

Drag items between days to reschedule. No other smart list has a calendar view.

#### 2.8.2 Today view sort

Today is sorted by time of day (morning items at top), with all-day items at the top of the day. Overdue items appear above today's items, in a collapsible "Overdue" section at the top.

#### 2.8.3 Pinned items

In the default sidebar/home view, the user can pin specific lists or smart lists to a "Pinned" section at the top. The remaining lists appear below in a "Lists" section. Smart lists by default appear in the pinned area at the top.

---

## 3. Item types in detail

### 3.1 Task

A task has a checkbox and represents a unit of work to be completed.

**Fields:**

- `id: <uuid>` — stable identity.
- `type: task`.
- `title: string`.
- `body: <markdown>` — the file body below frontmatter.
- `tags: [string]` — flat normalized strings.
- `list: <list_id>` — which list it belongs to.
- `section: string | null` — optional section name within the list.
- `parent: <uuid> | null` — optional parent item if this is a sub-item.
- `created_at: <iso8601>`.
- `modified_at: <iso8601>`.
- `created_by: human | agent_<name>` — for MCP integration.
- `done: boolean` — completion state.
- `completed_at: <iso8601> | null`.
- `due: <iso8601> | null` — date and optional time. Includes timezone.
- `due_all_day: boolean` — true if the date should be treated as all-day.
- `reminder: <reminder_block> | null` — see section 4.1.
- `triggers: <triggers_block> | null` — see section 4.
- `priority: none | low | medium | high`.
- `flagged: boolean`.
- `recurrence: <recurrence_block> | null` — see section 4.3.

### 3.2 Habit

A habit is a recurring counter with a goal per cycle.

**Type-specific fields (in addition to common fields):**

- `frequency: hourly | daily | weekdays | weekends | weekly | fortnightly | monthly | every_three_months | every_six_months | yearly | custom`.
- `frequency_custom: <recurrence_block> | null` — used when `frequency: custom`.
- `goal_per_cycle: integer` — minimum 1, default 1.
- `completion_log: { <cycle_key>: <count> }` — see section 3.2.1.
- `show_streak: boolean` — default true. User can disable per habit.
- `reminder: <reminder_block> | null` — habits can have reminders just like tasks.

**Constraints:**

- Habits cannot have sub-items (`parent` references to a habit are invalid).
- A habit's `done` field is computed: true if `completion_log` for the current cycle ≥ `goal_per_cycle`. Not stored separately.
- Counter cannot exceed `goal_per_cycle`. Tap "+1" past goal is silently ignored with subtle visual feedback (a bounce).

#### 3.2.1 Completion log format

Keys are cycle identifiers, format depends on frequency:

| Frequency | Cycle key example |
|---|---|
| hourly | `2026-05-08T14:00` |
| daily | `2026-05-08` |
| weekdays / weekends | `2026-05-08` (the specific weekday/weekend day) |
| weekly | `2026-W19` (ISO week) |
| fortnightly | `2026-W19` (every other ISO week from a configured start) |
| monthly | `2026-05` |
| every_three_months | `2026-Q2` |
| every_six_months | `2026-H1` |
| yearly | `2026` |

Stored entirely in the habit's frontmatter. Long-term storage (e.g., a daily habit running 5 years has ~1,825 entries) is acceptable — files stay in the tens of KB range.

#### 3.2.2 Heatmap visualization

Default view: one year of cells.

Three states per cell:
- **Blank** — no log entry, or count = 0 (missed).
- **Partial shade** — `0 < count < goal_per_cycle`.
- **Full shade** — `count == goal_per_cycle` (complete).

Counts cannot exceed goal, so there is no "exceeded" state.

Heatmap window for non-daily frequencies:
- Daily: 365 cells (one year).
- Weekly / fortnightly: 52 cells (one year).
- Monthly: 36 cells (three years, since 12 looks too sparse).
- Yearly: 5 cells (five years).

#### 3.2.3 Streaks

Streaks count consecutive cycles where `count == goal_per_cycle`. Partial completions break streaks (do not count as "complete").

Each habit has a `show_streak: boolean` field, default true. When disabled:
- No streak counter is shown anywhere in the UI for that habit.
- Heatmap still works.
- Completion log still works.
- Edit history still works.

Per-habit toggle is editable any time. A user creating a sensitive habit can disable streaks at creation; existing habits can be toggled later.

#### 3.2.4 Editing history

Each habit has a dedicated **Edit History** view, accessible from the habit's detail view. It shows a list of cycles (most recent first) with the count for each. The user can edit any cycle's count directly.

History edits do not have a heatmap-cell-tap shortcut — too inconsistent across platforms. The dedicated edit view is the only way to backfill or correct.

#### 3.2.5 Habit reminders

Habits use the same reminder block as tasks. Reminders are nudges, not stacking notifications:

- A habit can have a reminder time per cycle (e.g., "remind me at 9am every day").
- If a cycle's reminder time passes and the user hasn't logged completion, **one** notification fires.
- Subsequent missed cycles do not stack notifications. The user might see "you missed 3 days of meditation" as a single soft summary on the next cycle, not three separate alerts.

### 3.3 Note

A note is an item with the checkbox stripped. Pure markdown content with frontmatter.

**Type-specific behavior:**
- No `done` field. (Or `done` is ignored if present.)
- No completion semantics.
- Can have sub-items (notes can be parents of tasks, habits, or other notes).
- Can have all standard frontmatter fields except those that don't apply (`completed_at`, `recurrence` — recurrence on a note has no meaning).

Notes are useful as reference material alongside tasks ("here's the spec, here are the tasks to implement it"), as scratchpads, or as the children of meeting-summary parents in thread view.

---

## 4. Reminders, triggers, and recurrence

### 4.1 Reminder block

The reminder block is shared by tasks and habits.

```yaml
reminder:
  enabled: true
  early: <early_value>  # see 4.1.1
```

When `enabled: true`:
- A standard system notification fires at the item's `due` time.
- If `early` is set, an additional earlier notification fires at the offset before due time.

When `enabled: false` or `reminder` is absent: no notification. The item still appears in date-based views (Today, Scheduled) — it's just silent.

### 4.1.1 Early reminder values

A preset list with a custom builder:

- **None** — no early reminder.
- **5 minutes before**
- **15 minutes before**
- **30 minutes before**
- **1 hour before**
- **2 hours before**
- **1 day before**
- **2 days before**
- **1 week before**
- **1 month before**
- **Custom** — user picks a value (1, 2, 3...) and a unit (Minute, Hour, Day, Week, Month).

Frontmatter representation:

```yaml
early:
  value: 1
  unit: day
```

Or for presets, a string shorthand may be used (`early: "30m"`, `early: "1d"`) — TBD which is canonical for the schema. Both should be parseable by readers.

### 4.2 Triggers

A unified concept covering urgent alarms and location-based notifications. Both share the same architectural pattern: **the data is universal, the firing is device-restricted.**

```yaml
triggers:
  urgent:
    enabled: true
  location:
    enabled: true
    place_name: "Coles Toowoomba"
    coordinates: { lat: -27.563, lng: 151.954 }
    radius: 200  # metres
    on: arrival  # or 'departure'
```

Per-item, the file just declares which triggers are active. **Which devices fire them is a global setting**, not stored per-item.

#### 4.2.1 Urgent alarm

When `triggers.urgent.enabled: true` and the item's reminder fires, the notification escalates to a system-level alarm:

- **iOS/iPadOS 26+:** AlarmKit. Bypasses Focus mode and silent mode. Full-screen alarm presentation. Lock Screen and Dynamic Island integration. Watch propagation. Requires `NSAlarmKitUsageDescription` in Info.plist and explicit user permission.
- **iOS 25 and below:** Critical Alerts entitlement (if Apple grants) or fallback to Time Sensitive notifications. Less reliable.
- **macOS 26+:** AlarmKit available; fires as a prominent alert with sound.
- **watchOS 26+:** AlarmKit propagates from iOS or fires natively.
- **Android:** `USE_FULL_SCREEN_INTENT` permission + full-screen intent + custom alarm sound via MediaPlayer. Bypasses Do Not Disturb when properly configured.
- **Windows:** Critical Toast Notifications via WinAppSDK with `ToastScenario.Alarm`. Bypasses Focus Assist.
- **Linux:** Best-effort. Desktop notifications with `urgency=critical` (libnotify) plus directly playing an alarm sound. No reliable DND-bypass guarantee across desktop environments. Documented as best-effort.

**Caveat with AlarmKit:** when the user dismisses an urgent alarm, the app does not know. The reminder's `done` state does not change. Marking the underlying task complete is a separate user action. (This matches Apple Clock's behavior — dismissing the alarm just stops the noise.)

#### 4.2.2 Location triggers

When `triggers.location.enabled: true` and the user's selected device(s) detect arrival or departure at the configured coordinates within the radius, a notification fires.

**Platform support:**

| Platform | Background geofencing | Verdict |
|---|---|---|
| iOS | CoreLocation region monitoring. Up to 20 active geofences per app. | Works. |
| Android | Geofencing API. No hard limit. | Works. |
| macOS | CoreLocation works while app is foreground. Background unreliable. | Best-effort, limited. |
| Windows | Possible via Windows.Devices.Geolocation, awkward in practice. | Documented as not supported. |
| Linux | No standard background geofencing. GeoClue is foreground-only. | Documented as not supported. |

**Authoring is universal.** A user on any platform can create or edit a location-triggered reminder, with a full map picker (MapKit on Apple, Mapbox/MapTiler on Android via AndroidView, OpenStreetMap with Leaflet via WebView on Windows/Linux). Setting the location, radius, and arrival/departure trigger all work on every platform.

**Firing is iOS/Android only.** Other platforms display the location metadata on the item but do not fire the trigger. UI shows a small indicator: "Location trigger fires on iOS / Android."

#### 4.2.3 Trigger-capable devices setting

In Settings → Triggers:

- **Urgent Alarm Device** — pick exactly one device. Only that device fires urgent alarms. Default: the user's primary mobile device.
- **Location Reminder Devices** — pick one or more eligible devices (iOS, Android only). Default: all eligible mobile devices.

**With Lists Sync (paid):** the device list is populated from the user's account. Devices auto-appear when they sign in. Picker is reliable.

**With self-managed sync:** each device writes a small `_devices/<device-id>.yaml` file into the data folder on first run, declaring its name, OS, and capabilities. Other devices read these files to know what devices exist. Picker works but is best-effort — stale device entries are possible, and timing depends on sync propagation. Documented limitation.

**With no sync (single device):** the picker is hidden / N/A. The single device fires whatever triggers it can.

#### 4.2.4 Trigger indicator on the new-item sheet

When a trigger is enabled, a subtle info line appears below the toggle:

- Urgent: "Alarm on: Saxon's iPhone 17 Pro Max" (only shown when sync is active and a device is selected; otherwise hidden).
- Location: "Trigger fires on iOS and Android" (always shown when location is enabled, since it's a fundamental platform fact).

### 4.3 Recurrence

Tasks support recurrence. Habits have their own frequency model (section 3.2). Notes don't recur.

**Top-level recurrence options:**

- **Never** (default — task does not recur).
- **Hourly**
- **Daily**
- **Weekdays** (Mon–Fri)
- **Weekends** (Sat–Sun)
- **Weekly** (default: same weekday as `due`).
- **Fortnightly** (every 14 days).
- **Monthly** (same date each month).
- **Every Three Months**
- **Every Six Months**
- **Yearly**
- **Custom** — opens a builder.

**Custom builder:**
- Frequency: Hourly / Daily / Weekly / Monthly / Yearly.
- Every N units (numeric input).
- Optionally for Weekly: which days of the week.
- Optionally for Monthly: by date or by weekday position (e.g., second Tuesday).

**End repeat:**
- Never (continues forever).
- On Date (recurrence ends after specified date).

Frontmatter:

```yaml
recurrence:
  pattern: weekly  # or hourly|daily|weekdays|weekends|fortnightly|monthly|every_three_months|every_six_months|yearly|custom
  custom:
    frequency: weekly
    every: 2
    by_day: [MO, WE, FR]
  end:
    type: never  # or 'on_date'
    date: <iso8601>  # only when type: on_date
```

**Behavior:** on-schedule by default. The next instance is generated based on the original `due` time, regardless of when (or if) the previous instance was completed. After-completion recurrence ("every 3 days after I complete this") is not supported in v1; revisit in v2 if users ask.

When a recurring task is completed, the next instance is generated automatically. The completed instance is marked done with its `completed_at` timestamp; the new instance gets a new UUID and the next scheduled `due` time.

---

## 5. File format and data layer

### 5.1 Storage architecture

- **Markdown files with YAML frontmatter** are the source of truth.
- **One file per item.** Sub-items are separate files referencing parent UUID.
- **A SQLite index** (`.lists/index.db` in the data folder) handles search, smart list queries, and view performance.
- **The index is derived.** It can be deleted at any time and rebuilt from files. Nothing in the index is canonical.

### 5.2 Folder structure

```
~/Lists/                           # data root, user-pickable on first launch
├── Lists/                          # all user lists live here
│   ├── tasks-default-a3f7/        # the default "Tasks" list
│   │   ├── _list.yaml             # list metadata (name, icon, default type, sections)
│   │   ├── buy-milk-9b2c.md       # individual items
│   │   ├── call-mum-4d8e.md
│   │   └── ...
│   ├── work-7e1a/
│   │   ├── _list.yaml
│   │   ├── project-apollo-5c3d/   # nested sub-list
│   │   │   ├── _list.yaml
│   │   │   ├── ...
│   │   └── ...
│   └── ...
├── Habits/                         # habit-type lists could live here, or in Lists/ — TBD
├── _AI/                            # AI section — only present if user connects agents
│   ├── claude-code/
│   │   ├── lists-ios/             # auto-created per project
│   │   │   ├── _list.yaml
│   │   │   ├── _status.yaml       # live presence / last-active
│   │   │   └── ...
│   │   └── ...
│   ├── opencode/
│   │   └── ...
│   └── ...
├── Attachments/                    # all attachments referenced from items
│   ├── <uuid>.jpg
│   ├── <uuid>.pdf
│   └── ...
├── _devices/                       # one file per device, for self-managed sync only
│   ├── <device-id>.yaml
│   └── ...
├── _trash/                         # soft-deleted items, auto-purged after 30 days
│   └── ...
└── .lists/                         # hidden, per-device
    ├── index.db                    # SQLite index
    ├── prefs.yaml                  # local UI preferences
    └── search.db                   # FTS index
```

User-visible: everything except `.lists/`. The user can browse the data folder in Finder, Files, Explorer, or any file manager and see their data clearly.

### 5.3 Filename format

**Hybrid format**: `<slug>-<short_id>.md`

- `<slug>` — derived from the item's title, lowercased, spaces to hyphens, special characters stripped, capped at ~50 characters.
- `<short_id>` — first 4 characters of the full UUID, hex-encoded.
- `.md` extension.

Examples:
- `buy-milk-a3f7.md`
- `call-mum-9b2c.md`
- `2026-q2-okrs-7e1a.md`

The frontmatter UUID (`id:`) is the stable identity. The filename is cosmetic. When a title changes, the filename **may** be updated to reflect the new slug, but doesn't have to be. References across files always use the UUID, never the filename.

Lists (folders) use the same convention: `<slug>-<short_id>/`.

### 5.4 Frontmatter — universal fields

Every item has these fields regardless of type:

```yaml
---
id: a3f7b2c1-4d1e-4f8a-9c2b-1e8f4a3c2b9d
schema_version: 1
type: task  # or habit, or note
title: Buy milk
created_at: 2026-05-08T14:23:00+10:00
modified_at: 2026-05-08T14:23:00+10:00
created_by: human  # or agent_<name>
list: tasks-default-a3f7
section: null  # or section name
parent: null  # or parent UUID for sub-items
tags: [groceries, today]
flagged: false
priority: none  # or low | medium | high
---
```

### 5.5 Frontmatter — type-specific fields

#### 5.5.1 Task

```yaml
done: false
completed_at: null
due: 2026-05-08T17:00:00+10:00
due_all_day: false
reminder:
  enabled: true
  early:
    value: 15
    unit: minute
triggers:
  urgent: { enabled: false }
  location: null
recurrence: null
```

#### 5.5.2 Habit

```yaml
frequency: daily
frequency_custom: null
goal_per_cycle: 8
completion_log:
  2026-05-08: 6
  2026-05-07: 8
  2026-05-06: 0
  2026-05-05: 4
show_streak: true
reminder:
  enabled: true
  early: null
```

#### 5.5.3 Note

Notes have only the universal fields — no type-specific additions.

### 5.6 List frontmatter (`_list.yaml`)

```yaml
id: tasks-default-a3f7
name: Tasks
icon: list-bullet  # SF Symbol or named icon
color: blue
default_type: task  # what "+" creates by default — task, habit, or note
grocery_mode: false
sections:
  - name: This Week
    order: 0
  - name: Backlog
    order: 1
view:
  layout: vertical  # or 'column'
  sort: manual  # or by_due, alphabetical, by_created, by_priority
created_at: 2026-05-08T14:23:00+10:00
modified_at: 2026-05-08T14:23:00+10:00
agent: null  # or { type: 'claude-code', project_path: '/repos/lists-ios' } for AI lists
```

### 5.7 ISO 8601 dates with timezone

All datetime values use ISO 8601 with explicit timezone offset. Example: `2026-05-08T17:00:00+10:00`.

The default timezone for new items is the device's current timezone at first launch, settable in Settings. Each item can override its timezone independently.

This is critical for cross-timezone agents and multi-region sync — agents reading files from any timezone must interpret dates unambiguously.

### 5.8 Markdown body

The file body, below the closing `---` of frontmatter, is the item's markdown content.

**Supported markdown:**
- CommonMark (full spec).
- GitHub Flavored Markdown extensions (tables, strikethrough, task lists, autolinks, fenced code blocks).
- Inline `#tag` parsing (the app extracts these to the `tags:` frontmatter on save).
- Image embeds via `![alt](Attachments/<uuid>.<ext>)` syntax.

**Not supported in v1:**
- Wikilinks (`[[Other Note]]` style). Defer to v2.
- Mermaid diagrams. Defer.
- Footnotes. Defer.
- Math (LaTeX). Defer.

**Body length:** no hard cap. Soft warning at ~100KB in the editor: "This note is getting large; consider splitting into sub-items." Editor performance degrades meaningfully past ~1MB on mobile; document this practical limit.

### 5.9 Attachments

Attachments are stored as separate files in the `Attachments/` folder. Referenced from items via relative path:

```markdown
![Whiteboard photo](../Attachments/a3f7b2c1.jpg)
```

**v1 supported types:**
- Images: jpg, png, heic, webp.
- PDFs.

**v1 stretch:**
- Audio recordings (m4a, mp3, ogg).

**v2:**
- Arbitrary file types, with platform-appropriate previews.

Attachments use UUIDs as filenames to prevent collisions. The original filename is preserved in the markdown alt text or as a frontmatter annotation.

### 5.10 Round-trip safety

Files edited externally (vim, Notepad, Obsidian, any markdown editor) are picked up by the app via filesystem watching.

**External editors must not change:**
- The `id:` field. It's the stable identity.
- The `schema_version:` field.
- The `created_at:` field.

**External editors may change:**
- Title, body, tags, dates, reminder settings, priority, flag, all other frontmatter fields.

The app validates frontmatter on read. Invalid or missing required fields trigger a non-destructive flag in the UI ("This file may have been edited externally with errors") and the user can repair manually.

### 5.11 Index rebuild

The SQLite index (`.lists/index.db`) can be deleted at any time. On next app launch, it rebuilds from the source files. Rebuild time scales with item count: ~1,000 items rebuilds in <1s; 10,000 items in <5s on modest hardware.

A user-facing "Rebuild Index" button lives in Settings → Advanced for diagnostic purposes.

### 5.12 What lives only in the index, never in files

- Search FTS data.
- View preferences (per-list sort, per-list layout — these mirror to `_list.yaml` for sync, but the active rendering uses the index for speed).
- Sync state (last-synced timestamps, conflict markers) — for paid sync only.
- UI preferences (dark mode, theme accent, sidebar width).

These do not need to be in files because they're either derivable or device-local.

---

## 6. Sync

### 6.1 The single paid product: Lists Sync

Lists Sync is a hosted sync service. Available on every platform with identical behavior. Paid subscription required for multi-device use beyond the free tier.

**Pricing:** TBD. Reference points: Obsidian Sync ($5/mo), iA Writer subscriptions, Bear Pro ($30/yr), Things one-time. Aim for sustainable solo-business pricing — not loss-leader, not premium.

**End-to-end encryption:** all sync traffic is E2E encrypted. The server relays encrypted blobs and never reads content. Encryption keys are derived from the user's password (or a passphrase / recovery code). Key recovery is the user's responsibility — no server-side recovery.

**Self-hostable:** the sync server software is open-source under AGPL. Anyone can run their own instance and point Lists clients at it. Documentation, Docker images, and a one-line install script are provided.

### 6.2 Free local use, forever

A single device with Lists installed is fully functional and free, forever. No feature paywalls. No nag screens. No degraded experience. Use it as a single-device markdown reminders app and pay nothing.

### 6.3 Sync modes

#### 6.3.1 Lists Sync (paid)

User signs in. All devices on the account auto-discover each other. Real-time propagation (target: <5 seconds for small files). Live presence indicators. Trigger-device picker is reliable.

#### 6.3.2 Self-managed sync (advanced, opt-in per platform)

User points Lists at a folder synced by Syncthing, iCloud Drive, Dropbox, OneDrive, or any other file-sync provider.

**Per-platform support:**

- **macOS, Windows, Linux:** officially supported. User picks any path. Documented as working.
- **iOS:** advanced opt-in via the document picker. Marked best-effort. Sync timing and conflicts may be unreliable due to platform background limits.
- **Android:** advanced opt-in via the system file picker. Marked best-effort.

Self-managed sync gets you propagation but not the live presence features. Trigger-device pickers work but are best-effort.

#### 6.3.3 No sync (single device)

The default for new installs. Data lives in `~/Lists/` (or platform equivalent). No network activity beyond app updates.

### 6.4 Conflict resolution

When two devices edit the same item offline and the changes conflict:

- **Lists Sync**: a CRDT-based merge attempts automatic resolution where possible. When the merge can't be done cleanly, both versions are preserved as separate files (`buy-milk-a3f7.md` and `buy-milk-a3f7 (conflict 2026-05-08).md`) and surfaced in a "Conflicts" smart list. User picks which to keep.
- **Self-managed sync**: relies on the underlying sync provider's behavior. Most file-sync providers create conflict files (Dropbox, OneDrive) or last-write-wins (iCloud). Lists detects conflict files by name pattern and surfaces them.

### 6.5 Live presence

A signature feature of Lists Sync. Sub-5-second propagation for small `_status` files allows multi-device collaboration to feel alive.

**Status data per device:**

```yaml
device_id: macbook-saxon-a3f7
device_name: Saxon's MacBook Pro
last_seen: 2026-05-08T14:23:01+10:00
active_item: <uuid>  # the item currently being edited
typing: true
```

UI cues:
- Pulsing dot next to active devices in the sidebar.
- Subtle shimmer on items currently being edited by another device.
- New items animate in with a brief highlight.

**Live presence is Lists Sync only.** Self-managed sync providers can't propagate small files fast enough to support real-time presence.

### 6.6 Agent presence

Agent activity uses the same presence mechanism. The Claude Code hook script writes a `_status.yaml` into its project list folder. The app shows it as "working / idle / question pending" in the AI section.

### 6.7 No iCloud

Lists does not use iCloud Drive (file sync) or CloudKit (structured sync API). The reasoning:
- iCloud Drive is unreliable cross-platform.
- CloudKit is Apple-only, contradicting the cross-platform parity commitment.

A user can point self-managed sync at an iCloud Drive folder if they want, accepting the limitations. But Lists itself doesn't integrate with Apple's sync infrastructure.

### 6.8 Server-side processing

The sync server is **dumb**. It relays encrypted blobs. It does not read content, does not process, does not index, does not generate notifications.

This preserves end-to-end encryption and the "your data is yours" promise. Any future feature requiring server-side processing is a deliberate architecture decision made later, not by accident.

---

## 7. AI / agent integration (v2.0)

### 7.1 Two top-level sections in the app

The sidebar / home view has two top-level areas:

1. **Lists** — your normal reminders, habits, notes. Most users live here.
2. **AI** — separate area, populated only when the user connects an agent.

The AI area has two sub-sections:

- **AI Assistants** — conversational agents like opencode, Hermes. One list per connected assistant.
- **Agentic Coding** — project-scoped coding agents like Claude Code, Codex, Cursor. One list per project, auto-created.

For users who never connect an agent, the AI section is empty and unobtrusive (or hidden, configurable in Settings).

### 7.2 Files are the protocol

Agents don't talk to Lists via custom API. They write files into the user's data folder using the same file format as everything else.

Each agent (or each project for project-scoped agents) gets a folder under `_AI/<agent_name>/` (or `_AI/<agent_name>/<project_name>/` for projects). The agent writes:

- **Currently running work** → an item with a status field set to `working`.
- **Status updates and outputs** → sub-items.
- **Questions blocking on user input** → sub-items with `triggers.urgent: true` so the user is notified, plus a `blocking: true` flag in the item.
- **Completed work** → ticked items.
- **Scheduled work** (where the agent supports scheduling) → items with future `due` dates.

### 7.3 Per-agent integration scripts

The user installs a small per-agent script once. The script uses the agent's existing hook system to write to the Lists data folder.

| Agent | Hook system used |
|---|---|
| Claude Code | PreToolUse, PostToolUse, SessionStart, SessionEnd, Notification, Stop hooks. |
| Codex | SessionStart, AfterAgent, AfterToolUse, Stop hooks (stable as of v0.124+). |
| Cursor | beforeShellExecution, beforeMCPExecution, afterFileEdit, stop hooks. |
| opencode | 25+ lifecycle events via TypeScript plugin. |
| GitHub Copilot CLI | preToolUse hook. |
| Aider | No native hooks; integration not supported in v1. |

Lists publishes an open spec for the file format so any agent (current or future) with hook support can integrate. The spec is the same as the regular item file format, just with a few agent-specific frontmatter fields:

```yaml
agent_status: working  # or queued | working | needs_input | done | failed
created_by: agent_claude-code
agent_session: <session_id>
blocking: false  # set to true on question sub-items
```

### 7.4 What agents can reliably surface

Based on the actual capabilities of agentic tools in 2026:

- **Currently running work** — yes, via PreToolUse / PostToolUse hooks.
- **Questions / blocked moments** — yes, via Notification hooks.
- **Session history** — yes, via Stop hooks.
- **Truly scheduled future work** — only for agents with built-in schedulers (rare). Most don't have this.

Don't promise users that "scheduled" agent work universally appears. Document which agents support which states.

### 7.5 Disconnecting an agent

Three scenarios that look similar but are different:

1. **Session ends, agent still exists.** Nothing in Lists changes. The data persists; status updates just stop until the next session.
2. **User removes integration in Lists settings.** The agent's lists move to the regular Lists section, marked as archived. Data preserved.
3. **Underlying project deleted.** Lists detects this on the agent's next run and archives the orphaned project list (same as #2).

### 7.6 Manual delegation

A user can manually add an item to an agent's list. The agent's hook script reads it on the next event and acts on it. This is the "delegate to agent" gesture — not a special button, just "add an item to a list."

A "Send to agent" button on regular-list items is deferred to v2. Probably unnecessary given manual delegation works.

### 7.7 Permission model

The folder is the permission boundary. An agent's hook script writes only to its own folder. It cannot see anything in your regular Lists. There is no full-access "agent sees everything" mode. If a user wants their agent to act on personal stuff, they manually copy or add items to the agent's list.

---

## 8. Platform strategy

### 8.1 Universal commitments

- **Native UI on every platform.** No Compose Multiplatform Skia rendering, no Flutter, no React Native, no Electron.
- **Identical feature set on every platform** with narrowly-scoped exceptions for platform-specific affordances.
- **Local-first everywhere.** Sync is optional.
- **AGPL-3.0-or-later. Free.**

### 8.2 Launch platforms (v1)

- **iOS** — SwiftUI. Already substantially built (the existing Fields iOS app).
- **macOS** — SwiftUI/AppKit, sharing significant code with iOS.
- **Android** — Jetpack Compose. Net new.
- **Windows** — TBD between WinUI 3 (most native) and Avalonia (more shareable, MCP-driven dev tooling).
- **Linux** — TBD between GTK4/libadwaita (most native to GNOME) and Avalonia (if chosen for Windows).

Apple Watch, web, and CLI are deferred to post-v1.

### 8.3 Architecture

A **Rust core** exposed via UniFFI handles:
- Markdown + YAML parsing.
- File I/O with atomic writes.
- SQLite index management and queries.
- Full-text search (FTS5).
- Sync protocol (when paid sync ships).
- CRDT merging (when added).
- File watching for external edits.

Native UI shells consume the core on each platform:
- SwiftUI on Apple platforms.
- Jetpack Compose on Android.
- WinUI 3 or Avalonia on Windows.
- GTK4 or Avalonia on Linux.

UniFFI generates idiomatic Swift, Kotlin, and Python bindings from the Rust crate. Tools: `cargo swift` for Apple platforms, Cargo NDK Gradle Plugin for Android.

### 8.4 Platform-specific exceptions

Features allowed to be platform-specific because the platform demands it:

| Platform | Exceptions allowed |
|---|---|
| iOS | Live Activities, App Intents, Shortcuts, Lock Screen widgets, StandBy mode, AlarmKit, "When Messaging" trigger (deferred from v1 cross-platform). |
| macOS | Menu bar, multiple windows, NSToolbar, AppleScript bridge, Touch Bar (where present). |
| Android | Material You theming, App Actions, Quick Settings tile. |
| Windows | System tray, Windows Notifications XML, Jump List. |
| Linux | Tray (where DE supports it), libadwaita conventions on GNOME, Plasma integration on KDE. |

Anything not on this list works identically across platforms.

### 8.5 Default data folder

| Platform | Default location |
|---|---|
| iOS | App's Documents folder, visible in Files.app. |
| Android | App's external Documents folder. |
| macOS | `~/Lists` (user-pickable on first launch). |
| Windows | `%USERPROFILE%/Lists`. |
| Linux | `~/Lists` or XDG-compliant location. |

User-visible everywhere. Promise: open the folder, see your data. Copy it elsewhere as a backup.

### 8.6 Keyboard shortcuts (desktop)

Canonical shortcuts use Cmd on macOS and Ctrl on Windows/Linux:

| Action | Shortcut |
|---|---|
| New item | Cmd/Ctrl + N |
| New list | Cmd/Ctrl + Shift + N |
| Quick add | Cmd/Ctrl + Space |
| Search | Cmd/Ctrl + F |
| Today | Cmd/Ctrl + 1 |
| Scheduled | Cmd/Ctrl + 2 |
| Toggle complete | Cmd/Ctrl + . |
| Toggle flag | Cmd/Ctrl + Shift + F |
| Indent (sub-item) | Tab |
| Outdent | Shift + Tab |
| Toggle thread view | Cmd/Ctrl + T |
| Settings | Cmd/Ctrl + , |

### 8.7 Window management (desktop)

- **macOS, Windows, Linux:** support multiple windows. Each window can show a different list. Tabs within a window optional in v1, definite in v2.
- **iPadOS:** Stage Manager and split-view supported.
- **iOS, Android phones:** single-window, modal sheets for editing.

---

## 9. Visual and interaction design

### 9.1 Design philosophy

Calm. Information-dense without being cluttered. Animation that serves rather than performs. Native feel on every platform.

North stars: iA Writer's restraint, Things 3's polish, Apple Reminders' visual layout, Obsidian's data ethos.

### 9.2 Color and theming

- **Light mode** and **dark mode** required.
- System theme follow (default).
- OLED true-black mode (for AMOLED phones and dark-mode users who want maximum contrast).
- Custom themes: deferred to v2. v1 ships a single coherent theme per mode.

### 9.3 Typography

- **System fonts on each platform** (SF Pro on Apple, Roboto on Android, Segoe UI on Windows, Cantarell or system default on Linux).
- Monospace for code blocks and certain reference fields (UUIDs in advanced views).

### 9.4 Density

A user setting: Comfortable / Compact / Cozy. Default is Comfortable. Affects row heights, padding, and font sizes.

### 9.5 Animation

- Reduced-motion compliance by default (respects OS-level reduce-motion settings).
- Gentle, purposeful animations: list scroll, sheet presentation, completion checkmark, presence indicators.
- No bouncing physics, no springy overshoots, no decorative motion.

### 9.6 Empty states

- **Empty Today:** "Nothing scheduled today. ☀️" with a subtle "+ New" button.
- **Empty list:** "This list is empty. Tap + to add your first item."
- **Empty all:** first-run guidance.

### 9.7 First-run experience

A 30-second onboarding:
1. Welcome screen with one-line pitch.
2. Pick data folder location (or accept default).
3. Optional: connect Lists Sync (with clear "you can do this later" option).
4. Land on an empty Today view with a sample reminder pre-filled (which the user can complete or delete).

No mandatory account creation. No nag screens. No "rate this app" prompts.

### 9.8 Iconography

SF Symbols on Apple platforms, Material Symbols on Android, Lucide or Tabler on Windows / Linux. Consistent icon meanings across platforms even if the glyph differs slightly.

### 9.9 App icon

Custom icon, designed before launch. Two-tone, recognizable at all sizes from 16px to 1024px. Alternate icons (free) post-launch.

---

## 10. Behavior and interactions

### 10.1 Default home view

Sidebar layout:

```
[ Lists ] [ AI ]
─────────────────
PINNED
  ⊙ Today
  ⊕ Scheduled
  ✓ Completed
  ⚑ Flagged
  ⏰ Urgent
  ▦ All

LISTS
  📋 Tasks (default)
  💼 Work
    ↳ Project Apollo
  🏠 Personal
  🛒 Groceries
  ...

#  Tags
🗑  Recently Deleted
```

### 10.2 The "+" button

Bottom-right corner of every list view. Behavior:

- **Tap:** opens new-item editor (modal sheet) for the current list, with the current list's `default_type` (task/habit/note) pre-selected.
- **Drag onto a list (in sidebar):** drops the new item in that list, automatically setting its type to the destination list's `default_type`. Item is created inline and ready for typing — see 10.2.2.
- **Drag onto a section header (within current list or in column view):** drops the new item into that section. Item is created inline and ready for typing — see 10.2.2.
- **Long-press:** opens a type picker (Task / Habit / Note) for the current list, then opens the modal editor with the chosen type.

The new-item editor (modal) shows a small type-toggle icon at the top (checkbox icon for task, repeat icon for habit, document icon for note) — tap to cycle, long-press for picker.

#### 10.2.1 No always-visible empty entry rows per section

Lists explicitly does not show a permanent "tap to add" empty row at the bottom of every section. With multiple sections, this would produce N rows of empty space and make lists feel cluttered. Adding new items happens via the floating "+" button or its drag gesture.

#### 10.2.2 Inline editing for drag-created items

When the user drags the "+" onto a list or section, the new item is created inline at that position and immediately enters edit mode:

- The item appears as a new row with the cursor in the title field.
- The on-screen keyboard appears (mobile) or the title field gains focus (desktop).
- The user types the title and hits enter to commit, or escape / tap-away to cancel (which removes the row).
- During inline editing, fields beyond the title (date, priority, tags, etc.) are accessed via a **keyboard accessory bar** floating above the keyboard — see 10.2.3. The user does not have to leave the inline edit to set these.

Inline editing is the fast path for common adds. The modal editor (opened by tapping "+") remains available for users who want the full form upfront.

#### 10.2.3 Keyboard accessory bar (mobile)

While inline editing or editing any item's title, a slim bar floats directly above the keyboard with quick-access controls. Tapping any control adjusts the relevant field without leaving inline edit mode.

**Bar contents (left to right):**

- **Date / time** — opens a compact date+time picker as a popover above the bar. Picker has Today, Tomorrow, This Weekend, Next Week, "Pick a date", Clear.
- **Reminder** — toggle bell icon. Mirrors the date picker's reminder toggle. Greyed out if no date is set.
- **Tag** — opens a tag picker / autocomplete. Allows adding multiple tags. Tags also parseable inline by typing `#tag` directly in the title.
- **Priority** — cycles through None → Low → Medium → High on tap. Long-press for direct picker.
- **Flag** — toggle.
- **List** — shows current list name. Tap to move the item to a different list.
- **Type** — only shown when the current list allows multiple item types. Cycles task → habit → note.
- **More** — opens the full Details sheet for fields not on the bar (location, urgent, recurrence, early reminder).

The bar is scrollable horizontally if controls overflow on narrow screens.

**On desktop**, the equivalent is a thin inline toolbar that appears below the title row during edit, exposing the same controls. Most fields are also accessible via keyboard shortcut while editing (e.g., Cmd/Ctrl + D for date, Cmd/Ctrl + T for tag).

#### 10.2.4 Behavior when no section is targeted

If the user taps "+" without dragging (instead of dragging onto a section), the new item is created in the list's "Uncategorized" position (above the first section header) or, if no sections exist, simply at the end of the list. The user can drag it into a section afterward, or the item can be assigned to a section via the keyboard accessory bar's More menu / Details sheet.

### 10.3 The new-item editor (full)

Fields visible by default:

- **Title** — large text input. Inline `#tag` parsing.
- **Notes** — markdown body. Below title. Expandable.
- **Date & Time toggle** — when on, shows date picker and optional time picker.
- **Time zone** — defaults to user's default (set in Settings, initially device timezone). Per-item override via picker.
- **Reminder toggle** — on by default when date is set. Off by default with no date.
- **Repeat picker** — Never / Hourly / Daily / Weekdays / Weekends / Weekly / Fortnightly / Monthly / Every Three Months / Every Six Months / Yearly / Custom.
- **End Repeat** — Never / On Date.
- **Urgent toggle** — with explanatory text "Mark this reminder as urgent to set an alarm." Shows "Alarm on: [device]" when sync is active and a device is selected.
- **Inline tag editor** — chip-style.
- **Priority** — None / Low / Medium / High picker.
- **Flag** — toggle.

In the **Details / More Options** sheet (expanded view):

- **Early Reminder** — None / 5min / 15min / 30min / 1hr / 2hr / 1d / 2d / 1wk / 1mo / Custom. With unit picker.
- **List** — shows current list, tappable to change.
- **Tags** — full tag editor.
- **Location** — toggle. When on: map picker, search, arrival/departure, radius. Shows "Trigger fires on iOS and Android" indicator on non-mobile platforms.

### 10.4 Drag and drop

- **Within a list:** reorder items.
- **Between lists:** move to another list (cursor indicates drop target).
- **Onto a tag chip:** apply that tag.
- **Onto a date in calendar view (Scheduled):** reschedule.
- **Onto a section header:** assign to that section.

### 10.5 Bulk actions

Multi-select via long-press (mobile) or shift-click (desktop). Bulk actions:
- Delete (move to trash).
- Move to list.
- Apply tag.
- Mark complete / incomplete.
- Set priority.
- Flag / unflag.
- Reschedule.

### 10.6 Undo

- Cmd/Ctrl + Z everywhere.
- Stack depth: 50 actions per session.
- Does not survive app restart.

### 10.7 Swipe gestures (mobile)

- **Swipe right (short):** complete / uncomplete.
- **Swipe right (long):** flag.
- **Swipe left (short):** delete (with undo toast).
- **Swipe left (long):** more actions menu.

Swipes are configurable in Settings.

### 10.8 Long-press / right-click context menu

In priority order:
- Complete / Uncomplete
- Edit
- Add sub-item
- Toggle flag
- Set priority
- Move to list
- Add tag
- Duplicate
- Share
- Delete

### 10.9 Quick add (desktop global)

System-wide hotkey (default Cmd/Ctrl + Shift + L) opens a small floating quick-add window. Type, hit enter, item lands in default list. No window switching.

---

## 11. Notifications

### 11.1 Permission flow

Lists requests notification permission on first add of a notification-enabled reminder, not at first launch. Explanation copy: "Lists needs permission to send you reminders when your tasks are due."

For AlarmKit specifically (iOS 26+), separate permission request with `NSAlarmKitUsageDescription`: "Lists uses AlarmKit to play urgent alarms that bypass silent mode and Focus."

For location, on first add of a location-triggered reminder: "Lists uses your location to remind you when you arrive at or leave specific places."

### 11.2 Notification content

- **Standard reminder:** title + first line of notes (if present). Tap to open in app.
- **Urgent alarm:** full-screen presentation (per platform), title prominent, snooze and dismiss buttons.
- **Location trigger:** "Arrived at [place name]: [item title]" or "Left [place name]: [item title]".
- **Habit nudge:** "Time for [habit title]" — quiet, no count info.
- **Agent question (urgent triggered):** "[Agent name] needs your input on [item title]."

### 11.3 Snooze

Available on all reminder types. Options: 5, 10, 15, 30 minutes; 1 hour; tomorrow same time; custom.

### 11.4 Quick complete from notification

Where supported:
- iOS / iPadOS: notification action "Complete" marks the item done without opening the app.
- Android: same via Action button.
- macOS: same.
- Windows: ToastButton with arguments.
- Linux: best-effort; depends on the notification daemon.

### 11.5 No LLM features in v1

No on-device or cloud LLM features in the app itself. No natural language parsing (e.g., "tomorrow at 5pm" → date). No smart scheduling. No auto-summarization. No voice transcription.

This is by design — privacy-first, predictable, offline-capable. LLM features may come in v3+ as opt-in additions.

User-controlled LLMs (via MCP integration with their own agents) are a separate matter. That's section 7.

---

## 12. Privacy, security, and trust

### 12.1 Privacy promise

"Your data lives on your devices, in plain files you can read and own. We don't see it. We sync it (if you want us to), encrypted end-to-end, and we make the data layer open enough that you could replace us tomorrow."

### 12.2 Telemetry

**Off by default. Opt-in only.** When opted in:
- Crash reports via self-hosted GlitchTip (preferred for AGPL alignment) or Sentry (acceptable).
- No analytics, no usage tracking, no third-party SDKs.

### 12.3 Account model

- **No account for the free local app.** Use it without signing up.
- **Account required only for Lists Sync subscription.** Email + password (with passkey support where platform allows).
- **Self-managed sync requires no account at all.**

### 12.4 Data export

Export = ZIP of the entire data folder. Available anytime, free, even without sync subscription. The folder is the export. No special "export" feature is needed beyond a "Compress to ZIP" affordance.

### 12.5 Data import

v1 importers:
- Apple Reminders (via Shortcuts on iOS).
- Plain markdown folders (Obsidian-compatible vaults).

v1.5+ importers:
- Todoist
- Things 3
- TickTick
- Microsoft To Do

### 12.6 Account deletion

Closing a paid sync subscription:
- Files on user devices stay (they're local).
- Server-side encrypted blobs deleted within 30 days.
- Account record deleted within 90 days.
- User can request immediate deletion via support email.

### 12.7 Threat model

Primary threats:
- Casual snoopers (your roommate, a borrowed phone).
- Server compromise (mitigated by E2E encryption).
- Lost or stolen device (mitigated by OS-level encryption — Lists doesn't add an in-app PIN in v1; consider for v2).

Out of scope:
- Nation-state-grade adversaries.
- Compromised user device with active malware.

---

## 13. Open source and governance

### 13.1 License

**AGPL-3.0-or-later.** Both client and sync server.

Trademark "Lists" is registered (or planned to be) so forks must rebrand. The code is fully forkable; the name is not.

### 13.2 Contribution

- DCO sign-off on commits, no CLA.
- Code of Conduct based on Contributor Covenant 2.1.
- All contributors retain copyright; code is licensed to the project under AGPL.

### 13.3 Funding

- Lists Sync subscriptions (primary).
- GitHub Sponsors (secondary).
- No advertising. No data sales. No telemetry monetization.

### 13.4 Governance

Solo BDFL initially. Documented as such. Hand-off plan exists (section 13.5) but isn't activated.

### 13.5 Sustainability and exit plan

- **Time budget:** ~10 hours per week, sustainable alongside FIFO and other commitments.
- **Long absences:** issues continue to be readable; auto-responder explains response delays.
- **Health metric:** Lists Sync MRR + crash-free sessions percentage, checked monthly.
- **Sunset trigger:** if hours-of-joy-per-week drops below sustainable for 6+ months, evaluate handoff to a maintainer or graceful sunset (open-sourcing remaining server code, refunding active subscribers, archiving the project).

### 13.6 Distribution channels

| Channel | v1 | Notes |
|---|---|---|
| App Store (iOS) | Yes | Required for iOS distribution. |
| Mac App Store | Yes | Plus direct download via DMG. |
| Play Store | Yes | Plus direct APK. |
| F-Droid | TBD | Requires no-Google-Services build for Android. |
| Microsoft Store | Yes | Plus direct download via MSIX installer. |
| Direct download (DMG / MSIX / AppImage) | Yes | From lists.app or similar. |
| Homebrew | Yes (cask for macOS, formula for Linux). |
| Winget | Yes |
| Flathub | Yes (Linux). |
| Snap Store | Maybe | Linux secondary. |
| AUR | Yes (community-maintained). |

### 13.7 The fork question

AGPL means anyone can fork. Trademark forces rebrand. The moat is product polish, official paid sync that "just works," and user trust — not code that can't be copied. Lists explicitly does not design defensively against forks.

---

## 14. Roadmap

### 14.1 v1.0 — Local-first launch

Every launch platform: iOS, macOS, Android, Windows, Linux.

Features:
- Items: task, habit, note.
- Lists with nesting (sub-lists as folders).
- Sub-items with thread view.
- Sections within lists (manual + grocery auto + AI auto).
- Column view toggle per list.
- Tags with overview.
- Smart lists: Today, Scheduled (with calendar), All, Completed, Flagged, Urgent.
- Recurrence: full set including custom builder.
- Reminders with early reminder offsets.
- Triggers: urgent (AlarmKit on iOS / equivalents elsewhere), location (iOS/Android only).
- Attachments: images, PDFs.
- Markdown editing: CommonMark + GFM.
- Local notifications.
- Drag-and-drop, bulk actions, undo.
- Keyboard shortcuts on desktop.
- Quick add hotkey on desktop.
- Light / dark mode.
- Density toggle.
- Data export (folder ZIP).
- Apple Reminders import.

**No sync. No AI integration.**

### 14.2 v1.5 — Lists Sync ships

- Hosted sync service.
- E2E encryption.
- Live presence indicators.
- Self-hostable sync server released alongside.
- Conflict resolution UI.
- Trigger-device picker fully working.
- Additional importers: Todoist, Things, TickTick, Microsoft To Do.
- Audio attachments.

### 14.3 v2.0 — AI integration

- Two-section UI with Lists and AI.
- Per-agent integration scripts: Claude Code, Codex, Cursor, opencode.
- Auto-discovery of projects for agentic coding tools.
- Live agent presence indicators.
- "Question sub-items" with urgent triggers.
- Agent activity history.

### 14.4 Post-v2 backlog

- User-defined smart lists with query language.
- Calendar two-way sync (iCloud, Google, CalDAV).
- CLI for power users.
- Browser extension for quick-add and clipping.
- Watch app (Apple Watch, Wear OS).
- Multiple windows / tabs on desktop.
- Custom themes.
- Wikilinks.
- Mermaid, footnotes, math in markdown.
- Optional in-app PIN / biometric lock.
- "Send to agent" button on regular-list items.
- After-completion recurrence option.

### 14.5 The "nope, never" list

- Gantt charts.
- Time tracking.
- Built-in chat UI for AI.
- Social / sharing features beyond simple item share-sheets.
- Gamification beyond the toggleable streak counter.
- Hierarchical tags.
- Server-side LLM processing of user data.
- Ads.
- Telemetry without explicit opt-in.

---

## 15. Marketing and launch

### 15.1 Launch venues

In order of priority:
1. Show HN (Hacker News).
2. Mastodon (federated tech crowd) and Bluesky.
3. /r/iOSProgramming, /r/Android, /r/selfhosted, /r/ObsidianMD.
4. MacStories pitch (Federico Viticci).
5. MKBHD review pitch (long-shot, asymmetric upside).
6. Product Hunt (lower priority — wrong audience for privacy-first open source).

### 15.2 Headline pitches per venue

- **HN:** "Show HN: Lists – Local-first reminders, habits, and notes in plain markdown files (AGPL)"
- **Mastodon:** "After a year of work, Lists is here. Beautiful native reminders that store data in markdown files you own. AGPL, free local use, optional paid sync."
- **MacStories:** "Lists is a love letter to Apple Reminders' visual design and a rejection of its proprietary lock-in."

### 15.3 Landing page sections

1. Hero: one-line pitch + screenshots cycling across all five platforms.
2. Three-feature grid: Local-first, Cross-platform native, Open source.
3. Sync as the paid product (with self-host option called out).
4. AI integration teaser (post-v2).
5. Pricing.
6. FAQ.
7. Download / GitHub.

### 15.4 Press kit

Available at lists.app/press: logos, screenshots in light and dark mode for each platform, descriptions in 50/200/500-word formats, contact email, press release template.

---

## 16. Outstanding decisions

The following remain TBD and need decisions before launch:

1. **Pricing for Lists Sync.** Reference research done; specific number not picked.
2. **Trademark registration.** Legal step, hasn't happened yet.
3. **Habit reminder nudge timing details** — what time of day for habits without explicit reminder times?
4. **Custom themes feature** — confirmed deferred to v2; revisit if user demand is high.
5. **Windows UI framework** — WinUI 3 vs Avalonia. Final decision pending.
6. **Linux UI framework** — GTK4/libadwaita vs Avalonia. Final decision pending.
7. **F-Droid support** — requires no-Google-Services Android build; engineering cost vs user demand TBD.
8. **In-app PIN / biometric lock** — deferred to v2 unless beta feedback demands it sooner.

---

## 17. Documentation that will exist by launch

- README.md (in repo root).
- PRODUCT-SPEC.md (this document).
- AGENTS.md (cross-tool AI assistant instructions).
- CLAUDE.md (symlink to AGENTS.md).
- CONTRIBUTING.md.
- CODE_OF_CONDUCT.md.
- LICENSE (AGPL-3.0).
- File format specification (separate doc, public spec for third-party tools).
- Sync protocol specification (separate doc, for self-hosters).
- Per-agent integration scripts (in `integrations/` directory).
- User documentation site (lists.app/docs or docs.lists.app).

---

## Changelog

| Date | Change | Reason |
|---|---|---|
| 2026-05-08 | v1 initial spec | Captured from design conversation |
| 2026-05-08 | v2 consolidated spec | Folded in Fields screenshots, AlarmKit details, unified trigger model, location reminders, habit details, all locked-in answers |
| 2026-05-08 | v2.1 inline editing details | Added section 10.2.1–10.2.4: no always-visible empty rows; drag-onto-section creates inline; keyboard accessory bar for fast field access |
