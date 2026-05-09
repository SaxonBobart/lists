# Cache — the rebuildable SQLite contract

Every platform builds a local SQLite-flavoured query index over the file
tree. The cache exists for one reason: indexed queries (smart lists,
"reminders due today", "reminders in this list", "reminders with these tags")
are too slow to run by walking the file tree. The cache is **always
derivable** from the files; on conflict between cache and files, the files
win.

This directory documents the canonical column names + types as a
reference DDL. Each platform implements its own physical cache via its native
ORM:

| Platform | ORM / driver |
|---|---|
| iOS | SwiftData (planned; today: in-memory snapshot) |
| Android | Room |
| Windows | `Microsoft.Data.Sqlite` (raw ADO.NET) |
| Linux | `sqlite3` direct via Vala VAPI |

The physical schemas may differ — index choices, foreign-key declarations,
generated columns — but the **column names and types here are normative**.
That keeps cross-platform tooling (SQLite browser, ad-hoc analytic queries)
working without per-platform schema maps.

## Cache rebuild algorithm

Every platform implements the same cache-rebuild pass on cold start. Pseudocode:

```
walk every list folder under <library-root>/
for each folder:
    read .list.yml; parse and validate against shared/format/list.schema.json
    upsert into lists table
    for each *.md file in folder:
        stat file; compare mtime to lists_meta.last_seen_mtime
        if mtime mismatched or row absent:
            read file; parse frontmatter against shared/format/reminder.schema.json
            upsert into reminders table
            update last_seen_mtime
for each row in reminders where last_walk_id != current_walk_id:
    mark deleted_at = now (file disappeared from disk)
```

This pass is fast (no I/O for unchanged files; just `stat`). After the
initial pass, a `FileSystemWatcher` (or platform equivalent) catches runtime
changes; the periodic re-walk is a failsafe.

## Settings the cache must persist

The cache also stores per-device runtime state that is intentionally NOT
in the file tree (because it would conflict on sync):

| Table | Purpose |
|---|---|
| `device_settings` | Library root path, default destination list, hide-completed-after-seconds, urgent-alarm-volume |
| `notification_state` | Per-reminder pending notification handle / alarm id, so we can cancel them on edit |
| `cache_meta` | Schema version, last full-walk timestamp, walk id |

These three tables are device-local and are NOT synced even when sync ships.
Every device computes them from its files and its OS state.

## Schema migration

The cache is rebuildable, so cache schema migrations don't need to preserve
data — they just need to bump the schema version, drop the cache, and
trigger a re-walk on next launch. This means every platform can ship cache
schema changes independently as long as the **on-disk format** (under
`shared/format/`) doesn't change.
