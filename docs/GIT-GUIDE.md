# Git for this project

Git saves named checkpoints of your source code. GitHub stores a separate copy
online. Saving a local commit and pushing it to GitHub are separate actions.
Neither backs up the personal data inside the iPhone app.

## Where to work

Use `/Users/saxon/Developer/Projects/lists` as the current project. Work on `dev`.
`main` is the stable fallback; it can intentionally be older than dev. A T3
worktree is another folder with its own checked-out version, so it may not contain
the latest current app. Check before copying or merging between them.

## Everyday routine

1. Make a small, coherent change.
2. Check the app or focused tests appropriate to that change.
3. Inspect `git status` and `git diff` to see what will be saved.
4. Ask the agent to save a local checkpoint with a descriptive commit message.
5. Explicitly ask to push dev when you want the commits backed up to GitHub.

A commit saves tracked and staged source files, not ignored build outputs or
files that were never added. Review new files before adding them; credentials
and personal exports do not belong in Git.

## Safe checks

Run these from the canonical project folder:

```sh
git status --short --branch
git log -5 --oneline
git diff --stat
```

`ahead` means local commits have not been pushed to the recorded remote branch.
`behind` means the remote has commits missing locally. Fetch updates that
information without replacing your working files.

## Recovery

Ask the agent to inspect a previous commit and recover only the files or changes
you need. Keep the current version recoverable first. Avoid force-push, hard
reset, and cleaning untracked files as routine fixes.

On 30 October, `d9b91a1` saved the current app and existing cleanup locally.
A separately verified working-folder backup also exists outside Git; details
are in [the health investigation](PROJECT-HEALTH-2026-10-30.md).
