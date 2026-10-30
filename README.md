# Lists

Lists is an iOS app for tasks, notes and events, stored locally as Markdown
documents with YAML frontmatter. It is unpublished and still in development.
No account or Lists cloud service is required. A dated
[Home reference](design/screens/home-2026-10-27.jpg) uses an isolated sample library.

## Current app

- Tasks support completion, dates, reminders, priority, flags, tags, sections
  and nested items. Repeating tasks and completable events keep occurrence
  history in the same document.
- Notes use Live or Raw Markdown. The editor supports interactive tables,
  internal document and heading links, backlinks, code highlighting, equations
  and Mermaid diagrams. Rendering assets are bundled for offline use.
- Events support start/end times, all-day spans, time zones and recurrence.
  Event completion is optional.
- Lists can nest. Every list offers List and Calendar presentations; lists
  with named sections also offer Kanban-style Columns, including empty columns.
- Pinned views are Today, Scheduled, Flagged, Reminders, Alarms, Completed,
  All and Tags. Scheduled opens the global calendar. Today and Search are
  list-only; other applicable query views can also show Calendar.
- Calendar offers Year, Month, Single Day, an adaptive Multi Day timeline and
  List/agenda views. It projects the same documents used everywhere else.
- Incoming Apple Calendar connections import events into chosen lists and
  refresh while Lists is open or on request. Imported documents remain editable;
  source conflicts can be reviewed. Lists never writes changes back to EventKit.
- Documents support attachments, photos/video capture, PDF scanning, audio
  recording, local previews and Quick Look. Collections can also hold standalone
  files, ordered alongside items.
- Quick Capture, inline editing, move shelves, multi-select, copy/cut/paste,
  custom text properties, on-device voice search and Recently Deleted are
  implemented. Settings includes ZIP export, cache rebuild and an explicitly
  confirmed replacement with sample data.

Alarms currently use standard local notification delivery. AlarmKit alarms,
invitation responses, two-way calendar updates, cloud sync, collaboration and
non-iOS clients are outside the current implementation. See
[the roadmap](docs/ROADMAP.md) for verification still needed before release.

## Storage

The app-private library lives under `Documents/Lists/`:

```text
Lists/
  <list name>/
    .list.yml
    <item title>.md
    .files/
    <child list name>/
      .list.yml
  Attachments/
```

Names are sanitized and disambiguated on disk; stable identities remain in
metadata. Markdown, list headers and attachment files are authoritative.
Indexes and caches can be rebuilt. Files are inside the app sandbox rather than
an exposed Files/iCloud Drive folder; use Export library to obtain a ZIP copy.
Display preferences and incoming-calendar connection mappings stay device-local.

## Build and test

The active project is `platforms/ios/`. Development currently uses Xcode 27
and Swift 6.4; the deployment target remains iOS 26. XcodeGen owns project
generation and the Swift packages are resolved through Xcode.

```sh
cd platforms/ios
xcodegen generate
open Lists.xcodeproj
```

Choose an installed iPhone simulator or a supported iPhone and run scheme
`Lists`. Signing a device build requires a suitable development team.

`ListsTests` uses Swift Testing for logic/integration coverage and XCTest with
SnapshotTesting for visual contracts. Tests run in the app host on an iOS
simulator. Choose an available simulator UUID, then run:

```sh
LISTS_SIMULATOR_ID="paste-an-available-simulator-UUID"
xcodebuild \
  -project Lists.xcodeproj \
  -scheme Lists \
  -testPlan Lists \
  -destination "platform=iOS Simulator,id=$LISTS_SIMULATOR_ID" \
  -parallel-testing-enabled NO \
  test
```

XcodeBuildMCP CLI is also used for builds, tests and driven simulator checks.
Local simulator defaults and the verified interaction workflow are documented
in [AGENTS.md](AGENTS.md). Gesture verification combines focused logic tests
with driven exploration; there is no XCUITest target.

## Repository map

- [Project health investigation](docs/PROJECT-HEALTH-2026-10-30.md): configuration findings and priorities.
- Agent GitHub checkpoints run automatically after verified changes; see `AGENTS.md` and `scripts/agent-checkpoint.py`.
- [Product standard](PRODUCT-SPEC.md): behavior to preserve.
- [Architecture](docs/ARCHITECTURE.md): source map and storage invariants.
- [iOS design rules](design/ios-design-rules.md): current visual contracts.
- [Roadmap](docs/ROADMAP.md): release gates and deferred capabilities.
- [Snapshot guide](platforms/ios/ListsTests/SnapshotTests/README.md): capture
  and reference-review rules.
- [Audit record](docs/AUDIT-2026-10-27.md): cleanup scope and verification limits.

The local checkout is the development source of truth. `dev` is the working
branch and `main` is the stable fallback. Agents save and push coherent,
verified development changes automatically. Task branches get draft pull requests into `dev`. Releases and changes to `main`
require a separate maintainer decision.

## Privacy and license

Lists contains no analytics, advertising or telemetry. See the
[privacy policy](PRIVACY.md) for device permissions and data handling.
[Support issues](https://github.com/SaxonBobart/lists/issues) are public;
keep personal data out of reports.

Licensed under AGPL-3.0-or-later. See [LICENSE](LICENSE).
