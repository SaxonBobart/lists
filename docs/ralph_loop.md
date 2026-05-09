# Ralph Loop — what it is and how this project uses it

## What

A Ralph loop is a brute-force agentic-coding pattern: a loop that feeds the same prompt to an AI agent repeatedly, while persistent state (a backlog, a learning log, the codebase, git history) accumulates between iterations. Named after Ralph Wiggum from The Simpsons — the loop itself is dumb, but each iteration is a full smart Claude.

Two canonical implementations:

1. **Geoff Huntley's original** ([ghuntley.com/ralph](https://ghuntley.com/ralph/)) — a one-line bash loop:
   ```bash
   while :; do cat PROMPT.md | claude-code ; done
   ```
   Each iteration is a fresh Claude session. State lives in files (`fix_plan.md`, `AGENT.md`, specs, code, git). Geoff ran it for 3 months to build a complete programming language. His warning: "There's no way in heck I would use Ralph in an existing code base."

2. **Anthropic's `ralph-wiggum` plugin** ([anthropics/claude-code/plugins/ralph-wiggum](https://github.com/anthropics/claude-code/blob/main/plugins/ralph-wiggum/README.md)) — uses a Stop hook to intercept session exits and re-feed the prompt within the same Claude session. Invoked via `/ralph-loop "task" --completion-promise "DONE" --max-iterations 20`. The doc explicitly says always cap with `--max-iterations`; completion-promise alone is unsafe.

## How this project uses the pattern

This repo has Ralph infrastructure pre-built so anyone (you, future Claude, future-you with a paid subscription burning a hole) can fire an autonomous run.

### State files

- **`BACKLOG.md`** (root) — prioritised tasks. Top item is "next." Format: `- [ ] <slug> — <description>`. Done items move to `## Done` with a commit-sha annotation.
- **`docs/AGENT.md`** — append-only learning log (build commands, simulator quirks, gotchas). Future iterations read this so they don't relearn the same lesson.
- **`docs/PROMPT.md`** — the prompt template fed to each iteration. Tells Claude what to do (read state, pick top task, implement, verify, commit, update state, exit).
- **`docs/LOOP.md`** — append-only iteration log (timestamp · iter N · slug · outcome).
- **`docs/CURRENT.md`** — high-level milestone tracker; updated when milestone state shifts.

### Runner

`docs/loop_runner.sh` is a bash wrapper around `claude` with safety rails:
- `--max-iterations` cap (default 15)
- Sleep between iterations (default 10s)
- Logs to `docs/LOOP.md`
- Exits cleanly on `ITERATION COMPLETE` not appearing N times in a row

It is **executable but not currently being run**. Start it manually if you want a real autonomous loop:

```sh
./docs/loop_runner.sh                     # 15 iterations, default
./docs/loop_runner.sh --max-iterations 5  # bounded run
./docs/loop_runner.sh --dry-run           # show what would happen
```

### Branch discipline

Autonomous runs land commits on **feature branches** (`feat/m1-screens` for the current milestone), never on `main`. Saxon reviews and merges in the morning. If something goes sideways, `git branch -D feat/m1-screens` wipes the run.

## Anti-patterns to avoid

From Geoff's writeup + bitter experience:

- **No assuming code isn't implemented** — always search first (`grep` / `find` / Explore subagent)
- **No bloating the primary agent's context** — spawn subagents for parallel research
- **No multiple tasks per iteration** — one and done; the loop is the iteration mechanism
- **No placeholder implementations** — full or block (mark in BACKLOG, document in LOOP)
- **No skipping failing tests, no `--no-verify`, no `git reset --hard` without strong justification**
- **No running Ralph in someone else's untested production codebase** — Geoff's "no way in heck"

## Stopping conditions

The runner stops when:

- `BACKLOG.md` is empty (no `- [ ]` lines under "Next")
- `--max-iterations` reached
- 3 consecutive iterations exited with `ITERATION BLOCKED`
- Manual SIGINT (Ctrl-C)

## Cost note

Each Ralph iteration is a full Claude Code session. Cost compounds. The Anthropic plugin doc cautions: cap iterations, monitor logs, abort if something looks off. YC hackathon teams reportedly shipped 6 repos overnight for ~$297 in API costs. Rough order of magnitude: $10–$50 per overnight run on this project, depending on iteration count and depth.
