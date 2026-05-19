# Lists Agent Guide

Lists is an iOS-first, local-first app for tasks, habits, and notes. The active app lives in `platforms/ios/` and is built with SwiftUI, Swift 6.2, XcodeGen, and XcodeBuildMCP.

## Source of truth

- `PRODUCT-SPEC.md` captures product behavior. Keep it short and update it only when behavior changes.
- `docs/CURRENT.md` is the current status pointer. Keep it brief.
- `design/ios-design-rules.md` captures in-flight UI rules (item row layout, tags, sheet headers, completed-item styling, linger). Read it before changing visible iOS UI.
- iOS code is the active implementation. Android, Linux, and Windows are deferred until Saxon asks for them.
- `shared/` contains format schemas, fixtures, and cross-platform contracts. Some old files still use "reminder" wording; align them with the `Item` model when those files are next touched.

## XcodeBuildMCP defaults

- Use the installed official `xcodebuildmcp` skill before calling XcodeBuildMCP tools.
- Before the first build, run, or test action in a session, call `session_show_defaults`.
- Defaults are stored in `.xcodebuildmcp/config.yaml`:
  - project: `platforms/ios/Lists.xcodeproj`
  - scheme: `Lists`
  - simulator: `iPhone 17 Pro`
  - platform: `iOS Simulator`
- Prefer XcodeBuildMCP tools over raw `xcodebuild`, `xcrun`, or `simctl`.

## iOS project notes

- XcodeGen owns the Xcode project shape. If source files, test targets, or packages change, run `xcodegen generate` from `platforms/ios/`.
- Bundle id: `io.github.saxonbobart.lists`.
- Apple team: `LM99LGYW87` (Saxon's personal Apple ID, used for free signing + device testing). AlarmKit is deferred until a paid Developer Program account exists.
- Storage on iOS is app-private `Documents/Lists/` in the sandbox. Do not enable Files.app visibility or iCloud Drive storage without explicit approval.
- The app uses SF Pro/SF Mono. Do not add JetBrains Mono or switch the app-wide font design.

## How to verify iOS work

UI test infrastructure is currently retired — `ListsTests` and `ListsUITests` targets are deleted in the working tree and the Xcode project no longer references them. Until tests return, verify visible behavior via XcodeBuildMCP simulator runs (`build_run_sim`, `screenshot`, `snapshot_ui`) and log capture. Re-add this section with concrete patterns when the test targets come back.

Reset launch state with `--ui-testing-reset-data` in `launchArguments` so each run starts clean. Accessibility ids preserved on existing views (and to be set on new ones) for when tests return:

- `markdown.editor` — the UITextView
- `markdown.editor.cursor` — hidden element exposing the current `NSRange` as `"{location}-{length}"`
- `item.notes.expand` — opens the editor from item-detail
- `markdown.indent`, `markdown.outdent`, `markdown.dismissKeyboard`, `markdown.done` — toolbar buttons
- `floating.add` — main FAB

**Use Computer Use only for:**
- A final visual sanity check at the end of a feature (1-2 screenshots max).
- App-state inspection that simulator MCP tools physically can't reach (rare).

**Never** use Computer Use as a clicking loop. Every Computer Use screenshot costs roughly 50× more tokens than a programmatic assertion — when tests come back, default to assertions instead.

## Implementation discipline

- Work on `dev`. Keep `main` stable. Do not create extra branches or worktrees unless Saxon explicitly asks.
- Never push, merge to `main`, force-push, or run destructive git cleanup without explicit approval.
- Use Conventional Commits when committing: `feat(ios):`, `fix(ios):`, `docs:`, `chore:`.
- Tests are required for data-layer changes and important model/query behavior.

## Working style

- Saxon is the product owner and does not want jargon-heavy process docs. Lead with the practical product effect.
- If a decision has no user-visible difference, choose the conservative option and mention it briefly.
- Keep documentation lean. Remove stale planning notes instead of adding another layer of explanation.
