# Git, in plain English (solo project)

*A no-jargon guide to saving, backing up, and checkpointing Lists.*

---

## The two core ideas

1. **Commit = a save point.** Git takes a snapshot of the whole project and remembers it forever. You can always go back.
2. **Push = upload to GitHub.** GitHub is your off-site backup. Committing saves *locally*; pushing copies those saves to the cloud.

Rhythm: **make changes → commit (save) → push (back up).**

---

## Branch model

| Branch | What it is |
|---|---|
| `dev` | Daily work. This is your workshop. |
| `main` | Stable checkpoints. Only updated when a chunk of work is solid. |
| `v0.1.0`, `v0.2.0` ... | App version tags — snapshots worth remembering as releases. |
| Temp Claude branches | Experiments only. Never use for real work. Clean up after. |

**Rule:** Work happens on `dev`. `main` stays stable. Claude will never move `main` or create a tag without asking you first.

---

## The commands (shortcuts set up for you)

| You type | What it does |
|---|---|
| `git save "what I changed"` | Saves a snapshot (commit) on `dev` |
| `git ship "what I changed"` | Saves **and** uploads to GitHub in one step |
| `git sync` | Uploads whatever you've already saved |
| `git status` | Shows what's changed — harmless, run anytime |

**Example:**

```
git ship "fixed the section drag bug"
```

---

## Assisted checkpoint (the recommended way)

You don't have to run git commands yourself. Just say **"save my work"** or **"check in"** and Claude will:

1. Run `git status` and summarize what changed in plain English
2. Suggest a commit message
3. **Ask before committing** — you approve first
4. **Ask before pushing** — you approve separately

No silent automatic commits. Claude will always show you what it's about to do and wait for the OK.

---

## Moving work from dev to main

When a chunk of work is solid and you want to checkpoint it:

1. Tell Claude **"update main to match dev"** — Claude will fast-forward `main` and ask before pushing.
2. Optionally: tell Claude **"tag this as v0.1.0"** — Claude creates the tag and asks before pushing.

You stay in control. Nothing moves to `main` or gets tagged without your explicit OK.

---

## Safety net

- **Once committed, it's safe.** Even if you delete files afterward, the snapshot still has them.
- **Once pushed, there's a second copy on GitHub.** Two places, no single point of failure.
- **Undo a commit you didn't mean to make:** tell Claude "undo my last commit" — it rolls back cleanly and keeps your changes.
- **The golden habit:** when you finish a chunk of work, `git ship "..."` — or just ask Claude to do it.

---

## What you never need to worry about (solo dev)

- Pull requests and merges — those are for teams.
- Merge conflicts — only happen when two people edit at once.
- Rebasing, stashing, cherry-picking — power-user stuff you don't need.

---

*Short version: work on `dev`, ask Claude to save + push, and catch `main` up when things feel solid. That's it.*
