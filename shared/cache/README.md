# Cache

The cache is a rebuildable index over the markdown/YAML files.

Rules:

- Files win over cache data.
- If the cache is missing or corrupt, rebuild by walking the library folder.
- Cache migrations do not need to preserve user data if the source files remain intact.
- Keep column names close to file-format field names so debugging stays simple.

`schema.sql` is a reference shape, not mandatory production code for every platform.
