---
description: Incremental build of the Lists app via XcodeBuildMCP.
---

Run `mcp__XcodeBuildMCP__build_sim` against session defaults. If the build fails:
1. Read the build log path the hook surfaced.
2. Summarize the first 3 errors with file:line and a one-line cause.
3. Stop. Do not attempt fixes unless explicitly asked.
