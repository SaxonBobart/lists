# Fix Plan — UI / Editor / Privacy / A11y

Ready-to-implement spec for the six UI-side findings from `01-technical-health.md`,
verified against the live code in `audit/findings/verification-ui.md` and the editor
prior-art in `audit/research/ios-editor-engineering.md`. Each item gives the exact
**Where** (`file:line` + current shape), the **Change** (before→after Swift sketch),
the **Test**, and the **Regression risk**.

All paths are under `platforms/ios/Lists/` unless noted. All line numbers are from the
state of the repo when this plan was written — re-confirm with a fresh read before
editing, since earlier fixes in the order shift lines.

**Implementation order:** SEC-1 → BUILD-1 → ED-1 → ED-2/PERF-1 → UI-1 → A11Y-1.
SEC-1 is a one-liner privacy fix and goes first. BUILD-1 must land second because
**the `ListsTests` target does not compile today** (a single stale call), so no other
fix here can be regression-tested until it does.

---

## SEC-1 — Pin a local-only image provider on the read-only note renderer (DO FIRST)

**Where.** `Features/MarkdownEditor/MarkdownBodyView.swift:14-18`. The entire body is:

```swift
var body: some View {
    Markdown(source)
        .markdownTheme(.gitHub)
        .fixedSize(horizontal: false, vertical: true)
}
```

No image provider is set, so MarkdownUI falls back to its `DefaultImageProvider`
(→ `NetworkImage` → `URLSession.data(from:)`). A note body containing
`![](https://tracker.example/x.png)` fetches that URL — leaking IP/timing — the moment
the note is rendered (`ThreadView` is the call site). Confirmed CONFIRMED in
`verification-ui.md:48-55`; repo-wide there is no provider override anywhere.

**Change.** Pin both the block and inline image providers to the offline `.asset`
provider (which resolves bundle assets only and never touches the network). `.asset`
ships with MarkdownUI.

```swift
import MarkdownUI
import SwiftUI

struct MarkdownBodyView: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        Markdown(source)
            .markdownTheme(.gitHub)
            // Privacy: never fetch remote images from note bodies. `.asset`
            // resolves bundle assets only — a remote `![](http…)` renders as
            // nothing instead of pinging a third-party server (leaking IP).
            .markdownImageProvider(.asset)
            .markdownInlineImageProvider(.asset)
            .fixedSize(horizontal: false, vertical: true)
    }
}
```

Set **both** modifiers: `markdownImageProvider` covers block images, the inline one
covers `![]()` inside a paragraph; omitting the inline one leaves the leak half-open.

**Test.** Add to the existing `MarkdownBodyViewSnapshotTests` (a snapshot suite already
exists under `__Snapshots__/MarkdownBodyViewSnapshotTests`): render
`MarkdownBodyView("![remote](https://example.com/should-not-load.png)")` and snapshot it
— the recorded image must show no fetched content (a blank/alt box), proving the network
path is dead. A snapshot is the right tool because a unit test can't easily observe "no
URLSession call" without injecting a stub MarkdownUI doesn't expose. (Requires BUILD-1
first to compile the suite.)

**Regression risk.** Very low. The only behaviour change is that a *remote* image (which
nothing in a local-first app should contain) stops rendering; local/asset images are
unaffected. No layout change for text-only notes (the overwhelming majority).

---

## BUILD-1 — Make `ListsTests` compile (stale `SettingsView` call)

**Where.** `platforms/ios/ListsTests/SnapshotTests/SettingsViewSnapshotTests.swift:10`.

```swift
let view = SettingsView(store: store)
```

`SettingsView` gained a required second parameter (`SettingsView.swift:7-8`):

```swift
struct SettingsView: View {
    let store: ItemStore
    @Bindable var autoListPrefs: AutoListPreferences
    ...
}
```

so this call no longer type-checks and **the whole `ListsTests` target fails to compile**
— disabling every snapshot test (the project's only safety net). This is the single stale
call in the target; I grepped the rest of `ListsTests` and found no other `SettingsView(`,
`ItemDetailSheet(`, or `HabitDetailView(` mismatches.

**Change.** Supply an `AutoListPreferences`. Its initializer defaults to `.standard`
UserDefaults (`AutoListPreferences.swift:38`), so a bare `AutoListPreferences()` compiles
and seeds from defaults — fine for a snapshot fixture.

```swift
let view = SettingsView(store: store, autoListPrefs: AutoListPreferences())
```

Optional hardening (not required to compile): construct it against an ephemeral suite so
the snapshot doesn't read whatever is in the test runner's standard defaults —
`AutoListPreferences(defaults: UserDefaults(suiteName: "snapshot-\(UUID())")!)`. The
default order is hard-coded so the bare form renders deterministically regardless; use the
suite form only if a flaky snapshot shows otherwise.

**Test.** This *is* the test fix. After it, run the full `ListsTests` suite and confirm it
**builds and runs** (some image snapshots may need re-recording on the current toolchain —
that's expected and separate from the compile gate). Use the `test` skill / `test_sim`.
Then wire `ListsTests` into CI so the net can't silently switch off again (tracked in
`01-technical-health.md` as the "run tests in CI" half of BUILD-1).

**Regression risk.** None — test-only, single line.

---

## ED-1 — Route smart edits through the text view's input layer so native Undo works

**Where.** `Features/MarkdownEditor/EditorCoordinator.swift:383-404`,
`applyResult(_:to:storage:)`:

```swift
private func applyResult(_ result: (source: String, selection: NSRange),
                         to textView: UITextView,
                         storage: NSTextStorage) {
    let full = NSRange(location: 0, length: storage.length)
    storage.replaceCharacters(in: full, with: result.source)   // ← whole-doc replace
    textView.selectedRange = result.selection
    ...
}
```

Every smart edit funnels here — Return (`:52`), hardware Tab (`:64`), Backspace (`:82`),
marker-zone redirect (`:108`), checkbox tap (`:256`), paste (`:344`, `:352`), every
toolbar action (`:371`) — and `MarkdownTextView.updateUIView` does the same full replace
(`MarkdownTextView.swift:114-117`). There is **zero** `UndoManager` integration in the
subsystem. Replacing the entire `textStorage` behind the text view's back destroys the
tracking layer the system Undo relies on. The prior-art research is explicit
(`ios-editor-engineering.md:95-113`, quoting Apple's Frameworks engineer):

> "By modifying a `UITextView`'s `textStorage` directly, you're circumventing the middle
> layer that tracks updates and deletions… call the various methods on `UITextInput`…
> to keep the undo manager in a consistent state."

**Change.** The pure transforms already return a full new `source` string
(`EditorIntent.apply → (source: String, selection: NSRange)`, `EditorIntent.swift:48-49`).
Keep them — only the *application* changes. Diff old vs new to the **minimal changed
NSRange** (common-prefix/common-suffix in UTF-16, per research §Priority-2 step 3 and the
UTF-16 rule at `:123-134`), then apply that one range via the text view's input method,
which auto-registers undo and coalesces within the run loop.

Add a small UTF-16 diff helper:

```swift
/// Smallest changed NSRange between two strings, in UTF-16/NSString space
/// (the space NSRange/replace(_:withText:) operate in). Returns the range
/// in `old` to replace and the replacement substring from `new`.
private func minimalDiff(from old: String, to new: String) -> (range: NSRange, replacement: String) {
    let o = old as NSString, n = new as NSString
    let oLen = o.length, nLen = n.length
    var prefix = 0
    let maxPrefix = min(oLen, nLen)
    while prefix < maxPrefix,
          o.character(at: prefix) == n.character(at: prefix) { prefix += 1 }
    var suffix = 0
    let maxSuffix = min(oLen, nLen) - prefix
    while suffix < maxSuffix,
          o.character(at: oLen - 1 - suffix) == n.character(at: nLen - 1 - suffix) { suffix += 1 }
    let range = NSRange(location: prefix, length: oLen - prefix - suffix)
    let replacement = n.substring(with: NSRange(location: prefix, length: nLen - prefix - suffix))
    return (range, replacement)
}
```

Then rewrite `applyResult` to use the input layer:

```swift
private func applyResult(_ result: (source: String, selection: NSRange),
                         to textView: UITextView,
                         storage: NSTextStorage) {
    let diff = minimalDiff(from: storage.string, to: result.source)

    // Apply through the text view's UITextInput surface so UIKit's
    // tracking + UndoManager stay consistent (no direct textStorage poke).
    if let start = textView.position(from: textView.beginningOfDocument, offset: diff.range.location),
       let end = textView.position(from: start, offset: diff.range.length),
       let textRange = textView.textRange(from: start, to: end) {
        textView.replace(textRange, withText: diff.replacement)   // ← undoable, minimal
    } else {
        // Fallback only if range mapping fails (should not happen).
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length),
                                  with: result.source)
    }

    textView.selectedRange = result.selection
    if let storage = storage as? MarkdownStyler {
        storage.cursorRange = result.selection
        syncTypingAttributes(for: result.selection, in: textView, storage: storage)
    }
    textBinding.wrappedValue = result.source
    updateCursorIndicator(result.selection)
    // NOTE: do NOT re-add the full-document invalidateGlyphs/invalidateLayout
    // here — that is ED-2's job and is handled by the scoped styling path.
}
```

Notes that make this safe and correct:
- `textView.replace(_:withText:)` is the `UITextInput` method Apple names; it registers the
  inverse on the system `UndoManager` automatically and coalesces per run-loop pass, so a
  burst of smart edits doesn't produce one-undo-per-keystroke.
- `MarkdownTextView.updateUIView`'s `if uiView.text != text { full replace }`
  (`MarkdownTextView.swift:114-117`) is the *external binding → view* path (rare: the
  binding changed from outside). Leave it as a full replace, but route it through the same
  `minimalDiff` helper so an external edit is also a single small undoable step rather than
  a whole-document wipe.
- Selection isn't restored by direct-storage edits; `textView.replace` does set selection
  to the end of the inserted text, and we then assign `result.selection` explicitly, so the
  caret lands where the transform intends.

**Test.**
1. **Unit (no sim):** `minimalDiff` is pure and table-testable. Add `MinimalDiffTests` in
   `ListsTests`: identical strings → zero-length range at 0; single-char insert in the
   middle → length-0 range at the insert point with the inserted char; single-char delete
   → length-1 range, empty replacement; replace-run → the run's range and the new run;
   and an **emoji case** (insert before/after a family emoji `👨‍👩‍👧‍👦`) asserting the
   range is in UTF-16 units, guarding the research's grapheme/UTF-16 landmine
   (`:123-134`). This is the highest-value, fastest test and needs only BUILD-1.
2. **Behavioural (sim, XcodeBuildMCP):** type a few words, press Return on a `- [ ]` line
   (smart continuation), then invoke Undo (⌘Z / shake): the prior typing must still be
   undoable step-by-step, not wiped wholesale. Repeat for Tab-indent, checkbox tap, and a
   paste. Confirm undo *chunks* are sensible (word/run, not per-character), per the open
   question at `ios-editor-engineering.md:267-270`.

**Regression risk.** Medium — this is the core edit path. Risks: (a) NSRange↔`UITextPosition`
off-by-one if `diff.range` is miscomputed — covered by the unit table and the fallback
branch; (b) `textView.replace` fires its own delegate callbacks (`shouldChangeTextIn`,
`textViewDidChange`) — verify no re-entrancy loop (the smart paths return `false` from
`shouldChangeTextIn`, and `replace` inserts the *already-transformed* text which won't
re-trigger a marker rule, but exercise Return-on-list and checkbox-tap explicitly on the
sim to be sure); (c) cursor placement after a multi-line continuation — covered by the
behavioural pass.

---

## ED-2 + PERF-1 — Scope restyling to the edited list block; add a `[UUID:Item]` index

Two findings, one theme: stop doing whole-document / whole-list work on every change.

### ED-2 (a) — Restyle the edited paragraph(s), not the whole document

**Where.** `Features/MarkdownEditor/MarkdownStyler.swift:97-126`, `processEditing()`:

```swift
override func processEditing() {
    clearTokens()
    let full = NSRange(location: 0, length: backing.length)   // ← whole doc
    applyBaseAttributes(in: full)
    switch mode {
    case .live: applyLiveStyling(in: full)                    // ← full-doc line scan
    case .raw:  applyRawStyling(in: full)
    }
    if full.length > 0 {
        edited([.editedAttributes, .editedCharacters],
               range: full, changeInLength: 0)                // ← force-expand to full doc
    }
    super.processEditing()
}
```

and the **second** full-doc hammer in `EditorCoordinator.textViewDidChange`
(`EditorCoordinator.swift:135-140`) which `invalidateGlyphs`+`invalidateLayout` over the
whole document on every keystroke. So a plain keystroke is one full re-style + one full
glyph/layout invalidation; a smart edit adds a third full pass via `applyResult`
(`:395-400`). Cost grows with note length — the O(n²) the audit flagged.

**CRITICAL constraint (do not skip).** The full-document invalidation is **load-bearing**:
it exists to fix a real iOS-26 TextKit-1 bug where sibling list rows keep *stale
zero-width-marker glyphs* and drift one indent unit right (documented inline at
`MarkdownStyler.swift:105-119` and `EditorCoordinator.swift:122-134`; corroborated by the
`iOS 26 TextKit headIndent drift` memory and `ios-editor-engineering.md:168-176`).
Therefore the narrowing target is **the edited *list block*** — the edited paragraph **plus
every contiguous adjacent list/task row whose marker-glyph width could change** — **not**
just the typed line. Narrowing to only the typed line *will* reintroduce the drift.

**Change.** Compute a restyle range from `editedRange`, expand to enclosing paragraphs,
then expand again across contiguous list-marker rows, and run styling + the `edited`
expansion over *that* range only.

```swift
override func processEditing() {
    clearTokens()   // (see ED-2(c) below — token caches should become range-scoped)
    let restyle = restyleRange(around: editedRange)
    applyBaseAttributes(in: restyle)
    switch mode {
    case .live: applyLiveStyling(in: restyle)
    case .raw:  applyRawStyling(in: restyle)
    }
    if restyle.length > 0 {
        // Same dual-flag trick as before (glyph + layout regen this cycle),
        // but over the bounded list block instead of the whole document.
        edited([.editedAttributes, .editedCharacters], range: restyle, changeInLength: 0)
    }
    super.processEditing()
}

/// Edited paragraph(s), widened across any contiguous list/task/quote-list
/// rows so a marker whose glyph width just changed can't leave a stale
/// neighbour drifting (the iOS-26 headIndent bug the full-doc pass guarded).
private func restyleRange(around edited: NSRange) -> NSRange {
    let ns = backing.string as NSString
    guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
    let safe = NSRange(location: min(edited.location, ns.length),
                       length: min(edited.length, ns.length - min(edited.location, ns.length)))
    var range = ns.paragraphRange(for: safe)
    // Walk UP while the previous line is a list/task/numbered/quoted-list row.
    while range.location > 0 {
        let prev = ns.paragraphRange(for: NSRange(location: range.location - 1, length: 0))
        guard isListMarkerLine(ns.substring(with: prev)) else { break }
        range = NSUnionRange(range, prev)
    }
    // Walk DOWN likewise.
    while NSMaxRange(range) < ns.length {
        let next = ns.paragraphRange(for: NSRange(location: NSMaxRange(range), length: 0))
        guard isListMarkerLine(ns.substring(with: next)) else { break }
        range = NSUnionRange(range, next)
    }
    return range
}

private func isListMarkerLine(_ line: String) -> Bool {
    let r = NSRange(location: 0, length: (line as NSString).length)
    return Self.taskRegex.firstMatch(in: line, range: r) != nil
        || Self.bulletRegex.firstMatch(in: line, range: r) != nil
        || Self.numberedListRegex.firstMatch(in: line, range: r) != nil
        || Self.quotedTaskRegex.firstMatch(in: line, range: r) != nil
        || Self.quotedBulletRegex.firstMatch(in: line, range: r) != nil
        || Self.quotedNumberedListRegex.firstMatch(in: line, range: r) != nil
}
```

**Fenced code blocks** are the one cross-paragraph construct whose styling depends on lines
far from the edit. `applyLiveStyling` already caches `fenceMarkerLineRanges`
(`MarkdownStyler.swift:70`, `:219-227`). Extend `restyleRange` to also union in any cached
fence range the edit intersects (or, simpler and robust: if `editedRange` lands inside a
known fence, widen `restyle` to that whole fence). Setext-heading-style constructs aren't
in this grammar, so list-block + fence is the full cross-paragraph set.

Then **delete the redundant full-document invalidation** in
`EditorCoordinator.textViewDidChange` (`:135-140`) — once `processEditing` does a scoped
`edited(...)`, the framework invalidates glyphs+layout for the styled range as part of the
edit cycle, so the manual full-doc call is pure waste. Remove it and rely on the styler.
(Keep `textBinding`/cursor updates in that method.) Likewise, the `applyResult` invalidation
at `EditorCoordinator.swift:395-400` becomes unnecessary once ED-1 routes edits through the
input layer (which triggers `processEditing` naturally); drop it too.

The cursor-move path `invalidateForCursorChange` (`MarkdownStyler.swift:174-196`) already
edits only old line + new line + fence lines — it is **already scoped** and should be left
as-is *except* that it currently relies on `processEditing` expanding to full-doc (see its
`:193-195` comment). After this change it will expand to the *edited list block* instead,
which still covers old/new/fence lines it passed in. Re-verify cursor-driven marker
show/hide still works (it should — the passed ranges are within the restyle union).

### ED-2 (b) — Re-verify indent rendering on the simulator (mandatory)

Because the drift bug is the reason the full-doc pass existed, this change is **not done**
until validated on-sim per `ios-editor-engineering.md:258-261`:
- A long multi-level list (mix of `-`, `1.`, `- [ ]`, nested two levels, with a fenced code
  block in the middle). Type into the **middle** row and confirm **no sibling row drifts
  right**, markers stay column-aligned, and the fence panel stays intact.
- Toggle a checkbox mid-list and confirm neighbours don't shift.
- Capture before/after keystroke latency on a 1k+ line note in a **release** build
  (`:262-265`) to confirm the O(n²) is gone (debug builds exaggerate cost).

### ED-2 (c) — Token caches must match the scoped range

**Where.** `clearTokens()` (`MarkdownStyler.swift:128-133`) wipes `hideIndices`,
`substitutionMap`, `contextRangeByCharIndex`, `fenceMarkerLineRanges` every pass, and
they're rebuilt for the styled range. With full-doc styling the caches were always whole-
document; with scoped styling, clearing them but only rebuilding the edited block would
**lose glyph metadata for unedited rows** (their hide/substitution entries vanish → markers
reappear or mis-render). Spec: change the caches from "clear-all + rebuild-all" to
"evict entries whose char index falls in `restyle`, then rebuild only that range," and
shift indices in `hideIndices`/`substitutionMap`/`contextRangeByCharIndex` by
`changeInLength` for positions after the edit (they're keyed by absolute char index). This
is the fiddly part of ED-2 — budget for it and cover it with the test below.

### PERF-1 — `[UUID:Item]` index to kill O(items) per-cell lookups

**Where.** Every collection-view cell registration and swipe/menu builder does a linear
scan `parent.store.items.first(where: { $0.id == id })`:
- `Features/SmartList/SmartListCollectionView.swift:134` (cell), `:177` (trailing swipe),
  `:219` (leading swipe), `:252` (indent target), `:279` (context menu).
- `Features/ListDetail/ListDetailCollectionView.swift:296` (cell) and its swipe/menu paths.
- `ItemRow.swift:264` `hasSubItems` and `:359` `liveItem` also scan `store.items`.

With the SmartList bridge reconfiguring **every** row on **every** apply
(`SmartListCollectionView.swift:167`, confirmed `verification-ui.md:13`), this is
O(rows × items) per snapshot — fine at dozens, laggy at hundreds.

**Change.** Add a cached dictionary on the store, maintained wherever `items` is mutated,
and read it in the hot paths.

```swift
// In ItemStore (the @Observable that owns `items`):
private(set) var itemsById: [UUID: Item] = [:]

// Rebuild whenever `items` is assigned/loaded, and keep in sync on
// single-item mutations. Cheapest correct approach: a didSet.
var items: [Item] = [] {
    didSet { itemsById = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new }) }
}

func item(_ id: UUID) -> Item? { itemsById[id] }
```

Then replace the scans, e.g. `SmartListCollectionView.swift:134`:

```swift
// before
guard case .item(let id, let indent) = row,
      let parent = self?.parent,
      let item = parent.store.items.first(where: { $0.id == id }) else { return }
// after
guard case .item(let id, let indent) = row,
      let parent = self?.parent,
      let item = parent.store.item(id) else { return }
```

and the same substitution at every `first(where: { $0.id == id })` site listed above.
For `ItemRow.liveItem` (`:359`) use `store.item(item.id) ?? item`. `hasSubItems` (`:264`)
is a *contains-children* query, not an id lookup — if it shows up in profiling, back it with
a `[UUID: [UUID]]` children index built in the same `didSet`; otherwise leave it.

If a plain stored `didSet` is too coarse for the existing mutation flow (e.g. `items` is
appended to in many places), instead funnel all writes through existing mutators and update
both `items` and `itemsById` there — the audit notes writes already go through the store, so
this should be localized.

**Test.**
1. **Styler unit (ED-2(a)+(c), no sim):** add `MarkdownStylerScopedTests` in `ListsTests`.
   Build a `MarkdownStyler`, set a known multi-row list source, edit one row via
   `replaceCharacters`, and assert: (i) `glyphProperty(at:)`/`glyphSubstitution(at:)` for
   chars in **unedited** rows are unchanged (caches survived), (ii) the edited row's marker
   metadata is correct, (iii) `restyleRange` for an edit in the middle of a list returns a
   range covering the whole contiguous block, and (iv) an edit in a plain paragraph between
   two blank lines returns just that paragraph. This directly guards the cache-eviction
   correctness in ED-2(c).
2. **Index unit (PERF-1):** `ItemStoreIndexTests` — after `bootstrap()`/mutations,
   `store.item(id)` equals the array `first(where:)` result for every id, and returns `nil`
   for a random UUID. Cheap, needs only BUILD-1.
3. **Sim (ED-2(b)):** the indent re-verification walk above — **gating**, do not mark done
   without it.

**Regression risk.** ED-2(a)/(c): **High** — this touches the exact glyph-hiding machinery
the drift bug lives in; the scoped caches are the subtle part. Mitigate with the styler unit
test + the mandatory sim indent walk; if drift returns, widen `isListMarkerLine`'s block
walk (e.g. include blockquote/heading rows) before falling back to full-doc. PERF-1: Low —
a derived cache with a single source of truth; the only risk is a mutation path that bypasses
the `didSet`, caught by the index unit test if it asserts after each mutator.

---

## UI-1 — Route the row tap through the parent-owned `.sheet(item:)`

**Where.** `Features/Today/ItemRow.swift`. The row owns its own detail presentation:

```swift
@State private var isShowingDetail = false        // :56
...
Button(action: {
    if inSelectMode { onSelectToggle() }
    else { isShowingDetail = true }               // :63-68  (tap → own state)
}) { rowContent }
...
.sheet(isPresented: $isShowingDetail) {           // :151-157  (sheet inside the cell)
    if item.type == .habit { HabitDetailView(item: item, store: store) }
    else { ItemDetailSheet(item: item, store: store) }
}
```

This sheet is hosted **inside** a `UIHostingConfiguration` of a reconfiguring
`UICollectionViewListCell` (both bridges:
`SmartListCollectionView.swift:138-153`, `ListDetailCollectionView.swift:306-327`). The
SmartList bridge `reconfigureItems(ALL)` on every apply (`:167`), and the ListDetail bridge
**reloads** linger rows (`ListDetailCollectionView.swift:470-471`) — an explicit cell
teardown that resets `@State`. The in-repo comment at `ListDetailCollectionView.swift:448-462`
already documents that reconfigure "blanks the hosted `ItemRow`." So a sheet opened from the
row's own `@State` can be dismissed/blanked by the 1.5s linger timer or any store change.
The **safe parent path already exists and is wired**: all three screens hold
`@State detailItem: Item?` + `.sheet(item: $detailItem)` driven by the swipe
`onShowItemDetail` (`TodayView.swift:32,63-69`; `SmartListScreen.swift:47,80`;
`ListDetailView.swift:114,227-233`). The swipe "Details" action is immune; the tap is not.

**Change.** Give `ItemRow` an optional `onShowDetail` closure. When the host provides it
(the collection-view screens), the tap calls it so the sheet is owned by the *parent*, above
the reconfiguring cell. When it's `nil` (the plain-`List` callers — `SearchResultsView`,
`TagsOverviewView` — whose cells are **not** destructively reconfigured), fall back to the
existing internal sheet so those screens keep working unchanged.

```swift
// ItemRow — new optional hook (default nil preserves existing callers):
var onShowDetail: ((Item) -> Void)? = nil

// tap action (:63-68):
Button(action: {
    if inSelectMode {
        onSelectToggle()
    } else if let onShowDetail {
        onShowDetail(item)            // parent-owned .sheet(item:) — survives reconfigure
    } else {
        isShowingDetail = true        // fallback for non-cell hosts (Search/Tags)
    }
}) { rowContent }

// swipe "Details" action (:111-117): route through the SAME hook for consistency
Button {
    if let onShowDetail { onShowDetail(item) } else { isShowingDetail = true }
} label: { Label("Details", systemImage: "info.circle") }
```

Keep the `.sheet(isPresented: $isShowingDetail)` modifier (`:151-157`) for the fallback
path; it's inert when `onShowDetail` is set because nothing flips `isShowingDetail`.

Wire the two collection bridges to pass it down to `ItemRow`:
- `SmartListCollectionView`: it already carries `onShowItemDetail: (Item) -> Void`
  (`SmartListCollectionView.swift:24`). In `makeItemReg` (`:138-153`), capture it like the
  other closures and pass `onShowDetail: { onShowItemDetail(item) }` (or
  `onShowDetail: parent.onShowItemDetail`) into `ItemRow(...)`.
- `ListDetailCollectionView`: it has `onShowItemDetail` plumbed to the parent
  (`ListDetailView.swift:114`); thread it the same way into the `ItemRow(...)` in
  `makeItemReg` (`:307-327`).

No screen-level change is needed — `TodayView`, `SmartListScreen`, and `ListDetailView`
already declare `detailItem` + `.sheet(item:)`. `SearchResultsView` and `TagsOverviewView`
pass nothing, so they keep the internal-sheet fallback automatically.

**Test.**
- **Sim (XcodeBuildMCP), the load-bearing one** since the runtime dismissal is the part
  `verification-ui.md:18` could not film: complete a task to start the 1.5s linger, then
  immediately tap a *different* row to open its detail sheet; the sheet must **stay open**
  through the linger's `reloadItems`/`reconfigure`. Repeat in Today (smart list) and a
  list-detail screen. Before the fix this is where the sheet blanks/dismisses; after, it
  persists.
- **Snapshot/compile:** add a trivial `ItemRow(..., onShowDetail: { _ in })` construction in
  the existing `ItemRowSnapshotTests` to lock the new signature and confirm the closure
  variant renders identically (needs BUILD-1).

**Regression risk.** Low-to-medium. The default-`nil` parameter keeps Search/Tags behaviour
byte-for-byte. The collection-view screens move from a sheet-in-cell to the parent sheet they
*already* use for swipe-Details, so the presentation surface is unified, not new. Watch that
the habit-vs-task branch is preserved (it is — the parent `.sheet(item:)` blocks already
branch on `item.type == .habit`). One thing to verify: tapping a row no longer toggles
`isShowingDetail`, so any UI test asserting on that internal state must switch to asserting
the parent sheet appears.

---

## A11Y-1 — Make the editor accessible, kill the focusable phantom label, label the habit viz

Three independent sub-fixes; (b) is a one-liner, do it first.

### A11Y-1 (b) — Hide the alpha-0 cursor test-hook from VoiceOver

**Where.** `Features/MarkdownEditor/MarkdownTextView.swift:96-101`:

```swift
let cursorIndicator = UILabel(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
cursorIndicator.isAccessibilityElement = true     // ← focusable
cursorIndicator.accessibilityIdentifier = "markdown.editor.cursor"
cursorIndicator.alpha = 0                          // ← invisible but still in VO order
cursorIndicator.accessibilityValue = "0-0"
```

`alpha = 0` hides it visually but `isAccessibilityElement = true` keeps it in the VoiceOver
order, so VO lands on an empty 1×1 element (confirmed `verification-ui.md:64`). It exists
only as an XCUITest hook for cursor position.

**Change.** Keep it reachable by XCUITest (via identifier/value) but out of the VoiceOver
order for real users:

```swift
cursorIndicator.isAccessibilityElement = false
cursorIndicator.accessibilityElementsHidden = true
```

XCUITest can still query by `accessibilityIdentifier` even when `isAccessibilityElement` is
false in many setups; if a cursor-position UI test depends on it being an element, gate it
instead behind a launch argument (e.g. only set `isAccessibilityElement = true` when
`ProcessInfo.processInfo.arguments.contains("-uitest-cursor")`) so production VoiceOver never
sees it. Confirm against the existing cursor UI tests (search `markdown.editor.cursor` in
`ListsUITests`).

### A11Y-1 (a) — Expose an accessible plain-text representation + accessible checkboxes

**Where.** `Features/MarkdownEditor/MarkdownTextView.swift` (the `UITextView` is vanilla
aside from `accessibilityIdentifier = "markdown.editor"`, `:53`); markers are hidden only
visually (zero-width font / glyph substitution in `MarkdownStyler`), and the checkboxes are
drawn as SF Symbol *images* in `MarkdownLayoutManager.drawGlyphs` (`MarkdownLayoutManager.swift:25-63`)
over zero-width glyphs — with **no** accessibility element. So VoiceOver speaks the literal
backing string (`#`, `- [ ]`, `**`, fences) and never announces "checkbox."

**Change (scope to "usable," not a full a11y editor).** Two parts:

1. **Speak rendered text, not raw markup.** Provide an accessible value that strips the
   syntax the styler hides. The styler already knows which char indices are hidden
   (`hideIndices`) and which are substituted (`substitutionMap` → `☐`/`☑`). Add a method on
   `MarkdownStyler` that produces a VoiceOver string by walking `backing.string` and, for
   each char index, dropping hidden indices and replacing substituted ones with a spoken
   token:

   ```swift
   /// Plain, VoiceOver-friendly rendering: hidden marker chars removed,
   /// task brackets spoken as state. Live-mode only; raw mode reads source.
   func accessibleText() -> String {
       guard mode == .live else { return backing.string }
       let ns = backing.string as NSString
       var out = ""
       var i = 0
       while i < ns.length {
           if let sub = substitutionMap[i] {
               out += (sub == 0x2611 ? "checked, " : (sub == 0x2610 ? "unchecked, " : ""))
               // bullet substitution 0x2022 → spoken as "bullet, " if desired
           } else if !hideIndices.contains(i) {
               out += ns.substring(with: NSRange(location: i, length: 1))
           }
           i += 1
       }
       return out
   }
   ```

   Then keep it current on the text view. Simplest: in `EditorCoordinator.textViewDidChange`
   set `textView.accessibilityValue = (storage as? MarkdownStyler)?.accessibleText()`. (The
   `UITextView` keeps its normal editing semantics; we're only overriding what VO *reads*.)

2. **Make checkboxes accessible actions.** The visible checkbox is an image with no element.
   Add per-task accessibility elements, or — lighter and consistent with the tap path that
   already exists — expose a **custom rotor / activate action** so VoiceOver users can toggle
   the task under the cursor. Pragmatic v1: when VO focuses the editor, expose an
   `accessibilityCustomAction("Toggle checkbox")` that runs the same
   `EditorIntent.tapCheckbox(at:)` path the gesture uses (`EditorCoordinator.swift:246-259`),
   targeting the task line containing the caret. Full per-checkbox `UIAccessibilityElement`s
   positioned over each drawn symbol are the richer fix but are larger work; the custom
   action makes tasks operable now and matches the "usable end-to-end" bar in the finding.

   (A11Y-1(a) is explicitly the "deliberate, larger piece of work" half per
   `verification-ui.md:66`; this spec scopes it to *spoken rendered text + operable
   checkboxes*, which is the minimum for VoiceOver usability. A fully element-mapped editor
   can be a follow-up.)

### A11Y-1 (c) — Label the habit ring and stats

**Where.** `Features/Habits/HabitDetailView.swift`:
- Progress ring `ZStack` (`:148-165`) — three `Circle`s + two `Text`s, no combined label;
  VoiceOver reads "currentCount" and "of N" as separate fragments.
- `stat(label:value:)` (`:464-473`) and its `headerCard` uses (`:128-131`,
  Frequency/Goal/Streak) — value and label are separate `Text`s, read as disjoint fragments.
- The list-row habit ring in `ItemRow.habitRing` (`:317-352`) already has
  `accessibilityLabel` ("Increment habit"/"Habit complete") but **no value** for progress.

**Change.** Combine each viz into one labelled element with a value.

```swift
// Progress ring ZStack (:148-165): wrap and combine.
ZStack { /* …unchanged… */ }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Progress this cycle")
    .accessibilityValue("\(currentCount) of \(item.goalPerCycle)")

// stat(label:value:) (:464-473): make each card one element.
private func stat(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(value)...
        Text(label)...
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)          // e.g. "Streak"
    .accessibilityValue(value)          // e.g. "7"
}

// ItemRow.habitRing (:317-352): add a value alongside the existing label.
.accessibilityValue("\(currentCount) of \(liveItem.goalPerCycle)")
```

**Test.**
- **Sim + VoiceOver-style assertions (XcodeBuildMCP `snapshot_ui`):** the accessibility tree
  for the habit detail must show single elements reading "Streak, 7", "Goal, 3",
  "Progress this cycle, 1 of 3" — not loose number fragments. For the editor, focus
  `markdown.editor` and confirm its `accessibilityValue` is the stripped text ("checked, …"
  rather than "dash bracket x bracket"), and that "Toggle checkbox" appears as a custom
  action. Verify the cursor phantom label no longer appears as a focus stop.
- **Snapshot/compile:** the `.accessibilityElement`/label/value additions are compile-checked
  by the existing `ItemRowSnapshotTests`; no pixel change expected (a11y attrs don't render).

**Regression risk.** (b) Very low — confirm the cursor UI tests still pass (the one caveat).
(c) Very low — `.accessibilityElement(children: .ignore)` only changes what VO reads, not
layout; double-check no *other* a11y test asserted on the old per-fragment labels.
(a) Low-medium — overriding `accessibilityValue` on the text view shouldn't disturb editing,
but verify typing/selection still behave with VoiceOver **on** (custom actions must not
swallow normal text entry); test on the sim with VO enabled.

---

## Cross-cutting test gate

`BUILD-1` unblocks everything: until `SettingsViewSnapshotTests.swift:10` is fixed, the
`ListsTests` target won't compile and **none** of the unit/snapshot tests above can run. Land
SEC-1 (trivial, isolated) and BUILD-1 first, get the suite green (re-recording any
toolchain-drifted image snapshots), then implement ED-1 → ED-2/PERF-1 → UI-1 → A11Y-1, each
with its unit test landing alongside and the sim walks (ED-2 indent re-verify, UI-1 sheet
persistence, A11Y VoiceOver pass) as explicit completion gates per the iOS verification
workflow (XcodeBuildMCP runs + log capture + ≤2 Computer-Use screenshots — not a clicking
loop).
