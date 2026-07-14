# Architecture

This is the short map for contributors and agents. The live product is the iOS app in `platforms/ios/`.

## Runtime Shape

`ListsApp` creates one `ItemStore`, points it at the app-private `Documents/Lists/` folder, then hands that store to `ContentView`.

`ContentView` waits for bootstrap, surfaces file-recovery issues or a protected interrupted restore, then presents `SidebarView`.

Most screens read and mutate the same `ItemStore`. `ItemStore` owns the in-memory lists and items, serializes disk writes so newer edits cannot be overwritten by older ones, and delegates file I/O to `FileStore`. Rebuild and export take exclusive maintenance access across their complete file snapshot; mutations already in progress finish first, while later async and synchronous edits wait in one arrival-ordered queue and are drained before the gate reopens. Product-level mutations should live here when they affect stored invariants; for example, `applyMoveSync` is the shared rule for reparenting, cross-list moves, and descendant list/section cascades. Pure hierarchy answers live in `ItemHierarchy` and `ListHierarchy` so descendant lookup, selected-root filtering, child sorting, and list-parent cycle checks are shared without giving non-store code write access. Item write paths and loaded snapshots normalize parent/list/section relationships, habit bodies, and event start/end spans before writing; subtree helpers add descendant cascades when a move, delete, or restore affects children. Multi-file restores commit the requested root last and use a hidden manifest journal; bootstrap resumes an intact batch, but pauses hierarchy repair, expiry purge, and permanent deletion when expected members are unavailable. List delete/restore also lives here so list tombstones, descendant lists, and item tombstones stay coherent. List-parent writes and loaded snapshots are guarded in the store as well as the UI: add, edit, move, sidebar reorder, and bootstrap repair must never leave an active list under itself, a missing parent, a deleted parent, or one of its descendants.

Item move mode is shared UI state, not a modal route. `SidebarView` owns the `ItemMoveSession` and persistent bottom shelf, then passes that session into list detail, smart lists, Today, search, and tags so the shelf survives navigation; user-list detail screens commit destination picks through `ItemStore.applyMoveSync`.

`FileStore` is the only layer that knows the on-disk layout:

```text
Documents/Lists/
  Canvases/
    <canvas title>.canvas
    <canvas title>.paper
    <canvas title>.png
  <list name>/
    .list.yml
    <item title>.md
    <child list name>/
      .list.yml
```

Item files are markdown with YAML frontmatter. Human-readable filenames provide
portable relative-link targets while stable item ids remain in frontmatter.
`DocumentMarkdownIndex` resolves relative Markdown paths, heading fragments,
WikiLink targets, and legacy Lists URLs; `ItemStore` rewrites app-managed inbound
paths when an item or list moves or changes name. Files are the source of truth;
indexes and caches are rebuildable.

## Folders

- `App/` - app entry point and root loading state.
- `Core/Models/` - durable product types such as `Item`, `ItemList`, built-in module identity, reminders, recurrence metadata, and small model defaults like event start/end seeding.
- `Core/Stores/` - app state and mutation APIs. UI should usually go through `ItemStore`, not `FileStore`.
- `Core/Storage/` - plain-text persistence, frontmatter encoding, path handling, and recovery.
- `Core/Queries/` - smart-list filtering and pure query helpers such as Today/Scheduled/All sectioning, search grouping, and item/list hierarchy rules.
- `Core/Recurrence/` - RRULE parsing, recurrence expansion, and shared schedule/date formatting.
- `Core/Notifications/` - local notification scheduling.
- `Core/Preferences/` - app-wide, per-view, and auto-list preferences.
- `Core/Tags/` - tag parsing, casing, counts, active-tag filtering, and relation ordering.
- `Design/` - tokens, typography, spacing, and reusable UI components.
- `Features/` - user-facing screens, grouped by workflow.
- `Features/Shared/` - small user-facing behavior helpers shared by multiple feature screens.
- `Resources/` - asset catalogs and app resources.
- `ListsTests/` - unit tests and snapshot tests.

Android exploration is archived outside the active tree until Android work is explicitly reactivated.

## Large Files

Large files are not automatically bad, but they are where further simplification should happen:

- `Features/ListDetail/ListDetailCollectionView.swift` bridges SwiftUI into a UIKit collection/list view. Its support files own the real jobs: snapshot building, drag/drop delegate policy, drop-cue rendering, item drop-target resolution, hierarchy math, row models, row views, query helpers, cell registrations, context menus, swipe actions, and reorder commits. `ListDetailCollectionDragDrop.swift` owns the live drag/drop delegate callbacks and section-drop validation. `ListDetailBottomChrome.swift` owns the mutually exclusive selection toolbar / floating add / move-shelf drop target states, and `ListDetailEmptyStateView.swift` owns the empty list copy and icon. Inline editing is split the same way: `InlineItemEditor.swift` is the SwiftUI row shell, while `InlineEditController.swift` owns the `UITextView`, keyboard toolbar, sizing, and commit plumbing. The inline date/time popover owns state parsing and apply rules; its task date/time, event date, and repeat/early-reminder sections live in sibling `Inline*Section.swift` files. The list overflow menu lives in `ListDetailToolbarMenu.swift`; keep menu layout there and screen-routing state in `ListDetailView.swift`.
- `Features/Today/ItemRow.swift` owns row interaction/routing/swipes; `ItemRowLeadingControl.swift` owns the type-specific leading controls (task checkbox, event calendar/checkbox, note glyph, habit ring). `TodaySmartListSections.swift` owns Today vs Overdue sectioning so multi-day calendar events that overlap today render under Today instead of being treated like overdue tasks.
- `Features/SmartList/SmartListScreen.swift` owns smart-list screen routing and row-snapshot assembly; `Core/Queries/AllSmartListSections.swift` and `ScheduledSmartListSections` own the product grouping rules. `SmartListToolbarMenu.swift` owns smart-list menu layout and per-query preference bindings.
- `Features/Search/SearchResultsView.swift` owns the search overlay UI; `ItemSearch` owns active-result filtering and list grouping. `Features/Tags/TagsOverviewView.swift` owns the tags screen, while tag parsing/counting/filtering lives in `Core/Tags/Tag.swift` and chip components live in sibling tag feature files.
- `Features/Sidebar/SidebarListsCollectionView.swift` is the matching UIKit bridge for the nested sidebar list tree. Its bridge, self-sizing collection view, and hosted SwiftUI row content live in nearby support files.
- `Features/MarkdownEditor/MarkdownStyler.swift` is editor infrastructure. It is dense because text storage, layout, checkboxes, and highlighting meet there.
- `Core/Storage/AttachmentStore.swift` owns root-confined attachment paths,
  atomic imports, Markdown reference discovery, recoverable orphan quarantine,
  and paired PaperKit drawing source/portable-preview storage. Raw PencilKit
  sources are accepted at the document boundary without flattening their ink.
  `ItemStore` serializes those writes through the same maintenance gate used by
  library export.
- `Core/Models/CanvasDocument.swift` is the platform-independent JSON Canvas
  graph, while `Core/Storage/CanvasStorage.swift` owns each Canvas item's
  `.canvas` / `.paper` / `.png` / `.drawing.png` resource group.
  `Features/Canvas/CanvasItemView` coordinates item metadata and navigation.
  `PaperCanvasEditor` is the native iOS authoring surface: PaperKit persists ink
  and standard markup, while Lists link and Markdown cards render as PaperKit
  adornments and are also written as portable JSON Canvas file/link/text nodes.
  Its card inspector edits portable node geometry and color directly; the
  adornment is regenerated from that graph rather than becoming a second source
  of truth. Markdown card source remains raw Markdown and reuses the document
  Live/Raw editor instead of being converted into PaperKit text. Other platforms
  should render the same graph with their native canvas and drawing APIs rather
  than decoding PaperKit.
- `Core/Recurrence/RecurrenceEngine.swift` is only recurrence expansion math. The Reminders-style editor model lives in `RecurrenceRule.swift`, RRULE string splitting lives in `RRuleParts.swift`, and shared schedule/date copy lives in `ScheduleFormatting.swift`.
- `Features/ItemDetail/ItemDocumentView.swift` and `Features/QuickCapture/QuickCaptureSheet.swift` are large because they expose many item fields. `ItemDetailSheet` is intentionally only a thin router around document pages and habit detail; document page chrome plus title/tag/fact/body rows live in `DocumentPageRows.swift`, and document Details sheet card layout lives in `DocumentScheduleCard.swift`, `DocumentRepeatCard.swift`, and `DocumentMetadataCard.swift`, so the page file keeps the live-apply rules. Shared detail-form row chrome, item fact chips, glyph-label styling, and priority presentation live in `Design/Components/`; prefer extending those stable pieces before copying another row shape. Event start/end seeding lives in `EventDefaults`, and `ItemStore` calls the same normalization on writes and loaded data so events stay calendar-block-shaped even outside UI paths. Quick Capture's extracted sibling views own layout sections, while `QuickCaptureDraft` owns draft-to-`Item` conversion, discard-dirty detection, stable habit reminder-zone capture, and the no-notes-body rule for habit capture. RRULE string splitting lives in `RRuleParts`, and `ScheduleFormatting` owns repeat-end date parsing/formatting so Quick Capture, inline editing, document details, and recurrence expansion agree. Habit detail follows the same rule: `HabitDetailView` owns its read-first/edit routing, save/delete recovery, and live draft rules, while `HabitOverviewContent.swift`, `HabitCompletionLogView.swift`, `HabitDetailsForm.swift`, and `CompletionEntrySheet.swift` own progress, log, form, and entry-sheet layout. `HabitReminderSchedule` is the shared wall-clock schedule interpreter, and `NotificationScheduler` retains one repeating request per habit while delivered-alert acknowledgment happens only after durable completion. The row-completion fade rule shared by list, Today, and smart-list screens lives in `Features/Shared/ItemCompletionLinger.swift`.
- `Features/ListEdit/ListEditSheet.swift` owns the list create/edit UI; `ListEditDraft.swift` owns conversion into `ItemList` so name trimming, shopping mode, parent id, position, timestamps, and lamport rules stay testable outside SwiftUI. `ListParentPicker.swift` is only for assigning a parent to a list; item moves use the in-place shelf in List Detail.
- `Features/Settings/SettingsView.swift` is the app-wide product map; shared settings row chrome lives in `SettingsRows.swift`, the default new-item picker lives in `DefaultNewItemTypeRow.swift`, built-in module identity comes from `BuiltInModule`, and maintenance flows live in their own export/rebuild views.

## Change Rules

- XcodeGen owns the Xcode project. Edit `platforms/ios/project.yml`, then regenerate; do not hand-edit `Lists.xcodeproj`.
- Every interactive SwiftUI element should have an accessibility ID when it is created.
- Data/model/storage changes need focused tests.
- Visual changes need a snapshot test, a SwiftUI preview render, or a simulator screenshot, depending on the risk.
- Android, sync, AlarmKit, and non-iOS clients are outside the current iOS implementation until explicitly reactivated.
