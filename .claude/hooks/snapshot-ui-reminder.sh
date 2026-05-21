#!/usr/bin/env bash
# PreToolUse hook for coordinate-based UI MCP tools.
# Stateless reminder — backstop only. Real discipline lives in the
# gesture-test-author subagent prompt.

set -euo pipefail

cat <<'EOF' >&2
[hook] Reminder: call mcp__XcodeBuildMCP__snapshot_ui BEFORE this gesture tool.
       Use the accessibility id from the snapshot — never coordinates from a screenshot.
       If state changed since your last snapshot (sheet presented, list scrolled,
       item added/removed, any prior gesture), re-snapshot first.
EOF

# Exit 0 = informational; do not block.
exit 0
