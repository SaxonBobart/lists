# Current Status

## Active Work

Work happens on `dev`. See `GIT-GUIDE.md` for the branch model (`dev` = daily work, `main` = stable checkpoints). Milestone history is in `docs/CHANGELOG.md`.

## Environment: Xcode 27 beta (since 2026-06-10)

Saxon's devices and daily work are on Xcode 27 / OS 27 betas. No rollback planned.

- **UI driving:** Use Apple's native agent loop (`xcrun mcpbridge`, the `xcode` MCP): `DeviceInteractionStartSession` → `DeviceInteractionInstallAndRun` → `DeviceInteractionSynthesize` → `DeviceInteractionEndSession`. Verified working; each Synthesize call returns screenshot + UI hierarchy + app log. Full notes in `docs/research/xcode-27-agentic-testing.md`.
- **XcodeBuildMCP (v2.6.2):** Build / test / install / launch / `screenshot` work. The AXe UI tools (`snapshot_ui`, `tap`, `swipe`, `gesture`, `type_text`) are broken under Xcode 27 — drive UI via the xcode MCP's DeviceInteraction instead.
- **Simulators:** iOS 27 runtimes only. Default resolves by **name** (`iPhone 17 Pro`) — no pinned UDID, so it survives erasing/recreating sims. Simulator.app is gone; the GUI is `DeviceHub.app` (XcodeBuildMCP's `open_sim` is dead — open Device Hub directly, or just run headless). See `AGENTS.md` → MCP Tools.
- Gesture XCUITests are frozen smoke coverage — verify interactions via a driven session, not tests.

## What Exists

- iOS app: `platforms/ios/Lists.xcodeproj` (SwiftUI, Swift 6.2, XcodeGen)
- XcodeGen spec: `platforms/ios/project.yml`
- XcodeBuildMCP defaults: `.xcodebuildmcp/config.yaml`
- Core models, file storage, frontmatter codec, sample data, smart lists, tags, reminders, notification scheduling
- Item types: **task, habit, note, event** (events always have start + end; end is optional on disk for backward-compat only; completable is opt-in)
- Screens: sidebar, today, smart lists, list detail, item detail (document view), quick capture, habits, search, settings, recently deleted, tags, thread view
- Test targets: `ListsTests` (198 tests; snapshot baselines recorded on iOS 27 runtime), `ListsUITests` (XCUITest scaffolding, 8 classes)
- Backend audit fully closed 2026-06-11 — all 18 findings fixed. See `docs/archive/audit/` for history.

## Next Work

- **Calendar view over Scheduled** and **iCal import/export/sync** — event fields are already calendar-shaped for it.
- KaTeX math + mermaid rendering in `MarkdownBodyView` (WKWebView bridges).
- Tappable wikilinks.
- Driven-session verification of the 2026-06-11 document view + 2026-06-12 section/event batch (pending since Saxon is iterating on look first).

## Known Risks

- `ListDetailCollectionView.swift` (~2,281 lines) is the largest file. The 2026-06-13 consolidation pass trimmed `ItemDocumentView.swift` (UIKit bridges → `DocumentEditorBridges.swift` + `DocumentQuickDetailsBar.swift`) and relocated shared types out of `QuickCaptureSheet.swift` (`RepeatPreset`/`EarlyReminderPreset` → `Core/`), but left `ListDetailCollectionView` intact on purpose — its bulk is one extension over the controller's private state and can't be split mechanically. Not a bug.
- ~~Snapshot baseline drift~~ fixed 2026-06-13: `SnapshotEnvironment` now pins light mode (baselines used to inherit the sim's appearance setting), and all 49 baselines were re-recorded on the iOS 27 runtime. Full `ListsTests` suite green (199/199).

## Constraints

- Bundle id: `io.github.saxonbobart.lists`
- Apple team: `LM99LGYW87` (Saxon's personal Apple ID, free signing only)
- AlarmKit deferred until a paid Apple Developer Program account exists
- iOS data stays app-private in `Documents/Lists/` — no Files.app visibility, no iCloud
- Android code removed from repo (experiment; code in git history). Android, Linux, Windows, and sync remain deferred until explicitly requested.
