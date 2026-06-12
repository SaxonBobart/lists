# Markdown Editor Audit

## Verdict
**Minor issues, trending Solid.** This is genuinely impressive, careful work for an AI-assisted
build: the styler never mutates the underlying characters (styling is purely attributes + a
glyph-substitution delegate), every smart edit is a pure `(text, selection) -> (text, selection)`
transform, and the well-known TextKit `headIndent`/`firstLineHeadIndent` drift is correctly handled
everywhere it matters. The dominant risk for this code class — NSRange vs grapheme-cluster mixups —
is mostly dodged because markers are ASCII, but there is one real exception. The two issues most
worth fixing are **undo/redo (every smart action nukes the whole document, breaking native undo
coalescing)** and a **per-keystroke full-document re-style + double full-document glyph invalidation**
that will get slow on long notes. No crashes-on-common-path or data-corruption bugs were found.

## Findings

### [P1] Every smart edit replaces the entire document, destroying native undo
- **Where:** `EditorCoordinator.swift:383-404` (`applyResult`); called from Return (`:53`),
  Tab (`:64`), Backspace (`:82`), marker-zone redirect (`:108`), checkbox tap (`:256`),
  vertical-move sync, paste (`:344/:352`), and every toolbar action (`:371`).
- **What:** `applyResult` does `storage.replaceCharacters(in: <full document>, with: result.source)`
  for *any* smart action — even when only one character changed (e.g. typing a char in the marker
  zone, or toggling one checkbox). There is **no `UndoManager` integration anywhere** in the
  subsystem (confirmed: zero references to `undoManager`/`registerUndo`).
- **Impact:** UITextView's built-in undo records "replace whole doc A with whole doc B" as one giant
  step. After pressing Return on a list, a single Cmd-Z (hardware keyboard / iPad) likely reverts a
  large swath of the note at once, or undo behaves erratically because the recorded range no longer
  matches the typed-text coalescing UIKit expects. Typing between smart actions further fragments the
  stack. For a notes app this is a real, user-visible correctness/UX break.
- **Confidence:** High (that undo is not handled). Med on exact runtime symptom (depends on UIKit's
  internal undo coalescing for full-range replacements; needs a device check).
- **Fix:** In `applyResult`, compute the **minimal changed sub-range** (common-prefix / common-suffix
  diff between old and new source) and replace only that, instead of the whole string. That alone
  lets UITextView's native undo do the right thing for most edits. For multi-edit transforms, wrap
  the replacement in `textView.undoManager?.beginUndoGrouping()/endUndoGrouping()`.

### [P1] Whole-document re-style on every keystroke + double full-doc glyph/layout invalidation
- **Where:** `MarkdownStyler.processEditing()` `:97-126` (re-styles `0..<backing.length` every edit
  and force-`edited`s the full range); `EditorCoordinator.textViewDidChange` `:135-140`
  (`invalidateGlyphs` + `invalidateLayout` over the *full* document on every change);
  `applyResult` `:395-400` (full-doc invalidate again).
- **What:** `processEditing` unconditionally calls `applyBaseAttributes(in: full)` then
  `applyLiveStyling(in: full)` — re-running every regex (`enumerateSubstrings(.byLines)` plus
  ~20 inline regexes per line, plus a whole-document fence scan) across the *entire* note on every
  single keystroke. It then expands the edited range to the full document, and the coordinator
  *additionally* invalidates glyphs + layout doc-wide after the edit settles. So each keypress is
  O(document length), not O(line).
- **Impact:** Fine for short notes; on a long note (a few thousand lines / tens of KB — plausible for
  a "notes" surface) typing will visibly lag and the keyboard will feel sticky, because TextKit
  re-generates glyphs and re-lays-out the whole document per character. Battery/CPU cost too.
- **Confidence:** High that it is O(n) per keystroke. Med on the exact length where lag becomes
  perceptible (needs profiling on-device).
- **Fix:** Restrict re-styling to the edited paragraph range plus any open fence it participates in,
  rather than the full document. The full-doc glyph invalidation in `textViewDidChange`/`applyResult`
  is the heavy hammer used to fix sibling-row staleness (documented at length in the code); narrow it
  to the affected paragraph range(s) once styling is paragraph-scoped. This is the single biggest
  scalability risk in the subsystem.

### [P1] `ListMarker.detect` counts grapheme clusters but results are used as UTF-16 offsets
- **Where:** `ListContinuation.swift:112-167` (`detect` walks `Array(line)` of `Character`);
  consumed as NSString/UTF-16 offsets at `ListContinuation.swift:36` (`substring(from: contentStart)`),
  `EditorCoordinator.swift:78,98`, `BackspaceHandler.swift:34,50`, `CursorSnapping.swift:50,98,103`,
  `CheckboxToggler.swift:34`, `ToolbarAction.swift:264`.
- **What:** `detect` measures `indent`/`contentStart` in Swift `Character`s (grapheme clusters).
  Every call site then adds those numbers to `lineRange.location` (a UTF-16 offset) or uses them as
  an NSRange length. This is **safe today** only because the marker prefix and indent are pure ASCII,
  so grapheme count == UTF-16 count for the prefix. The latent bug is in the *numbered* branch:
  `chars[i].isNumber` + `Int(String(...))` accept non-ASCII Unicode digits (e.g. Arabic-Indic `٢`),
  while the styler's `numberedListRegex` uses ASCII `\d`. A multi-byte "digit" would make
  `detect`'s offsets diverge from UTF-16, mis-placing the caret or producing a wrong NSRange.
- **Impact:** Edge case (someone typing non-ASCII numerals to start a list). Worst plausible outcome
  is a wrong caret landing or a 1-off marker strip on that line; not a crash, because all NSRange uses
  are still clamped to line bounds. But it is exactly the class of latent index bug this code is prone
  to, and it's a correctness hazard if marker syntax ever grows beyond ASCII.
- **Confidence:** Med (real divergence; narrow trigger).
- **Fix:** Either constrain the numbered branch to ASCII `0-9` (matching the regex), or — cleaner —
  rewrite `detect` to work on the NSString / `utf16` view so all offsets are UTF-16 by construction
  and can never drift from call-site math.

### [P1] Quoted-task checkbox renders as tappable but tapping does nothing
- **Where:** styler paints the checkbox for `> - [ ] do` via `quotedTaskRegex` +
  `.sfSymbolCheckbox` (`MarkdownStyler.swift:338-388`); but `ListMarker.detect` recognises `> ` as
  `.blockquote` and never as a task (`ListContinuation.swift:158-164`), so
  `EditorCoordinator.taskLineRange` requires `case .task` (`:242`) and bails.
- **What:** A blockquoted task line draws a real SF Symbol checkbox (looks identical to a normal,
  tappable one), yet the checkbox tap gesture's hit-test rejects the line because the detected marker
  kind is `.blockquote`, not `.task`. Smart Return / Backspace on that line also treat it as a plain
  blockquote, not a task.
- **Impact:** User sees a checkbox inside a quote, taps it, nothing happens — a confusing dead
  control. Low-frequency construct, but a clear inconsistency between what's drawn and what's
  interactive.
- **Confidence:** High.
- **Fix:** Either teach `ListMarker.detect` to parse a quoted task (`>+ \s* - [ ] `) and return a
  `.task` kind with the correct `contentStart`, or stop rendering the SF Symbol checkbox for quoted
  tasks (tint the literal `[ ]` instead) so it doesn't look tappable.

### [P2] `wrapInline` toggle-off can read out of bounds on a doubled single-char marker near doc edges
- **Where:** `ToolbarAction.swift:161-170`.
- **What:** In the single-char (`*` / `` ` ``) un-wrap path, `rightStart + markerLen` is checked
  `< ns.length` before reading `ns.substring(..., location: rightStart + markerLen, length: 1)`. If
  the wrapped selection sits exactly at the end of the document, `rightStart + markerLen == ns.length`
  and the guard is false, so it skips — that's fine. But `leftStart - 1 >= 0` then reads
  `location: leftStart - 1` which is valid. The arithmetic is *just* in-bounds in the cases I traced,
  but it is fragile: the bounds checks and the reads are written separately and rely on `markerLen`
  being exactly 1. A future 3-char single-glyph marker, or an off-by-one in either clause, would index
  past the string and crash.
- **Impact:** No crash found on current inputs; a maintainability/robustness hazard in code that does
  manual NSString index arithmetic with `+1`/`-1` offsets.
- **Confidence:** Low (could not construct a crashing input with current markers).
- **Fix:** Replace the ad-hoc `leftStart - 1` / `rightStart + markerLen` reads with
  `NSLocationInRange`-guarded substrings, or use `rangeOfComposedCharacterSequence`/explicit
  clamped ranges so the read can never exceed `ns.length`.

### [P2] `headingRegex` allows H1–H6 syntax but styler caps the visual at level 4
- **Where:** `MarkdownStyler.swift:325-334` (`level = min(hashRange.length, 4)`,
  `headingFont` `:1168-1182` maps 5/6 to `.body`); regex allows only `#{1,4}`
  (`:1192`), yet the toolbar offers H5/H6 (`MarkdownReminderToolbar.swift:142-143`,
  `ToolbarAction.renderPrefix` emits `#####`/`######`).
- **What:** The toolbar inserts `##### ` / `###### `, but `headingRegex` is `^(#{1,4}) +` so a
  5- or 6-hash line is **not styled as a heading at all** in Live mode — it renders as plain body
  text with the literal hashes showing. Round-trips fine to disk (source is preserved), but the live
  preview silently fails for H5/H6.
- **Impact:** User picks "H5"/"H6" from the heading menu, gets visible `#####` text with no heading
  styling. Minor but a clear toolbar/renderer mismatch.
- **Confidence:** High.
- **Fix:** Widen `headingRegex` to `#{1,6}` and give levels 5–6 a font (even if both map to a small
  bold style), or remove H5/H6 from the toolbar menu. Pick one so toolbar and styler agree.

### [P2] Numbered-list continuation does not renumber; siblings/outdent diverge from CommonMark
- **Where:** `ListContinuation.swift:97` (`numbered(n)` → `n + 1`), and there is no renumber pass
  after Backspace/outdent/delete.
- **What:** Return after `3. foo` correctly yields `4. `. But deleting a middle item, outdenting, or
  inserting leaves the visible numbers stale (e.g. `1. / 2. / 4.`), and `detect` reads whatever digit
  is literally typed. There's no logic to renumber a list run. (This may be intentional — many editors
  leave raw numbers alone — but it's worth flagging as a behaviour gap.)
- **Impact:** Numbered lists can show non-sequential numbers after edits. Cosmetic in Live mode
  (numbers are shown verbatim), and arguably "source-faithful," but surprising to users used to
  auto-renumbering.
- **Confidence:** High (that no renumber exists); intent unclear.
- **Fix:** If auto-renumber is desired, add a renumber pass over the contiguous numbered run on
  Return/Backspace/outdent. Otherwise document it as intentional.

### [P3] `toggleLinePrefix` strips leading indent when toggling a list type
- **Where:** `ToolbarAction.swift:248-266` (`detectLinePrefixLength` returns `marker.contentStart`,
  which includes indent; comment at `:259-263` acknowledges "strip the WHOLE prefix including indent").
- **What:** Toggling bullet/number/task/quote via the toolbar removes the line's leading indentation
  as a side effect (the strip range starts at `lineStart`, not `lineStart + indent`).
- **Impact:** A nested item flattened to the left margin when the user only meant to change its marker
  type. Minor, but unexpected.
- **Confidence:** High (explicitly coded that way).
- **Fix:** Start the strip at `lineStart + (indent UTF-16 length)` and re-prepend the same indent in
  `newPrefix`, so marker-type toggles preserve nesting.

### [P3] `move(modifiers:)` ignores modifiers; shift/cmd/opt Up-Down don't extend selection
- **Where:** `CursorSnapping.swift:18-32` (`modifiers` is `_ = modifiers`, then ignored),
  `EditorCoordinator.markdownTextView(_:didRequestVerticalMove:)` `:311` always passes `[]`,
  and `MarkdownInternalTextView.keyCommands` `:48-49` registers plain Up/Down only.
- **What:** Hardware Shift+Up/Down (extend selection) and Option/Cmd+Up/Down are not handled by the
  arrow override; only bare Up/Down are intercepted. Since the bare-arrow key commands are registered
  but modified-arrow ones are not, modified arrows fall back to UIKit — which can't see through the
  zero-width marker glyphs and may land/extend into a phantom marker zone.
- **Impact:** On an external keyboard (iPad / Simulator), Shift+Up to select a line of a list may put
  the selection anchor in the marker zone, giving slightly-off selections. Soft-keyboard users
  unaffected.
- **Confidence:** Med (depends on UIKit's default vertical extension over zero-width glyphs).
- **Fix:** Register Shift/Cmd/Opt + Up/Down key commands too and route them through
  `CursorSnapping.move` with the real `MoveModifiers`, or explicitly document modified vertical moves
  as out of scope.

### [P3] Bare `- [ ]` with no trailing space is treated as content-bearing by Smart Return
- **Where:** `ListContinuation.swift:128-131` — for a task, if there's no char at `i+5`,
  `contentStart = i + 5` (the `]`); `detect` comment says bare `- [ ]` + Return should exit.
- **What:** For exactly `- [ ]` (no trailing space, caret at end = index 5 within content),
  `contentStart` is 5 and `afterMarker` = "" so the empty-marker exit path *does* fire — good. But the
  marker-zone redirect in `EditorCoordinator.shouldChangeTextIn` (`:92-112`) uses the same
  `contentStart`; typing into a bare `- [ ]` (no trailing space) redirects the insert to index 5,
  landing the char immediately after `]` with no separating space, producing `- [ ]x` which then no
  longer parses as a task line (the styler/`taskRegex` require a space after `]`). 
- **Impact:** Niche: only when a task marker exists without its trailing space. The line silently
  stops being a task. Low frequency because the auto-continuation always emits the trailing space.
- **Confidence:** Med.
- **Fix:** When redirecting an insert into a bare task marker, insert a separating space (or normalise
  `- [ ]` to `- [ ] ` first) so the line stays a valid task.

## Strengths
- **Styling never mutates characters.** `MarkdownStyler` is a true `NSTextStorage` whose `backing`
  string is exactly what the binding round-trips; all "hiding" is `.null` glyph properties +
  zero-width fonts + a `shouldGenerateGlyphs` substitution delegate (`MarkdownLayoutDelegate`). The
  on-disk markdown can't be corrupted by display logic. This is the right architecture and it's done
  correctly.
- **The TextKit `headIndent == firstLineHeadIndent` drift is fixed everywhere it should be**
  (`applyListIndent:678-684`, `applyQuotedListIndent:733-739`, `styleAsCode:1039-1043`, fence
  opener/closer `:266-270`) with accurate explanatory comments. The known drift class is genuinely
  closed for marker rows.
- **Clean separation: pure transforms vs UIKit glue.** Return/Backspace/Indent/Paste/Toolbar/Checkbox
  are all pure `(String, NSRange) -> (String, NSRange)` functions (`EditorIntent` dispatch), testable
  without a text view. The coordinator owns no business logic.
- **Consistent NSString/UTF-16 discipline at the call sites.** Apart from the `ListMarker` grapheme
  caveat (P1 above), range math uses `NSString.length`, `(text as NSString).length`, and
  `paragraphRange`/`lineRange` consistently — emoji/CJK *content* (as opposed to markers) is handled
  correctly because content offsets come from NSString, not `String.Index`.
- **Checkbox hit-testing is geometry-based, not glyph-based** (`taskLineRange:207-244`), correctly
  side-stepping the fact that the `[ ]` chars are zero-width-fonted; the rationale is well documented.
- **Coordinator retain-cycle posture is sound.** `cursorIndicator`, `textViewRef`, the three custom
  delegates, and the toolbar's `coordinator` are all `weak`; toolbar `UIAction` closures use
  `[weak self]`. UITextView retains its coordinator-as-delegate weakly per UIKit convention, so no
  obvious cycle. (UITextView↔coordinator ownership ultimately flows through the SwiftUI
  `makeCoordinator` lifetime, which is fine.)
- **Paste normalisation is correct and verbatim-safe** (`PasteHandler.normalize`): BOM strip, CRLF→LF,
  bare CR→LF, tab→4 spaces, no smart-typography mutation — matching the text view's disabled
  smart-quotes/dashes settings (`MarkdownTextView.swift:47-51`).
- **Fence pairing handles unclosed fences and doesn't terminate on blank lines** (`fenceRanges`),
  and the code-panel background correctly trims the trailing newline so the panel doesn't bleed a line
  below the closer (`MarkdownLayoutManager.swift:100-105`).

## Coverage
Read in full: `MarkdownStyler.swift`, `EditorCoordinator.swift`, `ToolbarAction.swift`,
`CursorSnapping.swift`, `ListContinuation.swift` (incl. `ListMarker`), `IndentHandler.swift`,
`BackspaceHandler.swift`, `CheckboxToggler.swift`, `PasteHandler.swift`, `EditorIntent.swift`,
`ExtensionParsers.swift`, `MarkdownTextView.swift`, `MarkdownInternalTextView.swift`,
`MarkdownLayoutManager.swift`, `MarkdownLayoutDelegate.swift`, `MarkdownReminderToolbar.swift`,
`MarkdownEditorView.swift`, `MarkdownBodyView.swift`. Checked the four host call sites
(ItemDetail/QuickCapture/Habit/Thread) for lifecycle/retain context and reviewed git history for
prior bug-fix intent.
**Not done (read-only constraint):** I did not build or run the simulator, so the two
"Med-on-symptom" items (P1 undo runtime behaviour, P1 per-keystroke perf threshold) are reasoned from
the code, not measured. The `Design/Components/...` folder is not referenced by the editor (it uses
raw UIKit + `ListsTokens`), so there was nothing editor-specific to read there.
