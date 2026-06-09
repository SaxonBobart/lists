# Lists for Android

An exploration build of Lists as a native Android 17-era app: Jetpack Compose,
**Material 3 Expressive** (dynamic color, expressive motion, FAB menu, wavy
progress), edge-to-edge, predictive back, no orientation locks. The design
target follows `docs/research/android-17-design.md`: M3 Expressive is the
design language; Android 17 is just the OS underneath.

## What works

- **The exact iOS on-disk format.** `core/` is a 1:1 Kotlin port of the iOS
  data layer: YAML-frontmatter markdown items, `.list.yml` list headers,
  sanitized folder names, nested lists, quarantine-don't-crash loading,
  tombstone soft deletes, the legacy `completion_log` migration, habit
  cycles/streaks ("never miss twice"), smart-list predicates, and the RRULE
  recurrence engine. **54 JUnit tests** cover round-trips against iOS-shaped
  fixtures. A future sync engine can treat both platforms as one library.
- Home with smart-list tiles (Today / Scheduled / All / Flagged / Completed /
  Tags) and the nested list tree.
- List detail: sections, thread children, sub-lists, quick-add bar,
  show-completed toggle, rename/delete.
- Tasks: complete (recurring tasks spawn their next occurrence in the stored
  timezone), due dates, priority, flag, urgent, tags, swipe to delete.
- Habits: ring on the row (tap to log), detail screen with streak card,
  per-cycle progress (+1/−1), contribution grid, recent log with delete.
- Notes, full item editor sheet, search, tags overview, recently deleted
  (restore / delete forever).
- First launch seeds the same sample library as iOS (same stable UUIDs).

## Building

`:core` is pure JVM and builds anywhere:

```sh
./gradlew :core:test
```

`:app` needs the Android SDK (the settings script skips it when no SDK is
found, so headless CI can still run core tests). Open `platforms/android/` in
Android Studio, or:

```sh
./gradlew :app:assembleDebug
```

versions: AGP 8.10, Kotlin 2.1.20, compileSdk/targetSdk 36, minSdk 31,
Compose BOM 2026.05.01 with **material3 pinned to 1.5.0-alpha20** for the
Expressive components.

> **Heads-up:** the `:app` module has not been compiled yet — it was written in
> an environment without access to Google's Maven (see repo network policy).
> Expect some first-build fixes, most likely in the alpha-API surface below.

### The deliberately small alpha-API surface

Everything from the material3 `1.5.0-alpha` track is confined to two files,
each with documented stable fallbacks:

- `ui/theme/Theme.kt` — `MaterialExpressiveTheme` + `MotionScheme.expressive()`
- `ui/components/ExpressiveBits.kt` — `FloatingActionButtonMenu`,
  `ToggleFloatingActionButton`, `Circular/LinearWavyProgressIndicator`,
  `LoadingIndicator`

If an alpha bump breaks a signature, fix or fall back in those two files only.

## Architecture

```
core/   pure Kotlin: models, Iso8601, FrontmatterCodec, FileStore,
        HabitCycle/HabitStats, SmartList, ItemSort, RecurrenceEngine
app/    Compose UI + ListsRepository (StateFlow over FileStore, mirrors the
        iOS ItemStore rules: memory-first writes, recurrence spawn on
        complete, cascade soft-delete, detach-on-restore)
```

Storage root is app-private `filesDir/Lists/` — the Android twin of the iOS
sandbox `Documents/Lists/`.

## Known gaps (vs. iOS / for later)

- No notifications/reminder scheduling yet (data is stored, nothing fires).
- No drag-to-reorder (manual `sort_index` is honored, just not editable).
- Markdown body is edited as plain text; no rendered markdown view.
- No section management UI (sections display; create/rename/reorder TBD).
- Habit log supports delete + "now" logging; arbitrary date backfill TBD.
- Single-pane navigation; `ListDetailPaneScaffold` two-pane is the natural
  next step for large screens.
- No app settings screen.
