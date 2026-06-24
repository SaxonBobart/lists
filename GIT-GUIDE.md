# Git, in plain English (solo project)

*A no-jargon guide to how Lists is saved, backed up, and checkpointed.*

**The short version: coding agents handle git. You never need to run a git command.**
(Arrangement as of 2026-06-13 — the maintainer asked for git to be fully handled.)

---

## The two core ideas

1. **Commit = a save point.** Git takes a snapshot of the whole project and remembers it forever. You can always go back.
2. **Push = upload to GitHub.** GitHub is your off-site backup. Committing saves *locally*; pushing copies those saves to the cloud.

Rhythm: **make changes → commit (save) → push (back up).** The active coding agent does all three.

---

## Branch model

| Branch | What it is |
|---|---|
| `dev` | Daily work. This is the workshop. |
| `main` | The safe-fallback checkpoint. Only updated when a chunk of work is solid. |
| `v0.1.0`, `v0.2.0` ... | App version tags — snapshots worth remembering as releases. |
| `archive/...` | Old experiments or cleanup snapshots kept as quiet bookmarks, not active branches. |

**Rules:**

- Work happens on `dev`. `main` stays stable.
- Coding agents commit and push `dev` at natural checkpoints, then tell you in one plain sentence what was saved. No approval ceremony.
- `main` and version tags only move after the agent tells you in plain English what's moving and you say OK. That's your safety net: if anything ever goes wrong on `dev`, `main` is a known-good version to fall back to.
- Agents keep GitHub branches tidy. Old experiments should be archived as tags, then deleted as branches.
- Agents never rewrite history or delete saved work.

---

## What you can ask an agent

| You say | What happens |
|---|---|
| *(nothing)* | The agent saves and backs up as it works, and tells you after |
| "what's changed?" | Plain-English rundown of unsaved/unbacked-up work |
| "update main" / "checkpoint this" | The agent explains what would move to `main`, then does it on your OK |
| "tag this as v0.1.0" | The agent creates the version tag, on your OK |
| "undo that" | The agent rolls back the last change cleanly |
| "go back to the safe version" | The agent restores from `main` |

---

## Safety net

- **Once committed, it's safe.** Even if files are deleted afterward, the snapshot still has them.
- **Once pushed, there's a second copy on GitHub.** Two places, no single point of failure.
- **`main` never moves silently.** Your fallback version is always one you heard about and OK'd.

---

## If you ever want to drive yourself

These shortcuts still exist; you never need them:

| You type | What it does |
|---|---|
| `git status` | Shows what's changed — harmless, run anytime |
| `git save "what I changed"` | Saves a snapshot (commit) on `dev` |
| `git ship "what I changed"` | Saves **and** uploads to GitHub in one step |
| `git sync` | Uploads whatever's already saved |

---

*Short version: you build the product, agents keep the snapshots and backups, and `main` is the safe copy that only moves when you say so.*
