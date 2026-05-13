# Current Status

## Active Work

The active implementation is the iOS app in `platforms/ios/`.

Work should happen on `dev`. Keep `main` stable.

## What Exists

- SwiftUI app project: `platforms/ios/Lists.xcodeproj`
- XcodeGen spec: `platforms/ios/project.yml`
- XcodeBuildMCP defaults: `.xcodebuildmcp/config.yaml`
- Core models, file storage, frontmatter codec, sample data, smart lists, tags, reminders, and notification scheduling
- Main screens for sidebar, today, smart lists, list detail, item detail, quick capture, habits, search, settings, recently deleted, tags, and thread view
- Swift Testing and XCTest coverage, including Markdown editor tests

## Next Work

- Stabilize the current iOS feature set on `dev`.
- Keep Markdown editor behavior covered by repeatable tests. Use `SmokeTests.testMarkdownEditorScreenshotsAndCursorMovement` when screenshots are needed; it writes PNGs to `artifacts/markdown-editor-screenshots/`.
- Realign `shared/format/` wording with the iOS `Item` model when the format contract is next touched.
- Defer Android, Linux, Windows, sync, and AlarmKit until explicitly requested.

## Constraints

- Bundle id: `io.github.saxonbobart.lists`
- Apple team: `899XX9P8T4` personal team
- AlarmKit is deferred until a paid Apple Developer Program account exists
- iOS data stays app-private in `Documents/Lists/`
- Use XcodeBuildMCP for build, test, run, screenshots, logs, and UI snapshots
