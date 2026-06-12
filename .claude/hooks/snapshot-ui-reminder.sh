#!/usr/bin/env bash
# PreToolUse hook for XcodeBuildMCP's coordinate-based UI tools.
# Stateless tripwire — these tools are BROKEN under Xcode 27.

set -euo pipefail

cat <<'EOF' >&2
[hook] STOP: this XcodeBuildMCP UI tool (tap/swipe/gesture/type_text/...) is
       BROKEN under Xcode 27 — AXe hardcodes the old SimulatorKit path
       (getsentry/XcodeBuildMCP#446). It will fail.
       Drive UI via the xcode MCP DeviceInteraction loop instead:
       StartSession -> InstallAndRun -> Synthesize -> EndSession.
       Hierarchy-first: tap only at center: coordinates / accessibility ids
       returned by DeviceInteractionSynthesize — never guess from screenshots.
       (If a future XcodeBuildMCP release fixes AXe, update this hook and
       AGENTS.md -> MCP Tools together.)
EOF

# Exit 0 = informational; do not block.
exit 0
