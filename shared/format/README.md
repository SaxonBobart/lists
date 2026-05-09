# Format — the on-disk file format

The on-disk file tree is the source of truth across every platform. This
directory documents the format formally: framing rules in `frontmatter.md`,
filename conventions in `filenames.md`, and machine-readable JSON Schemas for
the reminder body and the list metadata.

If the JSON Schema and the prose disagree, **the JSON Schema wins** — it's
the testable artifact.

## Files

| File | Purpose |
|---|---|
| `frontmatter.md` | How `---` opener / closer delimits YAML frontmatter from markdown body, plus rules for blank-line separators, line endings, and BOM handling. |
| `filenames.md` | Folder naming (per-list folder = `<list.id>`), file naming (`<reminder.id>.md`), reserved names (`.list.yml`, `.lists.yml`). |
| `reminder.schema.json` | JSON Schema for the YAML frontmatter of a reminder file. |
| `list.schema.json` | JSON Schema for the YAML body of a `.list.yml` file. |

## Validation

Every platform that reads or writes these files must validate parsed YAML
against the schemas in this directory, at minimum during the test pass over
`shared/fixtures/`. Production reads MAY skip schema validation for speed but
MUST handle missing or unknown keys gracefully (per the schema's
`additionalProperties: true` and the listed `required` array).

## Source

The schemas mirror the table in `SPEC.md` §6 (reminder model) and the
`.list.yml` example in `SPEC.md` §7 verbatim. Any change to those sections
must be reflected here in the same commit.
