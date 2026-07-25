# Lists Roadmap

Updated: 25 July 2026

This is the current execution handoff for new engineering threads. Durable
product behavior belongs in `PRODUCT-SPEC.md`; detailed Markdown findings and
reference-app research belong in `docs/MARKDOWN-EXPERIENCE-AUDIT.md`.

## Current checkpoint

The interactive Markdown-table milestone is complete at `097d0b2`:

- Tables behave as live document objects while retaining portable GFM source.
- Rows and columns support direct handle-based selection, contiguous range
  selection, context menus, and animated reordering.
- Multiline cells use TextKit measurement, keep the active caret visible, and
  grow only their containing row.
- Table cells support live inline Markdown for bold, italic, strikethrough,
  inline code, highlight, links, wikilinks, and inline math.
- Cell formatting uses the normal formatting and link flows in an inline-only
  mode; unsupported block actions stay unavailable.
- Raw mode remains literal Markdown.
- Paste intelligence supports URL-over-selection and rectangular TSV-to-GFM
  table conversion with one-step native Undo.
- Copy As exports either the active editor selection or the whole Markdown body
  as exact Markdown, semantic rich text, or rendered plain text. Existing
  table-specific Markdown and CSV copy actions remain in place.

Table work should now be treated as a protected interaction baseline. Further
changes should fix demonstrated defects or deliberately extend the product,
not redesign the interaction model incidentally.

## Next

### 1. Document and heading drag-to-link

- Drag a Lists document into an editor to create an internal Markdown link.
- Allow a heading to be the link destination.
- Preserve stable document identity, portable relative paths, heading
  fragments, and rename behavior.
- Validate the complete drag gesture and insertion result in the running app
  before considering the feature complete.

### 2. Search filters

Add discoverable filters for documents containing:

- Links or backlinks.
- Tables.
- Tasks.
- Images or other attachments.

Filters should build on the existing local document index and remain useful
offline.

### 3. Accessibility and keyboard polish

- Give table cells semantic row and column labels.
- Add VoiceOver actions for supported row and column operations.
- Stress-test table and Markdown layouts with Dynamic Type.
- Add hardware-keyboard commands for links, tables, and row/column navigation
  where they match the visible interaction model.
- Verify focus, selection, and cursor behavior across document objects.

### 4. Optional explicit external-link previews

Offer a user-triggered compact preview for external links. Do not fetch remote
metadata automatically. Any fetched metadata must be explicit, cached, and
consistent with Lists' local-first privacy model.

## Intentionally deferred

- Drawing and canvas creation.
- Proprietary block IDs.
- Automatic network metadata fetching.
- Destructive automatic orphan-file deletion.
- Android, web, sync, collaboration, AlarmKit, agent integrations, and App
  Store work unless Saxon explicitly reactivates them.

## Working agreement

- Work on `dev`; keep `main` stable.
- Preserve visible behavior, storage compatibility, and user data.
- Use focused tests for isolated logic and visible simulator/device validation
  for gesture or layout work.
- The running app remains the source of truth for interaction polish.
