# Current Status

## Active Work

The active implementation is the iOS app in `platforms/ios/`.

Work should happen on `dev`. Keep `main` stable.

## What Exists

- SwiftUI app project: `platforms/ios/Lists.xcodeproj`
- XcodeGen spec: `platforms/ios/project.yml`
- XcodeBuildMCP defaults: `.xcodebuildmcp/config.yaml`
- Core models, file storage, frontmatter codec, sample data, smart lists, tags, reminders, and notification scheduling
- Main screens for sidebar, today, smart lists, list detail, item detail, quick capture, habits, search, settings, recently deleted, tags, and thread view
- Swift Testing and XCTest coverage, including Markdown editor tests

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

Test coverage (all green):
- `ListsTests`: **227/227** — 49 behaviour + 30 toolbar + 12
  paste + 18 extension parsers + 4 GFM-corpus iteration + 59
  styler + 12 fixture round-trip + 43 model/store
- `ListsUITests`: **20/20** for toolbar tour + paste tour;
  pre-existing smoke + inline + cursor tests intact

Two pre-existing styler bugs from 9f6922b
(`leadingWhitespaceVisibleWhenCursorOnLine`,
`nestedLineFirstLineHeadIndentShrinksWhenCursorOnLine`) were also
fixed in this branch — the styler corpus is fully green for the
first time since those tests were authored.

## Next Work

- Render math via KaTeX in `MarkdownBodyView` (WKWebView bridge).
- Render mermaid via mermaid.js in `MarkdownBodyView` (WKWebView
  bridge).
- Tappable wikilinks: cross-item navigation when the wikilink
  resolves to an existing list/item.
- Realign `shared/format/` wording with the iOS `Item` model when
  the format contract is next touched.
- Defer Android, Linux, Windows, sync, and AlarmKit until
  explicitly requested.

## Constraints

- Bundle id: `io.github.saxonbobart.lists`
- Apple team: `LM99LGYW87` (Saxon's personal Apple ID, free signing only)
- AlarmKit is deferred until a paid Apple Developer Program account exists
- iOS data stays app-private in `Documents/Lists/`
- Use XcodeBuildMCP for build, test, run, screenshots, logs, and UI snapshots
