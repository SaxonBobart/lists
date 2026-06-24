---
description: Inspect the current simulator screen — screenshot (always), XcodeBuildMCP UI hierarchy (optional). Read-only.
argument-hint: "[--hierarchy]"
---

1. Call `mcp__XcodeBuildMCP__screenshot` and surface the image path.
2. If `--hierarchy` is passed, call `mcp__XcodeBuildMCP__snapshot_ui` and surface the relevant accessibility IDs, labels, and frames. If that fails, fall back to the xcode MCP's DeviceInteraction loop (`DeviceInteractionStartSession` → `DeviceInteractionSynthesize` with no interaction → `DeviceInteractionEndSession`) after confirming Xcode is open with the Lists project.
3. NEVER tap, swipe, or otherwise mutate state during this command.
