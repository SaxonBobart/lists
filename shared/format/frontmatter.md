# Frontmatter framing rules

A reminder file is a UTF-8 text file containing YAML frontmatter followed by
a markdown body. The framing is precise and every platform's parser must
implement it identically. The iOS reference implementation lives in
`platforms/ios/Lists/Core/Storage/FrontmatterCodec.swift`.

## Grammar

```
file       = bom? blank-lines? open-fence newline yaml close-fence newline body?
bom        = "\xEF\xBB\xBF"            (optional, stripped on read)
blank-lines = (newline)*               (any leading blank lines are skipped)
open-fence = "---"                     (exactly three hyphens, no leading whitespace)
close-fence = "---"                    (exactly three hyphens, no leading whitespace)
yaml       = (any-char-not-close-fence)*
body       = (any character)*          (markdown; may be empty)
newline    = "\n" | "\r\n"             (writers MUST emit "\n"; readers SHOULD accept both)
```

## Rules

1. **No leading whitespace on the fences.** A line that is `   ---` is *not*
   a fence. The line must be exactly `---` (three U+002D hyphens) followed by
   the line terminator.
2. **The opener must be the first non-blank line of the file.** Leading blank
   lines are tolerated but skipped.
3. **The closer terminates the YAML.** Everything after the closing fence's
   line terminator is the markdown body.
4. **A blank line between closer and body is conventional but not required.**
   Writers emit one blank line; readers strip leading blank lines from the body.
5. **Trailing whitespace on the body is stripped on read.** Writers do not need
   to add trailing newlines, but if they do, readers tolerate them.
6. **YAML emitter MUST preserve declaration order.** This makes file diffs
   readable. The iOS implementation uses Yams with `sortKeys = false`.
7. **Booleans and nulls use lower-case.** `true`, `false`, `null`. (YAML 1.2.)
8. **String values that look like dates, ints, or booleans MUST be quoted.**
   Specifically: `time: "14:30:00"` (quoted, because unquoted `14:30:00` is
   parsed as a sexagesimal int by some YAML 1.1 parsers — even YAML 1.2
   parsers vary here).
9. **Dates are ISO 8601 strings.** UTC `Z` suffix for timestamps; date-only
   for `date`; HH:MM:SS for `time`. Never serialise as a YAML native date —
   keep them strings to avoid parser-defined behaviour.
10. **Single tag is a slash-delimited scalar.** `tag: recipes/Mediterranean/Pasta`. Slashes are the only nesting mechanism — the hierarchy is a UI projection of the string. The field is optional; omit it for an untagged reminder.
11. **Empty arrays serialise as `[]`.** `completion_history: []`.
12. **Unknown YAML keys MUST be preserved on round-trip.** This is the
    forward-compat path: a v0.5 client reading a v0.6 file with new keys
    writes those keys back unchanged.

## Test corpus

Every platform's parser is exercised against `shared/fixtures/`. Adding a new
edge case adds a new fixture file; every parser must continue to round-trip
it byte-equal.

## What's NOT supported

- Multi-document YAML (`---\n---\n---\n`). One YAML doc per file.
- Comments inside YAML are not preserved on round-trip. A reminder file that
  contains `# this is a comment` in its frontmatter will lose that comment on
  the next save. (This matches Yams's behaviour and is acceptable for v1.)
- TOML or JSON frontmatter. Only YAML.
