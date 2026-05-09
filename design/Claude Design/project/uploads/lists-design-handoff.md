# Lists — Claude Design Handoff Brief

> **Purpose**: Use this document as the opening context for a fresh Claude Design session. It contains everything that session needs to start designing iOS v1.0 of Lists effectively, plus the bridge to Claude Code for implementation.
>
> **Companion document**: `lists-product-spec-v2.md` — the full product specification. Paste it alongside this brief, or reference it for any product detail.

---

## Project context in 90 seconds

**Lists** is a beautiful, local-first markdown app with rich reminders, habits, and notes. Data lives in plain markdown files with YAML frontmatter on disk. Free and open source (AGPL-3.0-or-later). Optional paid sync as the business model.

**Tech stack**: Rust core (markdown parsing, file I/O, SQLite index, eventual sync) exposed via UniFFI to Swift. Native SwiftUI on top. Future platforms (Android, Windows, Linux) will reuse the Rust core with their own native UI.

**Current status**: Designing iOS v1.0 from scratch. A previous iOS implementation exists as reference but is being fully redone. Solo developer, vibe coding with Claude Code, no formal design background.

**This Claude Design session's job**: produce the visual design language and per-screen mockups for iOS v1.0, in a form that can be handed to Claude Code for implementation.

---

## Design philosophy (north stars)

- **Calm, not loud.** No gamification beyond the toggleable streak counter. No notification badges screaming for attention. No bright reds on every error.
- **Information-dense without being cluttered.** Apple Reminders is the visual anchor. Things 3 is the polish anchor. iA Writer is the restraint anchor.
- **Animation that serves, not performs.** Gentle motion. Reduce-motion compliant by default.
- **Native feel.** This is a SwiftUI app. It should feel like an iOS app made by someone who loves iOS, not like a cross-platform app that "also runs on iOS."
- **Honest about its parts.** Empty states have personality but don't lie. Loading states show real progress. Errors are specific and actionable.

---

## Visual design decisions still open (this is your job)

These are the high-leverage design decisions that should be locked before per-screen mockups begin. Work through these in roughly this order:

### 1. Color system

- Primary accent color (the "this app is X color" identity color).
- Secondary accent (used sparingly — flags, urgent indicators, warnings).
- Light mode neutral palette (backgrounds, surfaces, dividers, text levels).
- Dark mode neutral palette.
- OLED true-black mode neutral palette.
- Semantic colors: success, warning, error, info.
- The exact shade for completed-item strikethrough, partial-shade vs full-shade in habit heatmaps, "live presence" pulse color.

### 2. Typography scale

- System font (SF Pro on iOS) with specific weights and sizes for: large title, title, body, caption, label, monospace.
- Dynamic Type behavior — how the scale responds to user text-size settings.
- Markdown rendering: H1–H4 sizes, code block styling, blockquote treatment.

### 3. Iconography

- Source: SF Symbols throughout, with custom symbols only where needed.
- Size conventions per context (sidebar, inline, button, accessory bar).
- The specific symbols for: task, habit, note, list, sub-list, tag, flag, urgent alarm, location trigger, reminder, completed, sub-item progress, agent presence.

### 4. Spacing and density

- Base spacing unit (probably 4pt or 8pt).
- Density modes: Comfortable / Compact / Cozy. What changes between them.
- List row heights, padding, separators.
- Section header treatment.

### 5. Animation language

- Sheet presentation duration and easing.
- Item completion checkmark animation.
- New-item-arrives animation (especially for inline-add and agent-posted items).
- Live presence pulse animation timing.
- Transition between vertical and column view.
- Thread view expand/collapse.

### 6. Motion-light fallback

For users with reduce-motion enabled: what's the alternative for each animation?

---

## Screens to mock up (in priority order)

### Tier 1 — core shell (must exist before anything else)

1. **Sidebar / home view**
   - Pinned section (smart lists by default).
   - Lists section with nested sub-lists.
   - Tags overview link.
   - Recently Deleted link.
   - Search field at top.
   - Light and dark mode.

2. **Today smart list (list view)**
   - Overdue section collapsed at top.
   - Today's items sorted by time of day, all-day items first.
   - Empty state.

3. **Single regular list view (vertical layout)**
   - Section headers with items grouped beneath.
   - Item row showing: checkbox, title, optional date/time, optional reminder bell or strikethrough-bell, priority indicator, flag, tag chips, sub-item progress badge.
   - The "+" floating action button bottom-right.
   - Empty state.

4. **Single regular list view (column layout)**
   - Same data as vertical but rendered as kanban columns.
   - Horizontal scroll on phone, all visible on iPad.
   - Drag items between columns.

5. **Item detail / edit modal sheet**
   - Title field at top.
   - Markdown body editor.
   - Date+time picker section.
   - Reminder toggle.
   - Repeat picker.
   - Urgent toggle with device indicator (when sync enabled).
   - Tags inline editor.
   - Priority picker.
   - Flag toggle.
   - Details / More Options section: Early Reminder picker, List picker, Location toggle.
   - Done button top-right, cancel top-left.

### Tier 2 — interactions and refinements

6. **Inline editing for drag-created items**
   - New row appears at drop location, cursor in title field.
   - Keyboard accessory bar visible above keyboard.
   - The bar contains: date/time, reminder toggle, tag, priority, flag, list, type, more.

7. **Keyboard accessory bar — full visual treatment**
   - Spacing, icon sizes, tap states.
   - How each control's popover appears (date picker, tag picker, priority cycle).
   - Scroll behavior when content overflows.

8. **Thread view**
   - Toggle from item detail.
   - H1 parent, H2 sub-items, H3 grandchildren visual hierarchy.
   - Inline editing within thread view.
   - Inline "+ add sub-item" affordance.
   - Toggle back to tree view.

9. **Habit detail view**
   - Title, frequency, goal display.
   - Heatmap (one year of daily cells by default).
   - Streak counter (when enabled).
   - "Edit history" button.
   - Increment counter (1/8 → 2/8 → ...).

10. **Habit edit history view**
    - Scrollable list of cycles, most recent first.
    - Each row editable to backfill counts.

11. **Scheduled smart list with calendar view toggle**
    - List view (default).
    - Month, Week, Day calendar variants.
    - Drag items between days.

12. **Tags overview**
    - All tags as chips at top.
    - Items grouped by tag below.
    - Multi-tag intersection (filter by multiple tags).

### Tier 3 — settings and meta

13. **Settings — top level**
    - Sections: Appearance, Sync, Triggers, Notifications, Data, About.

14. **Settings — Triggers**
    - Urgent Alarm Device picker.
    - Location Reminder Devices picker.
    - When sync is disabled: hide pickers, show explanatory text.

15. **Settings — Sync**
    - Lists Sync subscription state.
    - Self-managed sync folder picker.
    - Conflict resolution preferences.

16. **First-run onboarding**
    - Welcome screen.
    - Data folder pick.
    - Sync invitation (optional, skippable).
    - Land on empty Today view with one sample reminder.

### Tier 4 — empty states, error states, edge cases

17. **All empty states** (Today, Scheduled, list, tag overview, search no results, completed, recently deleted).

18. **Error states** (sync failed, file corrupted, permission denied, disk full).

19. **Loading states** (first sync, large index rebuild, attachment download).

20. **Conflict resolution UI** (when self-managed sync produces a conflict file).

---

## Design references (look at these for inspiration)

### Apps to study before designing

- **Apple Reminders (iOS 26)** — visual layout, list density, smart list arrangement, the new "urgent" toggle pattern.
- **Things 3** — animation craft, sheet presentation, the "magic plus" button, today-vs-evening split.
- **Bear** — markdown editing, tag treatment, sidebar density.
- **iA Writer** — typography, restraint, focus mode aesthetic.
- **Obsidian (mobile)** — file-as-truth UI patterns, settings depth.
- **Apple Notes** — folder nesting, gallery view treatment.
- **Tot** — single-screen polish, color use as primary navigation.

### What to take from each

- From Reminders: the visual hierarchy of smart lists vs custom lists, the urgent-alarm device indicator, the inline tag chips.
- From Things: the Today / Evening split idea (don't necessarily copy, but understand the design intent), the magic-plus drag interaction.
- From Bear: how a beautiful markdown editor looks on mobile.
- From iA Writer: how restraint reads as quality.
- From Obsidian: how to handle "your data is on disk" UX without scaring non-technical users.

### What NOT to take from any of them

- Do not copy Apple Reminders' date-forces-notification model. The decoupling is a Lists differentiator.
- Do not copy Things' proprietary file format. Files are markdown, full stop.
- Do not copy Obsidian's plugin culture / settings depth. Lists is opinionated and minimal.

---

## How to deliver designs to Claude Code

When designs are ready, the handoff to Claude Code works best as:

1. **Per-screen Figma exports as PNG at 2x resolution.** Saved into `references/designs/` in the new repo.
2. **A short text description per screen** in a `references/designs/SCREEN-NOTES.md` file. Things like "tap on a list row navigates to the list detail view" and "the date picker uses native iOS DatePicker style."
3. **The design tokens** (colors, spacing, typography) exported as a JSON or Swift file that Claude Code can import directly.

For Claude Code to implement a screen, the prompt structure that works best is:
> "Implement the [screen name] screen. The design is at `references/designs/[screen-name].png`. Match it pixel-for-pixel where possible. Use native SwiftUI components. Data comes from the Rust core via the existing Swift bindings. If anything in the design doesn't translate cleanly to SwiftUI, ask before deviating."

---

## Not to design (these are platform-default or out of scope)

- iOS system date and time pickers — use native components.
- iOS share sheet — use native.
- iOS keyboard — use native, only design the accessory bar above it.
- iOS notification appearance — system-controlled.
- AlarmKit alarm UI — system-controlled.
- App icon — separate exercise, not part of in-app design work.

---

## Deliverables to produce in this Claude Design session

By the end of the design session, you should have:

1. **A design system document** with the locked decisions on color, typography, iconography, spacing, animation. (Roughly: a "design tokens" reference.)
2. **Per-screen mockups** for at least Tier 1 (5 screens) and ideally Tier 2 (7 more screens). Tier 3 and 4 can be done later.
3. **A handoff package** ready to drop into the new repo's `references/designs/` folder.

Don't try to do all of this in one session. Lock the design system first (decisions 1–6 above), then mockup Tier 1, then Tier 2. Each can be a separate session.

---

## Project setup (for context, not for this design session to do)

The new empty repo is at `/Users/saxon/Developer/Projects/lists`. The archived old version is at `/Users/saxon/Developer/Projects/archive/lists`. The old version is reference-only — visual ideas can be drawn from it, code will not be copied.

When implementation begins (in Claude Code, after design), the Xcode project and Rust core scaffolding will be set up there. Designs from this session feed into `references/designs/` in that repo.

---

## What to ask the user (you, Saxon) at the start of the design session

1. "Have you read the product spec? Any sections you want to discuss before starting?"
2. "Want to start with the design system (color, typography, iconography) or jump to a specific screen?"
3. "Do you have a color in mind for the primary accent, or should we explore?"
4. "Any specific apps you've seen recently whose visual feel you want to capture?"
5. "What's the time budget for this design session — quick exploration, or deep dive on one screen?"
