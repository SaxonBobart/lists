# Project health investigation — 30 October 2026

## Conclusion

The current app has a coherent iOS project structure. There is no evidence here
that it needs a rewrite or a replacement Xcode project. The highest immediate
risk was confusion between different checkouts and unsaved development history.
This investigation preserves the current app as the baseline.

## Scope and baseline

The owner confirmed `/Users/saxon/Developer/Projects/lists` as the current app.
The task worktree started at `9bc24f2`, while canonical dev was at `d7c63b7`
with nine additional commits and substantial uncommitted work. Its existing
27 October cleanup had already removed obsolete code and documentation.
Those changes were not made by this investigation.

Before saving that work, the complete working folder, including ignored files
but excluding Git internals, was archived outside the repository. Every archived
regular file was verified against its original with SHA-256. The archive and
metadata are under `/Users/saxon/.codex/backups/lists/`, named
`before-git-checkpoint-20261030-101518.tar.gz` and its companion JSON.
Commit `d9b91a1` saves the preexisting current app and cleanup on dev. It is a
recovery checkpoint, not a claim that all those changes were reviewed here.
No app library was changed. No push, release, history rewrite, or main change
was performed. Fetching origin confirmed dev was ten commits ahead after this
checkpoint; those commits still existed only locally at that point.

## Verified configuration

- Active toolchain: `/Applications/Xcode.app`, Xcode 27.2 build `27B5028f`,
  Apple Swift 6.4. Swift language mode is correctly `6`.
- XcodeGen 2.46.0 reproduces the canonical project.pbxproj, shared Lists scheme,
  and app Info.plist byte for byte in a separate temporary copy. The actual
  project was not regenerated or edited.
- One app target and one hosted unit/snapshot test target. The scheme references
  the Lists test plan, whose target identifier matches the generated project.
- iOS deployment target remains 26.0. iPhone-only device family is intentional
  configuration, not evidence of broken iPad support.
- Debug/Release settings, app identifier and development team are centralized
  in project.yml. Resource folder handling preserves bundled editor renderers.
- All four direct packages have active uses: Yams for persistence, MarkdownUI
  and CMark for Markdown, SnapshotTesting for tests. Package.resolved is tracked.
- Canonical XcodeBuildMCP defaults point at the current project and an existing
  iPhone 18 Pro, UUID `87800814-E5C1-437B-89A5-945B035C070D`, iOS 27.2.
  The older task checkout points at an unavailable iPhone 17 Pro UUID.
- A fresh Debug simulator build through XcodeBuildMCP succeeded in 44.5 seconds.
  Its retained build log contained no `warning:` or `error:` matches.
- A separate Debug build-for-testing succeeded in 19.3 seconds, compiling and
  linking the hosted test bundle and producing test-run products. Tests were
  not executed in this investigation.
- A privacy manifest, permission descriptions, app icon, and bundled third-party
  licenses exist. Their presence alone does not establish release compliance.

## Remaining risks and priorities

1. **Keep the current baseline recoverable off this Mac.** The local checkpoint
   and verified backup now exist. Publishing dev remains a separate owner
   decision. Never reset or replace the canonical app from an older task branch.
2. **Make checkout selection explicit.** Shared agent instructions and absolute
   automation paths currently favor canonical dev. Before future changes,
   compare working directory, HEAD, dirty state, project path and simulator UUID.
   A build of canonical dev does not validate edits in another worktree.
3. **Add repeatable verification.** No GitHub Actions workflow exists. Introduce
   a deliberate macOS build/logic-test gate with an available supported SDK;
   treat runtime-specific snapshots separately. Do not pick a hosted Xcode image
   or enable external automation without checking availability and cost.
4. **Align test defaults with the documented workflow.** README disables parallel
   testing, while the test plan marks the hosted target parallelizable. Snapshot
   fixtures manage windows and global UIKit state. This is a configuration
   inconsistency to investigate with controlled runs, not a demonstrated race.
5. **Refactor by responsibility when fixing real behavior.** ItemStore is about
   5,014 lines; MarkdownTable 3,968; ItemDocumentView 2,463. Storage write ordering,
   rollback/recovery, text selection and gesture behavior are sensitive. Extract
   coherent helpers behind focused tests, one workflow at a time; splitting files
   solely to reduce line counts would not prove an improvement.
6. **Review ignored errors in specific user flows.** Some UI and clipboard paths
   use `try?`. The store also records failures and retains pending writes, so
   this syntax alone does not prove silent data loss. Inject failures and inspect
   recovery for each path before changing error presentation or rollback.
7. **Verify release and compatibility separately.** A Debug simulator compile
   does not establish Release signing, archive/export, accepted submission SDK,
   physical-device behavior, Calendar-account integration, or iOS 26 runtime
   compatibility. Keep those checks explicit before distribution.

## Verification limits

This was a structure/configuration investigation and local Git checkpoint.
No UI code was changed and no new visual verification was claimed. The prior
27 October audit reports 788 passing tests; that is historical evidence, not a
fresh result from this investigation. No dependency upgrades, deployment-target
changes, signing changes, remote publishing or blanket code deletion were made.
