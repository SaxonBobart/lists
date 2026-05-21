---
description: Run the full test suite (ListsTests + ListsUITests).
argument-hint: "[only-testing-spec]"
---

If arguments are provided, scope with `onlyTesting: ["$ARGUMENTS"]` (e.g. `/test ListsUITests/AddItemTests/testTapFABOpensQuickCapture`). Otherwise run the whole `Lists.xctestplan`.

Always use `mcp__XcodeBuildMCP__test_sim`. After completion:
1. Read the xcresult path surfaced by the hook.
2. Report pass/fail count and any failures with file:line.
3. If failures look flaky, do NOT relax assertions — propose stability fixes per the gesture-test-author rules.
