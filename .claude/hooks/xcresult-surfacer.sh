#!/usr/bin/env bash
# PostToolUse hook for test_sim / build_* MCP tools.
# Parses the tool output for xcresult paths and surfaces them so failures
# are inspectable without re-running.

set -euo pipefail

INPUT="$(cat)"

xcresult=$(printf '%s' "$INPUT" | grep -oE '/[A-Za-z0-9._/-]+\.xcresult' | head -n 1 || true)
build_log=$(printf '%s' "$INPUT" | grep -oE '/[A-Za-z0-9._/-]+/Logs/Build/[A-Za-z0-9._/-]+\.xcactivitylog' | head -n 1 || true)
runtime_log=$(printf '%s' "$INPUT" | grep -oE '/[A-Za-z0-9._/-]+\.log' | head -n 1 || true)

if [[ -n "$xcresult$build_log$runtime_log" ]]; then
  echo "[hook] artefacts:" >&2
  [[ -n "$xcresult"    ]] && echo "  xcresult:    $xcresult" >&2
  [[ -n "$build_log"   ]] && echo "  build log:   $build_log" >&2
  [[ -n "$runtime_log" ]] && echo "  runtime log: $runtime_log" >&2
  [[ -n "$xcresult"    ]] && echo "  open xcresult: open '$xcresult'" >&2
fi

exit 0
