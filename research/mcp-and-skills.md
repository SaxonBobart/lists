# MCP Servers and Claude Skills for Lists

_Snapshot date: 2026-05-03. Inputs: SPEC.md, research/00-current-state.md, web research._

The user already has XcodeBuildMCP, computer-use, the Anthropic-hosted
Gmail/Calendar/Drive servers, sequential-thinking, and sosumi connected, plus
the standard `superpowers:*` skills. Nothing here duplicates those — each
recommendation closes a gap the existing toolkit doesn't cover. Bias: solo
dev, file-tree-as-source-of-truth, cross-platform ahead. Tooling that doesn't
pull weight on a small repo is omitted on purpose.

---

## Part 1 — MCP servers worth adding

### Tier 1 (set up week 1)

#### 1. GitHub MCP Server (official)

- **Repo:** https://github.com/github/github-mcp-server
- **License:** MIT.
- **Why for this project:** the moment the repo goes public (required for AGPL
  distribution), Claude needs structured access to issues, PRs, releases, and
  Projects rather than round-tripping through `gh` shell. Concrete tasks:
  filing per-platform tracking issues from `platforms/<name>/PLAN.md`; cutting
  GitHub Releases with attached `.dmg`/`.apk`/`.exe`/`.AppImage` artefacts;
  triaging bug reports against the file-format spec by diffing against
  `SPEC.md`; syncing a Projects board for the multi-platform roadmap.
- **Setup:** remote OAuth at `https://api.githubcopilot.com/mcp/` (recommended)
  or local with `GITHUB_PERSONAL_ACCESS_TOKEN` env var.
- **Alternatives:** the archived `modelcontextprotocol/servers` GitHub server
  is deprecated. `gh` via Bash stays useful for ad-hoc calls; the MCP wins
  when structured payloads come back.

#### 2. SQLite MCP Server (read-only explorer)

- **Repo:** https://github.com/hannesrudolph/sqlite-explorer-fastmcp-mcp-server
- **License:** MIT.
- **Why for this project:** the rebuildable cache will be SwiftData (a SQLite
  file under the hood) on iOS and Room/native SQLite on Android/Linux/Windows.
  SPEC §7 says "files win" if the index disagrees — diagnosing that drift
  needs cache inspection. Concrete tasks: spot-checking that `loadAll()`
  populated the iOS index identically to a cold rebuild after a `.md` edit;
  comparing column population across platforms when the parity test corpus
  drives Android and Linux clients; running diagnostic queries like "any
  reminders with `urgent=true` and `time IS NULL`?" (an invalid state per §6).
- **Setup:** Python via `uvx`, point at the SwiftData store under
  `~/Library/Developer/CoreSimulator/Devices/<sim-uuid>/data/...`. Read-only
  prevents Claude from mutating the cache.
- **Alternatives evaluated:** Anthropic's reference SQLite MCP is archived
  (SQL-injection bypass — see Datadog write-up); skip it. `jparkerweb/mcp-sqlite`
  adds full CRUD, which is the wrong shape — only the parser should mutate the
  cache.

### Tier 2 (when the relevant phase starts)

#### 3. Mobile MCP — Android automation (Phase: Android client)

- **Repo:** https://github.com/mobile-next/mobile-mcp
- **License:** Apache 2.0.
- **Why for this project:** XcodeBuildMCP gives Claude a full iPhone-sim
  feedback loop. Once Android starts, parity with that loop is what lets the
  "drive sim before claiming done" memory note apply equally there. Mobile
  MCP works against emulators *and* real devices (the user has a Pixel),
  exposes accessibility-tree snapshots (matching XcodeBuildMCP's `snapshot_ui`
  semantics — fewer pixel-pushing bugs), and uses one API across both
  platforms.
- **Setup:** `npx -y @mobilenext/mobile-mcp@latest`. Requires Android Platform
  Tools, Node 22+, Android SDK. No auth.
- **Alternatives:** `minhalvp/android-mcp-server` (Apache 2.0, Python, raw
  ADB only); `srmorete/adb-mcp` and `richard0913/adb-mcp` (TS, similar
  scope). **Pick `mobile-next/mobile-mcp`** — most actively maintained, and
  the accessibility-tree story matches what's needed for SwiftUI-style
  assertion tests.

#### 4. Playwright MCP (Phase: docs site / store submissions)

- **Repo:** https://github.com/microsoft/playwright-mcp (official, Microsoft).
- **License:** Apache 2.0.
- **Why for this project, with caveats:** v1 excludes a web client (SPEC §3),
  so the fit is *around* the app: validating the eventual marketing/docs site
  renders markdown identically to the iOS detail view; submission-portal
  automation for App Store Connect / Play Console / Microsoft Partner Center /
  Flathub (none have first-class APIs for screenshot upload, asset metadata,
  release-notes paste). When a v2 web client lands, this becomes Tier 1.
- **Setup:** `npx @playwright/mcp@latest`. Persistent profile by default;
  switch to isolated for store submissions.
- **Alternatives:** `executeautomation/mcp-playwright`, `Automata-Labs-team/
  MCP-Server-Playwright` — both fine. Pick Microsoft official for longevity
  and accessibility-tree mode.
- **Recommendation: defer setup** until first store submission or first real
  docs site, but record now so it isn't re-discovered later.

### Tier 3 (nice-to-have)

#### 5. Linear MCP (only if the user adopts Linear)

- **Endpoint:** `https://mcp.linear.app/mcp` (official, OAuth 2.1, hosted).
- **License:** hosted, free for Linear Free/Standard.
- **Why it might earn a slot:** the per-platform milestone structure fits
  Linear's initiatives + projects model (added Feb 2026) better than a flat
  GitHub Issues list.
- **Why it might not:** GitHub Issues + Projects is free and lives next to
  the code — overkill for a solo dev. **Default: skip** unless Linear is
  already in use for other work.

### Servers explicitly evaluated and rejected

- **Filesystem MCP** (Anthropic reference). Claude already has Bash + Read/
  Edit/Write against `/Users/saxon/Developer/Projects/Lists/`, and
  the AGPL repo has no secrets to defend. Friction without value.
- **Git MCP** (Anthropic reference). `git` via Bash is faster and more
  flexible.
- **Postgres MCP.** No Postgres in v1. If a v2 sync server lands on Supabase
  Postgres, prefer a custom MCP — the archived Anthropic reference had a
  SQL-injection bypass.
- **Tauri/Electron/Flutter MCP.** None of those frameworks are picked yet
  (iOS = SwiftUI, Android = Compose, Linux = GTK4/Qt6, Windows = open). Flag
  for re-evaluation if Windows ends up Tauri-shelled.
- **Markdown vault / frontmatter MCPs** (`pvliesdonk/markdown-vault-mcp`,
  `caffeinatedwes/markdown-frontmatter-mcp`, `MarkScribe`). Aimed at
  Obsidian-style note querying, not at schema-validating frontmatter against
  a fixed contract. The Part 2 skills cover this without a server.
- **OpenAPI-to-MCP generators.** The shared schema isn't HTTP — JSON Schema
  fits better than OpenAPI. Tracked as a skill.
- **Windows-MCP / WSL MCPs.** Useful only if Windows builds happen on a
  Windows host. Dev machine is macOS; defer until the Windows phase decides
  local-vs-CI builds.
- **iCal / RRULE / ULID MCPs.** None mature exist. The skills below
  substitute.

---

## Part 2 — Claude skills worth creating

Skills use the `name: lists:<topic>` convention so they sort together
and don't collide with `superpowers:*`. Each is a markdown file with `name` +
`description` frontmatter (the only required fields per `anthropics/skills`)
and a body of instructions.

### Must-create-now (before cross-platform code lands)

#### S1. `lists:on-disk-format`

- **Description:** Canonical spec for `.md` reminder files and `.list.yml`
  list-metadata files. Source of truth for cross-platform parsers.
- **Problem it solves:** parser drift. Without one canonical sheet, the iOS
  parser writes `true` as a YAML bool while Android writes `"true"`, and a
  file round-tripped through both mutates every touch — destroying the
  human-diffable property the format exists to provide.
- **When to use:** writing or modifying any parser, codec, or fixture on any
  platform; reviewing YAML output; changing `Reminder` / `ReminderList`
  field shapes.
- **Skeleton:** folder layout (`Lists/<list-id>/.list.yml` +
  `<reminder-ulid>.md`); reminder YAML field table (copy of SPEC §6) with
  type + nullable + serialisation rules (booleans unquoted; dates
  `YYYY-MM-DD`; times `"HH:MM:SS"` quoted; arrays in flow style for short,
  block for long); frontmatter fence rules (`---\n…\n---\n\n<body>`,
  mandatory blank line); Yams-equivalent settings every parser must match
  (`sortKeys=false`, UTF-8, LF on write, tolerate CRLF on read); derived vs
  stored fields (`has_time` is derived); the Inbox ULID
  `00000000000000000000INBOX0`; pointer to `shared/fixtures/files/`.

#### S2. `lists:rrule-subset`

- **Description:** The exact RFC 5545 RRULE subset Lists supports
  (`FREQ + INTERVAL + BYDAY + BYMONTHDAY + COUNT + UNTIL`) and edge cases.
- **Problem it solves:** "we'll just import a full RRULE library on platform
  X" — and now habit streak calculations diverge because some libraries
  expand `BYSETPOS` and others don't.
- **When to use:** any time recurrence parsing, expansion, or the
  next-occurrence calculator is touched; reviewing PRs that add a new RRULE
  library dependency.
- **Skeleton:** supported fields with valid value ranges + ABNF; explicitly
  rejected fields (`BYSETPOS`, `BYHOUR`, `BYMINUTE`, `BYWEEKNO`,
  `BYYEARDAY`, `WKST`, `EXDATE`, etc.) with a reject reason for each;
  examples from SPEC §12 (DAILY, WEEKLY+BYDAY, every-other-week SA, monthly
  on the 1st); streak calculation rules from SPEC §12 — what "expected
  today" means; pointer to `shared/fixtures/rrule/` (input string + expected
  next-N occurrences).

#### S3. `lists:ulid-spec`

- **Description:** Crockford-base32 alphabet (`0123456789ABCDEFGHJKMNPQRSTVWXYZ`),
  48-bit ms timestamp + 80 bits randomness, monotonic generator behaviour,
  the fixed Inbox ULID.
- **Problem it solves:** wrong alphabet (someone uses standard base32 with
  `I L O U`); wrong byte order; non-monotonic generation (two reminders in
  the same ms sort unpredictably and break list order). The Inbox sentinel
  `00000000000000000000INBOX0` is easily lost across platforms.
- **When to use:** writing or reviewing any ULID generator/parser/filename-
  derivation code; any new platform's first commit.
- **Skeleton:** the alphabet with the four excluded letters spelled out and
  why; encoding (48 bits ms-since-epoch UTC + 80 bits CSPRNG, MSB-first into
  26 chars); monotonicity rule (when called twice in the same ms, increment
  the random portion as a u80 by 1, don't regenerate); Inbox sentinel
  reservation; pointer to `shared/fixtures/ulid/` test vectors.

### Create-when-platform-X-starts

#### S4. `lists:sqlite-cache-schema`

- **Description:** Canonical column names, types, and indices for the
  rebuildable index. Each platform writes its own DDL; this skill keeps the
  surface aligned.
- **Problem it solves:** when cross-platform tooling reads any platform's
  cache, it shouldn't have to handle three different `priority`
  representations (string vs int vs enum-discriminator).
- **When to use:** writing iOS `@Model`s, Android Room entities, or raw
  SQLite DDL on Linux/Windows; reviewing migration scripts.
- **Skeleton:** table list (`lists`, `reminders` — no `tags` table; tags
  inline as JSON array in v1); per-table column list with type/nullable/
  default (snake_case names match YAML keys for round-trip); index list
  (`(list_id, position)`, `(date) WHERE deleted_at IS NULL`,
  `(completed, completed_at)`, `(parent_id)`); what's NOT in the cache
  (full markdown body — no FTS in v1); rebuild procedure (walk tree, parse,
  upsert by `id`).
- **When:** start of Phase 2 (Android), or when the iOS SwiftData index is
  implemented (whichever first).

#### S5. `lists:notification-parity`

- **Description:** How each platform implements SPEC §14/§15 — iOS
  UNUserNotifications + AlarmKit; Android NotificationManager + AlarmManager;
  Windows Toast Notifications + Scheduled Tasks; Linux notify-send +
  systemd-timer.
- **Problem it solves:** silently skipping the urgent path on platforms
  where it's hard. iOS AlarmKit is paid-team-gated; Android needs full-
  screen-intent permission; Windows has no first-class equivalent (closest
  is the rarely-used "alarm" toast category); Linux has no native equivalent
  at all. Each implementation will be tempted to short-circuit, breaking
  the §14 invariant.
- **When to use:** writing notification scheduling on any new platform;
  reviewing per-platform research docs.
- **Skeleton:** state-to-mechanism mapping table (`urgent`, `has_time`,
  `date` → mechanism, per platform); permission model per platform and when
  to request; recurrence (schedule next occurrence only, reschedule on
  completion); identifier rule (notification id == reminder ULID for
  single-call removal); pointer to `platforms/<name>/notifications.md`.
- **When:** alongside per-platform research doc creation.

#### S6. `lists:add-platform`

- **Description:** Step-by-step checklist for adding a new platform target.
- **Problem it solves:** the second platform usually goes well; the third
  forgets parts because the second's setup wasn't documented at the time.
  Avoids "Linux has a parser but no file watcher".
- **When to use:** start of any new platform's implementation phase.
- **Skeleton:** folder under `platforms/<name>/` with canonical sub-tree
  (`README.md`, `PLAN.md`, `notifications.md`, `packaging.md`, `app/`);
  phases (parser+writer → cache schema → file watcher → smart-list queries
  → notifications/alarm → first-launch index rebuild → UI shell →
  packaging); required test deliverables (parser parity against
  `shared/fixtures/files/`, RRULE parity against `shared/fixtures/rrule/`,
  ULID parity against `shared/fixtures/ulid/`); distribution checklist
  (defers to `lists:cut-release`).
- **When:** start of Phase 2 (Android kickoff).

#### S7. `lists:agpl-section-7`

- **Description:** How to ship under AGPL through stores that prohibit AGPL
  (App Store, Play Store) — the Section 7 distribution exception spelled out.
- **Problem it solves:** App Store rejects strict AGPL because §13 requires
  any user be able to receive corresponding source from the app, and App
  Store terms prohibit that mechanism. AGPL §7 lets the licensor grant
  additional permissions; SPEC §17 commits to this but
  `LICENSE.app-store-exception` doesn't exist yet.
- **When to use:** preparing App Store / Play Console submission; adding the
  exception file; reviewing PRs touching licensing.
- **Skeleton:** wording template for the §7 grant (link to FSF examples,
  VLC and Krita precedents); where the grant lives
  (`LICENSE.app-store-exception` referenced from main `LICENSE`); what it
  permits (linking against Apple proprietary frameworks / Google Play
  Services that are otherwise AGPL-incompatible) and what it does NOT
  permit (closed-source forks); per-store implication table (App Store and
  Play Store yes-with-grant; MS Store yes; Flathub no exception needed;
  GitHub Releases no exception needed).
- **When:** when App Store submission becomes a real next step.

#### S8. `lists:cut-release`

- **Description:** Multi-platform release checklist with per-store quirks.
- **Problem it solves:** missing platform-specific bits — App Store
  screenshot sizes (one set per device class); Play Console wants `aab` not
  `apk`; MS Store wants `.msix` not `.exe`; Flathub takes a manifest PR;
  GitHub Releases want signed `.dmg`/`.apk`/`.AppImage` with checksums; the
  AGPL source link must accompany every store binary.
- **When to use:** cutting any release.
- **Skeleton:** pre-release (green CI, version bump in each platform's
  manifest, changelog entry, source-corresponding-to-binary tarball uploaded
  with checksum + signature); per-store steps (App Store, Play Console, MS
  Store, Flathub, GitHub Releases — one section each, field-by-field);
  source-availability link in each store's "support URL" and `README`;
  post-release smoke tests on each platform.
- **When:** ~2 weeks before first release.

### Defer

#### S9. `lists:fixture-corpus`

- **Description:** How `shared/fixtures/` is organised and how each platform
  consumes it for parity tests.
- **Problem it solves:** fixtures get out of sync with the spec; tests pass
  on iOS because Yams output matches and fail on Android because that
  library re-orders keys.
- **When to use:** writing or modifying any cross-platform parity test.
- **Skeleton:** layout (`files/`, `rrule/`, `ulid/`, `lexicon/`); file-naming
  convention (`<input>.input.yml` ↔ `<input>.expected.json`); "this is a
  parity test, not a unit test" framing; how to add a new fixture.
- **When:** when `shared/fixtures/` is first populated (Phase 5).

#### S10. `lists:shopping-lexicon`

- **Description:** The bundled ~200-entry shopping-item lexicon and how to
  add/edit entries.
- **Problem it solves:** lexicon entries get added on one platform's binary
  resource and forgotten on the others; or someone splits "frozen pizza"
  three ways across `Frozen`/`Pizza`/`Snacks` because there's no canonical
  taxonomy.
- **When to use:** adding entries, fixing miscategorised items, importing a
  third-party taxonomy as a starting point.
- **Skeleton:** canonical file location (`shared/lexicons/shopping.en.json`,
  copied into each platform's bundle at build time); schema
  (`{"term": string, "section": SectionEnum}` where Sections are fixed:
  `Produce | Dairy | Meat | Bakery | Pantry | Frozen | Beverages | Snacks |
  Household | Seafood | Other`); curation rules (lowercase, singular form,
  one canonical spelling, no brands, aliases as separate entries pointing to
  the same section); future-i18n note (filename `.en.json` leaves room for
  `de.json` etc.; v1 ships only `en`).
- **When:** when the lexicon file is first written (SPEC §13 calls this a
  "discrete pre-v1 task" — that's the trigger).

### Skills considered and not adding

- **`lists:swiftdata-vs-grdb`** — historical decision, made in SPEC
  §7. A skill would be archaeology.
- **`lists:icloud-sync`** — out of v1 scope.
- **`lists:supabase-auth`** — `/Users/saxon/CLAUDE.md` mentions
  Supabase but `research/00-current-state.md` notes that's stale; iOS has no
  sync code. Skip until Supabase actually re-enters scope.
- **`lists:tuist`** — `/Users/saxon/CLAUDE.md` says to run
  `tuist generate` but the actual repo uses a plain `.xcodeproj`. The
  CLAUDE.md instruction is stale; don't write a skill around an unused tool.

---

## Part 3 — Sources

### MCP server registries

- https://github.com/modelcontextprotocol/servers — official MCP reference servers (Anthropic).
- https://github.com/punkpeye/awesome-mcp-servers — community MCP server directory.
- https://registry.modelcontextprotocol.io/ — official MCP registry.
- https://www.pulsemcp.com/ and https://glama.ai/mcp/servers — discovery indices.

### MCP servers individually evaluated

- https://github.com/github/github-mcp-server — GitHub official MCP.
- https://github.com/hannesrudolph/sqlite-explorer-fastmcp-mcp-server — read-only SQLite MCP.
- https://github.com/jparkerweb/mcp-sqlite — full-CRUD SQLite MCP.
- https://github.com/mobile-next/mobile-mcp — cross-platform mobile MCP.
- https://github.com/minhalvp/android-mcp-server — Python ADB MCP.
- https://github.com/srmorete/adb-mcp — TypeScript ADB MCP.
- https://github.com/richard0913/adb-mcp — minimal ADB MCP.
- https://github.com/microsoft/playwright-mcp — Microsoft Playwright MCP.
- https://github.com/executeautomation/mcp-playwright — community Playwright MCP.
- https://linear.app/docs/mcp — Linear's hosted MCP.
- https://linear.app/changelog/2026-02-05-linear-mcp-for-product-management — Linear MCP additions.
- https://github.com/CursorTouch/Windows-MCP — Windows desktop UI automation MCP.
- https://github.com/spences10/mcp-wsl-exec — WSL command execution MCP.
- https://github.com/webconsulting/mcp-server-wsl-filesystem — WSL filesystem MCP.
- https://github.com/simpleswift/spm-mcp — Swift Package Manager MCP.
- https://docs.flutter.dev/ai/mcp-server — Dart/Flutter MCP.
- https://github.com/Arenukvern/mcp_flutter — community Flutter MCP.
- https://github.com/caffeinatedwes/markdown-frontmatter-mcp — markdown frontmatter MCP.
- https://github.com/pvliesdonk/markdown-vault-mcp — markdown vault MCP.
- https://glama.ai/mcp/servers/Erodenn/markscribe — MarkScribe MCP.
- https://github.com/higress-group/openapi-to-mcpserver — OpenAPI → MCP generator.
- https://securitylabs.datadoghq.com/articles/mcp-vulnerability-case-study-SQL-injection-in-the-postgresql-mcp-server/ — Datadog write-up justifying skipping the archived Postgres MCP.

### Skills framework references

- https://github.com/anthropics/skills — Anthropic's public skills repo (canonical SKILL.md frontmatter spec).
- https://github.com/obra/superpowers — superpowers skills framework the user already uses.
- https://github.com/obra/superpowers/blob/main/skills/writing-skills/anthropic-best-practices.md — Anthropic skill-writing best practices.
- https://www.anthropic.com/news/skills — Skills launch announcement.

### Spec / RFC sources

- https://datatracker.ietf.org/doc/html/rfc5545 — RFC 5545, iCalendar (RRULE source for skill S2).
- https://github.com/ulid/spec — canonical ULID spec (skill S3).

### Cross-platform reference

- https://v2.tauri.app/ — Tauri 2.0 docs.
- https://github.com/tauri-apps/awesome-tauri — Tauri ecosystem index (where `tauri-mcp-server` lives, if/when relevant).
