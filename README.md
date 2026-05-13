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

Markdown editor visual checks are covered by an XCUITest:

```text
SmokeTests.testMarkdownEditorScreenshotsAndCursorMovement
```

It saves screenshots to `artifacts/markdown-editor-screenshots/`.

## Useful Docs

- `AGENTS.md` - agent instructions and XcodeBuildMCP defaults
- `PRODUCT-SPEC.md` - compact product behavior spec
- `docs/CURRENT.md` - current status and next work
- `shared/` - schemas, fixtures, and cross-platform contracts
- `design/` - visual design prototype and tokens

## License

AGPL-3.0-or-later. See `LICENSE`.
