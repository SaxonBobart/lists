# PLAN — Multi-platform recommendation

_Synthesis of Phases 1–5. Read this first when you wake up._

## TL;DR

iOS is already in flight. The recommended order for the rest is **Android →
Linux → Windows**, with `shared/` (specs + fixtures + lexicons) as the
contract that keeps all four implementations in sync. **No shared Rust core
in v1** — every platform agent independently arrived at "pure native" being
cheaper than FFI plumbing across four toolchains.

The scaffolding for Android, Windows, and Linux now exists under `platforms/`
as placeholder structure (no real code). Four research docs under `research/`
explain the reasoning end-to-end. The shared contract under `shared/` is a
v0 draft derived from `SPEC.md` §6 and §7.

**Nothing has been committed.** The branch (`cleanup/full-reset`) is clean
of git history-wise; everything new sits in your working tree, untracked.
You can `git status` to see, `git add` to keep, or `git clean -fd
research/ platforms/ shared/` to discard.

## What's in the working tree after this overnight run

```
research/
├── PLAN.md                      ← you are here
├── 00-current-state.md          Phase 1 — repo / iOS state, discrepancies, implications
├── android-stack.md             Phase 2 — Kotlin + Compose + Room + Markwon (~3,400w, 40+ URLs)
├── windows-stack.md             Phase 2 — C# + Avalonia 11.3 + FluentAvalonia (~8,000w)
├── linux-stack.md               Phase 2 — Vala + GTK4 + libadwaita + Flatpak (~4,000w)
└── mcp-and-skills.md            Phase 3 — MCP servers + project-specific skills (~2,700w)

platforms/
├── android/                     Gradle/Kotlin layout — 11 stub files
├── windows/                     Avalonia .NET 9 solution layout — 14 stub files
└── linux/                       Meson/Vala/Flatpak layout — 18 stub files

shared/
├── README.md
├── format/                      on-disk file format spec + JSON Schemas
├── cache/                       canonical SQLite cache DDL
├── recurrence/                  RRULE subset + golden examples
├── ulid/                        ULID generation rules + sentinel ids
├── lexicons/                    shopping lexicon (skeleton; needs ~200 entries)
├── fixtures/                    golden parser inputs (1 list + 1 reminder; grow as bugs surface)
└── notifications/               cross-platform notif/alarm parity matrix
```

## Build order recommendation

### Why this order

I evaluated the four candidates on (a) audience size, (b) marginal effort to
implement well given the current code, (c) what's needed to ship something
shippable, and (d) what the project learns from the implementation.

| Platform | Audience | Marginal effort | Ships when? | What the project learns |
|---|---|---|---|---|
| iOS (complete) | Existing Apple users | M (already 60–70% built) | Soon — completion is the right next thing | The product feel under Apple-grade chrome |
| Android | Largest mobile install base | L | After iOS | Whether the format spec is correct (writing the second parser surfaces every ambiguity in the YAML+md format) |
| Linux | Small but design-motivated audience | L | After Android | Whether the cache + daemon model holds up on a "real" desktop OS where the OS doesn't manage your background process |
| Windows | Largest desktop install base | XL | Last | How to ship through the Microsoft Store + winget; how Avalonia survives on a platform that doesn't bend toward Mica+Acrylic naturally |

### Recommended order

1. **Finish iOS to v1 ship.** The remaining work is the SwiftData index
   (currently the file tree is re-walked into memory each launch), the
   notification scheduler (`UNUserNotificationCenter`), AlarmKit (gated on
   the paid Apple Developer program; presently blocked per the
   `M6 deferred` memory note), first-launch onboarding, and App Store
   submission. Treat `shared/format/`, `shared/recurrence/`, `shared/ulid/`
   as the iOS implementation's spec going forward — the next two platforms
   will be parser-roundtrip-tested against the same fixtures, so iOS owes
   itself the discipline of staying schema-clean.

2. **Android, when iOS is shipped or running stably in production.** Largest
   payoff per LOC; the AlarmKit-equivalent (`setAlarmClock`) does NOT need a
   paid developer account, so the urgent-reminders feature can ship on
   Android *before* it ships on iOS even though iOS designed it. Android's
   permission UX (POST_NOTIFICATIONS, SCHEDULE_EXACT_ALARM, USE_FULL_SCREEN_INTENT,
   foreground-service) is the bulk of the engineering budget — see
   `research/android-stack.md` §11.

3. **Linux, when Android is in beta.** The Linux design assets are ready
   (Adwaita-shaped JSX in `design/project/src-linux/`); the GTK4 + libadwaita
   + Vala + Meson + Flatpak chain is internally consistent and Flathub is a
   straightforward distribution. The single hardest problem on Linux is the
   alarm/wake daemon — every other piece (UI, parser, cache, notifications)
   is well-trodden ground. Open question raised by the Linux research:
   "shared Rust core or not." Default answer: not, unless the user starts
   building it for fun. The cost of a Rust core is paid in plumbing across
   FFI boundaries; the win is one parser instead of four.

4. **Windows, last.** Largest desktop audience but the highest design and
   engineering risk: no mockups exist (a Fluent design pass is a prerequisite),
   .NET 9 + Avalonia + FluentAvalonia is a solid stack but unfamiliar to
   anyone whose primary tooling is Apple's, code-signing infrastructure adds
   real cost (Azure Artifact Signing or a $300/yr EV cert for raw EXEs;
   MSIX needs a different cert). The OneDrive Files-on-Demand gotcha is a
   landmine — the cache rebuilder must check `FileAttributes.Offline` and
   skip-then-lazy-hydrate, or first launch over a typical Documents folder
   will hang for minutes hydrating files. See `research/windows-stack.md` §6.

### Dependencies between platforms

None hard, given that `shared/` is now in place. Soft dependencies:

- **Format-spec drift discoveries** from Android feed back into
  `shared/format/`. Same for Linux + Windows. Each new platform should grow
  the `shared/fixtures/` corpus.
- **The shopping lexicon** (`shared/lexicons/shopping.en.json`) is currently
  a 20-entry skeleton. Whoever (or whichever platform) ships the shopping
  list first owes the project a real ~200-entry pass.
- **The notification parity matrix** in `shared/notifications/README.md` is
  the contract; each new platform extends the table with its specific
  permission flow.

## Effort tiers (S / M / L / XL)

| Platform | Tier | Why |
|---|---|---|
| iOS (complete to ship) | M | 60–70% built. Remaining: SwiftData index, notification scheduler, AlarmKit (when paid Apple Dev unblocks), onboarding, App Store submission. ~3–6 weeks of focused work. |
| Android (zero → v1) | L | Greenfield. Compose + Material 3 is new if you haven't shipped Android before. Permission UX has many edge cases (POST_NOTIFICATIONS / SCHEDULE_EXACT_ALARM / USE_FULL_SCREEN_INTENT). Reproducible-build for F-Droid is fiddly. ~3 months. |
| Linux (zero → v1) | L | Greenfield. Vala/GTK/Meson/Flatpak is unfamiliar tooling unless you've shipped a GNOME app before. The daemon + RTC wake is the single hardest problem in this run. Audience is smaller, so polish bar is similar but with more contributor leverage. ~3 months. |
| Windows (zero → v1) | XL | Greenfield. No design mockups (must be designed first). .NET ecosystem. Code-signing infra (real money). OneDrive Files-on-Demand interaction. ~4 months. |

Total roadmap if every platform shipped sequentially: ~12–18 months. Two
platforms in parallel is possible but probably not as a solo dev — the
cognitive cost of context-switching between Compose + Vala on the same day
is not zero.

## Discrepancies surfaced during this run (worth resolving on Day 1)

These all surfaced in `research/00-current-state.md` and are listed there
in detail. Quick recap:

1. **License**: `LICENSE` says `AGPL-3.0-only`, README + `SPEC.md` say
   `AGPL-3.0-or-later`. Pick one. SPEC's "or later" is the safer default.
   Replace the `LICENSE` file with the full AGPL-3.0 text and add the
   "or later" clause if that's the call.
2. **CLAUDE.md is stale.** The user-level `~/CLAUDE.md` (canonical project
   instructions) talks about GRDB + Supabase + Tuist. None of those are in
   the actual codebase — Yams is the only SPM dep, no sync code, no Tuist.
   Update CLAUDE.md to match reality before more autonomous work happens.
3. **iOS rename — DONE, end-to-end.** Moved `apps/ios/` → `platforms/ios/`,
   renamed `OpenReminders/` → `Lists/` (source) and `OpenRemindersTests/` →
   `ListsTests/`, renamed `OpenReminders.xcodeproj` → `Lists.xcodeproj`, scheme
   renamed to `Lists`, bundle id changed to `io.github.saxonbobart.lists` (and
   `io.github.saxonbobart.lists.tests` for the test target). Then in a final
   pass: `mv /Users/saxon/Developer/Projects/{OpenReminders,Lists}` (top-level
   repo directory) and `mv /Users/saxon/.claude/projects/-Users-saxon-Developer-Projects-{OpenReminders,Lists}`
   (Claude Code memory namespace), with `.xcodebuildmcp/config.yaml`'s absolute
   `projectPath` and the 4 research docs that cited absolute paths all updated
   to `/Users/saxon/Developer/Projects/Lists/...`. The `.pbxproj`, `.xcscheme`,
   and `platforms/ios/project.yml` (XcodeGen spec — note: project uses XcodeGen,
   NOT Tuist as CLAUDE.md claims) were all edited so future `xcodegen generate`
   runs stay consistent. Verified with `xcodebuild -list`: project parses, Yams
   resolves, targets `Lists` + `ListsTests`, scheme `Lists`. Cleanup the user
   may want to do manually: shell aliases / IDE workspaces / browser bookmarks
   that pointed at `…/OpenReminders/`; and `rm -rf /Users/saxon/.claude/projects/-Users-saxon-Developer-Projects-OpenReminders`
   AFTER this Claude Code session ends (the active session keeps writing its
   transcript log to that path).
4. **Folder layout vs SPEC**: SPEC §7 says human-readable list folder names
   (`Inbox/`, `Groceries/`); code uses `<list.id>` (rename-safe). Code wins;
   update SPEC when convenient.
5. **iOS index**: SPEC §7 calls for SwiftData index alongside files; today
   the iOS app uses an in-memory snapshot loaded from `actor FileStore`.
   Build the SwiftData index before the corpus grows past a few hundred
   reminders.

## First three concrete tasks for when you wake up

In order:

### 1. Read the four research docs (~30 min)

Skim in this order:

1. `research/00-current-state.md` — confirms what I read about the codebase
   and surfaces the discrepancies above.
2. `research/PLAN.md` (this file) — the synthesis.
3. `research/mcp-and-skills.md` — quick (top-3 each, easy decision).
4. Pick the platform research doc you're most curious about and read it
   fully. The Windows doc is the longest (~8,000w) because Windows is the
   highest-stakes UI choice; the others are ~3–4,000w.

If anything in the platform recs seems wrong to you on the spot, the answer
is to read the agent's reasoning before pushing back — they cite ~40+ URLs
each, and several recommendations went against my prior assumption (e.g.,
Avalonia over WinUI 3, single Linux client over two).

### 2. Decide whether to keep the scaffolding (~5 min)

The scaffolding under `platforms/` and `shared/` is untracked. Three options:

- **Keep as-is.** `git add platforms/ shared/ research/ && git commit`. The
  layout is reviewable but no buildable code lives there yet, so the commit
  is documentation more than implementation. Recommended if you agree with
  the layout.
- **Iterate on the layout first.** E.g., rename `platforms/` → `apps/` to
  match existing iOS, or restructure the shared layer differently. Easy to
  do before the commit.
- **Discard.** `git clean -fd platforms/ shared/ research/`. If the
  research is interesting but the scaffolding isn't, you can keep
  `research/` and discard the rest with a more targeted clean.

### 3. Pick the second platform and start its first-tasks checklist (~when ready)

The recommendation is Android (largest audience per LOC; permission UX is
where the engineering budget goes; the parser parity check forces format
discipline). The first 10 tasks are listed in
`platforms/android/README.md` → "First-tasks checklist". Tasks 1–3 (Gradle
wrapper, version catalog, port the Frontmatter codec to Kotlin) take a
focused day each.

If you'd rather start somewhere else:

- **Linux** if you want to validate the desktop UX before committing to
  Windows and you enjoy GNOME tooling. Tasks 1–3 are install build deps,
  generate the GResource manifest, port the codec to Vala.
- **Windows** if you want to maximise audience reach and don't mind paying
  the design-pass-first cost. Tasks 1–3 are install .NET 9 + Avalonia
  templates, scaffold the projects, port the codec to C#.
- **Iterate iOS to ship** if you want to keep one platform fully focused.
  Wire SwiftData; build the notification scheduler; reach paid Apple Dev so
  AlarmKit unblocks; first-launch onboarding; submit.

## What I deliberately did NOT do

Per your constraints (with one explicit exception you authorised):

- **iOS source modification was OFF-LIMITS during the overnight run.** Then
  you asked to "consolidate the branding" and "change everything to match",
  which required editing `.pbxproj` + `.xcscheme` + 7 Swift test files +
  renaming + moving `apps/ios/` to `platforms/ios/`. You explicitly
  authorised the `.pbxproj` edit when the permission system blocked the
  initial attempt. Nothing else under `design/`, `docs/`, `SPEC.md`,
  `README.md`, `LICENSE`, `.gitignore` was touched (except that
  `docs/design/README.md` had path references updated to track the iOS move).
- **No package-manager invocations.** No `gradle wrapper`, no
  `dotnet new sln`, no `meson setup`, no `flatpak-builder`.
- **No commits.** Nothing is staged. Nothing is in `git`. Verify with
  `git status`.
- **No remote pushes.** There is no git remote configured anyway; the repo
  is local-only.
- **No installed dependencies.** No `npm install`, no `pip install`, no
  Homebrew, nothing.
- **No agents written for me ran tools that would have side effects beyond
  reading and writing files I created.** Each platform-research agent did
  read-only web research + file writes only into `research/`.

## What's left undone (future research worth doing)

Not strictly part of this overnight run but came up:

1. **iPad and macOS research.** Out of scope for this run but design assets
   exist under `design/project/src-{ipad,macos}/`. Likely SwiftUI-adaptive
   on the iOS codebase (iPad) and a separate SwiftUI for Mac target (macOS).
   Both are a fraction of a full new platform's work.
2. **Web client research.** Out of scope. The older `app-plan.md` proposed
   SvelteKit + IndexedDB + Service Worker; that direction is still
   defensible but the markdown-on-disk-as-source-of-truth pivot makes the
   web story harder (browsers can't watch a folder without WebFolder access
   or the File System Access API + opt-in user grant).
3. **Sync-server research.** Out of scope for v1. The SPEC §16 "ready for
   sync" architecture does the heavy lifting (`lamport`, `deleted_at`,
   `modified` are already in the data model). Future v2 work: sync transport
   (WebSocket vs polling), conflict resolution (LWW vs CRDT vs Yjs/Automerge),
   self-host story (Docker image), pricing model (per the older app-plan).
4. **A Fluent design pass for Windows.** The Windows research recommends a
   stack but flagged repeatedly that no mockups exist. Designing the Windows
   UI is a prerequisite to the implementation phase.
5. **The shopping lexicon.** Currently 20 entries in
   `shared/lexicons/shopping.en.json`. Needs ~200 to be useful. Pre-v1 task,
   one afternoon's content work.
6. **Section 7 distribution exception drafting.** SPEC §17 mentions an
   `LICENSE.app-store-exception` file is needed for App Store distribution
   under AGPL. Not yet written.
7. **Update CLAUDE.md** to match reality (GRDB + Supabase + Tuist references
   are stale).

---

End of plan. The full research is in this directory; the scaffolding is
under `platforms/` and `shared/`. Sleep well.
