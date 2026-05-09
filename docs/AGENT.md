# AGENT.md — learning log

Append-only. Each entry is a fact discovered while working that future iterations should know. Not a TODO list (that's BACKLOG.md). Not a status (that's CURRENT.md).

## Build / test / run

- **Build + run on simulator**: `mcp__XcodeBuildMCP__build_run_sim` (no args; uses session defaults from `.xcodebuildmcp/config.yaml`).
- **Run tests**: `mcp__XcodeBuildMCP__test_sim`.
- **Screenshot**: `mcp__XcodeBuildMCP__screenshot` returns a path; read it with the Read tool to see it.
- **UI hierarchy**: `mcp__XcodeBuildMCP__snapshot_ui` for tap-coordinate discovery.
- **No `tap` tool** in this XcodeBuildMCP install. Manual interaction needs the Simulator.app window — automated UI taps are not currently scriptable. Verify interactive flows via unit tests (toggleDonePersists pattern) instead.
- **Regenerate xcodeproj after adding new source files**: `cd platforms/ios && xcodegen generate`. XcodeGen picks up files by directory based on `project.yml`'s `sources: [{path: Lists}]`.

## Swift / SwiftUI gotchas

- **`ISO8601DateFormatter` is NOT Sendable** in the current SDK; `nonisolated(unsafe)` required for static instances. `DateFormatter` IS Sendable (opposite of intuition).
- **`@Observable` + SwiftUI**: pass the class as `let store: ItemStore` (no `@State` wrapper needed inside child views); SwiftUI tracks property accesses automatically.
- **Custom `Codable` + Equatable**: when you write a custom `init(from:)` and `encode(to:)` you may need to declare `Equatable` conformance separately or include all fields in CodingKeys. Watch for "Type does not conform to Equatable" — usually means a property type isn't visible.
- **Yams** (5.4.0 resolved): no `dateEncodingStrategy`. Convert `Date <-> String` manually via `ISO8601` helper.
- **SwiftUI `Color(light:dark:)`**: implemented via `UIColor { trait in ... }` initialiser. See `Lists/Design/Tokens.swift`.

## File format

- Per-list folder: `Documents/Lists/<listId>/`
- List metadata: `.list.yml` (single YAML object)
- Items: `<UUID>.md` with YAML frontmatter (`---\n...\n---\n` then markdown body)
- Body field is NOT in frontmatter; written separately by `FrontmatterCodec`. Custom `init(from:)` sets `body = ""` then `FrontmatterCodec.decode` populates it.
- Only-emit-when-non-default: `done`, `flagged`, `dueAllDay`, `priority` (when `.none`), `tags` (when empty), habit fields (only when `type == .habit`).

## Simulator

- **iPhone 17 Pro**, simulator id `65D9F3B1-4A19-4820-B6F7-703D4BDF823C`.
- **Bundle id**: `io.github.saxonbobart.lists` — shared with the archive build at `/Users/saxon/Developer/Projects/archive/lists`. If old data is in the simulator container, bootstrap will fail with `keyNotFound: created_at`. Wipe `~/Library/Developer/CoreSimulator/Devices/65D9F3B1.../data/Containers/Data/Application/<APP-UUID>/Documents/Lists` and relaunch. (See `feedback_wipe_sim_data_when_bundle_shared` memory.)
- **Bootstrap** runs on first appearance via `.task` on ContentView. Sample data seeds when no Lists folder exists.

## Design tokens

- Sage primary, warm-neutral surfaces. SF Pro Rounded for UI, SF Mono for metadata. See `design/Claude Design/project/tokens.css`.
- iOS implementation in `platforms/ios/Lists/Design/{Tokens,Typography,Spacing}.swift`.
- 13-color hue palette for list dots (use `ListsTokens.Hue.<color>`).

## Known stale / open

- `shared/format/` uses old "reminder" naming — needs realignment with new "item" primitive when next touched.
- `shared/lexicons/shopping.en.json` is a 20-entry skeleton; needs ~200 entries before grocery mode ships.
- App Store distribution under AGPL needs a `LICENSE.app-store-exception` file (per spec §17). Not needed until App Store is in scope (gated on paid Developer Program).
- AlarmKit (urgent triggers) is deferred until paid Developer Program. Personal Team `899XX9P8T4` doesn't support it.

## Commit / branch discipline

- Conventional Commits: `feat(ios):` / `fix(ios):` / `chore:` / `docs:` etc.
- Co-Authored-By: `Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer.
- Branch-per-milestone for non-trivial work. Active branch for M1: `feat/m1-screens`.
- Never push, never merge to main, never force, never `--no-verify` without explicit go.
