---
description: Inspect the current simulator screen — screenshot (always), UI hierarchy via DeviceInteraction (optional). Read-only.
argument-hint: "[--hierarchy]"
---

1. Call `mcp__XcodeBuildMCP__screenshot` and surface the image path.
2. If `--hierarchy` is passed, read the UI hierarchy through the xcode MCP's DeviceInteraction loop (`DeviceInteractionStartSession` → `DeviceInteractionSynthesize` with no interaction → `DeviceInteractionEndSession`). Requires Xcode open with the Lists project. Do NOT call `mcp__XcodeBuildMCP__snapshot_ui` — it is broken under Xcode 27 (see AGENTS.md → MCP Tools).
3. NEVER tap, swipe, or otherwise mutate state during this command.
