# Shared — cross-platform contracts

This directory holds **language-neutral contracts** that bind every Lists
client (iOS, Android, Windows, Linux) to the same on-disk format and the same
behavioural rules. Nothing here is executable code; everything here is either a
spec a human reads, a JSON Schema a machine validates against, a fixture file
a parser parses, or a static data file a client loads at runtime.

The platform research docs converged on **no shared Rust core in v1**:

- iOS already implements the parser in Swift + Yams.
- Android wants pure Kotlin (`research/android-stack.md` §9).
- Windows wants pure C# (`research/windows-stack.md` §3).
- Linux is the only clean Rust fit but only if the other three commit, which
  they don't (`research/linux-stack.md` §9).

The cost of FFI plumbing across four platforms exceeds the cost of
re-implementing a parser/cache against a shared spec four times. Every parser
that consumes the schemas and fixtures here must produce identical outputs;
the parity test suite is the enforcement mechanism.

## Directory map

```
shared/
├── README.md                ← you are here
├── format/                  the on-disk file format
│   ├── README.md
│   ├── frontmatter.md       framing rules (---/---, body separator)
│   ├── filenames.md         folder + filename conventions
│   ├── reminder.schema.json JSON Schema for reminder YAML frontmatter
│   └── list.schema.json     JSON Schema for .list.yml metadata
├── cache/                   the rebuildable SQLite cache contract
│   ├── README.md
│   └── schema.sql           canonical column names + types (non-binding example DDL)
├── recurrence/              the RRULE subset every platform must support
│   ├── README.md
│   └── examples.md          golden input/output expansions
├── ulid/                    the ULID generation contract
│   └── README.md
├── lexicons/                static data shipped to every platform
│   ├── README.md
│   └── shopping.en.json     shopping-item categorisation lexicon (placeholder skeleton)
├── fixtures/                golden parser-input files used by parity tests
│   ├── README.md
│   └── lists/
│       └── 00000000000000000000INBOX0/
│           ├── .list.yml
│           └── 01HX2A9F3K4VYTGN3RH8XPQM5K.md
└── notifications/           cross-platform notif/alarm parity matrix
    └── README.md
```

## How a platform uses this directory

1. **At build time**: parse the JSON Schemas with the platform's JSON Schema
   library and use them to validate test inputs. Some build systems can also
   codegen models from JSON Schema — fine to do, but the schemas in
   `format/*.schema.json` are the authoritative shape regardless.
2. **At test time**: copy or symlink `fixtures/` into the platform's test
   resources directory. Each platform's parser-roundtrip test must read every
   `.md` and every `.list.yml` under `fixtures/`, parse to the platform's
   model, re-emit, and assert byte-equal output. This is the parity guarantee.
3. **At runtime**: bundle `lexicons/shopping.en.json` as an app resource. Load
   on first launch.

## What goes here vs. what doesn't

**Goes here** (declarative, language-neutral):
- File format spec
- JSON Schemas
- SQL DDL for the cache (as documentation; each platform's ORM may reformat)
- Recurrence test cases
- ULID generation rules
- Bundled lexicons
- Fixture corpora

**Does not go here**:
- Application code in any language
- Platform-specific UI tokens (those live in `design/`)
- Sync transport specifications (out of scope for v1)
- Build scripts (those live per-platform under `platforms/`)
- Tooling (those live under `tools/` or per-platform)

## Versioning

Schemas under `format/` carry an implicit version (the set of fields). Adding
a new optional field is non-breaking — older clients ignore unknown keys.
Renaming or removing a field is breaking and requires a coordinated migration:

1. Add the new field as optional, populated alongside the old field.
2. Ship clients that read both, write the new field.
3. After a quiet period, mark the old field deprecated.
4. Eventually, ship a migration tool that walks the file tree and rewrites.

The `lamport` field exists precisely so concurrent migration writes can be
ordered after the fact — every change to the schema bumps every reminder's
`lamport`, which signals to downstream sync layers that a re-walk is needed.

## Status

**v0 draft.** All schemas are derived from `SPEC.md` §6 (reminder schema) and
§7 (storage). All fixtures are derived from the iOS reference implementation.
None of this is consumed by any client yet — that wiring is part of each
platform's first-tasks checklist.
