# Current Status

## Active Work

Work happens on `dev`. See `GIT-GUIDE.md` for the branch model (`dev` = daily work, `main` = stable checkpoints). Milestone history is in `docs/CHANGELOG.md`.

## Environment: Xcode 27 beta (since 2026-06-10)

Saxon's devices and daily work are on Xcode 27 / OS 27 betas. No rollback planned.

- **UI driving:** Use Apple's native agent loop (`xcrun mcpbridge`, the `xcode` MCP): `DeviceInteractionStartSession` → `DeviceInteractionInstallAndRun` → `DeviceInteractionSynthesize` → `DeviceInteractionEndSession`. Verified working; each Synthesize call returns screenshot + UI hierarchy + app log. Full notes in `docs/research/xcode-27-agentic-testing.md`.
- **XcodeBuildMCP (v2.6.2):** Build / test / install / launch / `screenshot` work. The AXe UI tools (`snapshot_ui`, `tap`, `swipe`, `gesture`, `type_text`) are broken under Xcode 27 — drive UI via the xcode MCP's DeviceInteraction instead.
- **Simulators:** iOS 27 runtimes only. Session default (iPhone 17 Pro) points at iOS 27.0. Simulator.app replaced by Device Hub.
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

- `ItemDocumentView.swift`, `ListDetailCollectionView.swift`, and `QuickCaptureSheet.swift` are large files. Not a bug, but extraction into focused helpers is a future cleanup option.
- Two snapshot baselines may need re-recording after the look-iteration round (cosmetic only — run `ListsTests/SnapshotTests` and update failing baselines with `record: true`).

## Constraints

- Bundle id: `io.github.saxonbobart.lists`
- Apple team: `LM99LGYW87` (Saxon's personal Apple ID, free signing only)
- AlarmKit deferred until a paid Apple Developer Program account exists
- iOS data stays app-private in `Documents/Lists/` — no Files.app visibility, no iCloud
- Android code removed from repo (experiment; code in git history). Android, Linux, Windows, and sync remain deferred until explicitly requested.
