# Lists

Lists is a local-first iOS app for tasks, habits, and notes stored as plain markdown files with YAML frontmatter.

Status: pre-v1, private, iOS-first.

## Open in Xcode

Requirements:

- Xcode 26+
- Swift 6.2
- iOS 26+ simulator
- XcodeGen, if project files need regenerating

```sh
cd platforms/ios
xcodegen generate
open Lists.xcodeproj
```

## Agent Workflow

Agents should read `AGENTS.md`. The default build/test/run path is XcodeBuildMCP using `.xcodebuildmcp/config.yaml`.

Current defaults:

- project: `platforms/ios/Lists.xcodeproj`
- scheme: `Lists`
- simulator: `iPhone 17 Pro`

## Tests

Two targets, both runnable via XcodeBuildMCP:

- `ListsTests` — unit tests + view-level snapshot regression via swift-snapshot-testing. Fast, no simulator launch. 48 baseline images live under `platforms/ios/ListsTests/SnapshotTests/__Snapshots__/`.
- `ListsUITests` — XCUITest gesture and flow coverage anchored on accessibility identifiers. Slower (each test launches the app); use sparingly for gestures that can't be exercised any other way.

Run via `/test` in Claude Code, or `xcodebuild -scheme Lists -testPlan Lists test`.

## Useful Docs

- `AGENTS.md` - agent instructions and XcodeBuildMCP defaults
- `PRODUCT-SPEC.md` - compact product behavior spec
- `docs/CURRENT.md` - current status and next work
- `design/` - visual design prototype and tokens

## License

AGPL-3.0-or-later. See `LICENSE`.
