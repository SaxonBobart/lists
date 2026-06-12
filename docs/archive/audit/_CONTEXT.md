# Shared Audit Briefing — READ THIS FIRST

You are one of several parallel agents auditing the **Lists** project. Work strictly within your
assigned domain. This file gives you the shared context, the rules, the severity scale, and the
exact output format. Follow it precisely so all findings compose into one report.

## What Lists is
iOS-first, local-first app for **tasks, habits, and notes**. Goal feel: calm, native, fast, private.
SwiftUI with some UIKit (UIViewRepresentable bridges for collection views & the text editor).
Swift 6.2, iOS **26.0** deployment target. Repo root: `/Users/saxon/Developer/Projects/lists`.
App code: `/Users/saxon/Developer/Projects/lists/platforms/ios/Lists/`.

## Core model & storage (the heart of the app)
- **One primitive: `Item`** with `type` = task | habit | note. Items live in lists; lists have
  optional sections; items may have one parent item (threads/sub-items); lists nest arbitrarily.
- **Files are the source of truth.** Layout in the app-private sandbox (NOT Files.app / NOT iCloud):
  ```
  Documents/Lists/<list name>/.list.yml
                              <item-id>.md          # YAML frontmatter + markdown body
                              <child list name>/.list.yml ...
  ```
- `.list.yml` = list metadata (stable `id` lives inside; folder name is the sanitized display name).
  Rename/reparent **physically moves the folder**. Illegal chars → `-`; sibling collisions → `(N)`;
  empty name → `Untitled`. Soft-delete via **tombstone** fields (for future sync). Delete cascades
  to descendants. `FileStore.loadAll` silently migrates a legacy `<root>/<listId>/` layout.
- Smart lists (Today/Scheduled/Flagged/Urgent/Completed/All) are **live queries**, not stored.
- Tags are inline `#tag` parsed from the title. Markdown body is part of the item.

## Stack & dependencies
- **Yams** 5.1.2 (YAML), **MarkdownUI** 2.4.1 (rendering), swift-snapshot-testing 1.18.0 (tests).
- Custom markdown **editor** is UITextView/TextKit in `Features/MarkdownEditor/` (NOT a web view).
- Project shape via **XcodeGen** (`platforms/ios/project.yml`). Do NOT treat `project.pbxproj` or
  `*.xcscheme` as hand-edited — they are generated.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS: NO`. App Group entitlement `group.io.github.saxonbobart.lists`
  and URL scheme `lists://` are declared. Bundle `io.github.saxonbobart.lists`.

## Repo map (Swift, by size — your navigation aid)
```
Features/ListDetail/ListDetailCollectionView.swift   1880   (UIKit collection bridge)
Features/QuickCapture/QuickCaptureSheet.swift         1320
Features/MarkdownEditor/MarkdownStyler.swift          1233   (live syntax styling)
Features/ItemDetail/ItemDetailSheet.swift             1162
Features/Sidebar/SidebarView.swift                     657
Core/Stores/ItemStore.swift                            637   (the main store / ObservableObject)
Features/Habits/HabitDetailView.swift                  583
Features/ListDetail/ListDetailView.swift               518
Features/ListEdit/ListEditSheet.swift                  488
Features/MarkdownEditor/EditorCoordinator.swift        465
Features/SmartList/SmartListScreen.swift               451
Features/MarkdownEditor/ToolbarAction.swift            428
Features/Today/ItemRow.swift                           425
Features/SmartList/SmartListCollectionView.swift       347   (UIKit collection bridge)
Core/Bootstrap/SampleData.swift                        334
Features/Tags/TagsOverviewView.swift                   319
Features/Settings/SettingsView.swift                   299
Core/Storage/FileStore.swift                           276   (load/save/move/delete on disk)
Core/Models/Item.swift                                 266
Features/RecentlyDeleted/RecentlyDeletedView.swift     228
Core/Preferences/ListViewPreferences.swift             204
... (~100 Swift files, ~18,900 LOC total)
Core/Storage/FrontmatterCodec.swift                     61   (YAML frontmatter <-> model)
Core/Queries/SmartList.swift                            87
Core/Models/ItemList.swift                             160 ; HabitCycle.swift 121 ; Reminder.swift 97
Core/Notifications/NotificationScheduler.swift         106
```
Folders: `App/`, `Core/{Bootstrap,Models,Notifications,Preferences,Queries,Storage,Stores,Tags}`,
`Design/{Components,Tokens}`, `Features/{Habits,ItemDetail,ListDetail,ListEdit,MarkdownEditor,
QuickCapture,RecentlyDeleted,Search,Settings,Sidebar,SmartList,Tags,Thread,Today}`.

## Caveats — do not trust docs blindly (verify against code)
- `AGENTS.md` references a `shared/` directory and a `research/` directory — **both are absent**.
- Docs describe test targets variously; `ListsTests` + `ListsUITests` **exist but are marked
  "unverified/scaffolding"** in git history. Treat as untrusted until proven.
- `docs/CURRENT.md` lists "Next Work" (KaTeX/mermaid via WKWebView, tappable wikilinks). Use as a
  signal of intent, not proof of state.
Where you find doc-vs-code drift, log it (it's a real finding for maintainability).

## YOUR CONSTRAINTS — CRITICAL
- **READ-ONLY.** Do NOT edit, create, or delete ANY file except your one findings file. Do NOT
  modify source. Do NOT build, run the app, or run any git command that changes state (no commit,
  checkout, stash, reset). Read-only shell only (`grep`, `find`, `git log`, `git show`).
- **Read your files thoroughly** — open them fully and reason about real behavior. This is a deep
  audit, not a skim. The founder coded this largely with AI help and wants genuine scrutiny.
- **Be concrete and honest.** No vague "consider refactoring." Cite `path:line`. If something is
  actually well-built, say so — false alarms and empty praise are both failures.
- **Don't fabricate.** If you're unsure whether something is a bug, mark Confidence: Low and say
  what you'd need to confirm it.

## Severity scale
- **P0** — data loss, crash on a common path, or a privacy/security breach.
- **P1** — likely functional bug, serious correctness/UX break, or crash on a plausible edge path.
- **P2** — minor bug, real maintainability hazard, or a risky smell.
- **P3** — nit / polish / style.

## Output — write `audit/findings/<NAME>.md` (your prompt gives <NAME>)
```
# <Domain> Audit
## Verdict
2–4 sentences, plain English, readable by a non-technical product owner. Overall health of this
area: Solid / Minor issues / Needs attention / Concerning — and why.
## Findings
### [Pn] Short title
- **Where:** path:line
- **What:** plain-English description of the issue
- **Impact:** what the user/product actually experiences if this bites
- **Confidence:** High / Med / Low
- **Fix:** concrete, specific suggestion
(repeat; order P0 first)
## Strengths
Specific things genuinely well-built in this area (for an honest, reassuring picture).
## Coverage
What you read; anything in-scope you could not get to.
```
Then **return to the dispatcher a SHORT summary (≤150 words)**: count by severity, the single most
important issue, and the area's overall health label. Do NOT paste the whole file back.
