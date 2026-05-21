# Snapshot Tests

Visual regression at the SwiftUI view level. No simulator launch — fast, parallelizable.

## How they work

Each test wraps a view in `UIHostingController` and calls `assertSnapshot(of:as:.image(...))`. swift-snapshot-testing renders the view off-screen and compares against a PNG in `__Snapshots__/<TestClass>/<testMethod>.<n>.png`.

## Recording new baselines

1. In the test, set `isRecording = true` (or `withSnapshotTesting(record: .all) { … }`).
2. Run the test once: `/test ListsTests/SnapshotTests/<TestName>`.
3. Remove `isRecording = true`. Run again — should PASS.
4. Commit the new images under `__Snapshots__/`.

## Re-recording all snapshots

Regenerate by running with `isRecording = true` on iPhone 17 Pro / iOS 26.x. Sim differences will diff against committed PNGs — keep the sim model stable.

## Coverage matrix

Most views snapshot at four variants:

| Variant | Why |
|---|---|
| iPhone 16, light, default dynamic type | The default UX |
| iPhone SE, light, default dynamic type | Tight horizontal layout |
| iPhone 16, light, accessibilityExtraLarge dynamic type | Catches large-text breakage |
| iPhone 16, dark, default dynamic type | Catches dark-mode-aware token regressions |

`.iPhone13Pro` and `.iPhoneSe` are the closest available `ViewImageConfig` presets in swift-snapshot-testing; they're treated as device-class proxies (modern iPhone vs compact iPhone).

## Hosts and stores

- `SnapshotHostBool` / `SnapshotHostString` — wrap views that need `@Binding`s the test owns.
- `TestStore.seeded()` — builds an `ItemStore` against a temp directory and runs the seed bootstrap. Use for any view that reads from the store (Sidebar, ListDetail, TodayView, smart lists). The seed item IDs are pinned in `SampleData.testIds`.
