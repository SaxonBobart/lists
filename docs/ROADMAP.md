# Lists Roadmap

Updated: 26 July 2026

This is the current execution handoff for new engineering threads. Durable
product behavior belongs in `PRODUCT-SPEC.md`; detailed Markdown findings and
reference-app research belong in `docs/MARKDOWN-EXPERIENCE-AUDIT.md`.

## Current checkpoint

The final pre-release product milestones are implemented:

- User-owned lists offer List and Calendar, plus Columns when they have durable
  named sections. Empty sections remain usable as Kanban columns.
- Smart lists, Today, tags, and search offer List and Calendar only.
- Calendar projects local Markdown documents into Agenda, Day, 3 Days, Week,
  Month, and Year views, with configurable recurrence, history, item-type, and
  global-list visibility.
- Calendar creation, opening, completion, duplication, moving, resizing, and
  recurring-item scope changes use the existing item and storage behavior.
- External-link previews and network metadata fetching remain excluded.

The Markdown experience milestone is also complete:

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
- Search has offline filters for links or backlinks, tables, Markdown tasks,
  and images or attachments.
- Table cells expose semantic row and column labels plus supported row and
  column operations to VoiceOver.
- Dynamic Type refreshes the live Markdown and table layouts without requiring
  the editor to reopen.
- Hardware keyboards can insert links and tables and move between table rows
  and columns with discoverable commands.

Table work should now be treated as a protected interaction baseline. Further
changes should fix demonstrated defects or deliberately extend the product,
not redesign the interaction model incidentally.

## Next

### 1. Real-device release gate

- Build and run the Release configuration on a supported iPhone.
- Verify local-notification authorization, task/event reminder delivery, and
  recurring habit delivery on iOS 27.
- Exercise camera/document import, attachment Quick Look, export, and restore.
- Exercise empty Kanban columns, cross-column reorder, Month drag/drop, timeline
  create/move/resize, recurring-item scope choices, and the calendar Settings
  filters.
- Spot-check the Markdown editor and interactive tables with VoiceOver, an
  accessibility Dynamic Type size, and a hardware keyboard; include Calendar
  and Columns in the accessibility pass.

### 2. TestFlight gate

- Keep `0.1.0 (1)` for the first upload unless App Store Connect already owns
  that build number.
- Create or finish the App Store Connect record, privacy answers, screenshots,
  subtitle, description, and review notes. Use the public issue tracker for
  support and `PRIVACY.md` for the privacy-policy URL after it reaches `main`.
- Archive with distribution signing, upload the build, and complete internal
  TestFlight processing and installation.

### 3. Public iOS release gate

- Resolve feedback from the internal TestFlight build without expanding scope.
- Decide whether the first public version remains `0.1.0` or becomes `1.0`.
- Run the final device smoke test, submit for review, and only then move
  `main` or create a release tag with Saxon's approval.

The generated iOS project already has a Release archive configuration, a
privacy manifest, no unused app-group entitlement, and the non-exempt
encryption declaration required for upload.

## Intentionally excluded or deferred

- Drawing and canvas creation.
- Proprietary block IDs.
- External-link previews and network metadata fetching are excluded. Web links
  remain portable inline Markdown across platforms.
- Destructive automatic orphan-file deletion.
- Android, web, sync, collaboration, AlarmKit, and agent integrations.

## Working agreement

- Work on `dev`; keep `main` stable.
- Preserve visible behavior, storage compatibility, and user data.
- Use focused tests for isolated logic and visible simulator/device validation
  for gesture or layout work.
- The running app remains the source of truth for interaction polish.
