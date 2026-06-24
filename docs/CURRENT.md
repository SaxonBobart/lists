# Current Status

Work happens on `dev`. Git model: `GIT-GUIDE.md`. Milestone history: `docs/CHANGELOG.md`. Plain-English roadmap: `JOURNAL.md`. Long-range product strategy: `FUTURE-PLAN.md`.

## Environment: Xcode 27 beta 2 / Swift 6.4 / iOS 27 beta

The full tool reality is in `AGENTS.md` -> "Facts you can't derive." Short version: build, test, install, launch, screenshots, and runtime snapshots work through XcodeBuildMCP. Apple now documents Device Hub as the current simulator/device surface. Verify any `tap`/typing action with a fresh screenshot or snapshot, because DeviceHub can desync and a tap may report success without changing UI. `open_sim` / `Simulator.app` are still gone under this toolchain; `build_run_sim` boots through DeviceHub as needed. Use the `xcode` bridge for IDE-context jobs such as SwiftUI previews, Issue Navigator diagnostics, Apple documentation search, or fallback device interaction.

## What exists

- iOS app: `platforms/ios/Lists.xcodeproj` (SwiftUI, Swift 6.4, XcodeGen; spec in `project.yml`).
- Parked Android experiment: archived in git tag `archive/android-experiment-2026-06-24`; it is not part of the active product until explicitly reactivated.
- App behavior standard: `docs/APP-STANDARD.md` captures the platform-neutral rules that iOS currently defines and Android should later translate.
- Core: models, file storage, frontmatter codec, sample data, smart lists, tags, reminders, notification scheduling.
- Item types: **task, habit, note, event** (events always have start + end; completable is opt-in).
- Screens: sidebar, smart-list queries including Today, list detail, item document view, quick capture, habits, search, settings, recently deleted, tags.
- Item move mode is in-place: Move actions or dragging a user-list row onto the bottom shelf start the shared shelf, then user lists provide `None` and row parent destinations while navigating between lists.
- Settings now has real local maintenance actions: export the app-private Lists folder as a ZIP, rebuild the in-memory cache from disk, show notification permission state, and set the default reminder time. Habits appear as a built-in module; external plugins, sync, location reminders, and AlarmKit-style urgent alarms are not current iOS surfaces.
- Tests: `ListsTests` uses Swift Testing for product rules, storage rules, recurrence, habits, quick capture, settings, render smoke coverage, and data-resilience coverage. XCTest remains only for snapshot baselines. XCUITest was retired 2026-06-13 — gestures are verified by unit-testing their logic plus driven simulator sessions.

## Known risks

- List Detail: `ListDetailCollectionView.swift` is still a UIKit bridge. Nearby support files now own snapshot building, drag/drop delegates, drop cues, drop targets, hierarchy math, row views, queries, models, registrations, context menus, swipe actions, reorder commits, bottom chrome, and empty state. Split it further only around focused behavior changes.
- Inline editing: `InlineItemEditor` is the SwiftUI row shell; `InlineEditController` owns UIKit text editing, toolbar, sizing, type flips, and commits; `InlineDateTimePopover` keeps state/apply rules while sibling section views own form rows.
- Sidebar and rows: sidebar collection support is split into bridge, self-sizing collection view, hosted row content, cell, and accessibility files. Shared list-tree flattening and cycle guards live in `ListHierarchy`. `ItemRow` owns row interaction/routing/swipes; `ItemRowLeadingControl` owns type-specific leading controls.
- Shared behavior: Today and smart-list screens share row rendering plus completion linger through `ItemCompletionLinger`; smart-list menu bindings live in `SmartListToolbarMenu`, and All/Scheduled/Today grouping rules live in `Core/Queries`.
- Date rules: recurrence expansion lives in `RecurrenceEngine`, the editor model in `RecurrenceRule`, RRULE splitting in `RRuleParts`, schedule/`UNTIL` formatting in `ScheduleFormatting`, and event start/end seeding in `EventDefaults` with storage enforcement in `ItemStore`.
- Detail and capture: `ItemDetailSheet` is a thin router. `ItemDocumentView` owns live-apply rules; `DocumentPageRows` owns page chrome; document Details cards live in separate schedule/repeat/metadata files. Quick Capture keeps sheet state in `QuickCaptureSheet`, draft/save/discard rules in `QuickCaptureDraft`, and layout in sibling views.
- Habits and lists: `HabitDetailView` owns routing/save/delete; sibling views own overview, log, form, and completion-entry layout. `ListEditSheet` owns list edit UI state; `ListEditDraft` owns `ItemList` creation/update rules.

## Constraints

- Bundle id `io.github.saxonbobart.lists`; Apple team `LM99LGYW87` (free signing only).
- AlarmKit-style urgent alarms are not in the current iOS app without a paid Apple Developer Program account.
- iOS data stays app-private in `Documents/Lists/` — no Files.app visibility, no iCloud.
- iOS is the active product; Android, Linux, Windows, and sync are outside the current implementation until explicitly requested.
