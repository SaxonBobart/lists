# Snapshot Tests

Visual regression at the SwiftUI view level. No simulator launch — fast, parallelizable.

## How they work

Each test wraps a view in `UIHostingController` and calls `assertSnapshot(of:as:.image(...))`. swift-snapshot-testing renders the view off-screen and compares against a PNG in `__Snapshots__/<TestClass>/<testMethod>.<n>.png`.

## Recording new baselines

The simplest way: delete the stale PNG(s) under `__Snapshots__/` and run the test — the library auto-records when no reference exists (the run "fails" with "Automatically recorded snapshot"). Run again — should PASS. Commit the new images. (`isRecording = true` / `withSnapshotTesting(record: .all)` also work.)

## Re-recording all snapshots

Delete all of `__Snapshots__/` and run `ListsTests` twice (record, then verify) on iPhone 17 Pro. Baselines were last recorded 2026-06-13 on the iOS 27.0 runtime; re-record when the sim runtime changes.

The interface style is pinned: `SnapshotEnvironment` forces `.light` into the device configs, so baselines no longer depend on the simulator's current appearance setting (which was the recurring source of whole-suite drift before 2026-06-13).

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
