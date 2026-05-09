# Filenames and folder layout

```
<library-root>/
├── .lists.yml                                (top-level list ordering — optional, see below)
├── 00000000000000000000INBOX0/               (list folder; name is the list's ULID)
│   ├── .list.yml                             (list metadata)
│   ├── 01HX2A9F3K4VYTGN3RH8XPQM5K.md         (reminder file)
│   └── 01HX2B...md                           (another reminder)
└── 01HX1B...K/                               (another list folder)
    ├── .list.yml
    └── 01HX2C...md
```

`<library-root>` is platform-specific:

| Platform | Default location |
|---|---|
| iOS | `Documents/Lists/` (in the app sandbox; iCloud-syncable) |
| Android (v1) | `getExternalFilesDir(null)/Lists/` (app-private external) |
| Android (v1.1+) | User-picked SAF tree URI (any folder) |
| Windows | `%USERPROFILE%\Documents\Lists\` |
| Linux | `$XDG_DATA_HOME/lists/Lists/` (default) or user-picked |

## Folder naming

- **List folders** are named by the list's **ULID id** verbatim, with no
  extension and no human-readable transform. This makes renames free (the
  user-visible name is in `.list.yml:name`; the folder never moves).
- **No nested list folders.** Lists are flat under the library root in v1.
  Sidebar grouping (`list_groups` from the older data model) is deferred.
- **Reserved folder names**: none currently. Future feature flags MAY use
  dot-prefixed folders (`.trash/`, `.attachments/`) for app-internal data;
  parsers MUST ignore folders that begin with `.` other than reading
  documented ones.

## File naming

- **Reminder files** are named `<reminder.id>.md`. The ULID is 26 ASCII
  characters; the full filename is 29 chars (`.md` extension).
- **List metadata** lives at `<list-folder>/.list.yml`. Exactly that name; case-
  sensitive on case-sensitive filesystems (which iOS, Android, and Linux are
  by default). On Windows, NTFS is case-insensitive but case-preserving;
  writers MUST use lowercase.
- **`.lists.yml`** at the library root records manual ordering of lists in
  the sidebar. Optional — if absent, the sidebar uses each list's `position`
  field instead. (V1 of the iOS app does not write this file.)

## Reserved characters

Filenames are ULIDs (Crockford base32), which only ever contain
`0-9 A-Z` minus `I L O U`. Folder names are also ULIDs. The library-root path
itself MAY contain any character valid on the host filesystem.

## Hidden files

Any file or folder beginning with `.` is treated as metadata and not
enumerated as user data:

- `.list.yml` — list metadata (read)
- `.lists.yml` — top-level ordering (read, optional)
- `.DS_Store`, `.git/`, etc. — OS / VCS noise (ignore)
- `.trash/`, `.attachments/`, `.sync/` — reserved for future use (ignore on read)

## Soft-delete tombstones

A reminder's `deleted_at` field being non-null marks it deleted. The file
remains on disk so that a future sync layer can replicate the tombstone. The
file is hidden from queries; the cache rebuilder includes it in the cache
with `deleted_at` set.

A garbage-collector (out of v1 scope) eventually hard-deletes files where
`deleted_at` is older than 30 days. Until that ships, tombstoned files
accumulate. This is acceptable.
