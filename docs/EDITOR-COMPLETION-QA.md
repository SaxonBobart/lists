# Editor completion verification

8 September 2026. Xcode 27, iOS 27 simulator; deployment target remains iOS 26.
The implementation preserves Markdown source and the existing table gestures.

## Automated coverage

The focused run covers editor completion, existing interaction regressions,
tables, paste handling, and attachment storage. It includes native Undo,
UTF-16 replacements, source preservation, code/math context, renderer output,
block geometry, file confinement, original-byte imports, relative destinations,
quarantine, and library export. Final result: **70 passed, 0 failed**.
The final result bundle is
`test_sim_2026-09-08T05-43-55-499Z_pid42432_3f15a5e0.xcresult`
in the local XcodeBuildMCP workspace. The app also builds successfully through
the Xcode project bridge.

## Driven simulator checks

- Generic Note header absent; collapsed title leads beside Back. Details and
  More remain directly accessible with and without the keyboard.
- More exposes Undo/Redo, Find and Replace, Attachments, and Editor Help.
  Find/Replace updates persisted text and Undo restores it.
- Inline/display equations and Mermaid render offline. Diagram height and
  consecutive audio-card height do not overlap following content. Raw Markdown
  removes overlays and retains the exact source.
- PNG preview and Quick Look; unavailable-file state; PDF thumbnail/page count;
  video poster and playback; audio playback and pause; starting video pauses audio.
- Attachment action menu and Remove/Undo preserve the reference and file.
- Audio recording starts, pauses, saves, and plays. Recording controls remain
  accessible inside the document presentation and at the library root.
- Ordinary prose and list continuation preserve the expected saved source.
- Table cell edits persist, and Undo/Redo restore visible cell text while
  retaining the focused cell, caret, and viewport.

Only a temporary QA note and its generated fixtures were edited. The existing
library was not reset. QA fixtures remain in the simulator for inspection.

## Device verification still required

These capabilities are implemented but simulator evidence does not establish
physical-device behavior:

- Recording through a locked screen, route changes, interruptions, low storage,
  forced termination, and recovery after relaunch.
- Physical camera photo/video capture, scanner capture and permission denial.
- Photos/iCloud and Files providers with large assets, cancellation, and partial
  import failures; animated-image behavior in the system viewer.
- VoiceOver, larger accessibility text sizes, hardware keyboard, dictation,
  and composed-language input on an actual phone.

Future clients should retain ordinary Markdown links and attachment files;
there is no new platform-specific document schema. Android/desktop work is not
part of this change. Capture does not add transcription or drawing tools.
