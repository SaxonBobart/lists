# iOS Editor Engineering: High-Performance Native Markdown Editor — Research

## Bottom line (for a non-technical product owner)

Lists' custom editor is architecturally sound and on the right path — a native
`UITextView` + `NSTextStorage` subclass is exactly how Bear, iA Writer, and the rest of
the serious "live markdown" apps are built. But it has two real, fixable engineering
faults that match what the audit found:

1. **It restyles the entire note on every keystroke.** On a long note this gets slow
   (the work grows with the square of the note's length). The fix is well-understood and
   used by every shipping editor: only re-style the paragraph(s) you actually edited.
2. **Undo is broken** because every "smart" edit (Return, Backspace, indent, paste,
   checkbox tap) silently rewrites the *whole document* behind the text view's back, which
   destroys the system's undo history. Apple's own framework engineer says directly: don't
   poke `textStorage` directly for user edits — go through the text view's input methods so
   undo stays consistent.

Neither requires a rewrite. **I recommend fixing both within the current TextKit 1
design and explicitly NOT migrating to TextKit 2 right now** — TextKit 2 is still buggy
for editing UIs in 2025–26 (even Apple's own TextEdit shows the glitches), and Lists
already depends on TextKit 1 glyph-level tricks that TextKit 2 doesn't cleanly support.
One latent correctness assumption (grapheme vs. UTF-16 character counting) is currently
harmless but should be documented before it bites.

---

## What the landscape / best practice looks like (May 2026)

### The two text engines, and which one to use

Since iOS 16 / macOS Ventura, every `UITextView`/`NSTextView` uses **TextKit 2 by
default**, and Apple's guidance is "transition to TextKit 2 as soon as possible"
([WWDC22 — What's new in TextKit and text views](https://developer.apple.com/videos/play/wwdc2022/10090/)).
TextKit 2 promises viewport-based layout (only lay out what's on screen) and removes the
error-prone "glyph" layer that TextKit 1 exposes.

**But the practitioner reality in 2025–26 is more cautious.** Marcin Krzyżanowski — who
*built* a TextKit 2 editor (STTextView) — published a blunt assessment in Aug 2025:
"TextKit 2 API and its implementation are lacking and unexpectedly difficult to use
correctly," with unstable height estimation, "juddery" scroller behaviour, and viewport
glitches *that even Apple's TextEdit exhibits*. His conclusion: "TextKit 2 might not be
the best tool for text layout, especially when it comes to text editing UI."
([TextKit 2 — the promised land](https://blog.krzyzanowskim.com/2025/08/14/textkit-2-the-promised-land/)).

Critically for Lists: **the moment you touch `UITextView.layoutManager`, the text view
silently falls back to TextKit 1 — permanently and irreversibly** ("Once a text view
switches to TextKit 1, there's no automatic way of going back… it's a one-way operation",
WWDC22). Lists subclasses `NSLayoutManager` (`MarkdownLayoutManager`) and reads
`textView.layoutManager` throughout, so **Lists is already a TextKit 1 editor** and would
get no TextKit 2 benefit without ripping out its glyph-hiding and custom-drawing code.

The styling models differ fundamentally:
- **TextKit 1**: style by mutating attributes inside the `NSTextStorage` subclass during
  `processEditing()` — exactly what Lists does.
- **TextKit 2**: style *display-only* via `NSTextContentStorageDelegate.textParagraphWith`,
  returning a restyled `NSTextParagraph` per paragraph *without* mutating the backing
  store — a genuinely nicer model for "source stays plain, display gets decorated," but
  one that doesn't support TextKit 1-style glyph hiding/substitution (how Lists collapses
  `- [ ]` markers to zero width and overlays SF Symbols).

### How shipping editors get performance: incremental, edited-range styling

The universal pattern — restyle only what changed:

- **Restyle the edited paragraph, not the document.** During `processEditing()`, the
  storage exposes `editedRange` (the chars UIKit knows changed). Expand that to the
  enclosing paragraph(s) and re-tokenize only those.
  [`NSTextStorage.processEditing()` docs](https://developer.apple.com/documentation/uikit/nstextstorage/1525980-processediting)
  and [Christian Tietze — attribute fixing](https://christiantietze.de/posts/2022/09/overview-of-attribute-fixing-in-nstextstorage/)
  note that attribute fixing already works on full-paragraph ranges, so paragraph-granular
  restyle is the natural unit.
- **Marklight** (open-source `NSTextStorage` markdown highlighter) does exactly this: its
  `processEditing()` passes `self.editedRange` to a processor that expands around the
  edited range to the surrounding paragraphs (explicitly to keep multi-line constructs
  like Setext headings correct) rather than re-scanning the whole string
  ([MarklightTextStorage.swift](https://github.com/macteo/Marklight/blob/develop/Marklight/MarklightTextStorage.swift)).
- **Runestone** (Simon Støvring's open-source iOS code editor, the most-cited "fast iOS
  text editor") gets its speed from two things: **Tree-sitter incremental parsing** (re-parse
  only the changed subtree, never the whole file) and an **AvalonEdit-derived red-black-tree
  line manager** for O(log n) line lookups. The result: "no detectable difference … opening
  complex 10,000+ line files versus simple ten-line files"
  ([Runestone README](https://github.com/simonbs/Runestone/blob/main/README.md),
  [MacStories review](https://www.macstories.net/reviews/runestone-a-streamlined-text-and-code-editor-for-iphone-and-ipad/)).
  Note: Runestone is a *third-party library Lists has ruled out*, and it doesn't use plain
  `UITextView` — it's a fully custom text view. The transferable lesson is **incremental
  parse + smart line indexing**, not the implementation.
- **Bear / iA Writer** don't publish internals, but both are native `NSTextStorage`-based
  live-markdown editors (no web view) and remain smooth on very long notes — consistent
  with edited-range styling rather than full-document restyle.

### Integrating custom edits with the native UndoManager

This is the cleanest part of the research because Apple answered it directly. From the
[Apple Developer Forums thread (Frameworks engineer reply)](https://developer.apple.com/forums/thread/730221):

> "By modifying a `UITextView`'s `textStorage` directly, you're circumventing the middle
> layer that tracks updates and deletions to the text view. Instead, call the various
> methods on `UITextInput` to update the underlying text storage in order to keep the undo
> manager in a consistent state."

Concretely, for user-initiated edits route through the text view, **not** the storage:
- `textView.insertText(_:)`, `textView.replace(_:withText:)`, `deleteBackward()` — these
  give automatic, correctly-coalesced undo.
- For attributed/multi-step edits where the input methods aren't enough, wrap the change in
  `undoManager?.beginUndoGrouping()` / `endUndoGrouping()` and register the inverse with
  `undoManager.registerUndo(withTarget:handler:)`
  ([Christian Tietze — undoable text changes](https://christiantietze.de/posts/2022/09/undoable-text-changes/)).
  The `UndoManager` coalesces all registrations within one run-loop pass into a single undo
  step automatically (so per-keystroke registrations don't produce per-keystroke undos as
  long as you stay synchronous on the main thread).
- Caveat from the same sources: direct storage edits don't restore *selection* on undo;
  you must capture and restore `selectedRange` yourself if you go that route.

A *separate* well-known pitfall, relevant to Lists' invalidation hack: applying attribute
changes with `.editedCharacters` (vs `.editedAttributes`) during `processEditing` makes the
layout manager run selection-fixup over the *whole* edited range and **moves the caret**.
The recommended separation is to apply styling on `textViewDidChange`/`NSText.didChange`,
distinct from the character edit
([Christian Tietze — why selection changes during highlighting](https://christiantietze.de/posts/2017/11/syntax-highlight-nstextstorage-insertion-point-change/)).

### The NSRange / UTF-16 vs grapheme pitfall

`NSString.length`, `NSRange`, and `NSAttributedString` are all **UTF-16-based**. Swift's
`String.count` counts **grapheme clusters**. They diverge for emoji and combining
sequences — a family emoji is 1 grapheme but 11 UTF-16 units; an offset computed in one
space and applied in the other corrupts ranges and "can cause text distortion and abnormal
behavior" in attributed text
([String.count vs NSString.length](https://www.logcg.com/en/archives/3253.html),
[objc.io — decomposing emoji](https://www.objc.io/blog/2017/12/19/decomposing-emoji/)).
Rule of thumb for any TextKit editor: **do all index math in UTF-16/NSRange terms** (use
`NSString` APIs end-to-end), and never mix in a `String.index`/`Array(string)` offset as if
it were an NSRange location.

---

## Implications for Lists ← the most important section

I read the actual editor (`platforms/ios/Lists/Features/MarkdownEditor/`). The audit's two
findings are confirmed in code, and there's a third (latent) one. Here's what to do, in
priority order.

### Priority 1 — Stop restyling the whole document on every keystroke (issue *a*)

**Where it is:** `MarkdownStyler.processEditing()` clears all token caches and runs
`applyBaseAttributes(in: full)` + `applyLiveStyling(in: full)` over
`NSRange(0, backing.length)` on *every* edit, where `applyLiveStyling` does
`enumerateSubstrings(in: full, .byLines)` — a full-document line scan per keystroke. It then
**force-expands** invalidation to the whole doc via
`edited([.editedAttributes, .editedCharacters], range: full)`, and on top of that
`EditorCoordinator.textViewDidChange` calls `invalidateGlyphs`/`invalidateLayout` over the
full range *again*. That's effectively three full-document passes per character — the O(n²)
the audit flagged.

**Fix (incremental, edited-range styling):**
1. In `processEditing()`, read `self.editedRange` and expand it to the **enclosing
   paragraph range(s)** (`(string as NSString).paragraphRange(for: editedRange)`), then run
   `applyBaseAttributes` + `applyLiveStyling` over *that* range only. This is the
   Marklight pattern and is the single biggest win.
2. Keep a small "dirty set" for genuinely cross-paragraph constructs (fenced code blocks,
   Setext headings, anything whose styling depends on lines other than the edited one).
   Lists already tracks `fenceMarkerLineRanges` — extend that idea so only those extra
   ranges, not the whole doc, get pulled into the restyle.
3. Scope the glyph/layout invalidation to the restyled range too, and **delete the
   redundant full-document `invalidateGlyphs`/`invalidateLayout` in
   `textViewDidChange`** once styling is range-scoped.

**Important nuance for Lists specifically:** the current full-document hack exists for a
real reason documented in the code — sibling list rows kept *stale zero-width-marker
glyphs* and drifted right (this ties to the known *iOS 26 TextKit headIndent drift* memory).
So the incremental version must still invalidate **every paragraph whose marker glyph
width could have changed**, not literally just the typed line. In practice: edited
paragraph + any adjacent list rows in the same list block. This is a narrowing from
"whole document" to "this list block," which is bounded and fast, while preserving the
fix for the drift bug. Validate on the simulator with a long note that the drift does not
return.

### Priority 2 — Make smart edits undoable (issue *b*)

**Where it is:** `EditorCoordinator.applyResult(...)` does
`storage.replaceCharacters(in: NSRange(0, storage.length), with: result.source)` for
*every* smart edit — Return, Backspace, hardware Tab, marker-zone redirect, paste, and
checkbox toggle all funnel through it. `MarkdownTextView.updateUIView` does the same
full-document `replaceCharacters`. None of this touches `undoManager`. Per Apple's forum
guidance above, this circumvents the tracking layer and corrupts the undo stack — typing
done before a smart edit can no longer be undone.

**Fix:**
1. **Route edits through the text view's input layer** instead of full-document
   `replaceCharacters`. Most of Lists' smart edits are intercepted in
   `shouldChangeTextIn` and already compute a precise replacement — change the *application*
   to a targeted `textView.replace(range, withText:)` / `insertText` / `deleteBackward()`
   on the **minimal changed range**, returning `false` from the delegate only when you've
   applied a non-default edit. This both fixes undo *and* makes Priority 1 easier (a small
   `editedRange` instead of a whole-document replace).
2. Where a single input-method call can't express the edit (e.g. inserting an
   attributed/multi-line list continuation), wrap it in
   `undoManager.beginUndoGrouping()/endUndoGrouping()` and `registerUndo` the inverse
   (capture and restore `selectedRange` too — direct storage edits don't restore selection).
3. **Compute minimal diffs, not full rewrites.** The pure
   `apply(to:selection:) -> (String, NSRange)` transforms are nicely testable, but the
   coordinator should diff old vs new to find the smallest changed NSRange and apply *that*,
   rather than replacing length-`n` with length-`n`. (A common-prefix/suffix diff is enough.)
4. Verify on-device that the system **Undo gesture (3-finger swipe / shake)** and `⌘Z`
   correctly step back through a mix of typed characters and smart edits.

### Priority 3 — Do NOT migrate to TextKit 2 (yet)

Recommendation: **stay on TextKit 1.** Reasons specific to Lists:
- Lists is *already* TextKit 1 (subclassed `NSLayoutManager`, direct `layoutManager`
  access) — there is no half-measure; TextKit 2 is all-or-nothing and one-way (WWDC22).
- Lists' core visual tricks — collapsing markers to zero-width glyphs
  (`glyphProperty = .null`), glyph substitution, SF-Symbol checkbox overlays in
  `drawGlyphs`, HR/code-panel drawing in `drawBackground` — are **TextKit 1 glyph-level
  APIs with no clean TextKit 2 equivalent**. TextKit 2's paragraph-restyle model
  (`NSTextParagraph`) is display-only and doesn't expose glyph hiding the same way.
- TextKit 2 still has shipping-quality problems for editing UIs in 2025–26
  (Krzyżanowski, above). Adopting it now trades two *bounded, well-understood* bugs for a
  class of *unbounded* layout/scroll bugs.
- The performance win Lists needs (Priority 1) comes from **edited-range styling**, which
  works perfectly in TextKit 1. TextKit 2's viewport layout mainly helps documents far
  larger than a typical note.

Revisit only if (a) Lists needs genuinely huge documents, or (b) a future iOS makes
TextKit 2 mandatory or fixes the editing-UI issues. Until then, the glyph-hiding design is
a reason to *stay*, not a debt.

### Priority 4 — Document the grapheme/UTF-16 assumption before it bites

`ListMarker.detect` builds `indent` and `contentStart` from `Array(line)` — **grapheme/
`Character` indices** — and the coordinator adds them straight onto **NSString offsets**
(`lineRange.location + marker.contentStart`, and the checkbox state-char index
`lineRange.location + marker.indent + 3`) to form `NSRange`s. This is **currently safe
only because every marker prefix is pure ASCII** (`-`, `*`, `+`, `[`, `]`, spaces, digits,
`>`), where 1 grapheme == 1 UTF-16 unit. It is a latent landmine: the instant any offset
is computed by walking *into content* (which can contain emoji/combining marks) and used
as an NSRange location, ranges will corrupt. Recommendations:
- Add a comment at `ListMarker.detect` stating the invariant: *offsets are valid as NSRange
  locations only because the marker prefix is ASCII; do not extend this to content.*
- Prefer doing marker detection over `NSString` (UTF-16) directly, or convert via
  `String.Index`↔UTF-16 deliberately, so the assumption isn't implicit.
- This pairs with the Priority-2 "minimal diff" work, which should also be done in UTF-16
  space.

### What Lists already gets right (keep)

- Native `UITextView`/`NSTextStorage`, no web view, no third-party editor — matches Bear /
  iA Writer and the founder's constraint.
- Plain-text source as the single truth, styling as pure display — the correct mental model
  (and the same one TextKit 2 would formalize).
- Pure, testable `apply(to:selection:)` edit transforms — excellent for correctness; only
  the *application* mechanism needs to change.
- All-`NSString`/`NSRange` math in the layout-facing code — the right call for TextKit.

---

## Open questions / things to validate

- **Does edited-range styling reintroduce the iOS 26 marker-drift / headIndent bug?** The
  full-document invalidation was added specifically to fix sibling-row glyph staleness.
  Validate on-simulator with a long multi-level list that narrowing the restyle to the
  edited list block keeps markers aligned.
- **Measure before/after.** Capture keystroke latency on a long note (e.g. 1k+ lines) in a
  *release* build (Runestone's README stresses release-config matters) to confirm the O(n²)
  symptom and the fix. Debug builds exaggerate the cost.
- **Undo coalescing granularity.** Confirm typing produces sensible undo *chunks* (word/run,
  not per-character) once routed through input methods, and that smart edits are their own
  undo steps — match what users expect from Notes/Bear.
- **Paste of large/structured content** through the input layer: does
  `markdownTextViewDidRequestPaste` still need a full replace, or can it target the
  selection range? Validate undo of a paste.
- **TextKit 2 reassessment trigger:** worth a fresh look only if Apple resolves the
  editing-UI instability or makes TK2 mandatory; not on the current roadmap.

---

## Sources

- [WWDC22 — What's new in TextKit and text views](https://developer.apple.com/videos/play/wwdc2022/10090/) (TextKit 1↔2 selection, one-way fallback on `layoutManager` access, "transition ASAP")
- [WWDC21 — Meet TextKit 2](https://developer.apple.com/videos/play/wwdc2021/10061/) (viewport layout, removal of glyph layer)
- [Marcin Krzyżanowski — TextKit 2: the promised land (Aug 2025)](https://blog.krzyzanowskim.com/2025/08/14/textkit-2-the-promised-land/) (real-world TK2 instability for editing UIs)
- [Apple Developer Forums — integrating custom changes into UITextView's UndoManager](https://developer.apple.com/forums/thread/730221) (Apple engineer: use `UITextInput` methods, don't poke `textStorage`)
- [Christian Tietze — Making NSTextStorage changes undoable](https://christiantietze.de/posts/2022/09/undoable-text-changes/) (`registerUndo`, run-loop coalescing, selection caveat)
- [Christian Tietze — Why the selection changes during syntax highlighting](https://christiantietze.de/posts/2017/11/syntax-highlight-nstextstorage-insertion-point-change/) (`.editedCharacters` vs `.editedAttributes` and caret movement)
- [Christian Tietze — Overview of attribute fixing in NSTextStorage](https://christiantietze.de/posts/2022/09/overview-of-attribute-fixing-in-nstextstorage/) (paragraph-granular fixing)
- [Apple — NSTextStorage.processEditing()](https://developer.apple.com/documentation/uikit/nstextstorage/1525980-processediting)
- [Marklight — MarklightTextStorage.swift](https://github.com/macteo/Marklight/blob/develop/Marklight/MarklightTextStorage.swift) (incremental edited-range markdown styling)
- [Runestone — README](https://github.com/simonbs/Runestone/blob/main/README.md) and [MacStories review](https://www.macstories.net/reviews/runestone-a-streamlined-text-and-code-editor-for-iphone-and-ipad/) (tree-sitter incremental parsing + AvalonEdit line manager)
- [STTextView (TextKit 2)](https://github.com/krzyzanowskim/STTextView) (reference TK2 editor by the critique's author)
- [String.count vs NSString.length](https://www.logcg.com/en/archives/3253.html) and [objc.io — Decomposing Emoji](https://www.objc.io/blog/2017/12/19/decomposing-emoji/) (UTF-16 vs grapheme pitfall)
