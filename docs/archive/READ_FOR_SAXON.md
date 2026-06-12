# Read For Saxon

Date: 2026-06-12

This is the plain-English summary of what we worked out tonight. Nothing in this file has been done yet. It is a morning checklist and prompt source for Claude Code.

## Bottom Line

The iOS app does not look like throwaway AI slop.

It looks like a real app built very quickly with frontier models. The foundations are better than you are worried they are: local file storage, item model, reminders, recurrence, habits, markdown, snapshots, and data tests all point in a coherent direction.

The risk is not that the app is fake or ruined. The risk is that the repo is getting noisy:

- stale docs
- branch confusion
- Android experiment noise
- huge Swift files
- too many tiny agent decisions memorialized in comments/docs
- Claude running too much verification for tiny changes

The next phase should be boring: consolidate, simplify docs, clean Git workflow, preserve current iOS behavior.

## First Step Tomorrow

Do not start by adding features.

Start with project orientation:

1. Confirm the current branch and whether it is pushed.
2. Delete Android if you still want it gone.
3. Simplify docs so only current iOS truth stays active.
4. Write a simple Git workflow you understand.
5. Only after that, do iOS code consolidation.

## Important Decision

Android is junk/noise for this project right now.

If you still feel that way tomorrow, tell Claude to delete `platforms/android/` and remove Android from active docs. Git history still keeps the old files if you panic later.

## App Health

Good signs:

- Product idea is coherent: tasks, notes, habits, events in one local-first iOS app.
- Storage/data layer looks intentionally hardened.
- Tests exist for real data-loss risks.
- iOS code organization is understandable.
- Strict Swift settings are in place.
- The document-style item page is product-correct if it now behaves how you want.

Risk signs:

- `ItemDocumentView.swift`, `ListDetailCollectionView.swift`, and `QuickCaptureSheet.swift` are very large.
- Some docs are stale or contradictory.
- Some comments/tests may describe old event behavior.
- Claude has probably over-documented and over-tested small changes.
- Current latest work may live on a temporary Claude branch, not `dev` or `main`.

This means: do not restart. Do not panic. Consolidate.

## Big Files

A big file is not automatically bad.

If `ItemDocumentView` works and feels right, keep the behavior. Do not ask Claude to redesign it.

Safe cleanup later means mechanical extraction only:

- move the title field into its own file
- move the body editor into its own file
- move the keyboard quick bar into its own file
- maybe move Details/event controls into a focused helper view

This should not change functionality. It is like splitting a long document into chapters.

Unsafe cleanup means changing state flow, bindings, navigation, persistence, or UI behavior. Do not let Claude do that unless it explains the bug or tradeoff first.

## Simple Git Mental Model

Use this:

- `dev` = daily work / workshop
- `main` = stable checkpoints
- version tags like `v0.1.0`, `v0.2.0` = app versions
- temporary Claude branches = experiments only
- commit = save point
- push = backup to GitHub

Do not use silent automatic Git.

Use assisted Git:

1. Claude checks status.
2. Claude summarizes changes.
3. Claude suggests a commit message.
4. Claude asks before committing.
5. Claude asks before pushing.

## Docs Shape

Active docs should be small.

Recommended active docs:

- `README.md`: short app overview and how to open/build.
- `PRODUCT-SPEC.md`: current user-visible iOS behavior only.
- `docs/CURRENT.md`: current status, active work, next priorities, known risks.
- `docs/PROGRESS.md` or `docs/CHANGELOG.md`: dated milestone history.
- `AGENTS.md`: rules for agents.
- `GIT-GUIDE.md`: plain-English solo Git workflow.

Old audits/research/plans can be archived or deleted later. For the first pass, prefer archive over delete unless it is clearly Android junk or duplicated noise.

## Testing Reality

The tests are not pointless, but Claude is using them too aggressively.

Test categories:

- Data/model tests: valuable. These protect against data loss, recurrence bugs, habit math bugs, corrupt files, time zones, and storage issues.
- Snapshot tests: useful for visual regression, but they will fail when you intentionally change visuals.
- XCUITests: useful as smoke checks, but do not treat complex gesture tests as absolute truth.
- Xcode 27 agent-driven verification: useful for manually/agent driving the app and checking UI hierarchy/screenshots, but it does not replace unit tests.

Use proportional testing.

Testing ladder:

- Docs-only change: no build/test required. Inspect diff.
- Tiny visual/style tweak: do not run the full suite. Maybe no test. Maybe screenshot if needed.
- Single SwiftUI component change: run the narrowest snapshot/unit test if one exists.
- Data/model/storage/recurrence/reminder change: run the specific unit test file/class first.
- Shared filtering/navigation behavior: targeted tests, then maybe the relevant target.
- Before merging to `main` or tagging a version: run the full appropriate batch.

Rule for Claude:

```text
Use proportional verification. Do not run all 198 iOS tests for tiny visual/style changes. Explain the narrowest useful verification and what was intentionally skipped.
```

## Claude Code Usage

As of tonight, based on current Claude Code docs:

Recommended default:

```text
/model opusplan
/effort high
```

Why: Opus plans, Sonnet implements. That is a good default for a non-programmer who wants strong judgment without burning maximum effort on everything.

Model choices:

- `sonnet`: daily coding, docs, small fixes, simple cleanup.
- `opus`: hard debugging, architecture, reviewing Claude's own work.
- `opusplan`: best default for you.
- `fable`: hardest/longest autonomous tasks if available.
- `haiku`: fast search/summarize chores.
- `best`: lets Claude choose the strongest available option, but less predictable.

Effort choices:

- `low`: tiny chores.
- `medium`: docs cleanup, mechanical edits.
- `high`: default.
- `xhigh`: architecture, data safety, large consolidation.
- `max`: do not use by default. It can overthink.
- `ultracode`: only for substantial, well-scoped autonomous work.

Permission mode:

- Use `plan` before big or unclear changes.
- Use `acceptEdits` after you approve a plan.
- Use `auto` only for boring, well-scoped work.
- Do not use `bypassPermissions` on the real repo.

Good loop:

1. Explore.
2. Plan.
3. Approve.
4. Implement.
5. Verify proportionally.
6. Summarize.
7. Ask before commit/push.

Use `/clear` between unrelated tasks. Long messy sessions make Claude worse.

Use a second opinion for risky work:

- Claude advisor
- subagent review
- Codex sanity check

## Main Prompt For Claude Tomorrow

Paste this into Claude Code:

```text
Focus only on project cleanup, docs, and Git workflow. Do not change iOS app behavior.

I want to simplify this repo so I can understand it as a solo non-programmer.

Use:
- model/effort appropriate for a consolidation pass
- proportional testing
- no full test suite unless there is a real reason

First: safety checkpoint
- Inspect current branch, git status, and whether the latest branch is pushed.
- Explain in plain English where the latest iOS work lives.
- Do not reset, merge, rebase, force-push, or rewrite history.
- If anything needs committing or pushing, ask me first.

Then cleanup:
- Delete the entire Android implementation. It was an experiment and is not part of the product.
- Remove Android references from active docs, except to say Android is deferred/not active if needed.
- Keep this as a cleanup-only change. Do not touch iOS app behavior.

Then docs consolidation:
- README.md: short app overview and how to open/build
- PRODUCT-SPEC.md: current user-visible iOS behavior only
- docs/CURRENT.md: current status, active work, next priorities, known risks
- docs/PROGRESS.md or docs/CHANGELOG.md: dated milestone history
- AGENTS.md: rules for agents working on this repo
- GIT-GUIDE.md: plain-English solo Git workflow

Keep important behavior and technical guardrails. Remove stale agent-history noise, duplicated explanations, Android noise, and contradictions.

During cleanup, specifically look for and flag/fix:
- stale comments saying events have optional/no end if current spec says events always have start and end
- tests that encode old behavior without saying they are backward-compat tests
- docs claiming main is the only branch if latest work is elsewhere
- Android references in active docs
- old audit docs pretending to be current truth
- instructions that force huge test runs for tiny changes

Git workflow:
- dev = daily work
- main = stable checkpoints
- version tags like v0.1.0, v0.2.0 = app versions
- temporary Claude branches = experiments only
- commit = save point
- push = back up to GitHub

Also create or document a simple checkpoint workflow for me. I do not want silent automatic commits. I want an easy assisted flow where Claude checks status, suggests a commit message, and asks before committing/pushing.

Hard rules:
- Do not change Swift code.
- Do not change iOS app behavior.
- Do not touch generated Xcode project files.
- Do not add new features.
- Do not delete useful iOS context.
- Prefer simple, short docs.
- Use proportional testing. For docs cleanup, no full test suite is needed.

Before editing, summarize what you plan to keep, shorten, move/archive, or delete.

After changes, summarize:
- what changed
- what was deleted
- what is now the source of truth
- what Git workflow I should follow
- whether anything still needs committing/pushing
```

## Later Prompt For iOS Consolidation

Do not use this until docs/Git are cleaned up and the current app behavior is frozen.

```text
Focus only on iOS. Ignore Android completely.

I want a consolidation pass, not a feature pass.

Assume the current product behavior is correct, especially the document-style item page. Do not redesign screens, move controls, change copy, change interaction patterns, or improve UX unless you find a real bug or contradiction and explain it first.

Your job is to make the codebase safer and clearer for future work while preserving how the app currently feels.

Good consolidation work includes:
- reducing obvious large-file risk where it can be done mechanically
- extracting clearly separate helper views or UIKit bridges without changing behavior
- removing or correcting stale comments/docs that contradict current behavior
- tightening tests around important behavior if needed
- improving naming or file organization only when it reduces future confusion
- leaving working product behavior alone

Do not:
- add new features
- introduce a new architecture
- rewrite working systems from scratch
- make broad style-only refactors
- touch generated Xcode project files by hand
- make changes just because a file is long
- run the full test suite for tiny mechanical changes unless there is a clear reason

If a change is low-risk and mechanical, do it. If a change could alter behavior, stop and explain the tradeoff first.

After changes, build/test only what is appropriate and summarize what changed, what stayed intentionally unchanged, what was verified, and what risk remains.
```

## Things To Watch For

Ask Claude to flag these during cleanup:

- stale comments saying events have optional/no end if current spec says events always have start and end
- tests that encode old behavior without saying they are backward-compat tests
- docs claiming `main` is the only branch if latest work is elsewhere
- Android references in active docs
- old audit docs pretending to be current truth
- instructions that force huge test runs for tiny changes

## Official Claude Code Docs Used Tonight

- Overview: https://code.claude.com/docs/en/overview
- Model configuration: https://code.claude.com/docs/en/model-config
- Permission modes: https://code.claude.com/docs/en/permission-modes
- Best practices: https://code.claude.com/docs/en/best-practices
- Fast mode: https://code.claude.com/docs/en/fast-mode
- Advisor: https://code.claude.com/docs/en/advisor
- Subagents: https://code.claude.com/docs/en/sub-agents

## Final Reminder

You are not sitting on an unsalvageable app.

You are sitting on a real iOS app that got built fast and now needs a calmer repo around it.

Tomorrow is not "make it smarter." Tomorrow is "make it easier to understand and safer to continue."
