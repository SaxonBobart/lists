# CLAUDE.md — Lists project guide

## Project at a glance

**Lists** is a calm, local-first markdown app for tasks, habits, and notes. Single primitive: `item` with `type: task | habit | note`. Storage: per-list folder containing `.list.yml` plus `<itemId>.md` (markdown body + YAML frontmatter). iOS first; Android, Linux, Windows planned.

`PRODUCT-SPEC.md` is the source of truth for product behavior. `docs/CURRENT.md` is the "you are here" pointer for the active milestone.

## How to run iOS

```sh
cd platforms/ios
xcodegen generate
open Lists.xcodeproj
```

Or via XcodeBuildMCP: `build_run_sim` (defaults set in `.xcodebuildmcp/config.yaml`).

## Hard constraints (don't break these)

- **Bundle id**: `io.github.saxonbobart.lists`
- **Team**: Personal Team `899XX9P8T4` (Saxon's Apple ID — paid Developer Program not affordable yet)
- **AlarmKit deferred** until paid team. Milestone order: M5 → M7 → M8 → M9 → (back to M6) → App Store
- **Storage on iOS**: app-private (`Documents/Lists/` in sandbox). NOT iCloud Drive, NOT Files.app visible. `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` stay off
- **Storage on other platforms** (when added): user-visible folder in a native location
- **No Rust core in v1**. Each platform implements its own parser+cache against `shared/format/` schemas
- **No JetBrains Mono shipped on iOS** — uses SF Pro Rounded + SF Mono (built into iOS)
- **Spec is `PRODUCT-SPEC.md` (v2, single `item` primitive)**. The archive at `/Users/saxon/Developer/Projects/archive/lists` and `shared/format/` use the older "reminder" naming; align as you touch them

## Working with Saxon

- **Saxon is non-technical** (product owner, vibe coder). Frame technical decisions as product effects, not jargon
- **Lead with a recommendation in plain English.** Don't ask him to flip checkboxes on jargon tables (FSEvents, App Group, RRULE, CRDT, etc.)
- **If a decision has no user-visible difference**, decide and mention briefly — don't ask

## Discipline (apply to every change)

- **Conventional Commits**: `feat(scope):`, `fix(scope):`, `chore:`, `docs:`. Scope is usually `ios`, `shared`, `android`, etc.
- **Branch-per-milestone** for non-trivial work. M0 scaffolding goes directly on `main` (these are the first commits)
- **Never push to remote without explicit go**. Same for opening PRs, merging
- **Never edit `CLAUDE.md` or `.claude/settings.json` without explicit go**
- **Tests are not optional for the data layer** — the file format is the source of truth and roundtrip tests catch silent corruption
- **Drive the simulator before claiming iOS work done.** Unit tests miss UX bugs. Use XcodeBuildMCP `build_run_sim` + `screenshot` + `snapshot_ui` + `tap` to verify the actual flow on iPhone 17 Pro
- **Computer-use type-tool gotcha**: macOS long-press accent picker triggers on the simulator. Use `write_clipboard` + `cmd+v` (paste) instead of typing characters

## Folder layout

```
lists/
├── PRODUCT-SPEC.md          single source of truth for product behavior
├── README.md
├── LICENSE                  AGPL-3.0-or-later
├── CLAUDE.md                this file
├── .gitignore
├── .claude/                 project-scoped Claude config
├── .xcodebuildmcp/          XcodeBuildMCP session defaults
├── design/                  design handoff bundle (HTML prototype + tokens)
├── docs/
│   ├── CURRENT.md           "you are here" milestone tracker
│   └── session_logs/        per-session work log (YYYY-MM-DD.md)
├── research/                multi-platform research (PLAN.md is the synthesis)
├── shared/                  language-neutral contracts (format spec, fixtures, lexicons)
└── platforms/
    ├── ios/                 active platform — SwiftUI + Swift 6.2 + iOS 26
    ├── android/             placeholder (later milestone)
    ├── linux/               placeholder (later milestone)
    └── windows/             placeholder (later milestone)
```

## Out of scope (don't add without discussing)

- iCloud-based sync (paid sync service is the future answer; iCloud is not the mechanism)
- A web or Electron client (deferred indefinitely)
- A team / multi-user mode (single-user multi-device only in v1)
- A Rust core (every platform stays native)
- Telemetry, analytics, crash reporters (privacy-first; opt-in only if ever added)

## Active milestone

See `docs/CURRENT.md`.
