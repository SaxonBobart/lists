# Git, in plain English (solo project)

*A no-jargon guide to how Lists is saved, backed up, and checkpointed.*

**The short version: Claude handles git. You never need to run a git command.**
(Arrangement as of 2026-06-13 — Saxon asked for git to be fully handled.)

---

## The two core ideas

1. **Commit = a save point.** Git takes a snapshot of the whole project and remembers it forever. You can always go back.
2. **Push = upload to GitHub.** GitHub is your off-site backup. Committing saves *locally*; pushing copies those saves to the cloud.

Rhythm: **make changes → commit (save) → push (back up).** Claude does all three.

---

## Branch model

| Branch | What it is |
|---|---|
| `dev` | Daily work. This is the workshop. |
| `main` | The safe-fallback checkpoint. Only updated when a chunk of work is solid. |
| `v0.1.0`, `v0.2.0` ... | App version tags — snapshots worth remembering as releases. |

**Rules:**

- Work happens on `dev`. `main` stays stable.
- Claude commits and pushes `dev` on its own at natural checkpoints, then tells you in one plain sentence what was saved. No approval ceremony.
- `main` and version tags only move after Claude tells you in plain English what's moving and you say OK. That's your safety net: if anything ever goes wrong on `dev`, `main` is a known-good version to fall back to.
- Claude never rewrites history or deletes saved work.

---

## What you can say to Claude

| You say | What happens |
|---|---|
| *(nothing)* | Claude saves and backs up as it works, and tells you after |
| "what's changed?" | Plain-English rundown of unsaved/unbacked-up work |
| "update main" / "checkpoint this" | Claude explains what would move to `main`, then does it on your OK |
| "tag this as v0.1.0" | Claude creates the version tag, on your OK |
| "undo that" | Claude rolls back the last change cleanly |
| "go back to the safe version" | Claude restores from `main` |

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

*Short version: you build the product, Claude keeps the snapshots and backups, and `main` is the safe copy that only moves when you say so.*
