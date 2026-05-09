# Lexicons

Static data files bundled with every platform's binary. Currently only one
exists: the shopping-item categorisation lexicon for shopping lists.

## `shopping.en.json`

Maps common English grocery item names to their canonical section. Loaded
once at first launch. Used by the shopping-list capture flow: when a user
adds a shopping item, the lexicon picks the section unless the user
overrides it.

The lexicon is **rules-based, not ML**. The cost of a wrong guess is one tap
to fix, and the win is offline determinism + zero network calls.

### Schema

```json
{
    "version": "1",
    "default_section": "Other",
    "sections": [
        "Produce", "Dairy", "Meat", "Seafood", "Bakery",
        "Pantry", "Frozen", "Beverages", "Snacks",
        "Household", "Other"
    ],
    "entries": {
        "milk":    "Dairy",
        "apple":   "Produce",
        "chicken": "Meat",
        "...":     "..."
    }
}
```

- `entries` keys are matched **case-insensitively** against the user's
  captured item title. Match is "any token in the title appears as a key" —
  e.g., "organic apples" matches `apple`.
- `default_section` is used when no key matches.
- `version` lets future updates ship changed lexicons without breaking
  existing clients (clients warn if `version` is higher than they support).

### Localisation

Future locales follow `shopping.<lang>.json` where `<lang>` is an ISO 639-1
language tag. The user's preferred locale picks the file at runtime; falls
back to `shopping.en.json` if the locale-specific file is absent.

### Status

The current `shopping.en.json` is a **placeholder skeleton with ~20 entries**.
The full v1 lexicon needs ~200 entries seeded by hand from a public-domain
grocery taxonomy. SPEC.md §13 calls this out as a "discrete pre-v1 task" —
one afternoon's content work; not algorithmic.

### Where each platform loads it

- iOS: bundled as a `Resources/Lexicons/shopping.en.json`; loaded via `Bundle.main`.
- Android: bundled as `app/src/main/assets/lexicons/shopping.en.json`; loaded via `AssetManager`.
- Windows: bundled as a `Content` item in the `.csproj`; loaded via `Application.GetResourceStream`.
- Linux: installed under `$datadir/lists/lexicons/shopping.en.json` by Meson.

Each platform copies (or symlinks during dev) from this directory.
