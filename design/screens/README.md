# Screen references

The historical full-screen PNG collection was retired in the October 2026
cleanup. It showed removed Assigned/Urgent tiles, old sample lists and superseded
document chrome, so it must not guide current UI changes.

[Home — 27 October 2026](home-2026-10-27.jpg) was captured on iPhone 18 Pro /
iOS 27.2 using an isolated sample library. It records that viewport and date,
not every screen or a permanent assertion about future builds.

For current visual evidence:

- Inspect a fresh capture from the running app on the simulator UUID configured
  in `.xcodebuildmcp/config.yaml`.
- Use the focused references beside tests under
  `platforms/ios/ListsTests/**/__Snapshots__/`, following the snapshot guide.
- Match current interaction contracts in `PRODUCT-SPEC.md` and
  `design/ios-design-rules.md`.

Never erase or reseed an existing library to refresh screenshots. Use a
controlled disposable/isolated sample library for destructive QA.
