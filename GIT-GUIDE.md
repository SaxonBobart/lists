# Git, in plain English (for a solo project)

*A no-jargon guide to saving and backing up Lists. You're working alone, so this is deliberately tiny — ignore everything the internet tells you about branches, pull requests, and merges. You don't need them.*

---

## The 30-second mental model

Two ideas, that's it:

1. **Commit = a save point.** Every time you commit, Git takes a snapshot of the whole project and remembers it forever. You can always go back to any save point. Think "save game."
2. **Push = upload the save points to GitHub.** GitHub is your off-site backup (and the home of your code online). Committing saves *locally*; pushing copies those saves to the cloud so they're safe if your Mac dies.

So the rhythm is always: **make changes → commit (save) → push (back up).**

---

## Your setup (already done for you)

| Thing | Value |
|---|---|
| Where your code lives online | `github.com/SaxonBobart/lists` (a **private** repo — only you can see it) |
| The one branch that matters | **`main`** — this is your project. Everything is on it. |
| Logged in as | `SaxonBobart` (push access works) |

> You also have two leftover branches (`dev` and `editor-archive-2026-05-13`). **Ignore them.** They're old pointers, not separate projects. If you ever want them gone for a totally clean slate, just tell me "delete the old branches" and I'll do it.

---

## The only commands you'll ever need

I set up three shortcuts for you so you never have to remember the long versions.

| You type | What it does | When |
|---|---|---|
| `git save "what I changed"` | Saves a snapshot of everything (a commit) | After you've done some work |
| `git ship "what I changed"` | Saves **and** uploads to GitHub in one go | The one you'll use most |
| `git sync` | Just uploads whatever you've already saved | If you saved earlier and forgot to upload |

**Example.** You tweaked the editor and want it backed up:

```
git ship "tweaked the markdown editor toolbar"
```

That's the whole workflow. Make changes, run `git ship "..."`, done — saved locally *and* backed up to GitHub.

> Want to just see what you've changed but not save yet? `git status` lists it. Harmless, run it anytime.

---

## The easiest path of all: just ask me

You said you'd rather not deal with Git — so don't. Any time, just say:

> *"commit and push everything"*  — or  — *"back up my work"*

…and I'll do the `git ship` for you with a sensible message. The shortcuts above are there for when you want to do it yourself; they're not required.

---

## Safety net (how to not lose anything)

Git is built so you basically *can't* lose committed work. A few comfort facts:

- **Once you've committed, it's safe.** Even if you delete files afterward, the snapshot still has them.
- **Once you've pushed, there's a second copy on GitHub.** Two places, no single point of failure.
- **Undo a save you didn't mean to make:** tell me "undo my last commit" — I'll roll it back and keep your changes. Nothing is destroyed.
- **The golden habit:** when you finish a chunk of work, `git ship "..."`. That's it. Frequent small saves > rare giant ones.

---

## What you can safely ignore (forever, as a solo dev)

The internet makes Git sound terrifying. None of this applies to you:

- ❌ **Branches** — you have one (`main`). Don't make more.
- ❌ **Pull requests / merges** — those are for teams. You're a team of one.
- ❌ **`git pull` / merge conflicts** — only happen when two people (or two machines) edit at once. As long as you work on one Mac, you'll never see them.
- ❌ **Rebasing, cherry-picking, stashing** — power-user stuff you don't need.

If you ever *do* start working across two Macs, tell me and I'll add a one-line "get the latest" step. Until then: **`git ship "..."` is your whole world.**

---

## What this project is (the scope)

The full, living map is in **[OVERVIEW.md](OVERVIEW.md)** — read that for the real picture. The one-paragraph version:

> **Lists** is a local-first iOS app that combines tasks, habits, and notes into one calm, native experience, where everything is stored as plain text files you own — no account, no sign-in, fully private and offline. It's a polished, working app today; the current phase is *finish & polish* before a quiet, free App Store launch, with optional paid cloud sync planned for later.

For deep technical detail, the `audit/` folder has the full breakdown.

---

*This file is just your cheat-sheet. When in doubt: `git ship "what I did"`, or just ask me.*
