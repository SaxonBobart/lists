# ULID — generation rules

Lists uses [ULIDs](https://github.com/ulid/spec) as the stable
identifier for every list and every reminder. ULIDs are 128 bits, encoded
as a 26-character Crockford base32 string.

## Format

```
01HX2A9F3K4VYTGN3RH8XPQM5K
└────┬────┘└─────┬─────────┘
     |          80 bits randomness (16 chars Crockford-base32)
     48 bits Unix timestamp in milliseconds (10 chars Crockford-base32)
```

## Crockford base32 alphabet

```
0 1 2 3 4 5 6 7 8 9 A B C D E F G H J K M N P Q R S T V W X Y Z
```

Note the omitted letters: `I`, `L`, `O`, `U`. (Avoids visual confusion with
`1`, `0`, and obscenity-as-substring respectively.)

## Generation rules

1. **Time component** is 48 bits = the Unix timestamp in **milliseconds**
   (not seconds). Big-endian. Encoded as the first 10 characters.
2. **Random component** is 80 bits of cryptographic randomness, encoded as
   the last 16 characters.
3. **Monotonic guarantee within the same millisecond.** If two ULIDs are
   generated in the same millisecond, the second's random component must be
   strictly greater than the first's, by treating the random component as a
   big-endian integer and incrementing. If incrementing would overflow,
   throw or wait for the next millisecond.
4. **Per-process generator state** to maintain monotonicity. Each platform's
   generator holds (last_ms, last_random) in process memory.

## Sortability

ULIDs are **lexicographically sortable by creation time**. This is the
property that lets Lists use `id` as the natural sort key in the
reminder list (newest at the bottom of the user's list, oldest at the top).

A consequence: a reminder file whose `id`'s 10-character timestamp prefix
disagrees with its `created` field is suspicious — either someone hand-
edited the file, or the original generator was buggy. The cache rebuilder
should accept it but log a warning.

## Crockford parse rules

Crockford base32 is **case-insensitive on decode** but **uppercase on encode**.
That is: a parser that reads `01HX2A9F3K4VYTGN3RH8XPQM5K` and
`01hx2a9f3k4vytgn3rh8xpqm5k` returns the same value. Generators always emit
uppercase.

## Reserved sentinel ids

Some ids are reserved for system-managed entities. Generators MUST NOT
produce these by chance (they're outside the random space).

| Sentinel | Purpose |
|---|---|
| `00000000000000000000INBOX0` | The bundled "Inbox" list. Created on first launch; survives renames. |

The Inbox sentinel is technically not a valid ULID under the time-prefix
rule (its first 10 chars are zeros), but it is treated as one for storage
purposes. New sentinels in future versions follow the same pattern:
`00000000000000000000<7CHARS>` where `<7CHARS>` is uppercase Crockford.

## Implementations

- **iOS**: in `platforms/ios/Lists/Core/Identifiers/ULID.swift` (~30 LOC).
- **Android**: hand-roll in Kotlin (≈40 LOC) or use [`ulid-creator`](https://github.com/f4b6a3/ulid-creator) (Apache-2.0). The hand-roll is recommended — it eliminates one dep and the code is trivial.
- **Windows**: hand-roll in C# or use [`NetUlid`](https://github.com/RyoukoKonpaku/NetUlid) (MIT). Hand-roll preferred.
- **Linux**: hand-roll in Vala (≈50 LOC). No suitable library exists.

## Test cases

Every platform's ULID generator must pass:

1. Generate 1000 ULIDs in a tight loop. Sort lexicographically. Resulting
   order must be the same as the order of generation (monotonic).
2. Generate at known timestamp T. Decode the first 10 chars. Decoded
   timestamp must equal T.
3. Generate 1,000,000 ULIDs. No collisions.
4. Decode the Inbox sentinel. The result is identifiable as the sentinel
   (no exception thrown).

## Why ULID and not UUID v7

UUID v7 has the same time-sortability property (since 2024 RFC 9562). The
practical reasons for ULID:

- **Crockford base32 is case-insensitive and human-typeable.** UUIDs use
  hyphens and 16 ambiguous characters (8/B, 0/O).
- **No hyphens.** Filenames stay short and the file path doesn't need
  escaping in any shell.
- **Implementations are simpler** (~30 LOC). UUID v7 needs a v4 fallback,
  variant bits, version bits.

The migration cost from ULID to UUID v7 if we ever wanted to is bounded:
both are 128-bit ids in a string envelope, so a cache-rebuild migration
that re-keys every file is a single afternoon.
