# Lists Agent Guide

Lists is an iOS-first, local-first app for tasks, notes, and events. The live implementation is `platforms/ios/` (SwiftUI, Swift 6.4, XcodeGen). Android and other platforms are parked unless Saxon explicitly reactivates them.

## Ownership and product fidelity

- Saxon owns product decisions; the agent owns technical choices. Ask only when a decision changes what users see, feel, or can do.
- The running app is the product source of truth. Preserve its appearance, interactions, capabilities, and storage compatibility unless evidence demonstrates a defect.
- Treat all existing tracked, untracked, and ignored user work as valuable. Establish a recoverable checkpoint before broad edits and never reset, discard, or overwrite it.
- Start UI-sensitive work from screenshots, runtime state, previews, or focused snapshots. Invisible cleanup must directly reduce risk or complexity in a behavior being protected.
- Match verification to risk. Do not run the full suite for an isolated edit.

## Stable environment facts

- The canonical checkout path is `/Users/saxon/Developer/Projects/lists`; the mixed-case path may resolve there. Use the canonical path for Xcode and XcodeBuildMCP.
- The active toolchain is Xcode 27 / Swift 6.4 with the iOS 27 SDK. Lists keeps an iOS 26 deployment target for compatibility; do not raise it without a product decision.
- Use the installed XcodeBuildMCP and Apple-authored skills for builds, tests, diagnostics, and UI validation. Open the canonical project in Xcode for GUI diagnosis. No native Xcode MCP connector is currently configured; configuring one requires separate user authorization.
- Use XcodeBuildMCP for structured simulator, device, logging, coverage, or LLDB workflows. Do not enable its `xcode-ide` workflow because that starts a second Xcode bridge and reintroduces authorization prompts. Read `.xcodebuildmcp/config.yaml` before the first build, run, or test. It records `platforms/ios/Lists.xcodeproj`, scheme `Lists`, and the available `iPhone 18 Pro` simulator UUID. The CLI does not expose MCP-only session commands; pass the project, scheme and simulator UUID explicitly. When MCP session tools are available, call `session_show_defaults`, compare them with this file, and correct stale session defaults before building. A live MCP process can inherit configuration from an older worktree even when canonical configuration is correct. Keep this machine's simulator UUID as the sole saved selector: a saved `simulatorName` can asynchronously re-resolve to the wrong runtime even with `useLatestOS`. Clear `simulatorName` before setting the exact UUID. MCP may backfill the name for display; keep it out of the saved config and pass the UUID explicitly to build/test/install calls. Use that exact UUID for Apple device sessions too: simulator names can also match the separate QA device. Before capturing, ensure the simulator is awake and Lists is foreground; a booted device alone is not a running app. Before using saved simulator defaults after an Xcode/runtime update, list available devices and verify the UUID still exists. If it is missing, choose an available device on the intended runtime and update the local defaults; do not resolve by name alone when multiple runtimes have the same device name.
- If Xcode requests external-agent authorization, ask Saxon to press **Allow** for that path and continue other useful work meanwhile.
- A reported launch or gesture is not proof. Capture a fresh hierarchy/screenshot before interaction and verify the resulting visible state afterward.
- In T3, use `device_list`, then `device_open` with host and exact device IDs, and the returned `agent-device` command for app launches, snapshots and all input. Use `device_screenshot` to inspect the screen. These host rules supersede historical AXe/Computer Use workarounds. Do not drive T3 devices through XcodeBuildMCP input, raw AXe, simctl, or another session. XcodeBuildMCP remains appropriate for builds, installs, logs and tests.
- If host device tooling fails, quote the exact error and follow its advice once. If it still fails, report the blocker; do not recreate connectors or change privacy permissions.

## Project and data rules

- XcodeGen owns project shape. Never hand-edit `project.pbxproj`, schemes, or `.xcconfig` files. Change `platforms/ios/project.yml`, close Xcode if necessary, and run `xcodegen generate` from `platforms/ios/` when sources, packages, or targets change.
- Bundle ID: `io.github.saxonbobart.lists`. Signing team: `LM99LGYW87`.
- User data lives in the app-private `Documents/Lists/` sandbox. Do not expose, migrate, or destructively transform it without a verified recovery path and storage-compatibility coverage.
- Keep SF Pro / SF Mono as the app-wide font system.
- `--ui-testing-reset-data` intentionally wipes the sandboxed Lists directory and is only for controlled test launches. Preserve useful isolated DEBUG sample-library fixtures; do not reset the ordinary library for screenshots.

## Verification contracts

- Prefer focused Swift Testing and snapshot coverage in `ListsTests`. Snapshot references live beside their tests in `__Snapshots__/` and are committed.
- Use driven exploration for gesture behavior; do not reintroduce XCUITest unless explicitly requested. Protect gesture algorithms with focused logic tests.
- Every interactive element receives a lowercase, dot-separated accessibility identifier such as `floating.add`, `markdown.editor`, or `item.row.<type>.<uuid>` in the same edit that creates it.
- For Markdown editor changes, exercise representative text, selection, list, and table flows; confirm the resulting text plus visible editor state.

## Git and documentation

- Work on `dev`; keep `main` stable. Use conventional commits, never force-push, and preserve superseded experiments with `archive/...` tags.
- Saxon authorizes automatic GitHub checkpoints during app work: after a coherent change and appropriate verification, review the diff, commit only the files owned by the task, and push the current development branch without asking again. Use `python3 scripts/agent-checkpoint.py --message "<conventional commit>" -- <explicit paths>`. A conversational/read-only turn with no changes needs no commit. If verification fails, fix it first or explicitly mark an intentionally preserved incomplete checkpoint; never claim checks passed.
- On `dev`, push to `origin/dev`. On a task/worktree branch, push that branch and create or update one draft PR targeting `dev` using `gh`; describe behavior, validation and remaining limits. Link the PR through the host tool when available. Do not create duplicate PRs. Never automatically merge, push `main`, create release tags, distribute builds, or force-push.
- This repository is public. Inspect staged changes for credentials, personal data, exports and unrelated work before publishing. Never stage everything blindly. If unrelated files are already staged, stop the checkpoint helper and preserve the index for their owner.
- A rejected push is not permission to reset/rebase/discard work. Fetch and inspect divergence; reconcile safely or report the concrete blocker while preserving the local commit.
- Before editing, compare this checkout and canonical dev. Build and verify the checkout being changed using an explicit project path. Never publish an old worktree as if it were the current canonical app.
- `PRODUCT-SPEC.md` records durable product behavior, `docs/ARCHITECTURE.md` maps current structure, and `design/ios-design-rules.md` records active visual rules. Keep them lean and update them only when their subject actually changes.
