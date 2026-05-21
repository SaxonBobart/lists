---
description: Surface the runtime log path from the last build_run_sim call. Does NOT re-launch.
---

Show the runtime log path from the most recent `mcp__XcodeBuildMCP__build_run_sim` output in this session. If no such call has been made, say so — do not re-implement log capture by tailing system log paths. Suggest the user run `/build` then re-invoke `/tail-logs`.

Filtering: if the user passes a search term, grep the log file with `grep -i <term>` and show matching lines.
