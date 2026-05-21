---
description: Inspect the current simulator screen — snapshot_ui (always) + screenshot (optional). Read-only.
argument-hint: "[--screenshot]"
---

1. Call `mcp__XcodeBuildMCP__snapshot_ui` and summarize the accessibility tree.
2. If `--screenshot` flag passed, also call `mcp__XcodeBuildMCP__screenshot` and surface the image path.
3. NEVER tap, swipe, or otherwise mutate state during this command.
