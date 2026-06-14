# Lists Agent Guide

Lists is an iOS-first, local-first app for tasks, habits, and notes. The active app is in `platforms/ios/` — SwiftUI, Swift 6.2, XcodeGen. iOS is the only live implementation; Android, Linux, and Windows are deferred until Saxon asks (old Android code lives in git history).

This guide is principles plus the handful of facts you can't infer. Use your judgment within the principles — don't wait for a script.

## How to work here

- **Match the check to the change.** Use the smallest verification that gives real confidence, and say what you checked and what you skipped. A docs/comment change needs no build — just read the diff. A style tweak or single view needs a screenshot or one snapshot test. A data/model/storage change needs its specific test file. Only a merge to `main` or a version tag earns a full run. **Never run the whole suite (~199 tests) to verify a small isolated change** — that's the slow trap, not diligence.
- **Reach for the lightest tool first.** A SwiftUI preview render beats a full build-and-launch for a layout question; a screenshot beats a driven session for "did it move." Escalate only when the lighter tool can't answer.
- **Lead with the product effect.** Saxon is the product owner and doesn't want process jargon — say what changes for the user, in plain English. If a decision has no user-visible difference, pick the conservative option and mention it in a line.
- **Keep docs lean.** Delete stale notes instead of layering new caveats on top.
- **Conventions are part of the edit, not a follow-up.** Accessibility IDs, tests for data-layer changes, and XcodeGen regen all happen in the same change that needs them.

## Facts you can't derive (keep these current)

These are fresh, environment-specific truths the model can't infer. If one goes stale, fix it here — don't silently work around it.

### Toolchain is Xcode 27 — what's alive and what's dead

- **Works (XcodeBuildMCP):** build, test, install, launch, `screenshot`, log capture (paths returned in `build_run_sim` output), coverage, simulator lifecycle. Prefer these tools over raw `xcodebuild`/`xcrun`/`simctl`. Call `session_show_defaults` before your first build/test/run in a session. Defaults live in `.xcodebuildmcp/config.yaml` (project `platforms/ios/Lists.xcodeproj`, scheme `Lists`, sim `iPhone 17 Pro`) and resolve by **name**, so they survive erasing/recreating sims.
- **Dead under Xcode 27 — do not use:** XcodeBuildMCP's AXe-based UI tools (`snapshot_ui`, `tap`, `swipe`, `gesture`, `type_text`) and `open_sim`. A system framework moved, AXe hardcodes the old path, and the fix was declined (getsentry/XcodeBuildMCP#446, closed). `Simulator.app` no longer exists — the device window is `DeviceHub.app`. These aren't a broken install; they're permanently gone on this toolchain.
- **Drive UI the native way instead** — the `xcode` bridge (`xcrun mcpbridge`) DeviceInteraction loop: `DeviceInteractionStartSession` (boots the sim) → `DeviceInteractionInstallAndRun` (after each code change) → `DeviceInteractionSynthesize` (tap/swipe/type/capture; each call returns a screenshot **plus** the view hierarchy with center coordinates, accessibility IDs, and the cumulative app log) → `DeviceInteractionEndSession` (always — open sessions are expensive). Run the Synthesize loop in a subagent. The bridge reads the running Xcode app, so the Lists workspace must be open. **Always read a hierarchy before any coordinate-based tap — never guess coordinates from a screenshot.**

### Two MCP servers, split by job

- **XcodeBuildMCP** — builds, tests, simulator, screenshots (above).
- **xcode (`xcrun mcpbridge`)** — IDE-context work the build driver can't do: SwiftUI preview rendering, Issue Navigator diagnostics, `DocumentationSearch` (Apple docs + WWDC transcripts in one query), and the DeviceInteraction UI driving above.

### XcodeGen owns the project shape

Never hand-edit `platforms/ios/Lists.xcodeproj/project.pbxproj`, the `*.xcscheme` files, or `.xcconfig` files. When sources, packages, or test targets change, edit `platforms/ios/project.yml` then run `xcodegen generate` from `platforms/ios/` — **close Xcode first**, or the bridge holds the project file open and generation breaks.

### Project specifics

- Bundle id `io.github.saxonbobart.lists`; Apple team `LM99LGYW87` (Saxon's personal Apple ID — free signing only; AlarmKit deferred until a paid Developer Program account exists).
- iOS storage is app-private `Documents/Lists/` in the sandbox — don't expose it to Files.app or iCloud Drive without explicit approval.
- Fonts are SF Pro / SF Mono — don't add other fonts or change the app-wide font design.
- Reset per-launch state with `--ui-testing-reset-data` in `launchArguments` (`ListsApp.swift` wipes the on-disk Lists directory when that arg is present).

## Verifying UI work

Two layers, each with one job — pick the one that fits, don't mix them:

1. **Snapshot + unit tests (`ListsTests`, swift-snapshot-testing)** — visual regression at the SwiftUI view level plus all unit coverage, no simulator launch. Catches silent layout changes. Run with `/test ListsTests/SnapshotTests`; add coverage with `/snapshot <ViewName>`. Reference images live in `__Snapshots__/` next to each test and are committed; a failing snapshot's diff image surfaces via the xcresult hook path.
2. **Driven exploration (the DeviceInteraction loop above)** — for iterating on a feature live in-session. Never commit driven gesture sequences as tests.

XCUITest was retired 2026-06-13 — it rotted against redesigns and never reliably verified real gestures (it's in git history). Don't reintroduce it without an explicit ask. Verify gestures by unit-testing their logic (reorder index math, swipe thresholds) plus a driven session.

**Accessibility IDs** follow `<screen>.<element>[.<id>]` — lowercase, dot-separated. Examples in code: `floating.add`, `item.row.<type>.<uuid>`, `item.notes.expand`, `markdown.editor`, `sidebar.list.<listId>`, `quickcapture.save`. Every interactive element gets one, added in the same edit that creates the view.

Slash commands shortcut the common actions: `/build`, `/test`, `/verify-screen`, `/snapshot`, `/tail-logs`.

## Git

Claude owns the git mechanics — see `GIT-GUIDE.md` for the full plain-English policy. In short: work on `dev`, keep `main` stable, commit at natural checkpoints and push `dev` as the off-site backup, then tell Saxon in one plain sentence what was saved. Move `main` or tag a version only after telling Saxon what's moving and getting an OK. Conventional Commits (`feat(ios):`, `fix(ios):`, `docs:`, `chore:`). Never force-push or rewrite history.

## Source of truth

- `PRODUCT-SPEC.md` — product behavior. Keep it short; update only when behavior changes.
- `docs/CURRENT.md` — current status pointer. Keep it brief.
- `design/ios-design-rules.md` — in-flight UI rules (row layout, tags, sheet headers, completed-item styling). Read it before changing visible iOS UI.
