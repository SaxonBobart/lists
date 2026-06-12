---
description: Run the test suite (ListsTests).
argument-hint: "[only-testing-spec]"
---

If arguments are provided, scope with `extraArgs: ["-only-testing:$ARGUMENTS"]` (e.g. `/test ListsTests/SnapshotTests/ItemRowSnapshotTests`). There is no `onlyTesting` parameter — scoping goes through `extraArgs`. Otherwise run the whole `Lists.xctestplan`.

Always use `mcp__XcodeBuildMCP__test_sim`. After completion:
1. Read the xcresult path surfaced by the hook.
2. Report pass/fail count and any failures with file:line.
3. If failures look flaky, do NOT relax assertions — investigate the root cause and propose a stability fix.
