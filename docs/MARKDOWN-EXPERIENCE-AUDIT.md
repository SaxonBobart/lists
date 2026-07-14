# Markdown Experience Audit

Updated: 14 July 2026

This audit compares Lists with the interaction patterns that make Bear, Apple
Notes, Obsidian, and Craft feel approachable despite supporting complex
documents. It now also records the implementation delivered from the audit.

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

## Document links — implemented

Lists keeps stable item identity in document frontmatter while using portable,
human-readable Markdown paths for links. This preserves reliable in-app
navigation without making exported documents depend on a Lists-only URL scheme.

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

Implemented Lists treatment:

- Render an internal link as restrained accent text on the normal text baseline.
  It never becomes a full-width card and can share a line with surrounding text.
- Store relative Markdown destinations such as
  `[Project notes](Project%20notes.md#Decisions)`. App-managed item/list renames
  rewrite inbound paths, while stable frontmatter ids continue to identify files
  internally. Legacy Lists URLs are still resolved and converted on load.
- The toolbar returns to Lists' established browse-in-place destination mode.
  The bottom shelf preserves context while navigating; choosing an item with
  headings turns that shelf into a compact whole-item or heading chooser.
- In Live Markdown, links are accent-colored underlined words on the normal text
  baseline. Tapping follows the destination even while editing. Moving the caret
  into a link reveals the complete `[label](destination)` source for manual
  editing; moving away hides it. Raw Markdown always shows literal source.
- Heading targets are stored as URL fragments on relative document paths.
  Opening one scrolls the destination without forcing its keyboard open.
- Incoming links appear beside outgoing links in the existing navigator.
- Insertion uses the captured source selection and never forces the link onto a
  new line.

## Images and attachments — implemented foundation and primary flows

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

Implemented behavior:

1. Files live under `Documents/Lists/Attachments/` with UUID filenames, atomic
   writes, root-confined resolution, ZIP export inclusion, and focused recovery
   tests. Unreferenced files move to a recoverable quarantine instead of being
   destroyed.
2. Markdown stores only portable `Attachments/<uuid>.<ext>` destinations.
3. The image toolbar action offers Photo Library, available Camera, document
   scanner, and Files. Pasted and dropped images use the same importer.
4. Local images render inline as stable rounded media and reveal their source
   only while editing that line. Files and images open through Quick Look.
5. Remote images remain blocked by default; external cards do not fetch remote
   metadata implicitly.

## Apple Pencil, drawing, and canvas — parked

Lists currently has no drawing or canvas creation surface. The PencilKit,
PaperKit, and unified canvas experiments were removed from `dev` after runtime
evaluation and preserved under the `archive/canvas-experiment-2026-07-14` tag.
Ordinary images, files, scans, inline previews, and Quick Look remain supported.
Any future drawing work should begin from the archived evidence and re-enter the
product only after its document behavior and interaction model are settled.

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
  images, or attachments.
- Accessible table cell labels (for example “Row 2, Column Status”), VoiceOver
  actions for row/column operations, Dynamic Type stress coverage, and keyboard
  commands for insert link/table and row/column navigation.

## Delivered sequence

1. Tables and their visual/interaction contracts.
2. Semantic internal links, heading targets, and backlinks.
3. Attachment storage, export, quarantine, and restoration.
4. Photos, paste/drop, files, scanner, inline rendering, and Quick Look.

Still intentionally deferred: proprietary block IDs, automatic network metadata
fetching, risky automatic orphan deletion, and drawing/canvas creation.
Drag/drop should be added only after driven gesture testing proves it does not
steal text selection or scroll.

This order deliberately puts data durability ahead of attractive attachment
UI. Tables and links can remain pure Markdown; images cannot be safe until their
files participate in backup, export, deletion, and recovery.
