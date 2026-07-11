# Markdown Experience Audit

Updated: 12 July 2026

This audit compares Lists with the interaction patterns that make Bear, Apple
Notes, Obsidian, and Craft feel approachable despite supporting complex
documents. It is a product-direction record, not an implementation commitment.
Only the table work described below was implemented during this audit.

## Product direction

Lists should keep Markdown as the durable, portable source of truth while
making common structures feel like native document objects. Syntax should
appear when it helps someone edit a structure, then recede without causing the
content to move. Advanced features should be discoverable through the keyboard
toolbar and contextual menus, but every document must remain useful as plain
text outside Lists.

Three patterns recur in the strongest reference apps:

1. **Fast syntax and direct manipulation coexist.** Bear and Obsidian retain
   Markdown or wikilink syntax, but autocomplete, context menus, and rendered
   objects remove the need to manipulate punctuation for routine edits.
2. **Objects remain in the writing flow.** Apple Notes tables, drawings, scans,
   and note links are inserted at the cursor and edited in place rather than in
   a separate document-management mode.
3. **Navigation is semantic.** A document link is not merely blue text. It has
   identity, survives title changes, exposes previews/backlinks, and can target
   a heading or block.

## Tables — implemented in this pass

Reference behavior:

- [Apple Notes tables](https://support.apple.com/en-ca/guide/icloud/mm1aa627ae18/icloud)
  start at 2×2, expose a handle to the left of a row and above a column, and add
  a row when Tab/Return is pressed in the final cell.
- [Bear tables](https://bear.app/faq/how-to-use-tables-in-bear/) keep a bold
  header row, use contextual row/column controls, and can be copied as CSV,
  HTML, or Markdown.

Lists already had the right technical foundation: portable GFM source, escaped
pipes, alignment markers, multiline cell encoding, equal-width mobile columns,
row/column menus, and Tab navigation. This pass keeps that representation and
adds the missing interaction polish:

- A stable leading handle gutter, so focusing a cell never shifts or narrows
  the table.
- One continuous 10-point rounded table surface with a subtle border, clipped
  grid, distinct header fill, and semibold header text.
- A subtle accent selection state for the active cell.
- Move Row Up/Down and Move Column Left/Right actions, with invalid boundary
  actions disabled.
- Copy as Markdown and Copy as CSV actions.
- Identical corner radius and cell padding in live editing and read-only
  rendering.
- Normalized read-only row widths for imperfect but parseable Markdown input.

The next table improvement should be drag reordering from the existing handles,
but only after driven interaction proves that it does not interfere with text
selection or vertical document scrolling. Column resizing is intentionally not
recommended on iPhone: fixed equal-width columns and wrapping are more
predictable in a narrow editor. A future iPad layout can reassess resizing.

## Document links

Current Lists behavior has the important data property already: internal links
target a stable item identifier rather than depending on a title. The weak point
is presentation and creation.

Reference behavior:

- [Bear wikilinks](https://bear.app/faq/how-to-link-notes-together/) autocomplete
  after `[[`, support aliases and heading targets, work from a hardware
  keyboard, and remain live after a title changes.
- [Apple Notes links](https://support.apple.com/en-gb/guide/iphone/iph908d1558b/ios)
  can use the target note title or custom text and can be inserted by typing
  `>>`.
- [Obsidian internal links](https://obsidian.md/help/links) autocomplete notes,
  headings, and blocks, distinguish unresolved destinations, and optionally
  update links after renames.

Recommended Lists treatment:

- Render an internal link inline as a compact document token: small document
  glyph, title or alias, and a restrained accent tint. It should sit on the text
  baseline rather than becoming a full-width card.
- Keep `lists://item/<stable-id>` in the Markdown destination. Render the live
  title when no custom label was supplied; retain custom labels verbatim.
- Open a unified picker from the toolbar, `[[`, and optionally `>>`. Search
  titles first, then expose headings after selecting a document.
- Tapping the glyph opens the destination. Long-press offers Preview, Open,
  Copy Link, Edit Display Text, and Remove Link. A broken target gets an
  explicit muted warning treatment instead of silently becoming a web link.
- Add heading anchors before block-level links. Heading targets are portable
  and understandable; proprietary block IDs should wait for a demonstrated
  use case.
- Surface backlinks in the existing document navigator rather than adding
  another persistent panel.

## Images and attachments

The current image toolbar action inserts a `![alt](path)` placeholder and image
paste is explicitly deferred in the editor. It should not be cosmetically
enhanced until Lists has a durable attachment model.

Reference behavior:

- [Bear attachments](https://bear.app/faq/insert-attachments/) insert photos and
  files from the iOS keyboard, show image/PDF previews, and use Quick Look for
  other files.
- [Obsidian attachments and embeds](https://obsidian.md/help/attachments) treat
  attachments as ordinary files and support paste, drag and drop, and inline
  embedding. [Its embed model](https://obsidian.md/help/embeds) also supports
  images, PDFs, audio, and linked note content.
- [Apple Notes](https://support.apple.com/en-us/118442) combines photos, video,
  scans, drawings, and web links in the same note flow.

Recommended implementation order:

1. Create a local-first attachment store under the existing Lists data
   directory. Use UUID filenames, atomic writes, reference counting or a safe
   orphan collector, export inclusion, and recovery coverage before UI work.
2. Store portable relative Markdown destinations such as
   `Attachments/<uuid>.<ext>` rather than absolute sandbox paths.
3. Replace the image placeholder action with a menu for Photo Library, Camera,
   Scan Document, Draw, and Choose File. Use `PhotosPicker`/Transferable for the
   library and the system document scanner for scans.
4. Render local images inline with a continuous corner radius, aspect-fit
   sizing, useful alt text, and a context menu for caption, replace, save, copy,
   Quick Look, and remove.
5. Add file cards for PDFs and other documents only after image persistence and
   export are proven. Never fetch remote images implicitly; retain the current
   privacy boundary unless the user explicitly chooses to load one.

## Apple Pencil and drawing

Drawing is a strong fit for Lists documents, but it should be an attachment
type rather than a second note-storage system.

Apple’s current stack makes [PaperKit](https://developer.apple.com/documentation/paperkit/getting-started-with-paperkit)
the best new implementation target. `PaperMarkupViewController` persists
structured shapes, images, text boxes, and PencilKit drawing data together.
[PencilKit's `PKCanvasView`](https://developer.apple.com/documentation/pencilkit/pkcanvasview)
remains the freehand ink surface and handles Apple Pencil input, scrolling, and
the system tool picker.

Recommended Lists design:

- “Draw” inserts a drawing attachment at the cursor and opens a full-screen
  PaperKit editor with the system tool picker.
- Persist the editable PaperMarkup representation plus a generated preview.
  The note embeds the preview through the same attachment path used by images.
- A tap selects the drawing; a second tap or Edit action reopens it. Outside
  edit mode it behaves like an image, including resize and Quick Look/export.
- Pencil double-tap/squeeze and Scribble should retain system behavior. Lists
  should not build a custom brush palette or handwriting recognizer before the
  native experience has been evaluated.
- Export should include both a universally viewable image and the editable
  sidecar, so drawings never become inaccessible if Lists is unavailable.

## Other Markdown experience findings

### High value

- **Paste intelligence:** selected text + pasted URL should become a titled
  link; spreadsheet cells should become a GFM table; pasted images should enter
  the attachment pipeline. Bear already uses these low-friction transforms.
- **Heading navigation:** keep the existing outline and add link-to-heading
  creation. Folding headings is useful later, but it must not hide scheduled or
  task content in ways that confuse Lists' other views.
- **Link preview on demand:** external links can offer a compact preview toggle,
  but fetching metadata must be explicit and cached because Lists is local-first
  and currently blocks remote image loading for privacy.
- **Consistent live syntax:** entering a formatted line reveals only the syntax
  needed to edit that line; leaving it restores the rendered object without
  changing its geometry. This should remain a regression contract for headings,
  lists, quotes, callouts, links, tables, code, math, and footnotes.

### Valuable after attachments and links

- Document/heading drag and drop, including dragging a Lists item into a note
  to create an internal link.
- Quick Look for PDFs and files.
- Copy As Markdown, rich text, and plain text for a selection or document.
- Search filters for documents containing links, backlinks, tables, tasks,
  drawings, images, or attachments.
- Accessible table cell labels (for example “Row 2, Column Status”), VoiceOver
  actions for row/column operations, Dynamic Type stress coverage, and keyboard
  commands for insert link/table and row/column navigation.

## Recommended sequence

1. Finish validating the table work and protect it with focused visual and
   interaction coverage.
2. Redesign internal links as inline semantic tokens and add heading targets.
3. Build the attachment storage/export contract before adding picker UI.
4. Add images, paste/drag/drop, scanner, and Quick Look.
5. Add PaperKit drawings on top of the proven attachment contract.
6. Add backlinks, richer paste transforms, and optional external-link previews.

This order deliberately puts data durability ahead of attractive attachment
UI. Tables and links can remain pure Markdown; images and drawings cannot be
safe until their files participate in backup, export, deletion, and recovery.
