# Crash Risk & Stability Audit

## Verdict
**Solid.** This is the most defensively-written area I reviewed. Every force-unwrap in
the app (19 of them) is a hard-coded UUID string literal in test sample data — none touch
user input or disk. All 27 `try!` calls compile fixed regular-expression patterns that
cannot fail. There are no `as!` casts, and the single `fatalError` is unreachable UIKit
boilerplate. The editor and tag code — the classic place iOS apps crash on emoji or odd
text — handle text positions with consistent, correct discipline and clamp every index.
The few real concerns are about **resilience**, not crashes: if one file on disk is
corrupt, the whole library silently fails to load with no message to the user.

## Findings

### [P1] One bad file on disk makes the entire library vanish, silently
- **Where:** `Core/Storage/FileStore.swift:176` (`try itemFiles.map { try readItem(at: $0) }`) and `:146`; surfaced at `App/ListsApp.swift:14-20`.
- **What:** `loadAll()` reads every list and item in one pass. If a single `.md` item file
  or `.list.yml` is malformed (bad date string, missing required key, truncated YAML), the
  `try` throws and aborts the **entire** load — every list and item, not just the bad one.
  The thrown error bubbles to `ListsApp`, which only does `print("Lists.bootstrap failed…")`.
  The app then shows an empty state (`isLoaded` stays false) with no indication that the
  user's data exists on disk but failed to load.
- **Impact:** A user whose files got nudged (a sync hiccup, a half-finished external edit, a
  power-loss mid-write, the documented `keyNotFound: created_at` case in your own notes) opens
  the app to find **everything apparently gone**. Because files are the source of truth and
  there's no error UI, a non-technical user can't tell "all my data is fine, one file is
  broken" from "I lost everything," and may panic or re-seed over good data.
- **Confidence:** High (the all-or-nothing throw and the print-only handler are both plain in
  the code; the only thing I can't see is whether a future error UI is planned — your notes
  say "lands when settings + maintenance ships," so this is known but not yet built).
- **Fix:** Make item loading per-file resilient: in `walk`, map items with `compactMap` and
  `try?` (or a do/catch that logs the offending path and continues) so one corrupt file is
  skipped, not fatal. Separately, when `bootstrap()` throws, show the user a non-destructive
  banner ("Some lists couldn't be opened") rather than a blank screen — and crucially, do NOT
  let the empty state lead to re-seeding sample data over a library that's actually present
  on disk.

### [P3] Numbered-list auto-continue can overflow on an absurd line number
- **Where:** `Features/MarkdownEditor/ListContinuation.swift:97` (`return "\(pad)\(n + 1). "`); reachable via `ListMarker.detect` at `:147-156` and `prefix(indentedBy:)`.
- **What:** A numbered-list line is parsed into `Int` then continued with `n + 1`. If a user
  types or pastes a line starting with the literal maximum 64-bit integer
  (`9223372036854775807. `) and presses Return, `n + 1` overflows and Swift traps (crash).
- **Impact:** Editor crashes — but only for a deliberately pathological 19-digit list number.
  Effectively no one hits this by accident.
- **Confidence:** High that the overflow exists; Low that any real user triggers it.
- **Fix:** Use `n.addingReportingOverflow(1)` and fall back to `n` (or cap at a sane max) on
  overflow. One line.

### [P3] `ListMarker.detect` mixes grapheme indices with UTF-16 offsets (latent, not currently triggerable)
- **Where:** `Features/MarkdownEditor/ListContinuation.swift:112-167` (`detect` builds `Array(line)` of `Character`s and returns `contentStart` as a Character index), consumed as a UTF-16 offset throughout `EditorCoordinator`/`CheckboxToggler`/`MarkdownStyler` (e.g. `EditorCoordinator.swift:98`, `CheckboxToggler.swift:34`).
- **What:** Marker detection counts in grapheme clusters (`Character`), but the rest of the
  editor pipeline works in NSString/UTF-16 units and adds `marker.contentStart` to UTF-16
  line locations. These two coordinate systems only coincide because every character a marker
  can match before `contentStart` (spaces, `-`, `*`, `+`, `>`, digits, `[`, `]`, `x`) is
  ASCII (one UTF-16 unit each). The day a marker grammar grows to accept any non-ASCII
  character before the content start, the offsets would silently diverge and could produce an
  out-of-range NSRange (crash) or mis-placed edit.
- **Impact:** None today — purely a latent trap for a future change. Worth a comment so it
  isn't discovered the hard way.
- **Confidence:** High that the assumption exists; today it holds, so no live bug.
- **Fix:** Add a comment at `ListMarker.detect` stating the ASCII-only invariant, or compute
  `contentStart` as a UTF-16 offset (`(String(chars[0..<contentStart]) as NSString).length`)
  to make it robust by construction.

## Reviewed and confirmed safe (not ignored)

- **All 27 `try! NSRegularExpression(pattern:)`** — `MarkdownStyler.swift:1192-1216` (21) and
  `ExtensionParsers.swift:30-83` (6). Every pattern is a compile-time string literal; a fixed
  valid pattern cannot throw at runtime. This is the canonical legitimate use of `try!`.
- **All 19 force-unwraps** — `Core/Bootstrap/SampleData.swift:11-35`, every one
  `UUID(uuidString: "…literal…")!` with a valid hard-coded UUID. Compile-time constants;
  cannot be nil.
- **The 1 `fatalError`** — `MarkdownReminderToolbar.swift:32`, inside
  `required init?(coder:)` marked `@available(*, unavailable)`. The toolbar is only ever
  built programmatically (`MarkdownTextView.swift:54`), never from a nib/storyboard. Standard
  unreachable UIKit boilerplate.
- **0 `as!` casts** in the app.
- **Division operators** (`ItemRow.swift:371`, `HabitDetailView.swift:487`,
  `HabitHeatmap.swift:89`, `ListDetailCollectionView.swift:1044/1074`) — none can crash:
  the habit-progress ones are `Double / Double` (a zero divisor yields `inf`, not a trap, and
  is then clamped by `min(1.0, …)`), `goalPerCycle` is pinned to `1...99` by every Stepper and
  defaults to 1 on decode anyway, and the touch-geometry ones use `max(height, 1)`.
- **Decoding** — `Item.init(from:)` (`Item.swift:171-200`) and `ItemList`'s decoder use
  `try`/`decodeIfPresent` with `??` defaults throughout; bad dates throw
  `DecodingError.dataCorruptedError` (`Item.swift:250-255`), never force-unwrap.
- **URL/Data** — `StorageRoot.swift:9` uses `.first ?? URL(fileURLWithPath:…)`; no
  force-unwrapped `URL(string:)`/`Data(contentsOf:)` anywhere.
- **Array indexing with computed indices** — every site I traced is guarded:
  `ListDetailCollectionView.swift:669` (`if sectionIndex == 0 { return }` before `-1`),
  `:1076` (`idx > 0`), `:1104/1106` (`if section.rows.isEmpty { return }` before `rows[0]`),
  `:1456` (`while !queue.isEmpty` + a `visited` set against cycles), `HabitHeatmap.swift:51`
  (`ForEach(0..<scale.count)`). `[idx]` writes in `ItemStore` all use a `firstIndex(where:)`
  result against the same array.
- **String `removeFirst()`/`dropFirst(n)`/`prefix(n)`** — `FrontmatterCodec.swift:42`
  (`dropFirst(4)` gated by `hasPrefix("---\n")`), `Tag.swift:53` & `PasteHandler.swift:41`
  (gated by `hasPrefix`), `FileStore.swift:266-272` (gated by `hasPrefix`/`last`), all safe.

## Strengths
- **Text/NSRange handling is genuinely careful.** The whole editor — `MarkdownStyler`,
  `EditorCoordinator`, `CursorSnapping`, `BackspaceHandler`, `ListContinuation`,
  `IndentHandler`, `ToolbarAction`, `CheckboxToggler` — works consistently in NSString/UTF-16
  space, derives every attribute/edit range from regex matches against the same string, and
  clamps positions with `min`/`max`/`guard … <= ns.length` before use. This is exactly the
  discipline that prevents the emoji/grapheme NSRange crashes that plague hand-rolled iOS text
  editors. `CursorSnapping.lineRange(containingCaret:)` and `isTrailingEmptyLineStart` in
  particular handle the trailing-newline edge correctly.
- **Editor logic is pure and bounds-validated at the boundary.** Each behaviour is a
  `(source, selection) -> (source, selection)` transform; `CheckboxToggler.toggle` re-validates
  `characterIndex >= 0 && < ns.length` even though the caller already computed a plausible
  index — defense in depth.
- **Decoders are forgiving and forward-compatible.** `decodeIfPresent … ?? default` on nearly
  every field means a `.md` with missing optional keys still loads, and unknown future keys are
  ignored — good for a file-is-truth model.
- **Disk mutations are throwing, not crashing**, all the way up to a single caught site in
  `ListsApp`. No `try!` on any file read/write/decode.
- **Defensive touches against corruption** show intent: the BFS in `ListDetailCollectionView`
  guards cycles with a `visited` set and an explicit comment ("avoid blowing the stack if the
  tree got corrupted").

## Coverage
Read in full: every editor file under `Features/MarkdownEditor/` (`MarkdownStyler`,
`EditorCoordinator`, `CursorSnapping`, `BackspaceHandler`, `ListContinuation`/`ListMarker`,
`IndentHandler`, `CheckboxToggler`, `EditorIntent`, `PasteHandler`, `ToolbarAction`,
`MarkdownTextView`, `MarkdownLayoutManager`, `ExtensionParsers`, `MarkdownReminderToolbar`);
`Core/Storage/{FileStore,FrontmatterCodec,StorageRoot}`; `Core/Stores/ItemStore`;
`Core/Tags/Tag`; `Core/Models/{Item decoder,HabitCycle}`; `Core/Bootstrap/SampleData`;
`Features/Habits/HabitHeatmap`; relevant spans of `ListDetailCollectionView`; `App/ListsApp`.
Ran repo-wide scans for `try!`/`fatalError`/`as!`, a string-and-comment-stripped force-unwrap
scan (Python), IUO declarations, division operators, computed-index subscripts, and
`removeFirst`/`dropFirst`/`prefix`/`[0]` collection ops.

Not exhaustively read (lower crash-density UI, sampled via grep only): the full bodies of
`QuickCaptureSheet` (1320 LOC), `ItemDetailSheet` (1162), `SidebarView`, `SmartListCollectionView`,
and the non-grepped regions of `ListDetailCollectionView` (1880). My index/range/force-unwrap
greps covered these files and surfaced nothing dangerous, but I did not read every line. The
two IUO data-source declarations (`SmartListCollectionView.swift:86`,
`ListDetailCollectionView.swift:117`) are the standard "assigned in `configureDataSource`
before first use" UIKit pattern and would only crash if accessed before setup — I did not
trace every access path, but the diffable-data-source lifecycle makes that the expected idiom.
