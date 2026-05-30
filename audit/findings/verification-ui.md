# Verification — UI/State, Markdown Editor, Security, A11y & Agent-Lists findings

Skeptic pass. READ-ONLY review of the exact code paths. Tried to DISPROVE each finding by reading the real code under `platforms/ios/Lists/`. Each finding gets a verdict, a `file:line` citation, and a one-line plain-English "what the owner should believe."

---

## UI-1 — `ItemRow`'s own `.sheet` lives inside reconfigured collection cells; can be torn down mid-interaction
**Verdict: CONFIRMED (architecture); PARTIAL on the runtime symptom (not filmed).**

The structural claim is exactly right, on every point.
- `ItemRow` owns its own detail presentation: `@State private var isShowingDetail = false` (`Features/Today/ItemRow.swift:56`); the row-body `Button` sets `isShowingDetail = true` (`:67`); the modifier `.sheet(isPresented: $isShowingDetail)` is on the row itself (`:151-157`). So the sheet is owned by SwiftUI content hosted **inside** the cell.
- Both bridges host `ItemRow` in a `UIHostingConfiguration` of a `UICollectionViewListCell`: `SmartListCollectionView.swift:138-153` and `ListDetailCollectionView.swift:306-327`.
- The SmartList bridge reconfigures **every** row on **every** apply: `snapshot.reconfigureItems(snapshot.itemIdentifiers)` (`SmartListCollectionView.swift:167`), and `updateUIView` calls `applySnapshot(animated: true)` (`:45-48`) — it runs on any observed `store`/`prefs` change.
- The linger timer is real and ~1.5s: `Task.sleep(for: .seconds(1.5))` then a `withAnimation` mutation of the observed `@State lingeringIds` in all three screens (`TodayView.swift:187`, `SmartListScreen.swift:419`, `ListDetailView.swift:497`). That mutation re-runs `updateUIView` → `applySnapshot` → the blanket reconfigure.
- The in-repo "sibling bug" evidence is genuine: `ListDetailCollectionView.swift:448-462` documents that an in-place reconfigure of a just-completed row's `UIHostingConfiguration` cell **"blanks the hosted `ItemRow`"**, which is why linger rows are `reloadItems`'d (`:470-471`) — a full cell teardown. A cell that is reloaded/blanked while presenting a sheet is the teardown case the finding describes.
- The safe parent path exists and is wired: parent `@State detailItem: Item?` + `.sheet(item: $detailItem)` driven by the swipe `onShowItemDetail` (`TodayView.swift:10,32,63`; `SmartListScreen.swift:21,47,80`; `ListDetailView.swift:56,114,227`). So the swipe "Details" action is immune; the row-tap path is not. Two paths, exactly as claimed.

Severity nuance worth noting: SmartList (Today + every smart list) **only** ever `reconfigureItems(ALL)` and has no linger-specific `reloadItems` (`SmartListCollectionView.swift:160-169`), whereas ListDetail does an explicit `reloadItems` for linger rows (`ListDetailCollectionView.swift:470-471`). A `reloadItems` is an unambiguous cell teardown that *will* reset `@State`; a bare `reconfigureItems` rebuilds the hosting configuration's rootView and, per the in-repo comment, blanks the row's content. The one thing I could not do under READ-ONLY is film the sheet actually dismissing — so the *mechanism* is CONFIRMED in code; the *user-visible dismissal* stays PARTIAL (the finding already rates it Med-High and flags the sim run as the open item). I found nothing that refutes it.

**Owner should believe:** Real. The row you tap opens its detail pop-up from inside a list cell that the app rebuilds whenever anything changes — including the 1.5s "fade out a finished task" timer — so the pop-up can close itself or stutter. The swipe→Details version is built the safe way; the tap version isn't. Fix is to make tap use the same safe path.

---

## ED-1 — Every smart edit replaces the entire document, destroying native undo
**Verdict: CONFIRMED.**

- `applyResult` replaces the whole document for *any* smart action: `let full = NSRange(location: 0, length: storage.length)` then `storage.replaceCharacters(in: full, with: result.source)` (`Features/MarkdownEditor/EditorCoordinator.swift:386-387`).
- Every smart path funnels through it: Return (`:52`), hardware Tab (`:64`), Backspace (`:82`), marker-zone redirect (`:108`), checkbox tap (`:256`), vertical-move sync is separate but paste (`:344`, `:352`) and every toolbar action (`:371`) all call `applyResult`. `MarkdownTextView.updateUIView` does the same full replace (`MarkdownTextView.swift:114-117`).
- **Zero** `UndoManager` integration in the whole subsystem: `grep -rn "undoManager|registerUndo|beginUndoGrouping|endUndoGrouping" Features/MarkdownEditor/` returns nothing (exit 1). Confirmed by the dedicated research file as well (`audit/research/ios-editor-engineering.md:180-186`).

**Owner should believe:** Real. Pressing Return/Tab/Backspace, tapping a checkbox, or using a toolbar button rewrites the entire note behind the system's back, so the built-in Undo (shake / ⌘Z) can't step back cleanly. A correctness/UX break for a notes app. The exact symptom needs a device check, but the cause is certain.

---

## ED-2 — Whole-document re-style every keystroke + double full-doc glyph/layout invalidation (O(n²))
**Verdict: CONFIRMED.**

- `MarkdownStyler.processEditing()` re-styles the WHOLE document every edit: `let full = NSRange(location: 0, length: backing.length)`, then `applyBaseAttributes(in: full)` and `applyLiveStyling(in: full)` (`Features/MarkdownEditor/MarkdownStyler.swift:97-104`), and then force-expands the edited range to the full doc: `edited([.editedAttributes, .editedCharacters], range: full, changeInLength: 0)` (`:120-124`). The code comment itself says this "expands the edited range to full-doc."
- The coordinator then invalidates glyphs **and** layout over the full document on every change: `let full = NSRange(0, textView.textStorage.length)` → `invalidateGlyphs(...)` + `invalidateLayout(...)` (`EditorCoordinator.swift:135-140`).
- And `applyResult` invalidates the full doc **again** for smart edits: `invalidateGlyphs`/`invalidateLayout` over `updatedFull` (`EditorCoordinator.swift:395-400`).

So a plain keystroke is one full re-style (processEditing) + one full glyph/layout invalidation (textViewDidChange); a smart edit adds a third full pass (applyResult). Per-keystroke cost grows with note length, exactly as claimed.

**Owner should believe:** Real. Typing re-formats the entire note on every keypress, so short notes are fine but long notes will feel laggy/sticky. The full-document hammer exists to fix a real alignment bug (documented in the code), so the fix is to narrow it to the edited paragraph(s), not remove it.

---

## SEC-1 — Markdown note bodies use MarkdownUI's default (remote-fetching) image provider
**Verdict: CONFIRMED.**

- The read-only renderer sets NO image provider: `Markdown(source).markdownTheme(.gitHub).fixedSize(...)` — that is the entire body (`Features/MarkdownEditor/MarkdownBodyView.swift:14-18`). No `.markdownImageProvider(.asset)`, no `.markdownInlineImageProvider`, no custom/no-op provider.
- Repo-wide there is no provider override anywhere: `grep -rn "markdownImageProvider|markdownInlineImageProvider|ImageProvider|NetworkImage" Features/` returns nothing (exit 1). So MarkdownUI's `DefaultImageProvider` is active by omission.
- The remote-fetch chain the finding cites (DefaultImageProvider → NetworkImage → `URLSession.data(from:)`) is a property of the resolved MarkdownUI/NetworkImage packages, which I did not re-open in this pass — but the *reachability gate* (no provider set on `MarkdownBodyView`) is the part that is in this repo, and it is confirmed open. `MarkdownBodyView` is reached with user content via `ThreadView` (`Features/Thread/ThreadView.swift`, the body renderer for notes).

**Owner should believe:** Real and the one genuine privacy leak. A note containing a remote image (`![](https://…)`) silently pings that third-party server — leaking the user's IP/timing — the moment the note is viewed, contradicting the "no network for local use" promise. One-line fix: pin an offline/asset image provider on the renderer.

---

## A11Y-1 — (a) editor reads raw markdown to VoiceOver + drawn checkboxes inaccessible; (b) hidden alpha-0 label is VoiceOver-focusable
**Verdict: CONFIRMED (both parts).**

(a) `MarkdownTextView` is a vanilla `UITextView` with no accessibility customization of its content: it sets `accessibilityIdentifier = "markdown.editor"` (`Features/MarkdownEditor/MarkdownTextView.swift:53`) but no `accessibilityLabel`/`accessibilityValue` exposing the *rendered* text. Markers are hidden only visually (zero-width font / glyph substitution in `MarkdownStyler`), so the backing string — the literal `#`, `- [ ]`, `**`, fences — is what VoiceOver speaks. The task checkboxes are drawn as SF Symbol images in the layout manager (`MarkdownLayoutManager.drawGlyphs`) over zero-width glyphs, with no accessibility element, so VoiceOver never sees "checkbox." A folder-wide grep for accessibility APIs in `Features/MarkdownEditor/*.swift` returns only the cursor label, the toolbar Close/Done buttons, and the identifier — nothing that voices content.

(b) The cursor test-hook label is hidden but VoiceOver-focusable, verbatim as claimed: a 1×1 `UILabel` with `cursorIndicator.isAccessibilityElement = true` (`MarkdownTextView.swift:97`) and `cursorIndicator.alpha = 0` (`:99`). `alpha = 0` removes it visually but `isAccessibilityElement = true` keeps it in the VoiceOver order, and nothing sets `accessibilityElementsHidden`. So VoiceOver can land on an empty element. Its `accessibilityValue` ("{loc}-{len}") is updated at `EditorCoordinator.swift:463`.

**Owner should believe:** Real. A blind user hears the raw markup ("dash bracket space bracket…") instead of "checkbox, unchecked," the visible checkboxes are silent, and there's an invisible focus stop (a test-only label) VoiceOver can get stuck on. Part (b) is a one-line quick fix; part (a) is a deliberate, larger piece of work.

---

## AGENT-1 — `ItemType` `Decodable` THROWS on an unknown `type:` value
**Verdict: CONFIRMED.**

- `ItemType` is a plain raw-value enum with auto-synthesized `Codable` and **no** custom permissive `init(from:)`: `public enum ItemType: String, Codable, Sendable, CaseIterable { case task, habit, note }` (`Core/Models/Item.swift:58-60`). Swift's synthesized decoder for a `RawRepresentable: Codable` enum throws `DataCorruptedError` when the raw value matches no case.
- The decode site is a **non-optional, throwing** decode — unlike every other field, which uses `decodeIfPresent ?? default`: `self.type = try c.decode(ItemType.self, forKey: .type)` (`Item.swift:174`). Compare the forgiving neighbours at `:178-199`.
- That throw is not caught per-file (`FileStore.walk` uses `try itemFiles.map { try readItem }`, `FileStore.swift:176`), so via the DI-1 class it would abort the entire `loadAll` and brick the library — the chain the finding describes.

**Owner should believe:** Real. A future or peer-written file with `type: question` (or any new type an older build doesn't know) doesn't just skip that one item — it currently fails the whole load. Adding a `question` type safely requires making this decoder permissive first.

---

## AGENT-2 — `FileStore.walk` would treat `_status.md` as an item and fail to decode it
**Verdict: CONFIRMED.**

- `walk` selects item files by extension only, with no name filter: `let itemFiles = entries.filter { $0.pathExtension == "md" }` then `let items = try itemFiles.map { try readItem(at: $0) }` (`Core/Storage/FileStore.swift:174-176`). A `_status.md` has `pathExtension == "md"`, so it is included. There is no `_`-prefix exclusion, no allowlist, nowhere in the load path.
- `readItem` → `FrontmatterCodec.decode` (`FileStore.swift:85-88`) requires a `---\n` opener (`FrontmatterCodec.swift:41`) and then decodes `Item.self`, which requires `id`/`type`/`title`/`list`/`created_at` (`Item.swift:171-177`). A heartbeat `_status.md` (free-form `current_task:`/`last_active:` fields, not Item frontmatter) throws either `Error.missingOpener` or `keyNotFound`.
- The throw propagates straight out of `walk`/`loadAll` (no per-file catch) → DI-1 brick.

**Owner should believe:** Real. The proposed per-list `_status.md` heartbeat file would be mistaken for a task file and, failing to parse, would take the whole library down on launch. `walk` must be taught to skip `_`-prefixed/non-item files before that feature exists.

---

## Summary

| Finding | Verdict |
|---|---|
| UI-1 (per-cell sheet torn down by reconfigure/linger) | **CONFIRMED** (architecture); PARTIAL on filmed symptom |
| ED-1 (full-doc replace breaks undo) | **CONFIRMED** |
| ED-2 (full-doc re-style + double invalidation, O(n²)) | **CONFIRMED** |
| SEC-1 (default remote image provider leaks IP) | **CONFIRMED** |
| A11Y-1a (raw markdown + silent checkboxes to VoiceOver) | **CONFIRMED** |
| A11Y-1b (alpha-0 label is VoiceOver-focusable) | **CONFIRMED** |
| AGENT-1 (`ItemType` decode throws on unknown) | **CONFIRMED** |
| AGENT-2 (`walk` mis-reads `_status.md` as an item) | **CONFIRMED** |

All seven findings hold against the exact code; none refuted. The only hedge is UI-1's *runtime* symptom (sheet visibly dismissing), which is unprovable under READ-ONLY — but its mechanism is confirmed in code and corroborated by an in-repo comment, so no severity reduction is warranted. No severity *increases* either: each verdict matches the original finding's stated confidence.
