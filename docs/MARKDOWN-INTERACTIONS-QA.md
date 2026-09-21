# Markdown interaction verification — 21 September 2026

Environment: Xcode 27 beta 6, Swift 6.4 in Swift 6 language mode, iOS 27
simulator, iPhone 17 Pro `E3BF33BE-4A66-4B02-B476-D432B6340C8D`.
The deployment target remains iOS 26. Xcode's persistent bridge was unavailable;
builds, focused tests and simulator interaction used XcodeBuildMCP.

## Automated regression coverage

The completed validation runs below passed with no failures or skipped tests. Counts overlap; they are
reported per run rather than added together.

| Run (UTC) | Tests | Coverage |
| --- | ---: | --- |
| 00:44 | 128 | Interaction overhaul, existing editor completion, minimal diffs, interaction regressions, paste and attachment storage |
| 00:54 | 135 | Overhaul, editor completion, minimal diffs and table editing |
| 01:04 | 78 | Overhaul, interaction regressions and table editing after layout fixes |
| 01:16 | 22 | Final overhaul tests plus document/list rename repair, duplicate filename repair and legacy UUID destination conversion |
| 01:39 | 82 | Final source: overhaul, interaction regressions and table editing, including revealed-link row/document sizing |
| 01:52 | 82 | Delivery build, after the keyboard frame-change restoration fix; same focused suites |

`MarkdownInteractionOverhaulTests` covers:

- Attachment boundary mapping, backward/forward deletion, selection replacement,
  native undo/redo, tall carets, blank paragraphs, inline references, literal code
  exclusions and preservation of the underlying file.
- Document identity based preview preferences and image/PDF defaults.
- Math/Mermaid content-only selection, closing-delimiter geometry, actual renderer
  errors, invalid-to-valid edits and rejection of superseded rendering requests.
- Offline Highlight.js tokens with UTF-16 offsets, aliases, unknown languages,
  completion replacement ranges and character-by-character fence entry.
- Parsed headings, duplicate anchors, Unicode, Setext headings, code/HTML
  exclusions, legacy formatted heading resolution and same-document fragments.
- Native inline-file selection actions, internal-link insertion and one-time
  restoration of body/table selections after cancellation.
- Populated/empty/nested lists, checklists, numbered lists and composed Unicode
  deletion. Existing table tests cover replacement, cell navigation and boundaries.

Result bundles are under the local XcodeBuildMCP `lists-c09153969160` workspace.
The final focused bundle is
`test_sim_2026-09-21T01-52-07-332Z_pid7955_eeab866e.xcresult`.

## Driven simulator checks

Disposable notes and generated PNG/PDF/text attachments were used, with fresh
hierarchies and screenshots after interaction. No library reset was performed.

- Compact image card shows title, type, size and local date. Standalone PDF opens
  as a first-page preview. Native long-press shows Open and Show/Hide Preview.
- Preview toggling leaves Markdown unchanged and survives reinstall/reopening.
- Taps on each side of an expanded image give the matching full-height blue caret.
  Backspace removes the full reference; Command-Z restores it. All fixture files
  remain byte-for-byte present after reference removal.
- Math source stays above its live result. Invalid `a^` exposes KaTeX's actual
  diagnostic; completing the superscript clears it. Mermaid closing-delimiter
  movement keeps source visible and the preview underneath.
- Opening-fence completion filters `sw` to Swift and replaces only the language.
  Rapid automation input initially reordered backticks; individual key entry and
  the native insertion regression both confirm correct source preservation.
- The next toolbar icon is visibly recognizable on the first page. The link
  button presents the compact Internal Link / External Link choice.
- Picking the second same-document Section inserts `#section-1`, returns to the
  original editor and restores its keyboard/caret. Cancelling the item browser
  also returns to the source editor. This pass exposed and fixed a missing return
  route, then added a caret recheck after keyboard layout settles.
  A fresh presentation initially omitted the 68-point accessory from its keyboard
  inset (322 rather than 390 points). Reloading the input views once on return
  restores native avoidance. The final screenshot confirms the caret is fully
  above the toolbar (`internal-link-return-fixed.png`).
- External Link inserts `[Exactly](https://example.com)` at the captured position
  and restores editing. Light appearance at extra-extra-extra-large text remains
  readable; keyboard dismissal works. Original dark/large settings were restored.
- Opening a missing PDF shows an Unable to Open Attachment message and preserves
  the reference. Screenshots from this pass are saved locally under
  `/tmp/lists-editor-qa-final/`.
- Cancelling External Link restores the unchanged source selection and keyboard.
- Table-cell External Link insertion and cancellation retain the original cell.
  The new native regression reproduces long revealed-link wrapping and verifies
  that the row and document grow together, the caret fits inside the cell, and
  leaving the cell collapses its height without changing Markdown.
  The final simulator check confirms all three source lines and the caret fit
  inside the border after External Link cancellation, with 47 points of clearance
  above the toolbar (`table-cancel-frame-change.png`). Restored input refresh
  handles both keyboard did-show and did-change-frame events, including a switch
  from the external URL field to an already-visible table keyboard.

## Physical-device limit

The native lifted context-menu path is exercised on the simulator. Haptic feel
requires a person holding the physical device and has not been verified by this
automated pass. A connected device alone is not evidence of tactile behavior.

## Cleanup

Both disposable QA notes were moved to Recently Deleted through normal in-app
confirmation. Only the three generated PNG/PDF/text fixtures were then removed
from Attachments, with copies retained in the local screenshot directory's
`fixture-backup` folder. Original notes and dark/large appearance settings were
preserved; the updated app was left running on the configured simulator.
