# Markdown audit — 12 September 2026

Scope: the current iOS editor, read-only Markdown rendering, table editing,
clipboard operations, and local attachments. Preserve the existing editor design,
ordinary Markdown storage, and calendar/list behavior. This is a correctness and
interaction audit, not a claim of complete CommonMark conformance.

## Fixed

| Area | Defect and correction |
| --- | --- |
| Unicode | Minimal text replacements could split surrogate pairs or composed characters. Diff boundaries now follow whole Swift characters while comparing exact UTF-16 spelling. Backspace and source-column movement also preserve whole characters. |
| Arrow keys | Live prose and wrapped list paragraphs used source-line jumps, skipping visible wrapped lines. UIKit now handles those movements; custom content-column tracking remains only for short marker transitions that need it. |
| Raw Markdown | Live table atomic selection/deletion and hidden list-marker snapping affected raw source. Raw editing now keeps those characters directly editable. |
| Code examples | Table detection, live/read-only styling, Mermaid detection, links, attachments, and prose assistance disagreed about top-level backtick/tilde fences, marker lengths, or unfinished fences. They now share fence detection. Nested shorter fences remain literal. |
| Literal paste | Structured paste could turn code examples into tables/links and replace tabs with spaces. Raw/code paste retains tabs and only normalizes BOM/newline spelling. Prose keeps the existing smart paste behavior. |
| Fence boundaries | The empty paragraph after a closed fence ending in a newline was mistaken for code. Closed and unfinished fences now have distinct EOF behavior. |
| Checklists | Tapping empty space below the final task, or a wrapped continuation line, could toggle it. Hit testing now requires the visible checkbox. |
| Inline file links | Y-only hit testing opened the first attachment when tapping prose or another file on the same line. Each label now uses its own glyph bounds. |
| Ordered lists | An extremely large numbered marker could overflow during Return continuation. Detection accepts one to nine ASCII digits consistently. |
| Tables | Fenced examples could become editable tables; mismatched header/divider widths were accepted; structural edits lost backslashes before escaped pipes. Literal examples remain text, malformed delimiters are rejected, and cell contents round-trip. |
| Table writing | A cell measured text within its old height, clipping the next line and shrinking its caret after Return. Cell text containers now keep width tracking with unrestricted vertical layout, and measurement includes the empty insertion line. Rows grow with typed text while caret reveal preserves focus. Return stays inside the cell; Tab remains cell navigation. |
| Undo after layout | Visual restyling falsely announced character changes, causing UIKit to clear the document's Undo history. Styling now announces attribute changes and explicitly invalidates glyphs; actual text edits retain their character-change notifications. |
| Inline syntax | Escaped emphasis was interpreted as formatting; multi-backtick code was paired as single-backtick spans. Escaped delimiters stay literal and code spans use matching run lengths without crossing fenced blocks. |
| Attachment references | Escaped closing brackets in labels were rendered but missed by the lifetime/clipboard index. Reference parsing is shared; display labels decode escapes without accumulating backslashes when renamed. |
| Attachment clipboard | Restoring files could replace matching text in prose/code, and paste into differently nested lists left wrong relative paths. Only actual attachment destination ranges change, rebased to the destination document. |
| Attachment files | File import could retain external symlink dependencies or accept directories. Imports copy regular-file contents; lookup/recovery reject directories and symlink redirection outside managed storage. |
| Media refresh | Image-to-link/path changes could retain a stale thumbnail or accept an older asynchronous load. Presentation reloads and checks cancellation before publishing an image. |
| Copy As | Invalid selection ranges could overflow before validation. Bounds are checked without overflowing. |

No attachment-format migration, library reset, remote fetching, new dependencies,
or Xcode project regeneration was needed.

## Verification

Toolchain: Xcode 27 beta 6, iOS 27 simulator, existing iOS 26 deployment target.
The regular iPhone 17 Pro simulator was used; its library was backed up before
interaction. A local archive tag preserves the starting revision `755547b`.

The broad focused regression run passed all 207 reported results with no failures
or skipped tests. It covered attachment storage/recovery, whole-item clipboard,
minimal diffs, table editing, editor interactions, callouts, paste, Copy As, and
all six existing Markdown snapshots (light, dark, larger text, tables, and remote
image suppression).

The new window-backed table check uses native text insertion in header and body
cells. It verifies `<br>` source, stable table structure, growing height, visible
caret, preserved focus, and document Undo/Redo after forced layout/restyling.
Separate checks cover actual cached sibling glyph regeneration and native arrow
command handling for wrapped paragraphs. The live Return-then-type reproduction
additionally exposed the cell text-container height feedback loop; the final
regression checks inserted text, long-line wrapping, and visible glyph/caret
geometry after layout. After that fix, all 68 selected table, interaction, history,
and Markdown snapshot checks passed again. The final simulator build succeeded
without warnings. A subsequent mounted SwiftUI document test also passed native
prose typing, the published More-menu Undo state, Undo/Redo, and binding/source
restoration with headings, a checklist, and a table in the same document. No
additional production change was needed for that check.

Live simulator checks confirmed cell selection and the matching row/column
controls, Return followed by visible second-line typing in both header and body
cells, row growth, retained focus, and caret clearance above the formatting bar.
The document More menu restored each test edit through Undo. The saved note body
matched its pre-test backup afterward; only its modification timestamp changed.
Ordinary prose typing and Return were also visibly confirmed. Subsequent More-menu
automation became unreliable during the prose Undo check; that interaction is not
claimed as a completed live check. The known temporary prose edit was removed with
the app stopped after verifying the exact diff against the backup. Existing
diagram/image rendering and a native PDF preview were also inspected.

## Attachment recommendation

Keep the existing plain-file model:

```text
Lists/
  Work/
    Meeting.md
  Attachments/
    <stable-id>.png
    <stable-id>.pdf
```

Markdown uses ordinary relative links. The app owns the physical filenames and
path maintenance; users name attachments through their Markdown descriptions.
The sidebar continues to show lists and items, not loose asset files. Images
appear inline; PDFs, audio, video, and other files use named attachments with
native viewing/playback. The existing Document Navigator Attachments tab provides
an on-demand index of the current document's files.

This is already mostly implemented. Storage and sidebar presentation are
separate choices, so avoiding sidebar clutter does not require a bundle format.

Recommended next product work, pending Saxon's decision:

- Polish the document's attachment browser rather than adding permanent sidebar
  entries for every file.
- Add a single-document **Markdown with attachments** export: a ZIP containing an
  ordinary `.md` file and its referenced assets with rewritten relative links.
  Full-library ZIP export already includes the files. Copying Markdown text alone
  cannot transport attachment bytes into another app; whole-item Lists clipboard
  does preserve them.
- Keep removing a reference separate from deleting a file. Shared references,
  recently deleted documents, and orphan recovery must remain safe.

The likely format referred to in the conversation is TextBundle. Its package
contains separate `text.*`, `info.json`, and `assets/` entries; it does not embed
image bytes inside Markdown itself. It could be an optional interchange format,
but is unnecessary as Lists' canonical storage. Source:
[TextBundle specification](https://textbundle.org/spec/).

## Remaining limits and follow-up

- The custom Markdown parser is not a complete CommonMark parser. Four-space
  indented code and fences nested inside blockquote/list containers still need a
  dedicated consistency pass across live styling and semantic rendering. The
  current fence corrections cover top-level fences, including up to three spaces
  of indentation.
- Whole-item clipboard payloads load attachment bytes into memory. Very large
  video collections need measured memory testing and potentially a streaming
  payload design; no arbitrary size limit was added in this pass.
- Real microphone/camera/scanner permissions and interruption recovery require
  physical-device QA. Existing tests do not establish those flows as newly
  verified on a phone.
- Hardware arrow behavior through wrapped prose, live list continuation, prose
  Undo through the More menu, and difficult table range-drag gestures need further
  responsive live verification; source-level tests are not a substitute for
  their visual behavior.
