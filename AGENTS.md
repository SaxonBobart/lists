# Lists Agent Guide

Lists is an iOS-first, local-first app for tasks, habits, notes, and events. The active app is in `platforms/ios/` — SwiftUI, Swift 6.4, XcodeGen. iOS is the only live implementation; Android, Linux, and Windows are parked until Saxon asks. If an Android experiment exists under `platforms/android/`, treat it as parked code and do not touch it unless Saxon explicitly reactivates it.

This guide is principles plus the handful of facts you can't infer. Use your judgment within the principles — don't wait for a script.

## How to work here

- **How we work together.** Saxon owns product decisions and speaks in plain English; you own the technical ones. Decide technical questions yourself and explain what you did in plain terms — don't hand Saxon a technical fork (`struct or class?`, `which library?`) to settle. Only surface a decision when it's genuinely a *product* call — something that changes what the user sees, feels, or can do — and when you do, ask about the product effect in plain English, not the implementation.
- **Match the check to the change.** Use the smallest verification that gives real confidence, and say what you checked and what you skipped. A docs/comment change needs no build — just read the diff. A style tweak or single view needs a screenshot or one snapshot test. A data/model/storage change needs its specific test file. Only a merge to `main` or a version tag earns a full run. **Never run the whole suite (~200 tests) to verify a small isolated change** — that's the slow trap, not diligence.
- **Reach for the lightest tool first.** A SwiftUI preview render beats a full build-and-launch for a layout question; a screenshot beats a driven session for "did it move." Escalate only when the lighter tool can't answer.
- **Lead with the product effect.** Saxon is the product owner and doesn't want process jargon — say what changes for the user, in plain English. If a decision has no user-visible difference, pick the conservative option and mention it in a line.
- **Keep docs lean.** Delete stale notes instead of layering new caveats on top.
- **Conventions are part of the edit, not a follow-up.** Accessibility IDs, tests for data-layer changes, and XcodeGen regen all happen in the same change that needs them.

## Facts you can't derive (keep these current)

These are fresh, environment-specific truths the model can't infer. If one goes stale, fix it here — don't silently work around it.

### Toolchain is Xcode 27 / Swift 6.4 — what's alive and what's dead

- **Works (XcodeBuildMCP):** build, test, install, launch, `screenshot`, log capture (paths returned in `build_run_sim` output), coverage, simulator lifecycle. Prefer these tools over raw `xcodebuild`/`xcrun`/`simctl`. Call `session_show_defaults` before your first build/test/run in a session. Defaults live in `.xcodebuildmcp/config.yaml` (project `platforms/ios/Lists.xcodeproj`, scheme `Lists`, sim `iPhone 17 Pro`) and resolve by **name**, so they survive erasing/recreating sims.
- **UI automation status (updated 2026-06-23):** XcodeBuildMCP `snapshot_ui` and `screenshot` are reliable for reading the running app. `tap` can report success without changing visible state when DeviceHub's mirror is stale or desynced; verify every driven action with a fresh screenshot/snapshot before trusting it. Starting the simulator surface from DeviceHub may help, but if taps still do not mutate UI, use screenshots plus focused tests, or fall back to the `xcode` bridge / Computer Use for manual exploration. (`open_sim` / `Simulator.app` are still gone — the device window is `DeviceHub.app`, and `build_run_sim` boots the sim for you.)
- **Apple docs cross-check (2026-06-24):** Xcode 27 beta 2 ships Swift 6.4 and Apple's Device Hub docs confirm Device Hub as the simulator/physical-device interaction surface. Release-note caveats that affect agents: Device Hub does not send two-finger touches, Accessibility Inspector cannot inspect simulator elements, and parallel simulator tests may keep running even when devices are not visible in Device Hub. Prefer XcodeBuildMCP snapshots/screenshots plus focused tests for evidence.
- **Full-res screenshots:** `xcrun simctl io <udid> screenshot out.png` writes a full-resolution PNG to disk (XcodeBuildMCP's `screenshot` returns a downscaled JPEG — fine for a quick look, not for design assets). Set appearance with `xcrun simctl ui <udid> appearance light|dark`.
- **`xcode` bridge fallback** — the `xcrun mcpbridge` DeviceInteraction loop (`DeviceInteractionStartSession` → `InstallAndRun` → `Synthesize` → `EndSession`) still exists for IDE-context driving when the bridge is needed; it reads the running Xcode app, so the workspace must be open. Prefer the XcodeBuildMCP tools above for plain UI driving. **Always read a hierarchy before any coordinate tap — never guess coordinates from a screenshot.**

### Two MCP servers, split by job

- **XcodeBuildMCP** — builds, tests, simulator, screenshots (above).
- **xcode (`xcrun mcpbridge`)** — IDE-context work the build driver can't do: SwiftUI preview rendering, Issue Navigator diagnostics, `DocumentationSearch` (Apple docs + WWDC transcripts in one query), and the DeviceInteraction UI driving above.

### XcodeGen owns the project shape

Never hand-edit `platforms/ios/Lists.xcodeproj/project.pbxproj`, the `*.xcscheme` files, or `.xcconfig` files. When sources, packages, or test targets change, edit `platforms/ios/project.yml` then run `xcodegen generate` from `platforms/ios/` — **close Xcode first**, or the bridge holds the project file open and generation breaks.

### Project specifics

- Bundle id `io.github.saxonbobart.lists`; Apple team `LM99LGYW87` (free signing only; AlarmKit-style urgent alarms require a paid Developer Program account before they can become a current iOS surface).
- iOS storage is app-private `Documents/Lists/` in the sandbox — don't expose it to Files.app or iCloud Drive without explicit approval.
- Fonts are SF Pro / SF Mono — don't add other fonts or change the app-wide font design.
- Reset per-launch state with `--ui-testing-reset-data` in `launchArguments` (`ListsApp.swift` wipes the on-disk Lists directory when that arg is present).

## Verifying UI work

Two layers, each with one job — pick the one that fits, don't mix them:

1. **Snapshot + unit tests (`ListsTests`, Swift Testing, swift-snapshot-testing)** — visual regression at the SwiftUI view level plus all unit coverage, no simulator launch. XCTest remains only for snapshot baselines. Catches silent layout changes. Run with `/test ListsTests/SnapshotTests`; add coverage with `/snapshot <ViewName>`. Reference images live in `__Snapshots__/` next to each test and are committed; a failing snapshot's diff image surfaces via the xcresult hook path.
2. **Driven exploration (XcodeBuildMCP runtime UI tools)** — for iterating on a feature live in-session. Never commit driven gesture sequences as tests.

XCUITest was retired 2026-06-13 — it rotted against redesigns and never reliably verified real gestures (it's in git history). Don't reintroduce it without an explicit ask. Verify gestures by unit-testing their logic (reorder index math, swipe thresholds) plus a driven session.

**Accessibility IDs** follow `<screen>.<element>[.<id>]` — lowercase, dot-separated. Examples in code: `floating.add`, `item.row.<type>.<uuid>`, `item.notes.expand`, `markdown.editor`, `sidebar.list.<listId>`, `quickcapture.save`. Every interactive element gets one, added in the same edit that creates the view.

Slash commands shortcut the common actions: `/build`, `/test`, `/verify-screen`, `/snapshot`, `/tail-logs`.

## Git

Agents follow `GIT-GUIDE.md` for the full plain-English policy. In short: work on `dev`, keep `main` stable, commit at natural checkpoints and push `dev` as the off-site backup, then tell Saxon in one plain sentence what was saved. Move `main` or tag a version only after telling Saxon what's moving and getting an OK. Conventional Commits (`feat(ios):`, `fix(ios):`, `docs:`, `chore:`). Never force-push or rewrite history.

## Source of truth

- `PRODUCT-SPEC.md` — product behavior. Keep it short; update only when behavior changes.
- `docs/APP-STANDARD.md` — platform-neutral behavior standard extracted from the iOS source of truth. Use it when translating Lists to Android or deciding whether a UI/code change matches the product.
- `docs/CURRENT.md` — current status pointer. Keep it brief.
- `design/ios-design-rules.md` — in-flight UI rules (row layout, tags, sheet headers, completed-item styling). Read it before changing visible iOS UI.
- `JOURNAL.md` — Saxon's plain-English log and roadmap. Read it for context on what Saxon cares about; don't edit it unless he asks.
