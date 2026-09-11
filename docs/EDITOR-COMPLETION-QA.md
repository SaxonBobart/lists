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

## Inline attachment visual refinement

The follow-up uses compact document/audio rows, transparent photo/video
surrounds, and long-press attachment actions. On the regular iPhone 17 Pro
simulator, refreshed runtime evidence confirmed separate consecutive audio
cards, playback/pause, seeking from 0:01 to 0:36, the complete video context menu,
and PDF Quick Look opening/closing. All 13 focused EditorCompletionTests passed,
including attachment row height and non-overlap checks. Apple Notes was unavailable on the local
simulator, so the comparison used Apple’s attachment documentation and published
Notes screenshots rather than a live Notes session.

## Markdown attachment presentation

The subsequent product decision replaces inline audio/video players and PDF
thumbnails with compact `[title](path)` links. Only Markdown image syntax
`![alt](path)` renders inline media. All types open on tap in the full viewer.
Show Image / Show as Link modifies only the leading `!` and uses native undo.
Attach Files creates links; the Photos flow creates image syntax for images.
This supersedes the visual presentation described in the earlier passes above.
Embedded images reserve their natural aspect ratio at the available note width.

Verified in the running app using a separate Weekend plans fixture: compact
PDF/audio/image links, PDF and audio viewers, Show Image expansion, Undo back to
the original link, attachment-source menu, and Raw Markdown. All 13 focused
EditorCompletionTests pass, including mixed link/embed layout, no overlaps, and
unchanged source. Screenshots and a screen recording capture this flow. The
system Files sheet did not expose usable automation controls, so a complete
import through that sheet was not verified in this pass.

## Cursor, attachment menu, and calendar follow-up

The keyboard paperclip now presents a native button menu without ending editor
focus. Real blank Markdown paragraphs keep body-text height; rendered display
math and diagrams reserve the full text column for hit testing. Hidden render
attributes no longer leak into newly typed text.

Driven checks on the regular iPhone 17 Pro confirmed a normal-height caret
between display math and Mermaid, typing before and after opening/dismissing
the attachment menu without refocusing, Undo restoring the original paragraph,
and tapping beside a diagram opening its viewer. The simulator suppressed its
software keyboard, so retained typing focus is verified but the visible keyboard
transition still needs a phone check.

Calendar now has the divider below the week strip in timeline modes. Two-day
swipes advance one day, and the week strip's range and selected-date indicator
follow the drag and settle with animation. Apple Calendar was inspected with a
recording and extracted frames. At this checkpoint the timeline columns still
changed on release; the continuous-paging follow-up below replaces that behavior.
The divider, one-day advancement, and highlight animation were verified live.

The focused editor completion, table, interaction regression, and calendar date
math run passed all 89 tests (99 cases including parameterized runs). The two
week-strip appearance references were separately reviewed: only capsule edge
rasterization changed when the range became one moving shape. Both updated
light/dark snapshot tests passed in the follow-up run.

One navigation crash occurred before reaching the editor during the first
verification launch (an Objective-C unrecognized-selector exception in UIKit
animation teardown). It did not recur after relaunch or during the completed
editor/calendar flows; its cause is not established.

## Continuous calendar paging and attachment selection

Calendar headers, all-day items, and timed columns now share a continuous
three-page surface, with the time gutter fixed. Dragging exposes neighboring
dates immediately; a display-synchronized settling animation completes before
the selected date changes. Short slow drags cancel; flicks project their release
velocity. Filtered weekdays retain their ordering. The all-day band interpolates
its height toward the incoming range. Reduce Motion skips the settling animation.

Driven recordings verified intermediate header positions, one-day swipes in both
directions, cancellation, and unchanged vertical scroll offset. All 34 focused
calendar tests passed, including existing light/dark timeline and all-day
snapshots. The all-day snapshot passed again after the height interpolation change.

While editing, file/image and rendered math/diagram taps select presentation
state without changing the text selection. Open and Edit Markdown are visible;
source editing reveals the original Markdown in place. Moving the caret away
renders it again. Long-press retains secondary actions. File controls have
verified 44-point tap targets and distinct accessibility identifiers. Image
controls overlay the image; selecting a tall image scrolls its controls into view.

The driven file flow verified reading-mode Quick Look, selection while editing,
retained keyboard focus/caret, exact source revelation, and rendering again after
moving the caret. Diagram selection and visible actions were also verified.
The 22-test editor completion/interaction run passed, including source/caret
preservation during attachment selection and clearing it after focus changes.
All 15 editor completion tests passed again after adding automatic control
visibility for tall images.

Full-width image selection, 44-point actions, and the retained long-press menu
were verified after stopping concurrent simulator tests. This exposed an image
source bug: the selection began at `!`, outside the nested link's styling
context, so only alt text was shown. Active attachment source now remains
entirely literal. Regression coverage checks that every image-source character
is visible and leaving the range restores its embed without changing the text.
All 16 editor completion tests passed with this correction.
The final driven recording confirms the complete `![description](path)` source
is visibly selected and moving the caret away restores the full-width image.
The latest build was left running in the owned QA note. No document text or
attachment files were modified during these selection/viewing checks.

## Remaining device checks

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


## Calendar interaction refinement — 11 September 2026

The supplied Apple Calendar recording was inspected at 30 frames per second.
The calendar now projects multi-day flick destinations, uses a moving window of
page surfaces, crossfades selection between fixed date positions, and fits two
to seven columns to window width. All-day band height follows the same offset.
Date-crossing haptics occur during the gesture. Event/handle pickup and release
have feedback; edge scrolling accelerates, creation previews are centred, and
resize previews stop at the displayed day's midnight boundaries. Staggered
overlapping events retain width with a small inset for later cards.

The focused calendar run covered 34 logic tests and 16 visual references across
subsequent runs. Updated references were inspected before acceptance; the new
staggered-overlap and five-column references were recorded and then passed.
Runtime checks confirmed a forward flick from September 11 to 15, reverse
movement from 15 to 14, and a faster reverse movement from 14 to 12. Fresh
accessibility state and screenshots agreed on the destination dates. Very short
automated swipes initially cancelled; final-translation sampling was corrected
before the final build. Saxon offered to check the difficult gestures directly,
so subjective swipe feel, reversal, edge scrolling and physical haptics remain
user checks rather than claims of complete simulator verification.


The later selection refinement replaces continuous crossfading with discrete
haptic-threshold changes: the range pill animates at the crossing, the previous
circle disappears, and its replacement scales in quickly. A fixed gutter divider
and viewport grid backing keep boundaries visible while paging and bouncing.
The resting timeline snapshot differences are confined to the gutter divider's
two physical-pixel columns; the rest of each reference is unchanged. The user
continues to verify animation feel directly in the simulator.
