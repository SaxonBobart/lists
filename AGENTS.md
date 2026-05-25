# Lists Agent Guide

Lists is an iOS-first, local-first app for tasks, habits, and notes. The active app lives in `platforms/ios/` and is built with SwiftUI, Swift 6.2, XcodeGen, and XcodeBuildMCP.

## Source of truth

- `PRODUCT-SPEC.md` captures product behavior. Keep it short and update it only when behavior changes.
- `docs/CURRENT.md` is the current status pointer. Keep it brief.
- `design/ios-design-rules.md` captures in-flight UI rules (item row layout, tags, sheet headers, completed-item styling, linger). Read it before changing visible iOS UI.
- iOS code is the active implementation. Android, Linux, and Windows are deferred until Saxon asks for them.

## MCP Tools

This project uses two complementary MCP servers, both at user scope.

### XcodeBuildMCP — primary build & simulator driver

Use for builds, tests, simulator lifecycle (`boot_sim`, `open_sim`, `list_sims`), install/launch/stop (`build_run_sim`, `install_app_sim`, `launch_app_sim`, `stop_app_sim`), view-hierarchy inspection (`snapshot_ui`), `screenshot`, log capture (build log + runtime log paths are returned in `build_run_sim` output), test runs (`test_sim`), and coverage (`get_coverage_report`).

- Use XcodeBuildMCP tools before falling back to raw `xcodebuild`, `xcrun`, or `simctl`.
- Before the first build, run, or test action in a session, call `session_show_defaults`.
- Defaults live in `.xcodebuildmcp/config.yaml`:
  - project: `platforms/ios/Lists.xcodeproj`
  - scheme: `Lists`
  - simulator: `iPhone 17 Pro`
  - platform: `iOS Simulator`

**Coordinate rule:** Always call `snapshot_ui` before any coordinate-based interaction. Never guess coordinates from a screenshot — `snapshot_ui` returns exact `AXFrame` rectangles plus accessibility IDs (e.g. `floating.add`); screenshots are for human-readable verification only.

Tap / swipe / touch / type tools are **not** enabled in the default XcodeBuildMCP workflow. If you need to drive UI, enable the UI Automation workflow per https://xcodebuildmcp.com/docs/configuration; until then, drive launch state via `launchArgs` (e.g. `--ui-testing-reset-data`) and verify via `snapshot_ui` + `screenshot`.

### xcode (xcrun mcpbridge) — IDE-only capabilities

Use for things that need the IDE's own context: SwiftUI preview rendering, Issue Navigator diagnostics, `DocumentationSearch` (Apple docs + WWDC transcripts in a single tool), and snippet execution in the context of an open source file.

- The bridge reads its context from the running Xcode app — the Lists workspace must be open for it to work.
- For Apple documentation lookups, prefer `DocumentationSearch` over the older `sosumi` skill; it returns WWDC transcripts in the same query.

## iOS project notes

- XcodeGen owns the Xcode project shape. If source files, test targets, or packages change, run `xcodegen generate` from `platforms/ios/`.
- Bundle id: `io.github.saxonbobart.lists`.
- Apple team: `LM99LGYW87` (Saxon's personal Apple ID, used for free signing + device testing). AlarmKit is deferred until a paid Developer Program account exists.
- Storage on iOS is app-private `Documents/Lists/` in the sandbox. Do not enable Files.app visibility or iCloud Drive storage without explicit approval.
- The app uses SF Pro/SF Mono. Do not add JetBrains Mono or switch the app-wide font design.

## How to verify iOS work

Testing has three layers, each with one job. Pick the layer that fits — don't mix them.

### 1. Snapshot tests (`ListsTests`, swift-snapshot-testing)

Visual regression at the SwiftUI view level. No simulator launch. Catches "did the layout silently change". Run via `/test ListsTests/SnapshotTests`. Add coverage with `/snapshot <ViewName>`.

Reference images live in `__Snapshots__/` directories next to each test file and are committed. If a snapshot test fails, the failure diff image is at `<DerivedData>/Logs/Test/<run>/Attachments/...` — open via the hook-surfaced xcresult path.

### 2. XCUITest gesture tests (`ListsUITests`)

End-to-end flows and gestures: drag-to-reorder, swipe-to-delete, custom DragGesture, sheet presentation, EditMode. Run via `/test ListsUITests`. Write via `/gesture-test <feature>`, which dispatches the `gesture-test-author` subagent — never write these by hand.

The subagent owns the stability patterns (XCUICoordinate, accessibility ids only, bounded waits, no thenHoldForDuration). Don't relax them.

### 3. XcodeBuildMCP + AXe for exploration

`snapshot_ui`, `tap`, `swipe`, `gesture` for iterating on a feature in-session. Read-only verification uses `/verify-screen`. Never commit MCP-driven gesture sequences as tests.

**Coordinate rule:** Every coordinate-based MCP tool (`tap`, `swipe`, `gesture`, `long_press`, `touch`) is preceded by `snapshot_ui` to get `AXFrame` rectangles and accessibility ids. A PreToolUse hook reminds you; the gesture-test-author subagent enforces it.

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
- Never push, merge to `main`, force-push, or run destructive git cleanup without explicit approval.
- Use Conventional Commits when committing: `feat(ios):`, `fix(ios):`, `docs:`, `chore:`.
- Tests are required for data-layer changes and important model/query behavior.

## Working style

- Saxon is the product owner and does not want jargon-heavy process docs. Lead with the practical product effect.
- If a decision has no user-visible difference, choose the conservative option and mention it briefly.
- Keep documentation lean. Remove stale planning notes instead of adding another layer of explanation.
