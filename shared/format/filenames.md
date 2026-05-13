# Filenames

Library layout:

```text
<library-root>/
  <list-id>/
    .list.yml
    <item-id>.md
```

Rules:

- List folders are named by stable ids, not list names.
- Item files are named `<item-id>.md`.
- List metadata is always `.list.yml`.
- Dot-prefixed files and folders are metadata and should not appear as user items.
- Soft deletes stay on disk until a later cleanup pass removes old tombstones.

iOS library root: app sandbox `Documents/Lists/`.
