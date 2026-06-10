# Current Status

## Active Work

The active implementation is the iOS app in `platforms/ios/`.

Work should happen on `dev`. Keep `main` stable.

## Environment: Xcode 27 beta (since 2026-06-10)

Saxon has moved all devices and daily work to the Xcode 27 / OS 27 betas
(no rollback planned). Practical consequences for agent sessions — see
`docs/research/xcode-27-agentic-testing.md` for sources:

- **XcodeBuildMCP UI driving is broken** under Xcode 27 (bundled AXe
  can't find SimulatorKit.framework — getsentry/XcodeBuildMCP#446; no
  fixed release as of 2026-06-10, latest is v2.6.2). Expect `tap`,
  `swipe`, `gesture`, `snapshot_ui` to fail. Build/test/install/launch/
  `screenshot` (xcodebuild/simctl-based) still work. Check for a newer
  XcodeBuildMCP release at the start of each Mac session.
- **Simulator.app no longer exists** — Device Hub is the simulator GUI.
  `open_sim` behavior may differ.
- **Interim interaction loop:** Apple's native agent simulator tools
  (boot / install / launch / touch synthesis / screenshots) via Xcode's
  coding assistant or `xcrun mcpbridge`. First Mac session on the beta
  should enumerate mcpbridge's tool list to learn whether the simulator
  tools are exposed to external agents.
- **Adaptive layout matters on iOS now:** Device Hub adds dynamic
  simulator resizing (foldable-prep). Avoid fixed-size/orientation
  assumptions in new iOS UI; resize-test new screens in Device Hub.
- Gesture XCUITests are frozen smoke coverage only (see AGENTS.md
  "Reality check") — verify interactions via a driven session.

## What Exists

- SwiftUI app project: `platforms/ios/Lists.xcodeproj`
- XcodeGen spec: `platforms/ios/project.yml`
- XcodeBuildMCP defaults: `.xcodebuildmcp/config.yaml`
- Core models, file storage, frontmatter codec, sample data, smart lists, tags, reminders, and notification scheduling
- Main screens for sidebar, today, smart lists, list detail, item detail, quick capture, habits, search, settings, recently deleted, tags, and thread view
- Test targets `ListsTests` (XCTest + swift-snapshot-testing, 49 tests) and `ListsUITests` (XCUITest scaffolding, 8 classes)

## Markdown editor — rebuilt 2026-05-13

The full coordinator + editor view was reset on this branch and
rebuilt under TDD. Pre-fix `MarkdownTextView.swift` (920 LOC,
zero unit tests) is preserved verbatim in the
`editor-archive-2026-05-13` worktree at
`/Users/saxon/Developer/Projects/lists-editor-archive`.

The replacement is a glue-only `MarkdownTextView.swift` (~110 LOC)
plus focused pure-transform modules under
`platforms/ios/Lists/Features/MarkdownEditor/`:

- `EditorIntent.swift` — tagged enum + `apply(to:selection:)` dispatch
- `ListContinuation.swift` — smart Return (bullet / numbered / task
  / blockquote / nested-indent continuation; empty-marker exit)
- `IndentHandler.swift` — Tab / Shift-Tab line indent + outdent
- `BackspaceHandler.swift` — smart Backspace (strip marker + join
  with previous line; outdent first when nested)
- `CursorSnapping.swift` — phantom marker-zone snap +
  content-column Up/Down arrow tracking
- `CheckboxToggler.swift` — tap-on-bracket toggles `[ ]` ↔ `[x]`
- `PasteHandler.swift` — source-verbatim paste (CRLF → LF, BOM
  strip, tab → 4 spaces; smart-typography off)
- `ToolbarAction.swift` — 25 Apple-Reminders-style toolbar buttons
  (bold / italic / strike / highlight / code / heading 1..6 /
  paragraph / bullet / numbered / task / blockquote / indent /
  outdent / link / image / code-block / table / hr / wikilink /
  footnote / math-inline / math-display / mermaid)
- `MarkdownReminderToolbar.swift` — the SwiftUI/UIKit accessory
  bar above the keyboard
- `ExtensionParsers.swift` — regex helpers for wikilinks,
  footnotes, math, mermaid

Test infrastructure was rebuilt on 2026-05-21 with a three-layer
stack: snapshot tests for view-layer regression, XCUITest for
gestures and flows, XcodeBuildMCP for in-session exploration. See
AGENTS.md "How to verify iOS work" for details.

## List nesting — landed 2026-05-19

Lists nest arbitrarily deep. Sidebar renders as a collapsible tree
(chevron column on the left, 20pt indent per depth); collapse state
persists across launches. Reorder mode entered via a pencil in the
"My Lists" header — system drag handles, drop-on-row to nest,
drop-between-rows to reorder siblings (parent-aware), swipe + long-press
disabled while active. List detail gains a collapsible "Sub-Lists"
section above its items. Three creation paths (sidebar long-press,
list ••• menu, root + with parent picker). Shared `ParentPickerSheet`
also drives the "Move to…" flow with a cycle guard.

On disk, folder names mirror the sanitized list display name and nest
on the filesystem — `Documents/Lists/Trip planning/Packing/.list.yml`
— so the storage tree reads cleanly on extract. Stable ids continue
to live inside `.list.yml`. Rename and reparent physically move the
folder. Sibling-name collisions auto-suffix `(N)`. `FileStore.loadAll`
silently migrates the legacy `<root>/<listId>/` layout on first launch
after upgrade.

## Next Work

- Render math via KaTeX in `MarkdownBodyView` (WKWebView bridge).
- Render mermaid via mermaid.js in `MarkdownBodyView` (WKWebView
  bridge).
- Tappable wikilinks: cross-item navigation when the wikilink
  resolves to an existing list/item.
- Defer Android, Linux, Windows, sync, and AlarmKit until
  explicitly requested.

## Constraints

- Bundle id: `io.github.saxonbobart.lists`
- Apple team: `LM99LGYW87` (Saxon's personal Apple ID, free signing only)
- AlarmKit is deferred until a paid Apple Developer Program account exists
- iOS data stays app-private in `Documents/Lists/`
- Use XcodeBuildMCP for build, test, run, screenshots, logs, and UI snapshots
