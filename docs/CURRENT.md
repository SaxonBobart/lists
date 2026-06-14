# Current Status

Work happens on `dev`. Git model: `GIT-GUIDE.md`. Milestone history: `docs/CHANGELOG.md`. Plain-English roadmap: `JOURNAL.md`.

## Environment: Xcode 27 / iOS 27 beta (since 2026-06-10)

Saxon's devices and daily work are on the 27 betas — no rollback planned. The full tool reality (what works, what's dead, how to drive UI) is in `AGENTS.md` → "Facts you can't derive." Short version: build / test / install / launch / `screenshot` work via XcodeBuildMCP; the AXe UI tools and `open_sim` are dead on Xcode 27, so drive UI via the `xcode` MCP's DeviceInteraction loop. Sims are iOS 27 runtimes, resolved by name (`iPhone 17 Pro`).

## What exists

- iOS app: `platforms/ios/Lists.xcodeproj` (SwiftUI, Swift 6.2, XcodeGen; spec in `project.yml`).
- Core: models, file storage, frontmatter codec, sample data, smart lists, tags, reminders, notification scheduling.
- Item types: **task, habit, note, event** (events always have start + end; completable is opt-in).
- Screens: sidebar, today, smart lists, list detail, item document view, quick capture, habits, search, settings, recently deleted, tags, thread view.
- Tests: `ListsTests` (199, green; snapshot baselines pinned to light mode, recorded 2026-06-13 on iOS 27). XCUITest layer retired 2026-06-13 — gestures verified by unit tests on their logic + driven sessions.

## Known risks

- `ListDetailCollectionView.swift` (~2,281 lines) is the largest file. Its bulk is one extension over the controller's private state and can't be split mechanically — intentional, not a bug. The 2026-06-13 pass trimmed `ItemDocumentView.swift` (UIKit bridges → `DocumentEditorBridges.swift` + `DocumentQuickDetailsBar.swift`) and relocated shared types to `Core/`, but left this file intact on purpose.

## Constraints

- Bundle id `io.github.saxonbobart.lists`; Apple team `LM99LGYW87` (personal Apple ID, free signing only).
- AlarmKit deferred until a paid Apple Developer Program account exists.
- iOS data stays app-private in `Documents/Lists/` — no Files.app visibility, no iCloud.
- Android, Linux, Windows, and sync are deferred until explicitly requested.
