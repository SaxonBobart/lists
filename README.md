# Lists

Lists is a local-first iOS app for tasks, habits, notes, and events.

It is built around one idea: your lists should feel native and fast, while the
data stays understandable. Items are stored as plain text files with YAML
frontmatter inside the app sandbox. There is no account, sign-in, sync service,
or cloud dependency in the current app.

Status: pre-v1, iOS-first, local-first.

## What Works Today

- Tasks with completion, due dates, reminders, priority, flags, tags, sections,
  sub-items, and markdown body text.
- Habits as a built-in first-party module, with cycle goals, flexible weekly or
  monthly goals, forgiving streaks, heatmap, completion log, and local reminders.
- Notes as markdown-first items without checkbox chrome.
- Events as calendar-shaped items with start, end, all-day support, recurrence,
  reminders, and optional task-style completion.
- Nested lists and sections.
- Smart lists: Today, Scheduled, All, Completed, Flagged, Urgent, and Tags.
- Search, Recently Deleted, Quick Capture, Settings, local export, and cache
  rebuild.
- In-place item move mode with a persistent bottom shelf for moving across
  lists without opening a modal picker.

## Scope

The live app is iOS:

```text
platforms/ios/
```

Android, Linux, Windows, sync, and external plugins are not active product
surfaces right now. Old Android exploration is archived in git tags, but iOS is
the source of truth for behavior.

## Data Model

Lists stores data under the app-private iOS Documents folder:

```text
Documents/Lists/
  <list name>/
    .list.yml
    <item-id>.md
    <child list name>/
      .list.yml
```

The files are the source of truth. Indexes and caches are rebuildable.

## Build

Requirements:

- Xcode 27 or newer
- Swift 6.4
- iOS 27 simulator
- XcodeGen, when regenerating `Lists.xcodeproj`

```sh
cd platforms/ios
xcodegen generate
open Lists.xcodeproj
```

The generated project uses scheme `Lists`. Agent defaults currently target an
`iPhone 17 Pro` simulator through XcodeBuildMCP.

For driven simulator checks, Xcode 27 uses the Xcode IDE bridge and Device Hub.
Open `Lists.xcodeproj` in Xcode-beta and accept Apple's bridge authorization
prompt before expecting taps or typing to work. If automation stalls, retry
after pressing **Allow** in Xcode; see `AGENTS.md` for the full agent checklist.

## Test

`ListsTests` uses Swift Testing for product and data rules. XCTest remains only
for snapshot baselines.

```sh
cd platforms/ios
xcodebuild \
  -project Lists.xcodeproj \
  -scheme Lists \
  -testPlan Lists \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

The old XCUITest target was retired. Gesture-heavy behavior is verified with
focused logic tests plus driven simulator sessions.

## Project Map

- `PRODUCT-SPEC.md` - the app behavior standard.
- `docs/ARCHITECTURE.md` - short contributor map for the current codebase.
- `design/ios-design-rules.md` - visual and layout rules for iOS work.
- `AGENTS.md` - working guide for coding agents.

## Git Model

- `main` is the stable fallback branch.
- `dev` is the daily work branch.
- Agents commit and push `dev` at natural checkpoints.
- `main` only moves after an explicit maintainer checkpoint or merge decision.
- Archive tags preserve older experiments without keeping stale branches alive.

## Contributing

This project is early and product-led. The most useful contributions are focused:

- clarify product behavior in tests or docs
- fix a real iOS bug
- simplify code without changing behavior
- improve local-first storage reliability
- improve accessibility or native iOS polish

Before changing visible UI, read `design/ios-design-rules.md`. Before changing
behavior, read `PRODUCT-SPEC.md`.

## Privacy and Support

- [Privacy policy](PRIVACY.md)
- [Support and bug reports](https://github.com/SaxonBobart/lists/issues)

## License

AGPL-3.0-or-later. See `LICENSE`.
