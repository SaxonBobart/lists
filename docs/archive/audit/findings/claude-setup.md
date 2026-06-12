# Claude Code / Agent Tooling Audit

## Verdict
**Minor issues, with one real footgun.** The agent setup is unusually thoughtful — the two
hook scripts are safe and well-written, the slash commands and subagents are tightly scoped,
the accessibility-id convention is real and matches the code, and the snapshot/test counts in
the docs are accurate. The problems are (1) a machine-level permission config that silently
**disables every guardrail** the project docs claim to enforce, (2) a destructive `git reset
--hard` pre-approved on Saxon's machine, and (3) several guidance docs that have drifted out of
sync with reality — ghost `shared/`/`research/` dirs, a "UI tools aren't enabled" instruction
that's false, and a "non-negotiable" gesture rule the committed tests already violate. None
will silently corrupt data, but the drift will send a trusting agent down wrong paths, and the
permission config means the safety language in AGENTS.md is decorative on this machine.

## Findings

### [P1] `bypassPermissions` globally voids every project guardrail
- **Where:** `~/.claude/settings.json:3` (`"defaultMode": "bypassPermissions"`), reinforced by `skipAutoPermissionPrompt:true` and `skipDangerousModePermissionPrompt:true` (lines 27-28)
- **What:** Saxon's user-level Claude config runs in bypass-permissions mode, so **no command prompts for approval** — not `git push`, not `git reset --hard`, not `rm -rf`. The carefully-curated allow-lists in `.claude/settings.json` and `.claude/settings.local.json` become irrelevant (an allow-list only matters when there's a prompt to skip), and AGENTS.md's repeated "never push/merge/force-push/destructive-cleanup without explicit approval" (AGENTS.md:103-104) is unenforceable here. The MEMORY note "never push/PR/merge without explicit go" is, on this machine, honor-system only.
- **Impact:** A misfiring agent can push to a remote, hard-reset the branch, or delete files with zero friction. For a solo non-technical owner doing autonomous overnight runs, that's the difference between "the agent asked first" and "the agent already did it."
- **Confidence:** High (config is explicit).
- **Fix:** This may be a deliberate choice for unattended runs — if so, document it loudly in AGENTS.md so future agents know the prompts won't save them and must self-restrain. Otherwise switch `defaultMode` to `"default"` (or `"acceptEdits"`) and rely on the per-tool allow-lists already written. At minimum add `"deny"` entries for `git push`, `git reset --hard`, `git rebase`, and `rm -rf` so even bypass mode blocks them.

### [P2] A `git reset --hard <old-sha>` is pre-approved on Saxon's machine
- **Where:** `.claude/settings.local.json:9` — `Bash(git -C /Users/saxon/Developer/Projects/lists reset --hard 90dc32a)`
- **What:** This exact destructive command is allow-listed. `90dc32a` is a real commit ("inline date/time pickers…") that currently sits **22 commits behind HEAD** (`2b224f3`). If any agent ever reconstructs and runs that command, it discards 22 commits of work with no prompt (and given the P1 above, no prompt would fire anyway). Allow-listing a *specific destructive invocation* is a leftover from a one-time recovery; it has no business persisting.
- **Impact:** Latent landmine. Low odds an agent re-issues the exact string, but the cost if it does is catastrophic and silent.
- **Confidence:** High that it's allow-listed; Low that an agent would trigger it.
- **Fix:** Delete lines 5-9 of `settings.local.json` (the `bundle create` and `reset --hard` one-shots). These are recovery artifacts, not standing permissions. `settings.local.json` is gitignored (`.gitignore:68`) so this only affects Saxon's machine, but it's still a loaded gun in the drawer.

### [P2] AGENTS.md tells agents to enable UI-automation tools that are already enabled
- **Where:** `AGENTS.md:31` vs `.mcp.json:10` and `.xcodebuildmcp/config.yaml:4`
- **What:** AGENTS.md states "Tap / swipe / touch / type tools are **not** enabled in the default XcodeBuildMCP workflow… enable the UI Automation workflow… until then, drive launch state via `launchArgs`." But `ui-automation` is already in `enabledWorkflows` in **both** config files, and the PreToolUse hook matcher (`settings.json:5`) explicitly matches `tap|swipe|gesture|long_press|touch|type_text|...` — i.e. those tools are live and expected. The doc describes a past state.
- **Impact:** An agent reads this, believes `tap`/`swipe` are unavailable, and either wastes a turn "enabling" a workflow that's on, or contorts itself into the obsolete `launchArgs`-only workaround instead of just driving the UI. Actively misleading.
- **Confidence:** High.
- **Fix:** Rewrite AGENTS.md:31 to say UI-automation tools ARE enabled (per `.xcodebuildmcp/config.yaml`), keep the `snapshot_ui`-before-coordinates rule, and drop the "until then" workaround.

### [P2] The "non-negotiable" `thenHoldForDuration: 0` rule is contradicted by the committed tests
- **Where:** Rule in `AGENTS.md:60-62` ("don't relax them") and `gesture-test-author.md:15` (rule #5: `thenHoldForDuration: 0.0` because "broken in current XCUITest"; `withVelocity: .default` because `.fast`/non-default "gets interpreted as swipe"). Violated in `ItemReorderTests.swift:26-29` & `:55-58` and `SectionReorderTests.swift:24-27` — all use raw `start.press(..., withVelocity: .slow, thenHoldForDuration: 0.5)`.
- **What:** The subagent's stability doctrine says (a) always use `thenHoldForDuration: 0`, (b) use the `pressAndDrag`/`commitDrag` helpers, (c) use `.default` velocity. The two reorder test files — the exact gesture the helpers were built for — bypass `pressAndDrag` entirely, hard-code `thenHoldForDuration: 0.5`, and use `.slow`. So the codebase ships two opposite "correct" patterns: the helper (`ListsUITestsSupport.swift:39-47`, hold=0) and the inline reorder tests (hold=0.5). Note the whole UITest suite is committed as "scaffolding, unverified" (commit `10f40b7`), so it's plausible neither pattern is proven to pass.
- **Impact:** A future agent invoking `/gesture-test` is told one rule is non-negotiable, then sees the existing tests doing the opposite. It can't tell which is right, and "match the existing code" leads it to violate the documented rule. Erodes trust in the whole rule set.
- **Confidence:** High (verified both files use the raw call with 0.5).
- **Fix:** Reconcile. Either the reorder tests are wrong (route them through `pressAndDrag`, set hold to 0) or the rule is wrong (some gestures need a non-zero hold) — pick one and make doc + helper + tests agree. Until the UITest suite is actually run to green, mark the rule "hypothesis, unverified" rather than "non-negotiable."

### [P2] `shared/` and `research/` directories are documented everywhere but don't exist
- **Where:** `AGENTS.md:11` (and the "Next Work" item `docs/CURRENT.md:82`), `README.md:46`, `PRODUCT-SPEC.md:99` ("shared recurrence docs"). Confirmed absent: `ls shared` / `ls research` → "No such file or directory". The retirement is recorded in commit `57fb450` and the MEMORY note "iOS-only (2026-05-19)".
- **What:** Three top-level docs describe `shared/` as containing "format schemas, fixtures, and cross-platform contracts" and instruct agents to "align them when next touched" / "realign `shared/format/` wording." There is nothing to touch. `research/` is referenced in this audit's own context too.
- **Impact:** An agent asked to "update the format contract" or "align the shared schema" will hunt for a directory that was deleted, then either fabricate it or stall. README's "Useful Docs" list points a newcomer at a dead path.
- **Confidence:** High.
- **Fix:** Remove the `shared/` bullet from AGENTS.md:11, the README:46 entry, the PRODUCT-SPEC:99 "shared recurrence docs" reference, and the `docs/CURRENT.md:82` "Realign shared/format/" Next-Work item. They're vestigial multi-platform scaffolding.

### [P3] `docs/CURRENT.md` test counts have drifted (8 vs 9 UITest classes)
- **Where:** `docs/CURRENT.md:16` says "`ListsUITests` (XCUITest scaffolding, 8 classes)."
- **What:** There are now **9** test classes under `platforms/ios/ListsUITests/` (AddItem, ItemReorder, MarkdownEditor, SectionReorder, SheetPresentation, SidebarReorder, SmartListNavigation, SwipeActions, plus `ListsUITestsPreflight`). The "49 tests" / "48 baseline images" figures elsewhere (`docs/CURRENT.md:16`, `README.md:36`) are accurate — verified 49 `func test`/`@Test` and exactly 48 committed PNGs — so this is an isolated stale count.
- **Impact:** Trivial. A status doc undercounts by one; no agent will act wrongly on it. Flagged only because the surrounding numbers are otherwise exact, so the drift stands out.
- **Confidence:** High.
- **Fix:** Update to "9 classes," or drop the count (it'll drift again).

### [P3] `xcresult-surfacer.sh` runtime-log regex is over-broad
- **Where:** `.claude/hooks/xcresult-surfacer.sh:12` — `grep -oE '/[A-Za-z0-9._/-]+\.log'`
- **What:** The runtime-log matcher grabs the **first** `*.log` path anywhere in the tool output. If XcodeBuildMCP output ever contains an unrelated `.log` line before the real runtime log, the hook surfaces the wrong path. (The `xcresult` and `build_log` regexes are appropriately anchored — `.xcresult` and `/Logs/Build/…\.xcactivitylog` — so only the runtime one is loose.)
- **Impact:** Cosmetic/informational only. The hook prints paths to stderr; it never executes anything, and `/tail-logs` re-derives the path from the actual tool output. Worst case the agent is shown a slightly-wrong log path and notices.
- **Confidence:** Med (depends on tool-output format I can't fully enumerate).
- **Fix:** Anchor it to the expected runtime-log shape (e.g. require `sim`/`run`/the bundle id in the path) or take the *last* `.log` match rather than the first. Low priority.

## Strengths
- **Both hook scripts are genuinely safe.** `set -euo pipefail`, `printf '%s'` (no format-string surprises), and crucially the path regexes use a character class (`[A-Za-z0-9._/-]`) that *excludes* every shell metacharacter (`;`, space, `$`, `` ` ``, `(`, `)`, quotes). I probed it with a malicious `;rm -rf` / `$(...)` path — it captures nothing. And the `open '$xcresult'` line is **printed to stderr, never executed**, so even a captured path can't run. No injection surface. `snapshot-ui-reminder.sh` is a static heredoc that consumes no input. (`.claude/hooks/*.sh`)
- **Statusline uses the correct safe pattern.** `eval "$(jq -r '@sh ...')"` — `@sh` is jq's shell-quoting operator applied to all 10 fields, the textbook-correct way to safely move JSON into shell vars. (`~/.claude/statusline-command.sh:4-15`)
- **The accessibility-id convention is real, not aspirational.** Every id AGENTS.md:73-79 cites (`floating.add`, `item.notes.expand`, `markdown.editor`, `sidebar.reorder.toggle`, `quickcapture.save/title`) resolves to actual source. The `--ui-testing-reset-data` flag AGENTS.md:87 describes is implemented exactly as claimed (`ListsApp.swift:27-28`). The `scrollToHittable`/`commitDrag` helpers the subagent references exist (`ListsUITestsSupport.swift`).
- **Subagents are tightly and correctly scoped.** `build-and-test` is given Read/Bash/MCP but **no Edit/Write**, with the prompt repeatedly reinforcing "you cannot modify any file" and "don't make a test pass by changing what's tested" — exactly right for a report-only loop. `gesture-test-author` is scoped to `ListsUITests/` + accessibility-id-only edits to app source.
- **Slash commands are minimal and consistent** with the MCP-first workflow; the `Lists.xctestplan` referenced by `/test` exists and wires both targets. Project `.claude/settings.json` permissions are conservative (read-ish MCP + two `xcodegen` invocations + `open *.xcresult` — no blanket `Bash` allow).

## Coverage
Read in full: `AGENTS.md`, `CLAUDE.md`, `README.md`, `PRODUCT-SPEC.md`, `docs/CURRENT.md`,
`design/ios-design-rules.md`; all of `.claude/agents/*.md`, `.claude/commands/*.md`,
both `.claude/hooks/*.sh`; `.claude/settings.json`, `.claude/settings.local.json`, `.mcp.json`,
`.xcodebuildmcp/config.yaml`; `~/.claude/settings.json`, `~/.claude/statusline-command.sh`.
Cross-checked doc claims against code: directory existence, test/snapshot counts, the
reset-data flag, accessibility ids, gesture-helper presence, the `thenHoldForDuration`/velocity
rule vs the actual reorder tests, the `git reset` SHA's distance from HEAD, and `ui-automation`
workflow enablement. Did not run anything (read-only). Plugin/marketplace internals
(`superpowers`, `ios-simulator-skill`) referenced in `~/.claude/settings.json` were noted but
their source is outside this repo and out of scope.
