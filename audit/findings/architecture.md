# Architecture & Maintainability Audit

## Verdict

**Minor issues — fundamentally sound, with a few real hazards.** For a codebase
built largely with AI help, the bones are genuinely good: a clean Core / Design /
Features split, a single source-of-truth store that every screen routes through
(no screen touches the disk directly), one well-designed `Item` primitive, and
unusually thorough explanatory comments. The maintainability risk is not the
architecture — it's **copy-paste duplication**. Three or four behaviors are
hand-cloned across files instead of shared, so a change in one place must be
made in 2-3 others or they silently drift. The very large files are mostly
*cohesive* (one big job each), not tangled "god files," but two of them are
near-identical twins that should share code. Docs reference a deleted `shared/`
directory.

**Maintainability grade: B / B-minus.** Safe to keep changing, *if* you know
which clones to keep in sync. The top 3 things below are what will bite.

---

## The top 3 things that will bite future changes

1. **The two big "sheet" files are clones (P1).** `QuickCaptureSheet` (1320) and
   `ItemDetailSheet` (1162) are ~70% the same code, duplicated verbatim. A fix to
   the date/reminder logic in one will be forgotten in the other.
2. **The "linger on completion" behavior is hand-copied into 3 screens (P2).**
   The comments literally say "Mirror of ListDetailView.toggleAndLinger." Three
   copies = three places to change, three places to get it wrong.
3. **Doc drift will mislead the next AI session (P2).** `AGENTS.md`, `README.md`,
   `docs/CURRENT.md`, and a code comment all describe a `shared/` folder that was
   **deleted**. An AI agent reading these as truth will hallucinate structure.

---

## Findings

### [P1] `QuickCaptureSheet` and `ItemDetailSheet` are near-duplicate 1200-line files
- **Where:** `platforms/ios/Lists/Features/QuickCapture/QuickCaptureSheet.swift`
  and `platforms/ios/Lists/Features/ItemDetail/ItemDetailSheet.swift`
- **What:** These two screens (create-item vs edit-item) share a huge amount of
  *identical* code, copy-pasted rather than shared. Verified duplicated symbols:
  `splitToggleRow`, `rowLabel`, `pickerRowLabel`, `placeholderRow`,
  `discardPopover`, the `dateBinding`/`timeBinding`/`urgentBinding`/`endRepeatBinding`
  helpers, the four `onChange(of:)` cascades for Date/Time/Reminder/Urgent
  (`QuickCaptureSheet.swift:136-186` ≈ `ItemDetailSheet.swift:156-204`, byte-for-byte),
  the entire `dateAndTimeSection` and `repeatAndEarlySection`, the
  `defaultDue`/`defaultEndRepeat`/`formatUntil` static helpers, the priority
  glyph/color/name helpers, and a private `nilIfEmpty` String extension declared
  in *both* files.
- **Impact:** This is the single biggest maintainability hazard in the app. Any
  change to how dates, reminders, repeat rules, or the discard-confirm flow work
  — a very likely area of future product iteration — has to be made twice, in two
  1200-line files, and kept perfectly in sync by hand. The day someone fixes a
  reminder bug in the edit sheet but forgets the capture sheet (or vice-versa),
  the two screens silently diverge and the app behaves differently depending on
  whether you're creating or editing. AI-assisted edits are *especially* prone to
  touching one and missing the other.
- **Confidence:** High
- **Fix:** Extract the shared form into one reusable piece. Concretely: pull the
  duplicated row helpers + the `onChange` cascade + the date/repeat/early sections
  into a shared `ItemFormFields` view (or a view-modifier + a small
  `ItemFormState` model holding the `hasDate`/`hasTime`/`repeatPreset`/… draft
  fields). Both sheets then become thin shells: capture seeds an empty draft, edit
  seeds from an existing `Item`, and both render the same fields. Don't rewrite the
  save logic — just stop maintaining the *form* twice. This is the highest-value
  refactor in the codebase.

### [P2] "Linger on completion" + view-options bindings cloned across Today / SmartList / ListDetail
- **Where:** `Features/Today/TodayView.swift:162-192`,
  `Features/SmartList/SmartListScreen.swift:390-424`,
  `Features/ListDetail/ListDetailView.swift:461-502`
- **What:** `toggleAndLinger`, `incrementHabitAndLinger`, and `startLinger` are
  copy-pasted into all three screens (the comments even read "Mirror of
  `ListDetailView.toggleAndLinger`"). The `showCompletedBinding` /
  `showOverdueBinding` / `sortBinding` helpers are likewise re-declared per screen.
  Separately, the child-visibility predicate
  `(showCompleted || !item.isComplete || lingering.contains(item.id))` is repeated
  inline in at least 4 places (`ListDetailView`, `ListDetailCollectionView`
  `flattenWithChildren`, `SmartListScreen` `allViewLists` + `flattenForAll`).
- **Impact:** The 1.5s linger window, its fade animation, and the "what counts as
  visible" rule are product-tuned values. Today they live in 3-4 copies. Tuning the
  feel (e.g. changing 1.5s, or making completed sub-items behave differently) means
  finding and editing every copy; miss one and Today fades differently from a list.
- **Confidence:** High
- **Fix:** Move the linger machinery into one place — either a small
  `@Observable LingerController` the screens share, or a view-modifier
  (`.lingersCompletions(store:prefs:)`). Put the child-visibility predicate on a
  single helper (e.g. `Item.isVisible(showCompleted:lingering:)` or a method on the
  store) and call it everywhere. Low-risk, high-clarity.

### [P2] Swipe-action / context-menu vocabulary duplicated between the two collection views
- **Where:** `Features/SmartList/SmartListCollectionView.swift:173-300` vs
  `Features/ListDetail/ListDetailCollectionView.swift:1286-1397` (and the context
  menu at `:1249-1282`)
- **What:** The Delete / Flag / Details trailing-swipe actions, the Indent /
  Outdent leading-swipe actions (including the "walk back to find the previous
  sibling" logic), and the Flag/Delete context menu are implemented twice, almost
  line-for-line, in the two UIKit collection-view coordinators.
- **Impact:** Add a new swipe action (e.g. "Move to list") or change Flag's icon
  and you must edit both coordinators identically. They've already diverged
  slightly (ListDetail's leading swipe uses the snapshot's immediate previous row;
  SmartList strides backward skipping non-item rows) — exactly the kind of subtle
  drift duplication breeds.
- **Confidence:** High
- **Fix:** Factor the action builders into shared free functions or a small
  `ItemRowActions` helper that takes `(item, store, callbacks)` and returns the
  `UISwipeActionsConfiguration` / `UIMenu`. Both coordinators call it. This also
  centralizes the `isOverdue(_:)` helper currently copied into 4 files
  (`ListDetailView`, `ListDetailCollectionView`, `SmartListCollectionView`,
  `TagsOverviewView`).

### [P2] Documentation references a `shared/` directory that was deleted
- **Where:** `AGENTS.md:11` ("`shared/` contains format schemas, fixtures, and
  cross-platform contracts" — present tense), `docs/CURRENT.md:84` ("Realign
  `shared/format/` wording…"), `README.md:46` ("`shared/` - schemas, fixtures…"),
  and code comment `Core/Models/ISO8601.swift:5` ("…per `shared/format/`").
- **What:** Commit `57fb450` ("retire deferred platforms + test targets") deleted
  the `shared/` and `research/` trees. The canonical agent guide and the status
  doc still describe `shared/` as if it exists. (`research/` is only referenced in
  the audit's own files, so that's fine.)
- **Impact:** This is a maintainability finding specifically because the project is
  driven by AI agents reading these docs as ground truth. An agent told "`shared/`
  contains the format contract" will look for it, not find it, and may invent or
  misplace files. The `ISO8601.swift` comment points a reader at a spec that's gone.
- **Confidence:** High
- **Fix:** Delete the three stale `shared/` doc references (or replace with "the
  on-disk format is defined by the Swift `Codable` models in `Core/Models/` +
  `FrontmatterCodec`"). Update the `ISO8601.swift` comment to cite the model
  instead of `shared/format/`.

### [P2] Documentation drift on test targets (note vs. reality)
- **Where:** `docs/CURRENT.md:16` + user MEMORY note ("test targets currently
  retired") vs. `platforms/ios/project.yml:64,83` and the live test files.
- **What:** History is muddled: commit `57fb450` says it *removed* `ListsTests` /
  `ListsUITests`; `CURRENT.md:51` says test infra was *rebuilt* on 2026-05-21. I
  verified the current truth: both targets **exist** in `project.yml`, the source
  files are present, `ListsTests` has **49** test functions and `ListsUITests` has
  **9** test classes — which matches `CURRENT.md`'s "What Exists." So the docs'
  *counts* are right, but the surrounding notes (and the user-memory "retired"
  flag) contradict the wiring.
- **Impact:** Confusing for anyone (human or AI) deciding whether tests are
  trustworthy/runnable. Low functional risk, real cognitive cost.
- **Confidence:** High (on the wiring; I did not *run* the tests, only counted)
- **Fix:** Reconcile to one sentence in `CURRENT.md`: "ListsTests (49) and
  ListsUITests (9 classes) exist and are wired into `project.yml`." Drop the
  "retired" framing from the memory note.

### [P3] Dead code left over from the SwiftUI → UIKit migration in `ListDetailView`
- **Where:** `Features/ListDetail/ListDetailView.swift`
- **What:** When list rendering moved into `ListDetailCollectionView`, several
  helpers on the SwiftUI shell were orphaned but not removed. Verified
  defined-but-never-called (each symbol appears only at its own definition):
  `private var sections` (`:432`), `items(in:)` (`:444`, 0 refs), `sectionName(for:)`
  (`:451`), `commitSectionRename` (`:375`), `isOverdue` (`:508`, the collection view
  has its own copy), and the `renamingSectionId` / `renameBuffer` / `renameFocus`
  state that only `commitSectionRename` reads (`:48-50`). ~70-80 lines total.
  (To their credit, the file *documents* the removal at `:348-356` — the leftover
  helpers just weren't all caught.)
- **Impact:** Low. It compiles and ships. But dead code misleads future readers
  ("is `sectionName` the source of truth for section titles?" — no, the collection
  view's `sectionDisplayName` is), and invites accidental edits to code that has no
  effect.
- **Confidence:** High
- **Fix:** Delete the six unused helpers and the three orphaned `@State`
  properties. Quick, safe cleanup.

### [P3] Sync/CRDT scaffolding is half-present and undocumented
- **Where:** `Core/Models/ItemList.swift:22` (`lamport: Int64`), incremented in
  `ItemStore.softDeleteList` / `restoreList` / `moveList`; **absent** from
  `Core/Models/Item.swift` (verified: 0 occurrences).
- **What:** `ItemList` carries a `lamport` logical clock (a sync/CRDT primitive)
  and the store bumps it on list mutations, but `Item` has no equivalent and most
  list mutations (`addList`, `updateList`, `addSection`, renames) don't bump it
  either. Sync is explicitly deferred per the product notes, so this is dormant
  scaffolding — but it's inconsistent (lists yes, items no) and unexplained.
- **Impact:** Low today. The risk is a future "we're adding sync" effort assuming
  `lamport` is maintained consistently when it isn't, leading to subtle
  reconciliation bugs. Tombstone fields are documented (`PRODUCT-SPEC.md:38`);
  `lamport` is not.
- **Confidence:** High
- **Fix:** Either (a) drop `lamport` until sync work actually starts (it can come
  back from git history), or (b) add a one-line note in `PRODUCT-SPEC.md` that it's
  unfinished sync scaffolding, lists-only. Don't leave it as a silent half-feature.

### [P3] `GlyphLabelStyle` lives in a feature file but is shared across features
- **Where:** defined in `Features/QuickCapture/QuickCaptureSheet.swift:1181`, used
  in `ItemDetailSheet` and `HabitDetailView` too.
- **What:** A genuinely shared, reusable SwiftUI `LabelStyle` is declared inside one
  feature's file rather than in `Design/`. Importing QuickCapture's file to get a
  label style is a backwards dependency.
- **Impact:** Minor. Works fine, but muddies the Design-vs-Features boundary the rest
  of the codebase respects well.
- **Confidence:** High
- **Fix:** Move `GlyphLabelStyle` into `Design/Components/` alongside the other
  shared view pieces.

### [P3] Repetitive structure *within* the big single-purpose files (not god-files, but dense)
- **Where:** `Features/MarkdownEditor/MarkdownStyler.swift` (1233);
  `Features/ListDetail/ListDetailCollectionView.swift` (1880)
- **What:** These two are the genuinely-large files, but each is **cohesive** — one
  does live markdown styling, the other does hierarchical UIKit drag-and-drop.
  Neither is a "god file mixing concerns." That said, both have internal
  copy-paste: in `MarkdownStyler`, the quoted-list handlers
  (`quotedTask`/`quotedNumbered`/`quotedBullet`, `:338-466`) mirror the plain ones,
  and the inline-marker handlers (bold/italic/strike/highlight, `:846-925`) repeat
  the same ~8-line "compute span → registerHide open/close → tint tertiary" block 5×.
  In `ListDetailCollectionView`, several frame-lookup helpers
  (`frameForItem`/`itemFrames`/`gapY`) walk the snapshot the same way.
- **Impact:** Editing risk here is **complexity, not tangling**. The drag/drop
  coordinator in particular has dozens of carefully-interacting state flags
  (`draggingItemId`, `dragSourceHidden`, `sectionDropTarget`, …) and many subtle
  iOS-26-specific workarounds. It works and is heavily commented, but it's the
  scariest file to change blindly — a small change to drop-target math can break
  reorder/nest in non-obvious ways. The good news: it's *isolated* (one file, one
  job) so blast radius is contained.
- **Confidence:** High (on the duplication); Med (on "realistic edit risk" — I read
  the logic thoroughly but did not run it)
- **Fix:** Don't rewrite either. Natural seams *if* you choose to split:
  `MarkdownStyler` → extract a `BlockMarkers` styler and an `InlineMarkers` styler
  (plus a shared `applyMarkerSpan(open,close,context)` helper to kill the 5× inline
  repeat); the regex table + `NSAttributedString.Key` extension could move to their
  own file. `ListDetailCollectionView` → the drop-target *geometry* (the
  `resolved…DropTarget` / `chooseIndent` / frame helpers) is a self-contained
  "given a touch point, what's the drop slot" calculator that could become its own
  `DropResolver` type, separating *where to drop* from *how to animate it*. Treat
  these as opportunities, not obligations.

---

## Strengths

These are genuinely well-built and worth protecting:

- **Clean layering, strictly enforced.** Verified: **zero** files under `Features/`
  reference `FileStore`, `FrontmatterCodec`, or `FileManager` directly. Every screen
  goes through `ItemStore`. Core (Models/Stores/Storage/Queries/…) → Design →
  Features is a real boundary, not aspirational. This is the most important
  maintainability property a codebase can have, and it holds.
- **`ItemStore` is a coordinator, not a god object.** It's 637 lines but every
  method is small, single-purpose, and follows one consistent pattern (mutate a
  copy → `store.writeItem` → update in-memory array → schedule notifications). It
  is the single source of truth for lists+items; UI state (sort, expand, linger)
  correctly lives in the views/prefs, not here. The one wart is the
  `update`/`applyUpdateSync` (and `reorder…`/`applyReorder…Sync`) pairs — a
  deliberate, well-commented sync/async split for UIKit drag animations, not
  accidental duplication.
- **The one-`Item`-primitive model is elegant, not overloaded.** Task/habit/note
  share one shape with type-gated fields; `isComplete` and the `Codable` encoder
  cleanly branch on `type` (e.g. habit fields only encode when `type == .habit`,
  `Item.swift:229-236`). Decoding is defensively `decodeIfPresent` with sane
  defaults everywhere, so old/partial files won't crash the app. This is a strong,
  forward-compatible design.
- **`FileStore` is careful where it matters most.** Atomic writes
  (`atomically: true`), a `pathById` map so callers never deal in paths,
  best-effort folder-rename migration that *keeps loading on failure rather than
  aborting* (`:163-171`), and thorough filename sanitization. The on-disk format
  reads cleanly on extract — exactly the local-first promise.
- **Pure, testable Core logic.** `SmartList.matches`, `ItemSort.sortedBy`,
  `HabitCycle.key`, and `HabitStats.streak` all take injectable `now`/`calendar`
  and have no side effects — easy to unit-test and reason about. 49 tests exist.
- **Comments explain the *why*, especially the hard parts.** The iOS-26 TextKit
  `headIndent` workaround, the "reload not reconfigure during linger" note, the
  lazy drag-source hiding — these are the kind of hard-won fixes that get
  re-broken without a paper trail, and they're documented. Zero `TODO`/`FIXME`/`HACK`
  markers and no large commented-out code blocks anywhere in the app.
- **Consistent conventions.** Accessibility-id scheme (`<screen>.<element>`) is
  applied uniformly; file/folder organization is predictable; naming is clear.

---

## Coverage

**Read in full:** `Item.swift`, `ItemList.swift`, `HabitCycle.swift`,
`SmartList.swift`, `ItemSort.swift`, `ItemStore.swift`, `FileStore.swift`,
`ListDetailCollectionView.swift` (all 1880 lines), `QuickCaptureSheet.swift`,
`ItemDetailSheet.swift`, `MarkdownStyler.swift`, `SmartListCollectionView.swift`,
`SmartListScreen.swift`, `TodayView.swift`, `ListDetailView.swift`. Plus
`AGENTS.md`, `docs/CURRENT.md`, `README.md`, `project.yml`, and targeted reads of
`ISO8601.swift`, `App/`, `Design/Spacing.swift`.

**Verified by search across the tree:** layering boundaries (Features→Storage),
duplication of linger/binding/swipe helpers, the `shared/` doc drift (incl. git
`show 57fb450`), test counts, `lamport` scope, dead-symbol reference counts in
`ListDetailView`, `GlyphLabelStyle` cross-file use, and absence of TODO/dead-code
markers.

**In scope but only skimmed (not line-by-line):** `SidebarView` (657),
`HabitDetailView` (583), `ListEditSheet` (488), `EditorCoordinator` (465),
`ToolbarAction` (428), `ItemRow` (425), and the smaller `MarkdownEditor/` modules.
I read their headers/structure and confirmed the patterns above (e.g. `isOverdue`
copies, shared helpers) but did not audit each in depth. The MarkdownEditor module
split (one glue `MarkdownTextView` + focused pure-transform files) looked like the
*best-factored* corner of the app from the outside — consistent with the rebuild
notes — and I did not find duplication smells there.

**Not done:** I did not build or run the app or tests (read-only constraint), so
"realistic edit risk" judgments on the drag/drop coordinator are from reading, not
runtime observation.
