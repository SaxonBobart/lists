# Snapshot tests

These XCTest cases run in the Lists app host on an iOS simulator. Small
components use fixed sizes; screen contracts use stable device-class presets.
Names such as iPhone16/iPhoneSE identify those layout contracts rather than the
simulator's actual hardware model. `SnapshotEnvironment` pins appearance traits.

Views using Liquid Glass/`UIVisualEffect` need a mounted key window and
`drawHierarchy` rendering. A `SnapshotTesting.wait(for:on:)` wrapper waits
before its nested image strategy mounts the controller. When toolbar settling
matters, mount first, wait for rendering, then capture and compare the image.
Settings uses one mounted capture; independent fresh-run comparisons support its compact native-edge reference update. Preserve the original SnapshotTesting PNG bytes when copying an approved reference: generic image re-encoding can truncate native 16-bit data.

## Reviewing references

1. Run the focused test on the configured simulator UUID and inspect the
   reference, actual image and diff.
2. Establish whether the mismatch is an app defect, fixture/timing problem,
   intentional product change or stable runtime rendering difference.
3. Fix defects or capture isolation first. Update only references justified by
   reviewed evidence; keep exact comparison precision.
4. Verify an updated reference in a fresh run, then include an aggregate run
   when isolation or cross-test state is relevant.

Keep existing references while investigating. Do not bulk delete/re-record them
to obtain a passing run. Runtime upgrades can justify reviewed native-rendering
changes, but do not automatically approve every mismatch.

## Coverage and fixtures

Contracts include light/dark, compact-width and accessibility Dynamic Type
variants according to risk. `.iPhone13Pro` and `.iPhoneSe` are library presets
for modern/compact phone layouts; fixed components use explicit size and traits.

`TestStore.seeded()` creates a temporary library. Fixtures and UserDefaults
suites must remain isolated. Preserve useful source/metadata, attachment,
hierarchy and visibility assertions alongside visual contracts.

Use Xcode's Lists test plan or the XcodeBuildMCP CLI with an explicit available
simulator UUID. The current project-local defaults live in
`.xcodebuildmcp/config.yaml`; do not select a device by name when duplicate
names exist across runtimes.
