#!/usr/bin/env bash
# PreToolUse hook for XcodeBuildMCP's coordinate-based UI tools.
# Stateless reminder — driven actions must be verified against fresh UI state.

set -euo pipefail

cat <<'EOF' >&2
[hook] XcodeBuildMCP UI driving is available, but DeviceHub can desync.
       Read the hierarchy before coordinate work, then verify every tap,
       swipe, or typed action with a fresh screenshot or snapshot before
       treating it as real app state.
       If driven actions report success but the UI does not change, fall back
       to the xcode MCP DeviceInteraction loop or Computer Use.
EOF

# Exit 0 = informational; do not block.
exit 0
