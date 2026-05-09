# 00 — Current State of the Repo (Phase 1 findings)

_Snapshot date: 2026-05-03. Branch: `cleanup/full-reset`. No git remote configured._

## TL;DR

Lists is a single-platform iOS app today, built fresh on the
markdown-native architecture described in `SPEC.md`. The product spec already
treats the on-disk file tree as the source of truth; the SwiftData/SQLite
"index" sitting alongside it is described in spec but **not yet implemented in
code** — the iOS app currently reads the entire snapshot from disk on each
launch via an `actor FileStore`. This is fine for v1 iOS but is the first thing
a second platform will want to formalise before reimplementing the parser
twice.

The repo also carries a much older multi-platform plan (`design/project/docs/app-plan.md`)
that predates `SPEC.md` and points at SQLite + per-platform native UI + a Rust
core. That plan is **stale on storage** (it predates the markdown decision) but
is **still useful** as a cross-platform UX reference, and the design wireframe
folder under `design/project/` already contains JSX/HTML mockups for **iPad,
macOS, Android, and Linux** (no Windows mockups exist).

## Repo layout (top level)

```
Lists/                        (top-level repo dir at /Users/saxon/Developer/Projects/Lists/)
├── README.md                 (3 lines — points at LICENSE, declares iOS-only)
├── LICENSE                   (1 line — "AGPL-3.0-only")  ⚠ see Discrepancies
├── SPEC.md                   (45 KB — canonical product spec, iOS-focused)
├── .gitignore                (covers Swift, Node, Rust(!), Tuist, Cocoapods, Carthage)
├── .xcodebuildmcp/
│   └── config.yaml           (XcodeBuildMCP defaults — iPhone 17 Pro sim, scheme Lists)
├── platforms/
│   ├── ios/                  (Lists.xcodeproj — the only built platform)
│   ├── android/              (skeleton only)
│   ├── windows/              (skeleton only)
│   └── linux/                (skeleton only)
├── shared/                   (cross-platform contracts: format, schemas, fixtures)
├── research/                 (this Phase 1–6 research run)
├── design/                   (read-only wireframe reference; see "Design assets" below)
└── docs/
    └── design/               (component/density docs that mirror iOS code)
```

`platforms/{android,windows,linux}/`, `shared/`, and `research/` were created
fresh for this overnight research run; their content is described in
`PLAN.md`. The follow-up "consolidate the branding" + "change everything to
match" pass moved iOS from `apps/ios/` to `platforms/ios/`, renamed the
target/scheme/folders/bundle id from `OpenReminders` to `Lists`, and updated
`docs/design/README.md` to track the iOS path move. A subsequent pass also
renamed the top-level repo directory `…/OpenReminders/` → `…/Lists/` and the
Claude Code memory namespace dir to match.

## iOS stack (as actually built, not as planned)

| Concern | What's in the code |
|---|---|
| Project format | **Plain Xcode project** (`platforms/ios/Lists.xcodeproj`). _No Tuist._ |
| Dependency manager | SPM via Xcode's resolved file. **One dep**: `Yams 5.4.0`. |
| Language | Swift 6 with strict concurrency (per CLAUDE.md). `actor` + `Sendable` everywhere I looked. |
| UI | SwiftUI on iOS 26+ (deployment target `26.0`, per SPEC §3). |
| Domain models | `Reminder`, `ReminderList`, `Priority`, `LocationTrigger`, `ListKind`, `ListAccentColor` under `Core/Models/`. Snake-case YAML keys mapped to camelCase Swift via custom `CodingKeys`. |
| Storage layer | `actor FileStore` reads/writes the file tree. `FrontmatterCodec<T>` splits `---\n…\n---\n\n<body>`. `YAMLCodec<T>` wraps Yams. `ISO8601` helper for date formatting. Located under `Core/Storage/`. |
| Repository | `RemindersStore` (`@Observable`, holds in-memory snapshot). |
| Index/cache | **Not implemented yet.** SPEC §7 calls for SwiftData index alongside files; the code currently re-walks the tree and parses every `.md` on bootstrap. |
| Features (built) | Capture sheet, Home grid, list view (per-section inline-new row, dividers), reminder detail (chip tag editor, recurrence presets), smart-list screens. |
| Tests | `ListsTests` mirrors the source tree; `Core/Storage` has `FileStoreTests` + `FrontmatterCodecTests`. ~38 Swift files total across app + tests. |
| iCloud / sync | None wired up yet. SPEC §16 describes the data contract (`lamport`, `deleted_at`, `modified`) but no transport layer has been built. |
| AlarmKit | **Spec'd but blocked** — Personal Apple Developer team only. Memory note `M6 deferred` says reorder to M7→M8→M9 until paid team is available. |

### On-disk format (verified by reading the codecs)

Per-list folders directly under the iCloud-syncable `Documents/Lists/` root.
Each folder is named by the list's **ULID id** (not by the human name as SPEC
§7 originally suggested — the code optimised for rename-safety):

```
Documents/Lists/
└── 00000000000000000000INBOX0/
    ├── .list.yml             (ReminderList YAML — kind, color, icon, lamport, …)
    └── <reminder-ulid>.md    (one file per reminder; YAML frontmatter + markdown body)
```

Reminder file shape:

```markdown
---
id: 01HX2A9F3K4VYTGN3RH8XPQM5K
list_id: 01HX1A0000000000000000000K
parent_id: null
title: …
created: 2026-04-30T10:23:00Z
modified: 2026-04-30T11:15:00Z
date: 2026-07-15
time: "14:30:00"
urgent: false
priority: high
flagged: true
tags: [trip, family]
recurrence: null
location_trigger: null
completed: false
completed_at: null
completion_history: []
section: null
position: 1024.0
deleted_at: null
lamport: 47
---

Markdown body…
```

Notes worth carrying forward:
- `id` is a 26-char Crockford-base32 **ULID** (sortable by creation time).
- `Inbox`'s id is fixed: `00000000000000000000INBOX0`.
- `has_time` is **derived**, not stored (Swift exposes it as `hasTime { time != nil }`).
- The frontmatter codec enforces `---` opener + closer; everything after the
  closing fence (after one blank line) is the body. Yams emits in
  declaration order (`sortKeys = false`) — file diffs stay deterministic.

## SPEC.md headlines that bind every platform

Reading `SPEC.md` end-to-end. The cross-platform-load-bearing items:

1. **Files are the source of truth, index is rebuildable.** Any platform's
   first launch must walk the tree, populate its local cache, and re-parse on
   `mtime` mismatch (§7 "Index rebuild").
2. **One unified reminder schema** with `parent_id` for sub-reminders, one
   level deep. (§6)
3. **Three list kinds in v1**: `task`, `habit`, `shopping`. Schema accepts
   future kinds (`note`, `journal_entry`, …) without changes. (§5)
4. **Six smart lists** are queries over the index, not stored collections:
   Today / Scheduled / Flagged / All / Completed / Urgent. (§8)
5. **Recurrence is RFC 5545 RRULE** but only the subset
   `FREQ + INTERVAL + BYDAY + BYMONTHDAY + COUNT + UNTIL` is in scope. (§7)
6. **Soft-delete tombstones** with `deleted_at`; sync-ready Lamport counters
   (§16) — every platform must persist these even if no sync code ships.
7. **Habit completion history** is inline in YAML (`completion_history: [date, …]`)
   in v1; sidecar JSON migration deferred to v1.2. (§12)
8. **Shopping items** are auto-categorised by a static lexicon (~200 entries,
   bundled JSON, no ML). (§13)
9. **Markdown body** uses a constrained subset (no LaTeX, no Mermaid, no embeds,
   no footnotes — §11).
10. **Notifications**: `UNUserNotificationCenter` for non-urgent; AlarmKit for
    `urgent && has_time`. Equivalent on each platform must be picked
    deliberately (per-platform research docs).

## Multi-platform planning that already exists

Two pre-existing planning artefacts. They contradict each other on storage —
SPEC.md is canonical; treat the older one as historical context.

### `design/project/docs/app-plan.md` (older, predates the markdown decision)

Lays out a seven-phase platform roadmap that is largely the right shape but
specifies SQLite + sync server + shared **Rust core** as the universal data
layer. With `SPEC.md`'s pivot to markdown-as-source-of-truth, the plan's data
sections are obsolete, but the platform-by-platform UI choices, the urgent-
reminders cross-platform table, and the monetisation/governance notes still
hold up. Phases as written:

| # | Platform | Stack proposed in old plan |
|---|---|---|
| 1 | iOS 26+ | SwiftUI + AlarmKit + WidgetKit + App Intents |
| 2 | Android 14+ | Kotlin + Compose + Material 3 + AlarmManager + WorkManager + Room |
| 3 | iPadOS | SwiftUI adaptive |
| 4 | macOS 15+ | SwiftUI for Mac, MenuBar, Spotlight |
| 5 | Web | SvelteKit/React + IndexedDB + Service Worker |
| 6 | Windows 11+ | WinUI 3 / .NET |
| 7 | Linux | GTK4 + libadwaita (GNOME) and Qt6 (KDE) — two clients |

The overnight task scopes platform research to **iOS, Android, Windows, Linux**
(no iPad, no macOS, no Web). Worth flagging — Windows and Linux have **no design
mockups yet**; iPad and macOS **do** have mockups but are out of this run's
research scope.

### `design/project/docs/data-model.md` (older, predates markdown)

A SQLite-centric schema with `accounts`, `devices`, `lists`, `sections`,
`reminders`, `subtasks`, `tags`, `reminder_tags`, `location_triggers`,
`attachments`, `alarms`, `templates`, smart-list rule JSON. Useful as a
**reference for what the SQLite cache schema should expose**, but the
authoritative schema is now derived from the YAML frontmatter (§6 of SPEC.md),
not from this document.

## Design assets (read-only)

`design/README.md` is explicit: the entire `design/` tree is read-only and is
visual reference, not code to port. Wireframes (HTML + JSX) exist for:

- iOS — `design/project/src/`
- iPad — `design/project/src-ipad/`
- macOS — `design/project/src-macos/`
- Android — `design/project/src-android/`
- Linux (GNOME/Adwaita + KDE) — `design/project/src-linux/`
- Widgets — `design/project/OpenReminders-Widgets.html`

**Windows is not represented in `design/`.** A mockup pass is a likely
prerequisite for Windows implementation.

## License + governance posture (as currently committed)

- `LICENSE` file says **`AGPL-3.0-only`** in a one-line note.
- `README.md` says **`AGPL-3.0-or-later`**.
- `SPEC.md §17` also says **`AGPL-3.0-or-later`** and adds:
  - DCO sign-off, no CLA.
  - Section 7 distribution exception for App Store linking against Apple
    proprietary frameworks; planned in `LICENSE.app-store-exception` (not yet
    written).
  - Trademark on "Lists" name + logo (logo not yet designed).
  - No telemetry by default; CI grep planned to fail builds containing
    analytics SDKs.

This needs reconciling — see Discrepancies.

## Discrepancies between docs and code (worth surfacing)

| Topic | Doc says | Code/state says | Action |
|---|---|---|---|
| Project name | `Lists` everywhere, end-to-end: SPEC, README, all `platforms/*` (including iOS — folder, xcodeproj, target, scheme, bundle id `io.github.saxonbobart.lists`), all `shared/*`, all `research/*`, the top-level repo directory itself (`/Users/saxon/Developer/Projects/Lists/`), and the Claude Code memory dir (`/Users/saxon/.claude/projects/-Users-saxon-Developer-Projects-Lists/`). | Fully reconciled. | None — though the user's external references (shell aliases, IDE workspaces, browser bookmarks) may still point at the old `…/OpenReminders/` path; update those manually. The active Claude Code session's transcript log was created at the old memory path before the rename and stays there until session end (cleanup: `rm -rf /Users/saxon/.claude/projects/-Users-saxon-Developer-Projects-OpenReminders` after this session ends). |
| License | AGPL-3.0-or-later (README, SPEC §17) | AGPL-3.0-only (`LICENSE`) | One-line `LICENSE` is wrong relative to SPEC. Replace with the full AGPL-3.0 text and decide -only vs -or-later. SPEC's "or later" is the safer default. |
| Tooling | CLAUDE.md (`/Users/saxon/CLAUDE.md`) says GRDB + Supabase + Tuist + email auth | Reality: SwiftData (planned) + no sync + plain Xcode project + Yams (no auth code) | CLAUDE.md is stale. Not modified by this overnight run (constraint: do not modify existing files), but flag for the user to update. |
| Index | SPEC §7: SwiftData index alongside files | iOS code: in-memory snapshot from `actor FileStore.loadAll()`; no SwiftData index | Choice: build SwiftData index for iOS now, or keep in-memory snapshot until corpus grows. Either works; spec describes the more scalable path. |
| Folder names | SPEC §7: human-readable list folder name (`Inbox/`, `Groceries/`) | Code: folder is `<list.id>` (rename-safe) | Code wins — update SPEC.md when convenient. |
| Old data plan vs SPEC | `design/project/docs/app-plan.md` and `data-model.md` describe SQLite-as-source-of-truth + sync server | SPEC.md describes markdown-as-source-of-truth + rebuildable cache | SPEC is canonical. The old docs remain valuable as UX/feature reference; mark them historical or fold what's still relevant into `docs/`. |

None of these block the platform-research phase — they're just things to fix
when the user is awake.

## Implications for new platforms

What every new platform inherits, non-negotiable:

1. **Same on-disk file tree.** A reminder created on Windows must be readable
   by iOS without translation. The YAML frontmatter schema and folder layout
   in §6/§7 of SPEC are the contract.
2. **Same id space.** Every reminder file is named `<ulid>.md`. Every
   `parent_id` / `list_id` / `id` is a 26-char Crockford ULID. The ULID
   generator must produce values lexicographically sortable by creation time.
3. **Lamport + tombstones**. Even pre-sync, every platform writes
   `lamport`, `deleted_at`, `modified` on every mutation. Without these, a
   future sync layer has nothing to merge on.
4. **Rebuildable cache.** Each platform owns its query/index choice (SwiftData
   on iOS, Room on Android, SQLite + native binding on Windows/Linux), but the
   cache must be a pure derivation of the file tree. Files win on conflict.
5. **Same RRULE subset**. Every platform parses `FREQ + INTERVAL + BYDAY +
   BYMONTHDAY + COUNT + UNTIL` and ignores the rest.
6. **Same shopping lexicon.** Bundled JSON resource shipped to every platform.
   Single shared file under `shared/lexicons/shopping.en.json` is the natural
   home (created in Phase 5).
7. **Constrained markdown subset** (SPEC §11 table). The renderer per platform
   may be different libraries, but the supported features are the same set.

What every platform owns alone:

- Native UI toolkit (Apple Reminders parity on iOS; Material 3 on Android;
  Adwaita on Linux GNOME, Breeze on KDE; Fluent on Windows).
- Notification + alarm scheduling APIs (no shared layer here — every OS is
  different).
- File watching (each OS has its own native API; the shared layer can specify
  the events the watcher must emit, not the implementation).
- Packaging / signing / distribution (App Store, Play Store, MS Store, Flatpak,
  Snap, Deb, Rpm, AppImage).

## Open architectural questions to resolve in the rest of this run

1. **Shared core: yes/no, and in what form?** Options:
   - **Pure spec** (no code): just the on-disk format, JSON Schema for YAML,
     SQLite cache schema, fixtures. Each platform implements its own parser.
   - **Shared library** (Rust + FFI / C ABI): one parser, one RRULE expander,
     one ULID generator, one cache writer. Higher up-front cost, but every
     platform consumes the same code.
   - **Hybrid**: pure spec for now; cherry-pick to shared lib later if cost of
     re-implementing a piece across 4 platforms exceeds FFI overhead. Most
     pragmatic for a solo dev.

   The per-platform research docs each weigh in; the answer is consolidated in
   `PLAN.md` and reflected in `shared/`.

2. **iOS reorganisation.** Today iOS sits at `platforms/ios/`. The new convention
   for new platforms is `platforms/<name>/`. Renaming `platforms/ios/` → `platforms/ios/`
   is a one-line `git mv` plus an update to `.xcodebuildmcp/config.yaml`'s
   `projectPath`, but it touches existing files (out of scope for this overnight
   run). Recorded as a first-day task in `PLAN.md`.

3. **`apps/` vs `platforms/` naming.** Going with `platforms/` for new work
   (matches the user's prompt). When iOS migrates, `apps/` becomes empty and
   should be removed.

## Sources read for Phase 1

- `/Users/saxon/Developer/Projects/Lists/README.md`
- `/Users/saxon/Developer/Projects/Lists/LICENSE`
- `/Users/saxon/Developer/Projects/Lists/.gitignore`
- `/Users/saxon/Developer/Projects/Lists/SPEC.md` (full)
- `/Users/saxon/Developer/Projects/Lists/design/README.md`
- `/Users/saxon/Developer/Projects/Lists/design/project/docs/app-plan.md`
- `/Users/saxon/Developer/Projects/Lists/design/project/docs/data-model.md`
- `/Users/saxon/Developer/Projects/Lists/docs/design/README.md`
- `/Users/saxon/Developer/Projects/Lists/docs/design/components.md`
- `/Users/saxon/Developer/Projects/Lists/docs/design/spacing-and-density.md`
- `/Users/saxon/Developer/Projects/Lists/platforms/ios/Lists/App/ListsApp.swift`
- `/Users/saxon/Developer/Projects/Lists/platforms/ios/Lists/Core/Models/{Reminder,ReminderList}.swift`
- `/Users/saxon/Developer/Projects/Lists/platforms/ios/Lists/Core/Storage/{FileStore,FrontmatterCodec,YAMLCodec}.swift`
- `/Users/saxon/Developer/Projects/Lists/platforms/ios/Lists.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `/Users/saxon/Developer/Projects/Lists/.xcodebuildmcp/config.yaml`
- `git log --oneline -30`, branches, remotes
