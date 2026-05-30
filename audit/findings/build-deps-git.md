# Build Config, Dependencies & Git Hygiene Audit

## Verdict
**Minor issues, with one notable cleanup item.** The build config is clean, modern, and internally consistent; dependencies are few, MIT-licensed, and free of known CVEs. The standout problem is **repo bloat**: the `.git` directory is 57 MB but only ~9.7 MB of that is actually reachable content — roughly **54 MB is orphaned junk** that a single garbage-collection command would reclaim. Beyond that, two declared capabilities (App Group, `lists://` URL scheme) are dead — declared but never used in code — and the `main` branch is frozen 100 commits behind real work. None of this breaks the build or leaks data; it's hygiene and a small amount of pre-launch tidying.

## Findings

### [P2] `.git` is 57 MB but only ~9.7 MB is real — 54 MB of orphaned objects
- **Where:** `.git/objects` (57 MB); `git fsck --unreachable` reports 2,785 unreachable objects, 54.6 MiB in unreachable blobs alone. A stray garbage file also exists: `.git/objects/2c/tmp_obj_1BYSpY` (0 bytes; `git count-objects -v` shows `garbage: 1`).
- **What:** The sum of *every blob reachable from any branch across all history* is only **9.67 MiB**. The repo is 6x larger than its real content because old/rewritten objects (from the editor rebuild, snapshot-PNG churn, the deleted `shared/` tree, amends/rebases) were never pruned. `git gc` has evidently not run; `in-pack: 100`, the rest are loose objects.
- **Impact:** Clones/pulls are ~6x heavier than necessary, and disk usage is inflated. No correctness or data impact — purely waste. It will keep growing as more history is rewritten.
- **Confidence:** High
- **Fix:** Run `git gc --prune=now` (optionally `git reflog expire --expire=now --all` first, since the reflog is only 72 KB / 116 entries and holds little of value). This should shrink `.git` from 57 MB to well under 10 MB. The stray `tmp_obj_*` file is cleaned up by the same gc. Consider enabling automatic gc (it appears to have been disabled or never triggered).

### [P2] App Group entitlement declared but never used
- **Where:** `platforms/ios/Lists/Lists.entitlements:5-8` and `project.yml:51-52` declare `com.apple.security.application-groups` → `group.io.github.saxonbobart.lists`. No code references it: `grep` for `forSecurityApplicationGroupIdentifier` / `containerURL` / `UserDefaults(suiteName:` across `Lists/` returns nothing. Storage actually uses `.documentDirectory` (`Core/Storage/StorageRoot.swift:9`).
- **What:** App Groups exist to share a container between an app and its extensions (widgets, share extension, etc.). There are no extensions in this project, and files are written to the app's private Documents directory, not the group container. The entitlement is dead.
- **Impact:** No functional harm today, but it's misleading (suggests cross-process sharing that doesn't exist) and an unused entitlement is a small attack-surface/review-noise item at App Store submission. On a free/personal team it also consumes a provisioning capability for no benefit.
- **Confidence:** High
- **Fix:** Remove the App Group from `Lists.entitlements` and `project.yml` until an extension actually needs it. Per the project's documented single-device local-first model, that may be never. Regenerate with `xcodegen generate` after editing.

### [P2] `lists://` URL scheme declared but never handled
- **Where:** `platforms/ios/Lists/Info.plist:21-31` and `project.yml:44-47` register URL scheme `lists`. No handler exists: `grep` for `onOpenURL` / `URLContexts` / `application(_:open:)` / `lists://` across `Lists/` finds only the Info.plist declaration itself.
- **What:** The app advertises that it can open `lists://...` deep links, but nothing in the code responds to them. Tapping such a link would launch the app and do nothing.
- **Impact:** Dead capability. Low harm, but it's a half-wired feature — either deep linking was planned and dropped, or it's copy-paste boilerplate. Misleads future readers and App Store reviewers about supported behavior.
- **Confidence:** High
- **Fix:** Either implement a handler (`.onOpenURL { ... }` on the root scene) if deep links are intended, or remove the `CFBundleURLTypes` block until they are.

### [P2] `main` branch is frozen 100 commits behind `dev`
- **Where:** `main` last commit `2026-05-09` ("chore: M0 milestone tracker"); `dev` last commit `2026-05-24`. `git log main..dev` = **100 commits**; `git log dev..main` = 0. Both are pushed to `origin`.
- **What:** All real development (the entire app as it exists) lives on `dev`. `main` — the repo's default/PR-base branch — is essentially the M0 skeleton and has not moved in two weeks. The project instructions even say "Main branch (you will usually use this for PRs)."
- **Impact:** Confusing for collaborators/CI and risky: anyone branching from `main` or opening a PR against it starts from a 2-week-old skeleton missing the whole app. If `main` is the branch protected/deployed, the deployed state is stale.
- **Confidence:** High
- **Fix:** Decide the trunk policy: either fast-forward/merge `dev` into `main` so `main` reflects reality, or formally make `dev` the default branch on the remote. Don't leave a 100-commit gap on the nominal default branch.

### [P3] Pinned versions in `project.yml` are stale floors that drift from `Package.resolved`
- **Where:** `project.yml:15-23` pins `Yams from: 5.1.2`, `MarkdownUI from: 2.4.1`, `SnapshotTesting from: 1.18.0`. `Package.resolved` actually locks Yams **5.4.0**, MarkdownUI 2.4.1, SnapshotTesting **1.19.2**.
- **What:** `from:` is a *minimum*, not a pin — SwiftPM resolves to the newest compatible version under the same major. So the YAML floors are already behind what's resolved. This is expected SwiftPM behavior (the real lock lives in `Package.resolved`, which IS tracked — good), but the stale floors are misleading and Yams is capped at the 5.x line: **Yams 6.x** (Swift 6 concurrency-mode build) exists and won't be picked up because `from: 5.1.2` permits only `<6.0.0`.
- **Impact:** Mostly cosmetic/maintainability. The one real consequence: the app silently stays on Yams 5.x; bumping to 6.x (better Swift 6 concurrency story) requires an explicit floor change.
- **Confidence:** High
- **Fix:** Refresh the `from:` floors to match `Package.resolved` (5.4.0 / 2.4.1 / 1.19.2) so intent and lock agree, and evaluate moving Yams to `from: 6.0.0`. Low priority.

### [P3] `SWIFT_TREAT_WARNINGS_AS_ERRORS: NO` masks accumulating warnings
- **Where:** `project.yml:14`.
- **What:** Compiler warnings (deprecations, unused vars, Sendable/concurrency warnings under Swift 6.2, implicit casts) won't fail the build, so they can pile up unnoticed. For an AI-assisted, fast-moving codebase this is exactly where subtle issues hide (e.g., Swift 6 strict-concurrency warnings that foreshadow real data races).
- **Impact:** Latent quality drift. Not a bug today, but the safety net is off precisely where this project would benefit from it.
- **Confidence:** Med (would need a clean build log to see how many warnings currently exist).
- **Fix:** Build once and review the warning count. If low, flip to `YES` to keep it that way. If high, that itself is a finding worth a cleanup pass. At minimum, leave a comment in `project.yml` explaining the deliberate choice.

### [P3] Generated `project.pbxproj` is committed and churns
- **Where:** `platforms/ios/Lists.xcodeproj/project.pbxproj` is tracked; `README.md:91` and `AGENTS.md:42` both state it's XcodeGen-generated and instruct running `xcodegen generate` when sources/packages change. The file has changed in **32 commits** and is the single largest cumulative path in history (~1.5 MB of accumulated diffs).
- **What:** Committing a generated, source-of-truth-elsewhere file is a deliberate convenience (you can open/build without running XcodeGen first), but it's also the project's top churn source and a classic merge-conflict magnet — and it bloats history.
- **Impact:** Noisy diffs and merge conflicts whenever files/targets change; contributes to the history weight. For a solo dev this is tolerable; with collaborators it gets painful.
- **Confidence:** High
- **Fix:** This is a reasonable tradeoff to keep — but if churn becomes a problem, gitignore `*.xcodeproj/` and make `xcodegen generate` a mandatory pre-build step (the README already documents the command). Decide one way; don't drift.

## Strengths
- **`.gitignore` is comprehensive and correct.** macOS cruft, DerivedData/build, `.swiftpm`, Pods/Carthage, `node_modules`, `.env*` (with `!.env.example`), `*.log`, `CLAUDE.local.md`, `.claude/settings.local.json` and worktrees are all ignored — *and* `Package.resolved` is explicitly force-tracked (`!Package.resolved`). Thoughtfully done.
- **No secrets, credentials, or user data tracked.** `git ls-files` shows no `.env`, `.p12`, `.mobileprovision`, `.cer`, no `.list.yml`/`.md` user content, no simulator containers, no DerivedData. The only "token"/"secret" grep hits are design `tokens.css`/`Tokens.swift` (false positives). Clean. (No P0/P1 here — explicitly checked.)
- **`Package.resolved` is tracked and fully pinned** (exact revisions + versions for all 8 transitive deps), so builds are reproducible.
- **Dependency footprint is small and healthy.** Only 3 direct deps, all **MIT-licensed** (App Store-safe), all in current major lines, **no known CVEs/advisories** for Yams, MarkdownUI, or swift-snapshot-testing as of May 2026. SnapshotTesting is at the latest (1.19.2). MarkdownUI 2.4.1 is the latest but its repo has entered **maintenance mode** (active development moved to a successor, "Textual") — worth tracking for longevity, not urgent.
- **Build config is modern and coherent:** Swift 6.2, `ENABLE_USER_SCRIPT_SANDBOXING: YES`, `GENERATE_INFOPLIST_FILE: NO` with a hand-kept Info.plist, sensible scheme wiring. Bundle id, team, and group identifiers are internally consistent.
- **`editor-archive-2026-05-13` is an intentional, documented archive** (37 commits of pre-rebuild editor history, matches the memory note about the editor rebuild). Not stale-by-accident — keep or delete deliberately.

## Notes & Coverage
**iOS 26.0 deployment target (audience implication, as requested):** `project.yml:5-6` sets the minimum to iOS 26.0. iOS 26 is brand-new; real-world adoption in mid-2026 is still a small fraction of devices (a new major OS typically takes 6-12 months to reach majority adoption, and many older-but-supported iPhones lag further). **Practically, almost no one outside the latest-OS early-adopter cohort could install this today.** That may be perfectly fine for a personal/pre-release project targeting the newest APIs (e.g. iOS 26 SwiftUI/TextKit features), but it is a hard ceiling on addressable audience if/when this ships. Recommend a conscious decision: keep 26.0 only if you genuinely depend on 26-only APIs; otherwise lowering to iOS 18/19 would multiply the installable base. Not a P-level defect — a product/market call to make before any public release.

**Signing/team `LM99LGYW87` (free/personal):** Confirmed personal team per project memory. The declared capabilities are App Group (unused — see P2) and the URL scheme (no entitlement needed). A free personal team supports App Groups in development, so nothing here *breaks the build*; but the unused App Group is the only capability that would matter, and it should be removed (P2 above). No paid-only capabilities (Push, iCloud, Sign-in-with-Apple) are requested, which is consistent with the free-account constraint — good.

**What I read:** `project.yml`, `Info.plist`, `Lists.entitlements`, `.gitignore`, `Package.resolved`, `README.md`/`AGENTS.md` (XcodeGen + branch guidance), and the storage code (`StorageRoot.swift`, `FileStore.swift`) to verify App Group/scheme usage. Ran read-only `git` (`ls-files`, `log`, `fsck`, `count-objects`, `rev-list`) and `du`. Verified latest dep versions, maintenance status, licenses, and advisories via web.
**Could not get to:** I did not build the app, so the actual current compiler-warning count (P3 above) is unconfirmed; and I did not run `git gc` (read-only constraint) so the post-gc size is a strong estimate (~9.7 MB reachable), not a measured result.
