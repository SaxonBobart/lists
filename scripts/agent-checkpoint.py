#!/usr/bin/env python3
"""Save explicitly reviewed task files and push the development branch.

Agents invoke this at verified checkpoints, as required by AGENTS.md. This is
not a timer or a chat hook: it never publishes arbitrary in-progress edits.
"""

import argparse
from pathlib import Path
import subprocess
import sys


class CheckpointError(Exception):
    pass


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def validate(root, paths):
    branch = git(root, "symbolic-ref", "--quiet", "--short", "HEAD")
    if branch in {"main", "master"} or branch.startswith("archive/"):
        raise CheckpointError(f"Automatic publishing is disabled on {branch}.")
    urls = git(root, "remote", "get-url", "--push", "--all", "origin").splitlines()
    allowed = {
        "https://github.com/SaxonBobart/lists.git",
        "https://github.com/SaxonBobart/lists",
        "git@github.com:SaxonBobart/lists.git",
        "ssh://git@github.com/SaxonBobart/lists.git",
    }
    if not urls or any(url not in allowed for url in urls):
        raise CheckpointError("origin must push only to SaxonBobart/lists on GitHub.")
    if git(root, "diff", "--cached", "--name-only"):
        raise CheckpointError("Files are already staged; preserve and review that index first.")
    clean_paths = []
    for value in paths:
        relative = Path(value)
        if (relative.is_absolute() or ".." in relative.parts or not relative.parts
                or value.startswith(":") or any(char in value for char in "*?[\n\r")):
            raise CheckpointError("Use explicit repository-relative paths, not the whole repository.")
        # Deleted tracked paths are valid. Symlinks to outside files are not.
        resolved = (root / relative).resolve()
        if not resolved.is_relative_to(root.resolve()):
            raise CheckpointError(f"Path leaves the repository: {value}")
        if any(part == ".git" for part in relative.parts):
            raise CheckpointError("Git internals cannot be checkpointed.")
        clean_paths.append(relative.as_posix())
    # Expand directories using Git, so credential checks apply to their contents.
    candidates = git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *clean_paths)
    for value in candidates.split("\0"):
        name = Path(value).name.lower()
        if (name == ".env" or name.startswith(".env.") and name != ".env.example"
                or Path(value).suffix.lower() in {".pem", ".p12", ".p8", ".key", ".mobileprovision"}):
            raise CheckpointError(f"Possible credentials require separate review: {value}")
    return branch, clean_paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--message", required=True)
    parser.add_argument("--check", action="store_true", help="Validate and show scope without staging, committing or pushing")
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        branch, paths = validate(root, args.paths)
        if not args.message.strip():
            raise CheckpointError("A descriptive commit message is required.")
        subprocess.run(["git", "-C", str(root), "diff", "--check", "--", *paths], check=True)
        if args.check:
            print(f"Ready: {branch} -> origin/{branch}; reviewed scope: {', '.join(paths)}")
            return
        subprocess.run(["git", "-C", str(root), "add", "--", *paths], check=True)
        if git(root, "diff", "--cached", "--name-only"):
            subprocess.run(["git", "-C", str(root), "diff", "--cached", "--check"], check=True)
            subprocess.run(["git", "-C", str(root), "commit", "-m", args.message], check=True)
        # Explicit refspec avoids accidentally pushing tags or another branch.
        # Normal push rejects non-fast-forward updates; no automatic rewrites.
        subprocess.run(["git", "-C", str(root), "push", "--set-upstream", "origin", f"HEAD:refs/heads/{branch}"], check=True)
        print(f"Published {git(root, 'rev-parse', '--short', 'HEAD')} to {branch}.")
        if branch != "dev":
            print("Agent next step: create/update one draft PR targeting dev, then link it in the host.")
    except (CheckpointError, subprocess.CalledProcessError) as error:
        print(f"Checkpoint stopped: {error}. Existing files/commits are preserved.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
