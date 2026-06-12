# Build & Compile Health Audit

(Persisted by the dispatcher — the read-only build agent has no Write tool. Content verbatim from the agent.)

## Verdict
**Minor issues — one real, easily-fixed regression.** The shipping app is in excellent build health: a full clean build of the `Lists` app target for the iOS 26 simulator **succeeds with zero compiler warnings** (the lone "warning:" in the log is a harmless AppIntents tooling notice, not a code defect). However, the **`ListsTests` snapshot-test target does not compile** — the latest commit (`2b224f3`) added a required `autoListPrefs:` parameter to `SettingsView.init` but never updated `SettingsViewSnapshotTests`, so anyone running Cmd+U / `build-for-testing` hits a hard build failure. The `ListsUITests` target compiles fine.

## Findings

### [P1] `ListsTests` target fails to compile — stale `SettingsView` call after HEAD commit
- **Where:** `platforms/ios/ListsTests/SnapshotTests/SettingsViewSnapshotTests.swift:10` (cascading error at `:13`)
- **What:** Production `SettingsView` now requires `init(store: ItemStore, autoListPrefs: AutoListPreferences)` (`SettingsView.swift:6-8`), but the test still calls `SettingsView(store: store)`. Errors: `:10:45: missing argument for parameter 'autoListPrefs'` and a knock-on opaque-return-type error at `:13:16`. The param was introduced in HEAD commit `2b224f3`; the test (last touched `8a7fa0b`) wasn't updated.
- **Impact:** The entire `ListsTests` unit/snapshot suite cannot build, so it cannot run. `xcodebuild build-for-testing` / Cmd+U fails (exit 65). All snapshot coverage (13 files) is dark until this compiles. Invisible during normal app builds, which is why it slipped in.
- **Confidence:** High (reproduced from a clean `build-for-testing`).
- **Fix:** `let view = SettingsView(store: store, autoListPrefs: AutoListPreferences())` (`AutoListPreferences` has a no-arg-capable init). Process fix: run `build-for-testing` (or CI) on every commit.

### [P3] Test running gated by the test plan, not the scheme's inline `<Testables>` (cosmetic doc-drift)
- **Where:** `Lists.xcodeproj/xcshareddata/xcschemes/Lists.xcscheme:75-76` vs `Lists.xctestplan`
- **What:** Scheme's `<Testables>` block is empty; tests are registered via `Lists.xctestplan` (lists both targets). Valid/intentional (XcodeGen from `testPlans:`), not a bug, but can mislead a maintainer.
- **Impact:** None at runtime; readability hazard.
- **Confidence:** High. **Fix:** none required; note so nobody "fixes" the empty block and double-registers.

## Strengths
- **App target is genuinely clean.** 281 `SwiftCompile` invocations, **zero** Swift/Clang source warnings, zero notes, zero errors — under **Swift 6 language mode** with full strict-concurrency checking (no `SWIFT_STRICT_CONCURRENCY` opt-out). For an AI-assisted ~18.9k LOC codebase, no accumulated deprecations, no Sendable/data-race warnings, no unused-var noise is a strong signal.
- **No latent bug-class warnings.** Checked the dangerous ones (`result of call unused`, unreachable code, non-exhaustive switch, infinite recursion) — none. `CLANG_WARN_UNREACHABLE_CODE`, `CLANG_WARN_INFINITE_RECURSION`, `CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE` enabled and clean.
- `ListsUITests` (10 files) compiles without error.
- The "warnings-as-errors OFF → warnings may have accumulated" worry is **unfounded for the app target**. The real gap is process: nobody compiled the *test* targets, which is where the breakage lives.

## Coverage
- Clean build of scheme `Lists`, Debug, `iPhone 17 Pro` (iOS 26.4.1). Log: `/tmp/lists-audit/build-app.log` (`BUILD SUCCEEDED`).
- `build-for-testing` (compiles Lists + ListsTests + ListsUITests). Log: `/tmp/lists-audit/build-tests.log` (`TEST BUILD FAILED`, exit 65).
- Verified Swift 6.2, iOS 26.0 target, `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO` (Debug + Release).
- Did **not** run the suites (compile health only; `ListsTests` can't link until the P1 fix). Did not build Release or the MarkdownUI package scheme.
