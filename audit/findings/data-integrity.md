# Data Integrity & Persistence Audit

## Verdict
**Needs attention.** The per-file *write* path is genuinely solid — every save is atomic (`write(atomically:)`), the folder model is clean, and soft-delete/cascade logic is careful. But the *read* path is the weak point and it is the single highest-stakes area in the app: `loadAll` is all-or-nothing, so **one corrupt or partially-written `.md`/`.list.yml` makes the entire library fail to load** and the app hangs forever on "Loading your lists…" with everything invisible. There is no quarantine, no skip-the-bad-file recovery, and no user-facing error. Two further real bugs (item duplication on cross-list move; silent un-delete on a malformed `deleted_at`) compound the risk. None of these are theoretical — they sit on common, shippable paths.

## Findings

### [P0] One bad file makes the WHOLE library unloadable (no skip / no quarantine)
- **Where:** `Core/Storage/FileStore.swift:176` (`let items = try itemFiles.map { try readItem(at: $0) }`), `:146` (`let list = try readList(at: listFile)`), propagated by `:184`/`:192`/`:136`; surfaced at `Core/Stores/ItemStore.swift:24-49` and `App/ListsApp.swift:13-21`.
- **What:** `walk` reads every `.md` and `.list.yml` with `try` and no per-file `do/catch`. A single file with bad YAML, a missing required key (`keyNotFound: created_at`), a bad date, or a truncated/half-written frontmatter throws straight out of `loadAll`. `bootstrap()` then throws before `self.isLoaded = true` runs. `ContentView` (`App/ContentView.swift:7`) only ever shows `SidebarView` once `isLoaded == true`, so the app sits on `BootstrapPlaceholder` ("Loading your lists…") **permanently**. The only signal is a `print` to the console (`ListsApp.swift:19`) that no end-user sees.
- **Impact:** Total, silent loss of access to the user's entire notes library because of one damaged item file. The data may still be on disk, but the app can't show *any* of it and gives the user no path forward. This is exactly the failure class flagged in project memory (`feedback_wipe_sim_data_when_bundle_shared`) — there it was worked around by manually wiping the container, which is not an option for a real user. For a local-first notes app this is the worst-case outcome.
- **Confidence:** High.
- **Fix:** Make load resilient per file: wrap each `readItem`/`readList` in `do/catch`, collect failures into a `quarantined: [(URL, Error)]` list, and continue loading everything that parses. Surface a non-blocking banner ("3 items couldn't be opened") and still set `isLoaded = true` so the rest of the library renders. Move the bad files to a `Lists/.quarantine/` folder rather than leaving them to re-fail every launch. At minimum, `bootstrap` should set `isLoaded = true` in a `defer`/`catch` so the app is never permanently wedged.

### [P0] Cross-list move duplicates the item on disk (old `.md` never deleted)
- **Where:** `Core/Storage/FileStore.swift:77-83` (`writeItem`); triggered by `Core/Stores/ItemStore.swift:185` (`update`) / `:200` (`applyUpdateSync`); user path at `Features/ItemDetail/ItemDetailSheet.swift:1045` (`item.listId = listId`) and `:702` (list picker), also `Features/Habits/HabitDetailView.swift:376` (`draft.listId = list.id`).
- **What:** `writeItem` derives the file path from `item.listId` and writes `<newList>/<id>.md`. When a user changes an item's list in the detail sheet (or habit editor), `update` only writes the new file — nothing deletes the old `<oldList>/<id>.md`. The file's basename is the item UUID, which is stable across the move, so the stale copy is *not* overwritten; it just lingers.
- **Impact:** After moving an item between lists, the next `loadAll` reads **both** copies into `items` (one with the new `listId`, one with the old). The item appears in two lists at once, smart lists double-count it, and toggling/deleting one copy leaves the other behind (a "zombie" that reappears on relaunch). This is real, observable data corruption from a routine action.
- **Confidence:** High. (Worth a 30-second sim repro: move a Work item to Personal, force-quit, relaunch — expect it in both.)
- **Fix:** `update` should detect a `listId` change versus the in-memory copy and call `store.deleteItem(oldItem)` (old `listId`) before/after writing the new file. Cleaner still: give `FileStore` a `moveItem(_ item, fromListId:)` that does delete-then-write atomically, and have the store route all `listId` changes through it.

### [P1] Malformed `deleted_at` silently *un-deletes* an item or list
- **Where:** `Core/Models/Item.swift:198,259-265` and `Core/Models/ItemList.swift:113,153-159` (`decodeDateIfPresent` → `ISO8601.date(from:)` returns `nil` on a bad string, no throw).
- **What:** Required dates (`created_at`, `modified_at`) throw on a bad value (`decodeDate`, `Item.swift:245-257`), but optional dates use `decodeDateIfPresent`, which maps an *unparseable but present* string to `nil` instead of throwing. So a `deleted_at:` line that got mangled (sync edit, manual export round-trip, partial write) decodes as "not deleted."
- **Impact:** An item the user deleted silently reappears as live. Conversely a corrupt `completed_at`/`due` quietly drops the value. The tombstone is the safety mechanism for Recently Deleted; corrupting it resurrects data the user intended gone — surprising and, for notes a user deleted deliberately, a small privacy/correctness problem.
- **Confidence:** High (logic is unambiguous); Med on real-world frequency (depends on how files get mangled, which is more likely once sync/export exists).
- **Fix:** Make `decodeDateIfPresent` distinguish "absent" from "present-but-invalid": if the key exists and parsing fails, throw `dataCorruptedError` (so it's caught by the per-file quarantine from the first finding) rather than returning `nil`.

### [P1] No write serialization per item — fire-and-forget `Task`s can land out of order
- **Where:** `Core/Stores/ItemStore.swift:178-183` (`applyReorderItemsSync`), `:200-212` (`applyUpdateSync`), `:449-470` (`applyReorderSectionsSync`); called from `Features/ListDetail/ListDetailCollectionView.swift:1588,1596,1642`.
- **What:** `FileStore` is an `actor`, so two writes never physically interleave (good). But the *sync* variants spawn unstructured `Task { try? await store.writeItem(...) }` with no ordering guarantee between tasks. During a drag that fires `applyUpdateSync(copy)` immediately followed by `applyReorderItemsSync(...)` (both touching the same item id), the two detached tasks can be scheduled in either order. The actor serializes them, but if the *reorder* task wins the race it writes a copy carrying the pre-edit `parentId`/`section`, clobbering the just-applied indent/move on disk. In-memory state is correct; disk can disagree until the next write.
- **Impact:** Occasional "my reorder/indent didn't stick after relaunch" — the in-memory UI looks right so it's hard to notice, then a relaunch reveals disk drift. Low frequency, but it's a silent correctness gap precisely where the user is actively reorganizing.
- **Confidence:** Med — the interleaving is plausible but I couldn't prove the exact scheduling without running it; the two call sites firing back-to-back at `1588`+`1596` is the concrete trigger.
- **Fix:** Have the sync helpers enqueue onto a single serial pipeline (e.g. an `AsyncStream`/actor-owned queue) so writes for a given drag commit in submission order; or fold the update+reorder into one `writeItem` batch per drag rather than two independent tasks.

### [P2] Legacy folder-rename migration in `walk` can still collide / loses error visibility
- **Where:** `Core/Storage/FileStore.swift:152-172`.
- **What:** The migration renames a legacy `<listId>` folder to `sanitize(name)` with a `(N)` suffix loop (`:155-161`). The loop only checks `fm.fileExists` at that instant; if two sibling legacy folders sanitize to the *same* name, they're walked one at a time so the second does get a `(2)` — that part is OK. But on a `moveItem` failure it silently swallows the error (`:166-170`) and keeps the *old* `<listId>` basename, while `pathById` is still set correctly (`:178`), so the app limps on. The real hazard: this migration mutates the user's folder layout during a *read*, before anything is known-good, and a crash mid-migration leaves a half-renamed tree. It's mostly idempotent (re-run re-attempts), but a partial `moveItem` on some filesystems is not guaranteed atomic across the whole subtree.
- **Impact:** Edge-case: after an interrupted first launch on legacy data, a list folder may be left under its old id-name. It still loads (map is correct), so low blast radius — but it's destructive-in-place logic running at the most fragile moment (initial load) with no logging.
- **Confidence:** Med.
- **Fix:** Log migration failures (don't `catch`-and-discard). Consider gating migration behind a completed-load check, or writing a `.migrated` marker so a crash mid-migration is detectable and resumable rather than silently re-attempted.

### [P2] `writeItem` throws if the list folder isn't mapped — capture can fail hard
- **Where:** `Core/Storage/FileStore.swift:78` → `listDirectory(for:)` `:201-206` (throws `fileNoSuchFile` when `pathById[listId] == nil`).
- **What:** `writeItem` requires the item's `listId` to already exist in `pathById`. That's populated by `loadAll`/`writeList`. If an item is ever created against a `listId` that hasn't been written (e.g. a list that failed to load under the P0 bug, or a race where the list write hasn't completed), the item write throws. Most call sites use `try?` (`QuickCaptureSheet.swift:1171`, `ItemDetailSheet.swift:1088`), so the throw is **swallowed silently** — the user taps "save," the sheet dismisses, and the item is simply gone.
- **Impact:** Silent loss of a just-captured item with zero feedback. Requires an unusual list state to trigger, but the universal `try?` swallowing means when it does happen the user has no idea.
- **Confidence:** Med (the throw is certain; reaching it needs an unmapped list).
- **Fix:** Don't swallow capture/save errors — surface a toast/alert on failure. Optionally have `writeItem` fall back to creating the list folder from the in-memory `ItemList` rather than throwing.

### [P2] Sample-data seed keys off `loaded.isEmpty`, which an error can't reach but an empty-but-present tree can
- **Where:** `Core/Stores/ItemStore.swift:27-43`.
- **What:** Seeding only runs when `loadAll()` returns an empty array. Because `loadAll` *throws* (rather than returning `[]`) on a read error, a corrupt library will not be silently re-seeded over — which is actually the safe behavior, so credit there. The residual smell: if the root exists but contains only empty/junk subfolders with no `.list.yml`, `walk` returns `[]` and the app **re-seeds sample data on top**, mixing demo content into a user's (admittedly already-broken) directory. Narrow, but worth a guard.
- **Impact:** Demo lists reappearing in an unexpected state. Low likelihood.
- **Confidence:** Low.
- **Fix:** Gate seeding on a one-time "did-seed" flag (e.g. a marker file or `UserDefaults`) rather than purely on `loaded.isEmpty`.

### [P3] `ISO8601.swift:5` doc references a non-existent `shared/format/`
- **Where:** `Core/Models/ISO8601.swift:5`.
- **What:** Comment points at `shared/format/`, which per project memory was retired (commit 57fb450). Doc-vs-code drift.
- **Impact:** None functional; misleads future readers about the format's source of truth.
- **Confidence:** High.
- **Fix:** Drop the stale path reference.

## Strengths
- **Atomic single-file writes.** Every `.list.yml` and `.md` is written with `write(to:atomically:encoding:)` (`FileStore.swift:62,82`), so a crash mid-write can't truncate or corrupt the target file — it either has the old contents or the new. This is the right primitive and it's used consistently.
- **Folder rename/reparent is a real `moveItem`, not copy-delete** (`FileStore.swift:50`), preserving items and nested children in one operation, with `pathById` re-synced afterward (`refreshDescendantPaths`, `:240-258`). The `(N)` collision suffix (`resolveTargetURL`, `:211-235`) correctly excludes the list's own current folder (`:226`) so renaming a list to itself doesn't spuriously bump to "(2)".
- **`sanitize` is genuinely careful** (`:263-275`): strips path separators, control chars, leading dots (no hidden folders), trailing dots/space, clamps to 80 chars, and falls back to `Untitled`. Handles emoji/Unicode names fine (they're legal in HFS+/APFS).
- **Soft-delete + cascade logic is thoughtful**: cascade tombstones the whole subtree (`softDeleteList`, `ItemStore.swift:322-335`), restore detaches from a still-deleted parent so it doesn't vanish again (`restoreList`, `:340-354`), `moveList` rejects cycles (`:360-374`), and 30-day purge is bounded and uses `try?` so one undeletable file doesn't abort the sweep (`purgeExpiredTombstones`, `:596-608`).
- **Defensive decoding for optional/new fields**: most non-essential keys use `decodeIfPresent` with sensible defaults (`Item.swift:178-199`, `ItemList.swift:105-115`), so adding fields or reading older files generally won't break — the schema is forward/backward tolerant *except* for the required-date and present-but-invalid-date cases noted above.
- **Section migration is idempotent and well-reasoned** (`migrateLegacySectionsIfNeeded`, `ItemStore.swift:538-570`): skips lists that already have sections, skips already-UUID section refs, preserves first-appearance order.

## Coverage
Read fully: `FileStore.swift`, `FrontmatterCodec.swift`, `ItemStore.swift`, `SampleData.swift`, `Item.swift`, `ItemList.swift`, `HabitCycle.swift`, `Reminder.swift`, `ISO8601.swift`, `Tag.swift`, `StorageRoot.swift`, `App/{ListsApp,ContentView}.swift`, and the persistence call sites in `ListDetailCollectionView.swift` and `ItemDetailSheet.swift`. Traced the cross-list-move and reorder-write paths to their UI triggers.
**Could not fully verify (read-only, no run):** (a) the exact task-scheduling race in the [P1] reorder finding — confirmed the back-to-back `applyUpdateSync`+`applyReorderItemsSync` call sites but did not observe out-of-order landing on disk; (b) whether any UI surfaces a `listId` change for non-habit items beyond the detail sheet's picker (found the detail-sheet + habit-editor paths; did not exhaustively grep every feature). Both warrant a quick simulator repro to pin frequency.
