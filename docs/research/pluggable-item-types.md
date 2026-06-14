# Pluggable Item Types — Vision + First Step

*Design note, recorded 2026-06-14 on Saxon's call. **Planning only — no code yet.** Captures the intent and the first concrete step, grounded in the current architecture.*

## The idea

Three of the four item types — **task, note, event** — are the same thing wearing a different control surface: a markdown body plus a small affordance (a checkbox, a calendar span). **Habits are the odd one out** — they have no markdown body, their own completion model, and their own detail screen. They share almost nothing with the others.

So instead of `ItemType` being a fixed enum that the whole app branches on, the goal is to make item types **pluggable**: each type is a self-contained module that the core dispatches to, and **habits become the first such plugin**. New kinds of items can then be added later without touching the core.

## Why habits are the clean first plugin

Habits are *already* the most isolated type in the codebase — this isn't a hopeful refactor, the seams already exist:

- **Own detail surface:** `Features/Habits/HabitDetailView.swift` (+ `HabitHeatmap.swift`) — habits never open the shared `ItemDocumentView`.
- **Own state model:** timestamped completions in `HabitCompletion` / `HabitCycle`, orthogonal to the `done` flag tasks/events use.
- **Own store mutations:** `ItemStore.logCompletion` / `deleteCompletion` / `updateCompletion`, all already guarded by `type == .habit`.
- **Own query rules:** excluded from the Scheduled and All smart lists (`SmartList.swift`).
- **No markdown body:** PRODUCT-SPEC is explicit — "habits have no notes body at all."

The other three types keep using the shared markdown-document path unchanged.

## What a "type plugin" provides

A registry/protocol surface where each type supplies:

- **Row control surface** — the leading control in a list row (checkbox / ring / glyph).
- **Detail surface** — which screen opens (shared document view vs. a dedicated one).
- **State / completion semantics** — what "done" or "logged" means for this type.
- **Smart-list participation** — capability flags (e.g. `includeInScheduled`, `includeInAll`) instead of hard-coded `!= .habit` checks.
- **Capture form** — the type-specific fields in quick-capture / New Item.

The core stays type-agnostic and dispatches through this surface.

## First step (when it's built — not now)

1. **Carve the habit boundary.** Move habit-only fields behind a nested `HabitData` value, and gather habit behavior (detail view, completion mutators, cycle/streak stats, smart-list rules) behind the plugin surface.
2. **Convert the dispatch points.** Roughly 13 files currently `switch item.type` — `ItemRow`, `ItemDetailSheet`, `ItemDocumentView`, `SmartList`, `QuickCaptureSheet`, `ItemStore`, `InlineItemEditor`, `SettingsView`, `DocumentQuickDetailsBar`, and the codec. Each becomes a call into the plugin instead of an inline branch.
3. **Generalize.** Once habits ride the plugin surface cleanly, the same surface accepts additional/default item-type plugins.

## Hard constraints

- **No behavior change.** This is an internal refactor; the app should look and act identically when it lands.
- **On-disk format stays stable.** `ItemType` is a raw string on disk and unknown types already decode as `task` in the current codec — keep that, so old files and forward-compat both survive.
- **Stage it.** Coupling is moderate-to-high today, so extract habits cleanly behind the boundary *first*, prove it, then generalize — don't try to make everything pluggable in one pass.
