---
description: Generate a snapshot test for a SwiftUI view.
argument-hint: "<ViewName>"
---

Generate a snapshot test for the SwiftUI view named in $ARGUMENTS:
1. Locate the view in `platforms/ios/Lists/Features/` or `Design/Components/`.
2. Identify its initializer dependencies and any @Binding requirements.
3. Write a SnapshotHost wrapper if the view takes bindings.
4. Create `platforms/ios/ListsTests/SnapshotTests/<ViewName>SnapshotTests.swift` with these variants:
   - iPhone 16 (.portrait), default dynamic type, light mode
   - iPhone SE (.portrait), default dynamic type, light mode
   - iPhone 16 (.portrait), accessibility3 dynamic type, light mode
   - iPhone 16 (.portrait), default dynamic type, dark mode
5. Run with `isRecording: true` first to seed the reference images, then revert to `isRecording: false`.
6. Run the test once to confirm green.
