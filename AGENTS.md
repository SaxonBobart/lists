# Lists Agent Guide

Lists is an iOS-first, local-first app for tasks, habits, notes, and events. The live implementation is `platforms/ios/` (SwiftUI, Swift 6.4, XcodeGen). Android and other platforms are parked unless Saxon explicitly reactivates them.

## Ownership and product fidelity

- Saxon owns product decisions; the agent owns technical choices. Ask only when a decision changes what users see, feel, or can do.
- The running app is the product source of truth. Preserve its appearance, interactions, capabilities, and storage compatibility unless evidence demonstrates a defect.
- Treat all existing tracked, untracked, and ignored user work as valuable. Establish a recoverable checkpoint before broad edits and never reset, discard, or overwrite it.
- Start UI-sensitive work from screenshots, runtime state, previews, or focused snapshots. Invisible cleanup must directly reduce risk or complexity in a behavior being protected.
- Match verification to risk. Do not run the full suite for an isolated edit.

## Stable environment facts

- The canonical checkout path is `/Users/saxon/Developer/Projects/lists`; the mixed-case path may resolve there. Use the canonical path for Xcode and XcodeBuildMCP.
- The active toolchain is Xcode 27 / Swift 6.4 with the iOS 27 SDK. Lists keeps an iOS 26 deployment target for compatibility; do not raise it without a product decision.
- Prefer the persistent local `xcode-proxy`, which maintains one connection to Xcode 27's first-party MCP bridge, and Apple-authored skills for project-aware builds, tests, previews, issue inspection, documentation, and UI validation. Ensure this project is open in Xcode and inspect the available tools before use.
- Use XcodeBuildMCP as an extended-automation fallback for structured simulator, device, logging, coverage, or LLDB workflows. Do not enable its `xcode-ide` workflow because that starts a second Xcode bridge and reintroduces authorization prompts. Its defaults are in `.xcodebuildmcp/config.yaml` for `platforms/ios/Lists.xcodeproj`, scheme `Lists`, and `iPhone 17 Pro`; call `session_show_defaults` before its first build, run, or test.
- If Xcode requests external-agent authorization, ask Saxon to press **Allow** for that path and continue other useful work meanwhile.
- A reported launch or gesture is not proof. Inspect the UI hierarchy before coordinate interaction and verify each state-changing action with a fresh snapshot, screenshot, log, or changed visible state. Use Computer Use only when purpose-built simulator interaction is unavailable or unreliable.

## Project and data rules

- XcodeGen owns project shape. Never hand-edit `project.pbxproj`, schemes, or `.xcconfig` files. Change `platforms/ios/project.yml`, close Xcode if necessary, and run `xcodegen generate` from `platforms/ios/` when sources, packages, or targets change.
- Bundle ID: `io.github.saxonbobart.lists`. Signing team: `LM99LGYW87`.
- User data lives in the app-private `Documents/Lists/` sandbox. Do not expose, migrate, or destructively transform it without a verified recovery path and storage-compatibility coverage.
- Keep SF Pro / SF Mono as the app-wide font system.
- `--ui-testing-reset-data` intentionally wipes the sandboxed Lists directory and is only for controlled test launches.

## Verification contracts

- Prefer focused Swift Testing and snapshot coverage in `ListsTests`. Snapshot references live beside their tests in `__Snapshots__/` and are committed.
- Use driven exploration for gesture behavior; do not reintroduce XCUITest unless explicitly requested. Protect gesture algorithms with focused logic tests.
- Every interactive element receives a lowercase, dot-separated accessibility identifier such as `floating.add`, `markdown.editor`, or `item.row.<type>.<uuid>` in the same edit that creates it.
- For Markdown editor changes, exercise representative text, selection, list, and table flows; confirm the resulting text plus visible editor state.

## Git and documentation

- Work on `dev`; keep `main` stable. Use conventional commits, never force-push, and preserve superseded experiments with `archive/...` tags.
- Commit and push `dev` at coherent checkpoints. Ask before moving `main` or creating a release tag.
- `PRODUCT-SPEC.md` records durable product behavior, `docs/ARCHITECTURE.md` maps current structure, and `design/ios-design-rules.md` records active visual rules. Keep them lean and update them only when their subject actually changes.
