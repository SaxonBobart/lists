# Lists

**Tasks, habits, notes, and events — in one calm, native iOS app built on plain files you own.**

No account. No sign-in. Works offline. Everything is stored as ordinary text files on your phone.

Status: pre-v1, private, iOS only. Built with SwiftUI on Xcode 27 / iOS 27 beta.

## Open in Xcode

Requirements:

- Xcode 27+
- Swift 6.2
- iOS 27 simulator
- XcodeGen (if project files need regenerating)

```sh
cd platforms/ios
xcodegen generate
open Lists.xcodeproj
```

## Build defaults (XcodeBuildMCP)

Configured in `.xcodebuildmcp/config.yaml`:

- project: `platforms/ios/Lists.xcodeproj`
- scheme: `Lists`
- simulator: `iPhone 17 Pro`

## Tests

- `ListsTests` — unit tests + snapshot regression (swift-snapshot-testing). Fast, no simulator launch. Baselines in `platforms/ios/ListsTests/SnapshotTests/__Snapshots__/`. (The former XCUITest target was retired 2026-06-13; interactions are verified via driven simulator sessions.)

Run via `/test` in Claude Code, or `xcodebuild -scheme Lists -testPlan Lists test`.

## Key docs

| Doc | What it covers |
|---|---|
| `AGENTS.md` | Rules for agents working on this repo |
| `PRODUCT-SPEC.md` | Compact current iOS behavior spec |
| `docs/CURRENT.md` | Active status, next work, known risks |
| `docs/CHANGELOG.md` | Dated milestone history |
| `GIT-GUIDE.md` | Plain-English solo Git workflow |
| `design/ios-design-rules.md` | Visual rules for iOS UI changes |

## License

AGPL-3.0-or-later. See `LICENSE`.
