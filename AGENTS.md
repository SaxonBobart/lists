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
- Use XcodeBuildMCP for structured simulator, device, logging, coverage, or LLDB workflows. Do not enable its `xcode-ide` workflow because that starts a second Xcode bridge and reintroduces authorization prompts. Read `.xcodebuildmcp/config.yaml` before the first build, run, or test. It records `platforms/ios/Lists.xcodeproj`, scheme `Lists`, and the available `iPhone 18 Pro` simulator UUID. The current CLI does not expose MCP-only session commands; pass the project, scheme and simulator UUID explicitly. Use that exact UUID for Apple device sessions too: simulator names can also match the separate QA device. Before capturing, ensure the simulator is awake and Lists is foreground; a booted device alone is not a running app. Before using saved simulator defaults after an Xcode/runtime update, list available devices and verify the UUID still exists. If it is missing, choose an available device on the intended runtime and update the local defaults; do not resolve by name alone when multiple runtimes have the same device name.
- If Xcode requests external-agent authorization, ask Saxon to press **Allow** for that path and continue other useful work meanwhile.
- A reported launch or gesture is not proof. Capture a fresh hierarchy/screenshot before interaction and verify each state change afterward. Keep input paths distinct:
  - `/opt/homebrew/bin/xcodebuildmcp` resolves to Homebrew 2.7.0. Its public `ui-automation tap` accepts element refs and delays, but does not expose `--tap-style`. It can report success without changing the UI on this iOS 27.2 stack.
  - Its bundled driver is `/opt/homebrew/Cellar/xcodebuildmcp/2.7.0/libexec/bundled/axe`, AXe 1.8.0. Raw `axe tap --id <fresh-accessibility-id> --tap-style physical --udid <simulator-uuid>` is supported. The prior setup verified it against the default path at the same selector/point; the final audit also verified current-build Search open/close on the first attempt with fresh snapshots. Rejection by the wrapper does not invalidate the driver option. The bundled driver may need the framework environment supplied by XcodeBuildMCP's `getBundledAxeEnvironment()` helper.
  - Explicit wrapper HID input is separately supported: `ui-automation touch --simulator-id <uuid> --element-ref <fresh-ref> --down --up --delay 0.12`. It activated Search in the earlier setup verification, but a later current-build pass reported success with unchanged UI. In the final audit, wrapper HID targeted Search at `(60,790)` with no change, while the raw selector resolved `(60,814)` and opened Search. This is an observed path/point difference, not proof of its deeper cause. Use fresh targeting rather than a hard-coded offset; do not treat either observation as a universal guarantee.
  - If a fresh-target retry still has no effect, the authorized Computer Use fallback against Device Hub (`com.apple.dt.Devices`) has verified Search, Settings and attachment navigation on the current build. Do not recreate a proxy or change permissions to work around a reported-success/no-change result.

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
- Keep edits local unless Saxon requests a commit or push. Ask before moving `main` or creating a release tag; never infer publishing permission from a cleanup or documentation task.
- `PRODUCT-SPEC.md` records durable product behavior, `docs/ARCHITECTURE.md` maps current structure, and `design/ios-design-rules.md` records active visual rules. Keep them lean and update them only when their subject actually changes.
