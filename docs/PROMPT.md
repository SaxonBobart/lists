# PROMPT.md — Ralph loop prompt

This is the prompt fed to a fresh Claude Code session by `loop_runner.sh`. Each iteration is independent — context lives in files, not in a conversation.

---

You are working on the **Lists** project at `/Users/saxon/Developer/Projects/lists` — a calm, local-first markdown app for tasks, habits, and notes. iOS first, multi-platform later.

## What to do this iteration

1. **Read state** (in order, don't skip):
   - `BACKLOG.md` — top "Next" item is yours
   - `docs/AGENT.md` — known build commands + gotchas + simulator notes
   - `docs/CURRENT.md` — milestone tracker (where things stand)
   - `CLAUDE.md` — project discipline (conventions, constraints)
   - `PRODUCT-SPEC.md` — the product spec (only the sections relevant to your task)
   - The relevant existing code under `platforms/ios/Lists/` — **search before assuming code doesn't exist**

2. **Pick the top "Next" item** from BACKLOG.md. One task per iteration. Do NOT do multiple tasks.

3. **Implement it fully** — no placeholders, no TODOs, no "I'll come back to this." If you can't ship it complete, write the blocker to `docs/LOOP.md` and exit without committing.

4. **Verify before claiming done**:
   - Data-layer changes → `mcp__XcodeBuildMCP__test_sim` (zero failures, zero new warnings)
   - UI changes → `mcp__XcodeBuildMCP__build_run_sim` then `screenshot` then read the screenshot to eyeball it. Compare against the design prototype in `design/Claude Design/project/src/screens-mobile.jsx` (or related JSX) where applicable.
   - Format changes → re-read a real on-disk file under `~/Library/Developer/CoreSimulator/Devices/65D9F3B1-4A19-4820-B6F7-703D4BDF823C/data/Containers/Data/Application/<APP-UUID>/Documents/Lists/` to confirm shape.
   - **Iteration is not done until** build is green, tests pass, screenshot matches, AND commit is on the active feature branch.

5. **Commit** on the active feature branch (`feat/m1-screens`):
   - `git checkout feat/m1-screens` (create if missing: `git checkout -b feat/m1-screens main`)
   - Conventional Commits: `feat(ios): <one-line>` / `fix(ios): <one-line>` / `refactor(ios): <one-line>`
   - Include a body explaining the WHAT and WHY
   - Co-Authored-By: `Claude Opus 4.7 (1M context) <noreply@anthropic.com>`
   - **Never push, never merge to main, never force-push, never `--no-verify`.**

6. **Update state**:
   - `BACKLOG.md` — move the completed item from "Next" to "Done" with `<short-sha> · <iteration N>` annotation
   - `docs/LOOP.md` — append `YYYY-MM-DD HH:MM · iter N · <slug> · committed <sha>` (or `· blocked: <reason>`)
   - `docs/AGENT.md` — append any new gotcha you learned (be precise; future iterations will read this)
   - `docs/CURRENT.md` — keep in sync if the milestone state shifted

7. **Exit cleanly.** Output `ITERATION COMPLETE` (or `ITERATION BLOCKED` if you exited at step 3 without a commit).

## Hard rules

- **One task per iteration.** Don't bundle.
- **Search before assuming.** Use `grep` / `find` / Explore subagents. The project has structure — don't reinvent what's already there.
- **No placeholders.** Full implementation or block.
- **No `git push`, no merge to main, no force-push, no `--no-verify`, no `git reset --hard`.**
- **No edits to `CLAUDE.md` or `.claude/settings.json` without explicit go.**
- **3-strike rule:** if a single task fails 3+ times across iterations, mark it `blocked` in BACKLOG with the reason and skip to the next.
- **Drive the simulator before claiming UI work done.** Per `feedback_drive_sim_before_claiming_done` memory.
- **If bootstrap fails with `keyNotFound: created_at`-style errors**, wipe simulator's `Documents/Lists/` for the bundle (per `feedback_wipe_sim_data_when_bundle_shared` memory) and retry. Do NOT silently skip.

## Subagent guidance

Spawn parallel `Explore` subagents for any cross-codebase research. Don't bloat your own context window. The primary agent (you) should focus on the implementation.

For a single targeted lookup, use `grep`/`find` directly via the Bash tool — don't spin up a subagent for that.

## End of prompt
