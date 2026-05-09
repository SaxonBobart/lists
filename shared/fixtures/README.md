# Fixtures — golden parser inputs

Small corpus of canonical reminder files and `.list.yml` files used by every
platform's parser parity tests.

## How a platform consumes this

1. Symlink or copy `fixtures/lists/` into the platform's test resources tree.
2. For each `.md` and `.list.yml` file:
   - Read the file.
   - Parse to the platform's domain model.
   - Re-emit using the platform's writer.
   - Assert the re-emitted bytes equal the original bytes.
3. For each parsed reminder:
   - Validate the YAML against `shared/format/reminder.schema.json` (if a JSON
     Schema validator is available — optional but recommended).
4. Run the platform's RRULE expander against any reminder with a `recurrence`
   field; cross-check against `shared/recurrence/examples.md`.

## What "byte-equal" means here

Strict byte equality — same line endings, same key order in YAML, same
quoting of strings, same trailing newline. The framing rules in
`shared/format/frontmatter.md` and the YAML emission rules ("preserve
declaration order", "block syntax for arrays", "always quote `time` strings")
exist precisely to make byte-equal round-trip practical.

If a platform's parser cannot produce byte-equal output, that platform's
saves will dirty every file it touches, defeating the iCloud-Drive-friendly
"your data is plain files" pitch. Catch this at the parity-test stage.

## Adding a fixture

When a platform discovers a parser bug or a new edge case:

1. Add a new file under `fixtures/lists/<list-folder>/`.
2. Verify the iOS reference parser handles it.
3. Verify every other platform's parser handles it. Each platform that
   doesn't already pass adds the failing case to its bugs queue.

## Current corpus

| File | What it tests |
|---|---|
| `lists/00000000000000000000INBOX0/.list.yml` | Minimum viable list metadata: the Inbox sentinel id, all required fields, no optional fields. |
| `lists/00000000000000000000INBOX0/01HX2A9F3K4VYTGN3RH8XPQM5K.md` | Reminder with rich metadata: tags, priority, flag, recurrence, completion history. Markdown body with bold + lists + code. |

The corpus is **intentionally small** for v0. As parser bugs surface in
each platform, the corpus grows. Every fixture has a comment at the top
linking to the bug or test it represents (or "initial" for the v0 set).

## What NOT to put here

- Personal data, real reminder text, anything sensitive.
- Locale-specific text that's hard to test against (use ASCII or simple
  Unicode where possible).
- Fixtures that depend on the current date — recurrence anchors should be
  fixed historical dates so the expansion doesn't drift.
