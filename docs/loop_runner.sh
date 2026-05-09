#!/usr/bin/env bash
# loop_runner.sh — Ralph loop runner for the Lists project.
#
# Reads docs/PROMPT.md, pipes it to `claude -p` repeatedly, and logs each
# iteration's outcome to docs/LOOP.md. Stops when --max-iterations reached,
# when BACKLOG runs out, or when 3 consecutive iterations report BLOCKED.
#
# USAGE:
#   ./docs/loop_runner.sh                     # 15 iterations, 10s sleep
#   ./docs/loop_runner.sh --max-iterations 5
#   ./docs/loop_runner.sh --sleep 30
#   ./docs/loop_runner.sh --dry-run           # print what would happen, don't call claude
#
# REQUIREMENTS:
#   - `claude` CLI installed and authenticated (you can `claude --version` to confirm)
#   - Run from the repo root

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MAX_ITERATIONS=15
SLEEP_BETWEEN=10
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-iterations) MAX_ITERATIONS="$2"; shift 2 ;;
        --sleep)          SLEEP_BETWEEN="$2"; shift 2 ;;
        --dry-run)        DRY_RUN=1; shift ;;
        *) echo "unknown arg: $1"; exit 2 ;;
    esac
done

PROMPT_FILE="docs/PROMPT.md"
LOOP_LOG="docs/LOOP.md"
BACKLOG_FILE="BACKLOG.md"

if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Missing $PROMPT_FILE. Cannot run the loop."
    exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
    echo "Claude CLI not found in PATH. Install with: npm install -g @anthropic-ai/claude-code"
    exit 1
fi

backlog_is_empty() {
    ! grep -qE '^- \[ \] ' "$BACKLOG_FILE" 2>/dev/null
}

consecutive_blocked=0
iteration=0

echo "Ralph loop starting in $REPO_ROOT"
echo "Max iterations: $MAX_ITERATIONS · Sleep: ${SLEEP_BETWEEN}s · Dry-run: $DRY_RUN"

while (( iteration < MAX_ITERATIONS )); do
    iteration=$((iteration + 1))

    if backlog_is_empty; then
        echo "BACKLOG empty. Stopping after $((iteration - 1)) iterations."
        break
    fi

    echo "----- iter $iteration of $MAX_ITERATIONS -----"
    timestamp="$(date '+%Y-%m-%d %H:%M')"

    if (( DRY_RUN == 1 )); then
        echo "[dry-run] would feed $PROMPT_FILE to claude"
        sleep 1
        continue
    fi

    # Run a single Claude iteration. Output goes to stdout so you can watch.
    output="$(cat "$PROMPT_FILE" | claude -p --dangerously-skip-permissions 2>&1)"
    echo "$output"

    if echo "$output" | grep -q "ITERATION COMPLETE"; then
        consecutive_blocked=0
        echo "$timestamp · iter $iteration · runner saw ITERATION COMPLETE" >> "$LOOP_LOG"
    elif echo "$output" | grep -q "ITERATION BLOCKED"; then
        consecutive_blocked=$((consecutive_blocked + 1))
        echo "$timestamp · iter $iteration · runner saw ITERATION BLOCKED ($consecutive_blocked consecutive)" >> "$LOOP_LOG"
        if (( consecutive_blocked >= 3 )); then
            echo "Three consecutive BLOCKED iterations. Stopping."
            break
        fi
    else
        echo "$timestamp · iter $iteration · runner saw NO sentinel — assuming exit OK" >> "$LOOP_LOG"
        consecutive_blocked=0
    fi

    sleep "$SLEEP_BETWEEN"
done

echo "Ralph loop done. Iterations attempted: $iteration."
