# Markdown Editor Evolution — Tables, Math, Drawing, Attachments & a Block Model

Compiled 2026-05-30. Confidence: **high** — every external library version/license and every Apple-API/WWDC claim was verified against primary sources. The one material change since the scout's draft is an *upgrade* in certainty, not a contradiction: the Lists editor is now code-verified to be on TextKit 1, which sharpens the recommendations rather than overturning them.

---

## Summary

- **Today's editor is built on the old text engine (TextKit 1).** That's not a bug — it works — but it's the single fact that shapes every option below. The modern features you'd want (live drawings, math, tables embedded *inside* the note) need the new engine (TextKit 2). Moving to it is a real project, not a flip of a switch.
- **The slowness is real and confirmed in the current code.** Every keystroke — and even every time you move the cursor — re-styles and re-lays-out the *entire note*. On a long note that gets sluggish. There's a known fix, but it's tangled with a bug the current code was deliberately written to mask, so it needs careful work, not a one-liner.
- **Tables, math, and drawings are all achievable natively** without web views or third-party web editors. Good, well-maintained, MIT-licensed Swift libraries exist for math; Apple's own PencilKit handles drawings; Apple's Markdown parser handles tables.
- **Apple gives us no built-in table support on iPhone/iPad.** Even Craft (a polished competitor) had to work around this. So tables are the most "hand-built" of the three features.
- **The "your notes are plain Markdown files you own" promise can survive all of this** — drawings and images become separate files in a folder next to the note, referenced by a normal Markdown link/embed. The note stays human-readable text.
- **The robust, future-proof architecture is a "block model" like Notion's** — the note becomes a list of independent blocks (paragraph, table, drawing, math) instead of one giant string. This is the deepest change but it simultaneously fixes the performance problem, makes corruption local instead of catastrophic, and makes embedding non-text content natural.
- **My recommendation is staged:** do the cheap performance fix and a file-on-disk attachment convention first (small adds), prove out the new text engine with a drawing prototype next, and treat the full block model as the eventual destination — adopted deliberately, not rushed.

---

## 1. The foundational fact: the Lists editor is on TextKit 1 today

**This is code-verified, not inferred.** It reframes everything else.

Apple's text-rendering system comes in two generations. TextKit 1 (the `NSLayoutManager` world) is the original; TextKit 2 (the `NSTextLayoutManager` world) is the modern rewrite that shipped in iOS 15 and became the default for `UITextView` in **iOS 16**. The new features we care about — live embedded views, and "only lay out what's on screen" performance — exist **only** in TextKit 2.

The Lists editor is firmly on TextKit 1. Evidence in `platforms/ios/Lists/Features/MarkdownEditor/`:

- **`MarkdownLayoutManager.swift`** declares `final class MarkdownLayoutManager: NSLayoutManager` — subclassing `NSLayoutManager` is itself a TextKit 1 type. It overrides `drawBackground`/`drawGlyphs` and uses glyph-based APIs (`characterRange(forGlyphRange:)`, `lineFragmentRect(forGlyphAt:)`, `boundingRect(forGlyphRange:in:)`, `enumerateLineFragments(forGlyphRange:)`, `enumerateEnclosingRects(forGlyphRange:...)`).
- **`MarkdownTextView.swift`** wires the TextKit 1 stack by hand: it creates the layout manager and calls `storage.addLayoutManager(layout)`. Manually adding a layout manager to an `NSTextStorage` builds the TextKit 1 object graph.
- **`EditorCoordinator.swift`** calls `textView.layoutManager.invalidateGlyphs(...)`, `.invalidateLayout(...)`, `.enumerateLineFragments(...)`.

Per Apple's WWDC22 session, **merely accessing `layoutManager` forces an irreversible fallback to TextKit 1** — "Once a text view switches to TextKit 1, there's no automatic way of going back." So this isn't accidental; the editor is committed.

**Consequence:** Adopting TextKit 2 (and therefore live embedded views and viewport-only layout) is a **migration**, not a property you simply preserve. The current custom rendering — code-block panels, inline-code pills, horizontal rules, SF-Symbol checkbox overlays — is implemented as `NSLayoutManager.drawBackground`/`drawGlyphs` overrides. All of that would need to be re-expressed against TextKit 2's fragment/decoration drawing model to move off TextKit 1.

### Verified TextKit 2 facts (from Apple, verbatim)

- WWDC22 (Session 10090): "In iOS 16, the UIKit transition to TextKit 2 is complete, with all text controls using TextKit 2 by default, including `UITextView`." On accessing `layoutManager`: "the text view replaces its `NSTextLayoutManager` with an `NSLayoutManager` and reconfigures itself to use TextKit 1." Fallback also triggers on "attributes not yet supported by TextKit 2, such as **tables**, or when **printing**." View-based attachments are "only possible with TextKit 2."
- WWDC21 (Session 10061): "Layout in TextKit 2 is always noncontiguous" — it lays out "only the portions of text that are visible on the screen, plus an additional over-scroll region." Confirmed components: `NSTextLayoutManager`, `NSTextContentStorage` (backed by `NSTextStorage`), `NSTextElement`, `NSTextLayoutFragment` (immutable), `NSTextViewportLayoutController`.
- Nuance worth keeping: the TextKit 2 classes *shipped* in iOS 15 / macOS 12, but `UITextView` did not adopt TextKit 2 by default until **iOS 16** (in iOS 15 only `UITextField` used it).

---

## 2. The performance problem, confirmed in the current code

The "re-styles the whole document on every keystroke" worry is **true for this codebase, and worse than first described.**

`MarkdownStyler.swift` (an `NSTextStorage` subclass) runs `processEditing()` on every edit cycle. It computes `full = NSRange(location: 0, length: backing.length)`, applies base attributes and live styling over the **whole document**, then deliberately calls `edited([.editedAttributes, .editedCharacters], range: full, changeInLength: 0)` to force full-document glyph + layout invalidation. And `invalidateForCursorChange()` does the same thing on **every cursor move**, not just on typing.

Because the editor is TextKit 1, there is also **no viewport-only layout** to bound the cost — the whole note re-lays out. So restyle is full-document per edit *and* per caret move, and layout is full-document too.

**The known fix** is to re-style only the edited paragraph range(s) instead of `0..length`, using `NSTextStorage`'s incremental hooks (`edited(_:range:changeInLength:)`, `processEditing()`, `editedRange`/`changeInLength`/`editedMask`, and the delegate `textStorage(_:didProcessEditing:range:changeInLength:)` — all real, iOS 7+ APIs).

**The catch, specific to Lists:** the current `MarkdownStyler` *already* overrides `processEditing` but throws away the edited range **on purpose** — its own comments say the full-document hammer was added to fix a sibling-glyph staleness bug. So the perf fix is not "start using `processEditing`." It is "stop force-expanding to full-doc and re-style only the affected paragraph(s)" — which requires solving the underlying glyph-invalidation bug another way. This is real, careful work, not a drop-in.

---

## 3. Tables

- **No native iOS attributed-string table primitive exists.** `NSTextTable` / `NSTextTableBlock` are **AppKit-only** (macOS 10.4+; documented under `developer.apple.com/documentation/appkit/nstexttable`); there is no UIKit equivalent. Craft confirms independently: "The Apple built in API can't create tables, because `NSAttributedString` on iOS is not supporting it." macOS does it via `NSTextTable`.
- **Craft's export workaround** (verbatim from their blog): convert their custom table representation to an **HTML table**, insert a unique token, run `NSAttributedString` HTML conversion, then replace the token with the real table content. (Useful precedent for *export*, not for in-editor rendering.)
- **`swift-markdown` does parse GFM tables.** Verified in-repo: `Sources/Markdown/Block Nodes/Tables/` contains `Table.swift`, `TableHead.swift`, `TableRow.swift`, `TableCell.swift`, `TableBody.swift`, `TableCellContainer.swift`. `public struct Table: BlockMarkup` with `public enum ColumnAlignment`. **Naming correction:** they are top-level types `TableHead` / `TableRow` / `TableCell` / `TableBody` — *not* dotted members `Table.Head` / `Table.Row` / `Table.Cell`.
- **In-editor rendering of a table-as-view** would use `NSTextAttachmentViewProvider` — which requires the TextKit 2 migration (see §1). Until then, a table can only be drawn manually (the AppKit primitive isn't available on iOS) or rendered as a non-editable preview.

---

## 4. Math

Three credible native paths, all verified, no web views required for two of them:

| Library | License / version | Engine | Strengths | Limits |
|---|---|---|---|---|
| **SwiftMath** (mgriebling) | MIT, v1.7.1 (2024-12-18) | CoreText/CoreGraphics → `UIView` (`MTMathUILabel`), **no WebView** | Lightest; "significantly faster than using a UIWebView"; ships 12 bundled math fonts (default Latin Modern Math); a full Swift port of iosMath | **Math-mode only**; missing some commands (`\middle`, fine spacing `\:` `\;` `\!`); active (263 commits, last release Dec 2024) |
| **iosMath** (kostub) | MIT, v2.2.0 (2026-05-16) | Native CoreText engine | The engine SwiftMath ports; **actively maintained** (corrects an earlier "date unknown" note) | Obj-C-era API surface; math-mode focus |
| **LaTeXSwiftUI** (colinc86) | MIT, v2.0.0 (2026-04-03), Swift 6, iOS 15+ | MathJaxSwift (MathJax) → SVG → rasterized image, **off the main thread**, dual SVG+image caches | Best correctness + **best accessibility**: inline (`$...$`, `\(...\)`) and block (`$$...$$`, `\[...\]`) plus environments (align/cases/matrix); VoiceOver via the Speech Rule Engine (SRE) producing natural-language descriptions | Heaviest of the three; relies on MathJax under the hood |

- **KaTeX accessibility is genuinely broken on iOS** (KaTeX issue #820, still **OPEN** as of 2026-05-30): visible math is `aria-hidden=true` and the MathML is visually hidden, so iOS VoiceOver touch-exploration can't focus equations; only linear swipe navigation reaches them. This supports preferring native SRE (LaTeXSwiftUI) over KaTeX-in-a-WebView.
- **Ranking:** SwiftMath = lightest, math-mode only; LaTeXSwiftUI = best correctness + a11y but heavier; **avoid a per-equation `WKWebView`.** Insertion into the editor again uses a view-based attachment, gated on the TextKit 2 migration.
- **Open:** real-world scaling of *many* inline equations in one editor is untested.

---

## 5. Drawing (PencilKit)

- **`PKDrawing` is confirmed and well-suited.** Available iOS 13.0+ / iPadOS 13.0+ / Mac Catalyst 13.0+ / macOS 10.15+ / visionOS 1.0+. It has `dataRepresentation()` and `init(data:)`, conforms to `Codable`, offers `image(from:scale:)`, exposes `strokes` (`[PKStroke]`), and `requiredContentVersion`. The serialization story is clean: a drawing round-trips to/from a `Data` blob.
- **Bear 2's sketcher** (Bear blog, 2023-10-04) is built on "Apple's PencilKit drawing tools," embedded inline and **re-editable**, saved "once you leave Edit Mode or switch to another note," with an expandable canvas (drag handle) and ruled/dots/grid backgrounds.
- **What Bear's blog does NOT say:** the on-disk serialization of a sketch (PKDrawing `Data` vs rasterized image vs both). The `.bearnote = textbundle-zip + assets/` detail comes from third-party reverse-engineering (mivok/bear_backup) + Bear's FAQ — treat the exact sketch payload format as **inferred**, not documented.
- **Reasonable architecture (inferred, not a Bear internal):** store the `PKDrawing` as a **sidecar asset referenced by id**, and embed either an editable canvas or a tappable raster preview as a view-based attachment / block.

---

## 6. Attachments (embedding views inside text)

- **`NSTextAttachmentViewProvider`** is the right mechanism. Apple docs confirm iOS 15.0+, with members `view`, `tracksTextAttachmentViewBounds`, `attachmentBounds(for:location:textContainer:proposedLineFragment:position:)`, and `loadView()`. The documentation ties it to coordination via `NSTextLayoutManager` — i.e. **TextKit 2**. WWDC22: live `UIView`/`NSView` text attachments are "only possible with TextKit 2." So this central mechanism for tables/math/drawings/images is correct, with the standing caveat that Lists must migrate off TextKit 1 to use it (§1).
- **TextKit 1 legacy path** (`NSTextAttachment.image` + `attachmentBounds`; community libs like `SubviewAttachingTextView`) is the older approach; Apple's first-party view providers are preferred on iOS 16+.
- **Vendor storage** ("Bear/Craft store attachments as binary assets referenced by id") is supported in spirit by Craft's per-block `NSAttributedString` model and Bear's `assets/` folder, but the precise storage is partly reverse-engineered — **inferred.**

---

## 7. Block-based architecture (the Notion model) + the performance payoff

- **Notion's data model** (blog, 2021-05-18, confirmed verbatim): every block = `id` (UUID v4) + `type` + `properties` + `content` (ordered array of child block ids) + `parent` (parent block id). "Everything you see in Notion is a block… even pages themselves." Transactional validation duplicates a "before" snapshot, applies ops to an "after" copy, and validates both before committing.
- **The corruption-isolation advantage** — "a malformed/weird block stays isolated and does NOT break parsing of everything downstream, unlike one bad fence or pipe re-framing the whole single-string lexer" — is **well-grounded reasoning, presented as inference, not a quoted vendor guarantee.** Notion documents block independence, id-referenced content, and snapshot validation; it does not literally say "a corrupt block won't corrupt rendering of later blocks." But the conclusion follows from the architecture: decoupled blocks are structurally more corruption-resistant than a monolithic Markdown string. (This directly addresses the "one bad file/section bricks the note" class of risk.)
- **Craft** (blog, 2024-05-15) converts **each block's** internal representation to `NSAttributedString` and exports plain text / Markdown / HTML / RTF via `registerDataRepresentation(forTypeIdentifier:...)` on `NSItemProvider`. So a block model **still uses `NSAttributedString` per block** — you don't throw away the rich-text engine, you scope it to a block.
- **`swift-markdown` AST** is "immutable/persistent, thread-safe, copy-on-write value types that only copy substructure that has changed" (like SwiftSyntax), confirmed on the official README. **But there is no first-party incremental re-parse API** in swift-markdown (confirmed absent as of v0.8.0). The COW tree gives cheap structural sharing, but you drive incrementality yourself by re-parsing the edited block/range.
- **Industry precedent** for incremental highlighting (tree-sitter/Lezer, CodeMirror 6, xi-editor) is correctly characterized. Obsidian-mobile (CodeMirror 6 in a WebView via Capacitor) is the **rejected contrast** given Lists' pure-native constraint.

**Why this matters for performance:** in a block model, an edit touches one block. You re-parse and re-style *that block* and re-lay-out *that block's* view — not the whole note. It is the cleanest, most durable version of the §2 fix, because the "only re-do the edited region" boundary is structural rather than something you carefully compute inside one giant `NSTextStorage`.

---

## Recommendations for Lists

1. **Treat the TextKit version as the central architectural fork.** Everything visual-and-embedded (math, tables, drawings, images) lives in TextKit 2. The editor is on TextKit 1 today. Decide deliberately *when* to migrate; don't drift into it.
2. **Do the performance fix before any feature work — but do it properly.** It is not a one-liner: it means undoing `MarkdownStyler`'s intentional full-document force-invalidation and solving the sibling-glyph staleness bug it masks. Prototype the scoped-restyle path and verify the bug stays fixed before shipping.
3. **For math, default to SwiftMath for the lightweight case and LaTeXSwiftUI when accessibility/correctness matter.** Both are MIT and native-friendly. Never embed a `WKWebView` per equation, and avoid KaTeX-in-a-WebView for anything VoiceOver users will touch (issue #820).
4. **For drawings, use PencilKit and store the `PKDrawing` as a sidecar file** referenced from the note — this is also the key to keeping the "plain Markdown you own" promise (see below).
5. **For tables, set expectations:** they are the most hand-built feature because Apple gives iOS nothing. `swift-markdown` locates and parses them; rendering is yours. Keep Craft's HTML-token trick in your back pocket for *export*.
6. **Adopt the block model as the destination, not the first step.** It is the right long-term answer for robustness, performance, and embedding — but it is the deepest change. Stage toward it.

---

## RECOMMENDED DIRECTION for Lists

### The storage promise, made concrete

The core promise is "plain Markdown files you own." Non-text content does **not** break that — it gets externalized:

- A note stays a human-readable `.md` (or `.list.yml` per the current model) text file.
- A **drawing** is written as a sidecar file in a sibling folder, e.g. `assets/<uuid>.drawing` (the `PKDrawing.dataRepresentation()` blob) — optionally with a rendered `assets/<uuid>.png` for previews and for any reader that can't open the drawing format. The note references it with an ordinary Markdown image embed: `![sketch](assets/<uuid>.png)` or a link to the editable blob.
- An **image / attachment** is a file in `assets/`, embedded via standard Markdown `![]()`.
- A **table** is *already* plain text — GFM pipe tables — so it serializes natively with zero special handling.
- **Math** is plain text too — `$...$` / `$$...$$` LaTeX — so it also serializes as-is.

This is the **textbundle pattern** (note text + `assets/` folder), the same shape Bear and others converge on. The note remains openable and diff-able in any text editor; the binary blobs sit beside it. The "files you own, no lock-in" promise is preserved because the only non-text artifacts are standard image/drawing files referenced by relative path.

### How it stays robust/containerized like Notion

The robustness comes from **block decoupling**. If the note is a sequence of independent blocks (each a small text run, table, drawing reference, or math run), then a malformed block degrades to a visible "couldn't render this block" placeholder while every other block renders fine. A monolithic single-string parser, by contrast, lets one bad fence or pipe re-frame the lexer for everything after it. (This is reasoned inference from Notion's documented block-independence + snapshot-validation, not a quoted guarantee — but it is sound, and it directly targets the "one bad section bricks the note" failure mode.) Crucially, the on-disk format can *still be plain Markdown*: blocks are an in-memory/runtime structure, with Markdown as the serialization. You get containerization at runtime without giving up the text file on disk.

### The three architecture options

#### Option A — Incremental hardening on TextKit 1 (smallest change)

Keep the current single `UITextView` + custom `NSLayoutManager`. Fix the perf hammer (scoped restyle). Add images/drawings via the **legacy TextKit 1 attachment path** (`NSTextAttachment.image` + a tap to open a full-screen PencilKit/preview editor — *not* a live in-line editable canvas). Store drawings/images as `assets/` sidecars now. Tables and math render as **non-editable previews** (tap to edit in a sheet), or stay as raw text.

- **Pros:** No migration. Delivers the storage convention and the perf win — the two highest-value, lowest-risk wins — quickly. Doesn't disturb the existing custom rendering.
- **Cons:** No *inline live* views (no in-place editable drawing, no inline-rendered math/tables in the flow) — those need TextKit 2. Perf is still bounded by full-document layout (TextKit 1 has no viewport-only layout), so very long notes stay a concern even after scoped restyle. You're investing in an engine Apple has already moved past.

#### Option B — Migrate the single editor to TextKit 2 (medium change)

Move the existing `UITextView` to TextKit 2: stop touching `layoutManager`, re-express the custom code-block panels / inline-code pills / horizontal rules / checkbox overlays as TextKit 2 fragment/decoration drawing, and adopt `NSTextAttachmentViewProvider` for **live, inline** math, tables, drawings, and images. Keep one text storage for the whole note.

- **Pros:** Unlocks the modern feature set (live embedded views) *and* viewport-only layout (the real fix for long-note performance — only on-screen text lays out). Stays "one editor," conceptually close to today.
- **Cons:** The migration is a genuine project: all current `NSLayoutManager` draw overrides must be rebuilt against TextKit 2's model, which is different in shape (immutable layout fragments, viewport controller). Cost is **unquantified** and would need a spike. Restyle is still scoped by hand inside one `NSTextStorage` — better than today (viewport layout helps), but not as clean as per-block isolation. Corruption is still document-wide at the parse layer unless you also segment.

#### Option C — Block model (deepest change)

Render the note as a `UICollectionView` (diffable data source, iOS 13+) of blocks, each block its own small TextKit 2 `UITextView` or a specialized view (table, drawing, math), composed via `UIHostingConfiguration` (iOS 16) where SwiftUI helps. Markdown stays the on-disk serialization; blocks are the runtime structure. `swift-markdown` parses the file into block AST nodes; each block re-parses/re-styles independently.

- **Pros:** Best on every axis that matters here — **performance** (edit touches one block; the "only re-do the edited region" boundary is structural, and off-screen blocks aren't even laid out), **robustness** (a bad block is an isolated placeholder, Notion-style), and **embedding** (a drawing/table/math block is just a different cell — no attachment gymnastics inside a giant text run). Maps cleanly to the `assets/`-sidecar storage model. Matches how Notion and Craft actually build.
- **Cons:** The largest re-architecture. Cross-block behavior that's free in one text view becomes work you implement: selection spanning blocks, cursor moving between blocks, copy/paste across blocks (Craft wrote a whole blog about how hard cross-app paste is), find-in-note, undo across blocks. swift-markdown has **no incremental re-parse API**, so you drive block-level incrementality yourself (cheap, since blocks are small). It's a multi-milestone effort.

### Recommendation

**Stage A → B → C, and only commit to each stage when the prior one's value is banked.**

1. **Now (small adds, do regardless of long-term direction):** Ship the **scoped-restyle performance fix** (carefully, per §2) and the **`assets/`-sidecar storage convention** for images and PencilKit drawings, opened via a full-screen editor. This delivers the two highest-leverage wins — speed and the ability to own embedded content as plain files — *without* betting on a migration. Both survive whatever architecture you land on.
2. **Next (a contained spike, not a commitment):** Prototype **one** TextKit 2 capability on a throwaway branch — most likely an inline editable PencilKit attachment — to *measure* the migration cost of re-expressing the custom drawing overrides and to test the open risks (many live attachments in one view; LaTeXSwiftUI VoiceOver quality on-device). This converts the biggest unknown into a number before you spend on it.
3. **Eventually (the destination):** Adopt the **block model (Option C)** as the structural answer to performance, robustness, and embedding — but enter it deliberately, milestone-scoped, with the cross-block behaviors (selection, paste, undo, find) explicitly planned. It is where Notion and Craft live for good reasons, and it is the cleanest home for tables/math/drawings as first-class blocks while keeping plain Markdown on disk.

**Why not jump straight to C?** Because the two things that hurt today — slowness and the lack of an owned-file convention for embedded content — are fixable in Stage 1 at a fraction of the cost, and because the migration cost (Stage 2's whole point) is currently *unquantified*. Buy the cheap wins, measure the expensive one, then commit.

---

## Planned extensions roadmap (syntax additions)

*Added 2026-06-14. This is the **syntax-extension** companion to the architecture work above: which widely-accepted markdown extensions to add, and where each plugs in. **Core markdown stays exactly as-is — these are additive.** Several are already detected by the parser (`Features/MarkdownEditor/ExtensionParsers.swift`) and even inserted by the toolbar; they just don't render or navigate yet, so much of this is "finish what's half-built," not "start from scratch."*

*Guiding constraint (from §1): live **inline** embedding (tables, rendered math) is gated on the TextKit 2 / block-model migration. So ship **read-only rendering first** (via `MarkdownBodyView` + MarkdownUI) and keep live in-editor rendering out of the current scope.*

### 1. Finish the already-parsed set

| Extension | Status today | Plan |
|---|---|---|
| **Wikilinks** `[[Page]]` / `[[Page\|alias]]` | parsed (`ExtensionParsers.wikilinkRanges()`); toolbar inserts; not navigable | resolve the target item and make it tappable → navigate to that item |
| **Footnotes** `[^id]` + `[^id]: …` | parsed (`footnoteRefRanges()` / `footnoteDefRanges()`); not rendered | render refs/defs in the read-only view |
| **Math** `$…$` / `$$…$$` | parsed (`mathInline/DisplayRanges`); not rendered | render read-only via a native lib (SwiftMath / LaTeXSwiftUI per §4 — **never KaTeX-in-WebView**) |
| **Mermaid** (`mermaid` fenced block) | parsed (`mermaidBlockRanges()`); not rendered | render diagrams in the read-only view |
| **GFM tables** | already render read-only in MarkdownUI; toolbar inserts a template | keep; live inline editing stays out of the current scope (§3) |

### 2. Callouts / admonitions

`> [!NOTE]`, `> [!WARNING]`, `> [!TIP]`, etc. — styled blockquote variants (Obsidian / GitHub convention). New detector in `ExtensionParsers.swift` + a live attribute in `MarkdownStyler.swift`, plus a MarkdownUI theme treatment for read-only.

### 3. Live tag styling + autocomplete

Today `#tags` are only extracted to item metadata on save (`Tag.extractInline` in `Core/Tags/Tag.swift`) — they look like plain text while typing. Plan: colour `#tags` inline in the editor (new live attribute in `MarkdownStyler.applyLiveStyling`) and offer autocomplete sourced from existing tags. Makes tags feel first-class, matching other workspace apps.

### 4. Syntax-highlighted code blocks

Fenced code blocks already parse their language hint (e.g. a block tagged `swift`). Plan: language-aware colouring inside the fence — in the live editor's code-block rendering (`MarkdownLayoutManager` draw path) and/or the read-only MarkdownUI theme. The most overtly "developer-friendly" touch.

### Reuse map (for whoever builds this)

- **Detect syntax:** `Features/MarkdownEditor/ExtensionParsers.swift` (regex detectors)
- **Live styling:** `MarkdownStyler.swift` (`applyLiveStyling`)
- **Custom draw:** `MarkdownLayoutManager.swift` (`drawBackground` / `drawGlyphs`)
- **Toolbar (already wired for the half-built set):** `ToolbarAction.swift` + `MarkdownReminderToolbar.swift`
- **Read-only render:** `MarkdownBodyView.swift` (MarkdownUI / cmark-gfm)
- **Tags:** `Core/Tags/Tag.swift` (`Tag.extractInline`)

---

## Sources

- **Meet TextKit 2 — WWDC21 Session 10061** — https://developer.apple.com/videos/play/wwdc2021/10061 — 2021 (WWDC21) — [official], high
- **What's new in TextKit and text views — WWDC22 Session 10090** — https://developer.apple.com/videos/play/wwdc2022/10090 — 2022 (WWDC22) — [official], high
- **NSTextAttachmentViewProvider — Apple Developer Documentation** — https://developer.apple.com/documentation/uikit/nstextattachmentviewprovider — current (verified 2026-05-30) — [official], high
- **NSTextStorage — Apple Developer Documentation** — https://developer.apple.com/documentation/uikit/nstextstorage — current — [official], high
- **PKDrawing — Apple Developer Documentation** — https://developer.apple.com/documentation/pencilkit/pkdrawing — current (verified 2026-05-30) — [official], high
- **NSTextTable — Apple Developer Documentation (AppKit, macOS-only)** — https://developer.apple.com/documentation/appkit/nstexttable — current — [official], high
- **Exploring Notion's Data Model: A Block-Based Architecture** — https://www.notion.com/blog/data-model-behind-notion — 2021-05-18 — [secondary], high
- **The Challenges of Cross-App Copy-Paste and Our Solutions (Craft)** — https://www.craft.do/blog/the-challenges-of-cross-app-copy-paste-and-our-solutions — 2024-05-15 — [secondary], high
- **How and why to use the new sketcher in Bear 2** — https://blog.bear.app/2023/10/how-and-why-to-use-the-new-sketcher-in-bear-2/ — 2023-10-04 — [secondary], high
- **swift-markdown — GitHub (swiftlang)** — https://github.com/swiftlang/swift-markdown — v0.8.0, 2026-05-07 — [official], high
- **SwiftMath — GitHub (mgriebling), MIT** — https://github.com/mgriebling/SwiftMath — v1.7.1, 2024-12-18 — [secondary], high
- **iosMath — GitHub (kostub), MIT** — https://github.com/kostub/iosMath — v2.2.0, 2026-05-16 — [secondary], high
- **LaTeXSwiftUI — GitHub (colinc86), MIT** — https://github.com/colinc86/LaTeXSwiftUI — v2.0.0, 2026-04-03 — [secondary], high
- **KaTeX — official site** — https://katex.org/ — current — [official], high
- **VoiceOver can't read KaTeX's hidden MathML — KaTeX Issue #820** — https://github.com/KaTeX/KaTeX/issues/820 — open (verified 2026-05-30) — [official], high
- **Lists codebase — `platforms/ios/Lists/Features/MarkdownEditor/`** — 2026-05-30 (dev branch) — [official/primary], high

---

## What couldn't be confirmed

- **Bear's exact on-disk serialization of an inline PencilKit sketch** (PKDrawing `Data` vs rasterized image vs both) is not documented by Bear; only "built on PencilKit" is confirmed. The `.bearnote = textbundle-zip + assets/` detail is third-party reverse-engineering (mivok/bear_backup) + FAQ, not from the sketcher blog.
- **No first-party incremental re-parse API in swift-markdown** (confirmed absent as of v0.8.0). The COW AST gives structural sharing, but incrementality must be driven manually by re-parsing the edited block/range.
- **Real-world performance of many `NSTextAttachmentViewProvider` live views** in one `UITextView` (e.g. dozens of inline equations) is not specified by Apple — needs an on-device prototype.
- **On-device VoiceOver quality of LaTeXSwiftUI's SRE descriptions vs KaTeX MathML** on current iOS (2026) is undocumented — should be tested, not assumed.
- **Craft's / Bear's exact prose-block vs many-block boundary** (how much text lives in a single rich-text block) is inferred from blogs, not a published internal spec.
- **Lists-specific:** removing `MarkdownStyler`'s intentional full-document force-invalidation (the perf fix) requires solving the original sibling-glyph staleness bug it was added to mask; the safe scoped-restyle approach for this exact code path is unverified and needs prototyping.
- **A full TextKit 2 migration cost for Lists is unquantified:** the current custom rendering (code-block panels, inline-code pills, horizontal rules, SF-Symbol checkbox overlay) is implemented as `NSLayoutManager` draw overrides and would need re-implementation against TextKit 2 fragment/decoration drawing.
