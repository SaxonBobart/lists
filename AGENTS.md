# Lists Agent Guide

Lists is an iOS-first, local-first app for tasks, habits, and notes. The active app lives in `platforms/ios/` and is built with SwiftUI, Swift 6.2, XcodeGen, and XcodeBuildMCP.

## Source of truth

- `PRODUCT-SPEC.md` captures product behavior. Keep it short and update it only when behavior changes.
- `docs/CURRENT.md` is the current status pointer. Keep it brief.
- `design/ios-design-rules.md` captures in-flight UI rules (item row layout, tags, sheet headers, completed-item styling, linger). Read it before changing visible iOS UI.
- iOS code is the only active implementation. The Android experiment was removed from the repo (code preserved in git history). Android, Linux, and Windows remain deferred until Saxon asks for them.

## MCP Tools

This project uses two complementary MCP servers, both at user scope.

### XcodeBuildMCP — primary build & simulator driver

Use for builds, tests, simulator lifecycle (`boot_sim`, `list_sims`), install/launch/stop (`build_run_sim`, `install_app_sim`, `launch_app_sim`, `stop_app_sim`), `screenshot`, log capture (build log + runtime log paths are returned in `build_run_sim` output), test runs (`test_sim`), and coverage (`get_coverage_report`). (`open_sim` and `snapshot_ui` are dead under Xcode 27 — see status note below.)

- Use XcodeBuildMCP tools before falling back to raw `xcodebuild`, `xcrun`, or `simctl`.
- Before the first build, run, or test action in a session, call `session_show_defaults`.
- Defaults live in `.xcodebuildmcp/config.yaml`:
  - project: `platforms/ios/Lists.xcodeproj`
  - scheme: `Lists`
  - simulator: `iPhone 17 Pro`
  - platform: `iOS Simulator`

**Coordinate rule:** Always read a UI hierarchy before any coordinate-based interaction — never guess coordinates from a screenshot. Under Xcode 27 the hierarchy comes from `DeviceInteractionSynthesize` (frames, center points, accessibility IDs like `floating.add`); screenshots are for human-readable verification only.

**Xcode 27 status (verified 2026-06-11):** build / test / install / launch / `screenshot` work. The AXe-based UI tools (`snapshot_ui`, `tap`, `swipe`, `gesture`, `type_text`) are broken under Xcode 27 — SimulatorKit.framework moved and AXe hardcodes the old path (getsentry/XcodeBuildMCP#446, closed not-planned). Drive UI via the xcode MCP's DeviceInteraction tools instead (see layer 3 below).

**Simulator GUI = Device Hub (not Simulator.app).** Xcode 27 removed `Simulator.app`; the device window is `DeviceHub.app`. XcodeBuildMCP's `open_sim` still hunts for the old `Simulator.app` and always fails ("Unable to find application named 'Simulator'") — that's a stale tool, not a broken install. `build_run_sim` / `test_sim` / `screenshot` all work headlessly without it. To show the window for a human, open Device Hub directly: `open "$(xcode-select -p)/../Contents/Applications/DeviceHub.app"`. The sim default resolves by **name** (`iPhone 17 Pro`), not a pinned UDID, so it survives erasing/recreating sims.

### xcode (xcrun mcpbridge) — IDE capabilities + UI driving under Xcode 27

Use for things that need the IDE's own context: SwiftUI preview rendering, Issue Navigator diagnostics, `DocumentationSearch` (Apple docs + WWDC transcripts in a single tool), snippet execution — and, since Xcode 27, **simulator UI driving** via the DeviceInteraction tools.

- The bridge reads its context from the running Xcode app — the Lists workspace must be open for it to work.
- For Apple documentation lookups, prefer `DocumentationSearch` over the older `sosumi` skill; it returns WWDC transcripts in the same query.
- UI-driving lifecycle (verified on Lists 2026-06-11): `DeviceInteractionStartSession` (early — boots the sim) → `DeviceInteractionInstallAndRun` (after each code change) → `DeviceInteractionSynthesize` (tap/swipe/type/capture; each call returns screenshot + hierarchy with center coordinates and accessibility ids + cumulative app log) → `DeviceInteractionEndSession` (always — open sessions are expensive). Run the Synthesize loop in a subagent following Apple's `device-interaction` skill (`xcrun mcpbridge run-agent skills export --output-dir <absolute path>` to get it).

## iOS project notes

- XcodeGen owns the Xcode project shape. If source files, test targets, or packages change, run `xcodegen generate` from `platforms/ios/`.
- Bundle id: `io.github.saxonbobart.lists`.
- Apple team: `LM99LGYW87` (Saxon's personal Apple ID, used for free signing + device testing). AlarmKit is deferred until a paid Developer Program account exists.
- Storage on iOS is app-private `Documents/Lists/` in the sandbox. Do not enable Files.app visibility or iCloud Drive storage without explicit approval.
- The app uses SF Pro/SF Mono. Do not add JetBrains Mono or switch the app-wide font design.

## How to verify iOS work

**Proportional verification rule:** Use the narrowest check that gives confidence. Do not run all ~198 tests for docs-only, style, or tiny isolated changes. Always state what was checked and what was intentionally skipped.

| Change size | Minimum check |
|---|---|
| Docs / comments only | No build needed — inspect the diff |
| Style tweak / single view | Screenshot or targeted snapshot test if one exists |
| Single component change | Run only the relevant snapshot or unit test class |
| Data / model / storage / recurrence | Run the specific test file first |
| Shared behavior change | Targeted tests, then the relevant target |
| Before merging to `main` or tagging a version | Full appropriate batch |

Testing has three layers, each with one job. Pick the layer that fits — don't mix them.

### 1. Snapshot tests (`ListsTests`, swift-snapshot-testing)

Visual regression at the SwiftUI view level. No simulator launch. Catches "did the layout silently change". Run via `/test ListsTests/SnapshotTests`. Add coverage with `/snapshot <ViewName>`.

Reference images live in `__Snapshots__/` directories next to each test file and are committed. If a snapshot test fails, the failure diff image is at `<DerivedData>/Logs/Test/<run>/Attachments/...` — open via the hook-surfaced xcresult path.

### 2. XCUITest gesture tests (`ListsUITests`)

End-to-end flows and gestures: drag-to-reorder, swipe-to-delete, custom DragGesture, sheet presentation, EditMode. Run via `/test ListsUITests`. Write via `/gesture-test <feature>`, which dispatches the `gesture-test-author` subagent — never write these by hand.

**Reality check (Saxon, 2026-06):** in practice this layer has never reliably verified real gesture behavior — it works for static/boilerplate flows, but drag/reorder/complex-list interactions had to be verified by manually driving the app and screenshotting (i.e., layer 3). Treat the existing gesture tests as smoke coverage, not as the source of truth for gestures. Do not add new gesture XCUITests without explicit approval; prefer unit-testing the gesture logic (reorder index math, swipe thresholds) and verifying interactions via a driven session. The planned direction is to retire most of this layer in favor of agent-driven verification (Xcode 27's native agent loop at GM, XcodeBuildMCP today).

**Status (verified 2026-06-13): 21 of 30 fail on the iOS 27 beta — not app bugs.** Two causes: (1) iOS 27 changed accessibility element resolution, so identifiers set on UICollectionView cells (e.g. `sidebar.list.<id>` in `SidebarListsCollectionView`) no longer match `app.buttons[...]` queries ("legacy vs modern attribute" mismatch in the logs); (2) some tests reference controls removed in later redesigns (`sidebar.reorder.toggle`, parts of the old markdown-editor chrome). The app renders and behaves correctly — `ListsTests` (199 unit + snapshot) is the green safety net. Don't burn time re-greening this layer ad hoc; it needs a deliberate retire-or-rewrite decision with Saxon.

The subagent owns the stability patterns (XCUICoordinate, accessibility ids only, bounded waits, no thenHoldForDuration). Don't relax them.

### 3. Driven exploration (Apple DeviceInteraction loop; XcodeBuildMCP AXe on Xcode 26)

Iterating on a feature in-session. Under Xcode 27, drive UI with the xcode MCP's `DeviceInteractionSynthesize` loop (see the xcode MCP section above) — XcodeBuildMCP's `snapshot_ui`/`tap`/`swipe`/`gesture` are broken on the beta. Build/launch via XcodeBuildMCP still; `/verify-screen` still works for screenshots but its `snapshot_ui` half fails. Never commit driven gesture sequences as tests.

**Coordinate rule:** every coordinate-based interaction is preceded by a hierarchy read (Synthesize with an empty `interactionCommand`, or the hierarchy returned by the previous call) and taps at `center:` coordinates or accessibility-id-matched elements. Never guess from screenshots.

### Accessibility-id convention

`<screen>.<element>[.<id>]`, dot-separated, lowercase. Examples currently in code:

- `floating.add` — main FAB
- `item.row.<type>.<uuid>` — item rows (deterministic UUIDs; see SampleData.swift)
- `item.notes.expand` — opens markdown editor from any detail sheet
- `markdown.editor`, `markdown.editor.cursor`, `markdown.modePicker`, `markdown.done`, etc.
- `sidebar.list.<listId>`, `sidebar.smartlist.<smartListId>`, `sidebar.reorder.toggle`
- `quickcapture.title`, `quickcapture.save`, `quickcapture.cancel`

Every interactive SwiftUI element gets an identifier. When adding new views, add the identifier in the same edit — not as a follow-up.

### Build / test commands

All via XcodeBuildMCP (the `xcode` MCP is for IDE-context tools like SwiftUI previews and DocumentationSearch). Slash commands shortcut the common ones: `/build`, `/test`, `/verify-screen`, `/gesture-test`, `/snapshot`, `/tail-logs`.

Reset state per launch with `--ui-testing-reset-data` in `launchArguments` — `ListsApp.swift` removes the on-disk Lists directory when that arg is present.

### What never to edit by hand

- `platforms/ios/Lists.xcodeproj/project.pbxproj` — generated by XcodeGen.
- `platforms/ios/Lists.xcodeproj/xcshareddata/xcschemes/*.xcscheme` — generated by XcodeGen.
- `.xcconfig` files — none exist; if they appear, route through `project.yml`.

When source files, packages, or test targets change, edit `platforms/ios/project.yml` then run `xcodegen generate` from `platforms/ios/`. Close Xcode first; the xcrun mcpbridge MCP needs Xcode open in normal use but breaks if Xcode is holding the project file open during generation.

### Computer Use

Reserved for final visual sanity checks (1-2 screenshots max per session) and rare app-state inspection MCP can't reach. Never use as a clicking loop.

## Implementation discipline

- Work on `dev`. Keep `main` stable. Do not create extra branches or worktrees unless Saxon explicitly asks.
- **Claude owns git (Saxon, 2026-06-13).** Saxon doesn't drive git and doesn't want approval round-trips on the mechanics. Commit on `dev` at natural checkpoints and push `dev` to GitHub as the off-site backup — then tell Saxon in one plain-English sentence what was saved and why. No status/message/approve ceremony.
- `main` is the safe-fallback checkpoint. Fast-forward `main` (or create a version tag) only after telling Saxon in plain English what's moving and getting an OK.
- Never force-push, rewrite history, or run destructive git cleanup.
- Use Conventional Commits when committing: `feat(ios):`, `fix(ios):`, `docs:`, `chore:`.
- Tests are required for data-layer changes and important model/query behavior.

## Working style

- Saxon is the product owner and does not want jargon-heavy process docs. Lead with the practical product effect.
- If a decision has no user-visible difference, choose the conservative option and mention it briefly.
- Keep documentation lean. Remove stale planning notes instead of adding another layer of explanation.
