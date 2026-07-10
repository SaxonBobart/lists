# Snapshot Tests

Visual regression at the SwiftUI view level. No simulator launch — fast, parallelizable.

## How they work

Each test calls `assertSnapshot(of:as:.image(...))`. Screen contracts use a device configuration; small components use a fixed-size layout so the reference image contains the component rather than a mostly empty phone canvas. Views containing Liquid Glass or another `UIVisualEffect` render through the host app's key window with `drawHierarchyInKeyWindow: true`.

## Recording new baselines

The simplest way: delete the stale PNG(s) under `__Snapshots__/` and run the test — the library auto-records when no reference exists (the run "fails" with "Automatically recorded snapshot"). Run again — should PASS. Commit the new images. (`isRecording = true` / `withSnapshotTesting(record: .all)` also work.)

## Re-recording snapshots

Delete only the references owned by the changed contract, then run that focused snapshot suite twice (record, then verify) on iPhone 17 Pro. Do not bulk re-record unrelated screens. Re-record affected references when the simulator runtime changes.

The interface style is pinned: `SnapshotEnvironment` forces `.light` into the device configs, so baselines no longer depend on the simulator's current appearance setting (which was the recurring source of whole-suite drift before 2026-06-13).

## Coverage matrix

Screen-level contracts choose from these variants according to risk:

| Variant | Why |
|---|---|
| iPhone 16, light, default dynamic type | The default UX |
| iPhone SE, light, default dynamic type | Tight horizontal layout |
| iPhone 16, light, accessibilityExtraLarge dynamic type | Catches large-text breakage |
| iPhone 16, dark, default dynamic type | Catches dark-mode-aware token regressions |

`.iPhone13Pro` and `.iPhoneSe` are the closest available `ViewImageConfig` presets in swift-snapshot-testing; they're treated as device-class proxies (modern iPhone vs compact iPhone). Component snapshots should instead use `.fixed(...)` with an explicit light or dark trait collection.

## Stores

- `TestStore.seeded()` — builds an `ItemStore` against a temp directory and runs the seed bootstrap. Use for any view that reads from the store (Sidebar, ListDetail, TodayView, smart lists). Keep seed-facing assertions based on visible behavior, not generated item IDs.
