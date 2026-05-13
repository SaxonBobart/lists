# Shared Contracts

`shared/` holds format contracts and test fixtures used to keep future platforms compatible with the iOS app.

The active app is iOS. Nothing in this directory is executable app code.

## Contents

- `format/` - markdown/YAML file format notes and JSON Schemas
- `fixtures/` - golden parser inputs
- `recurrence/` - small RRULE subset and examples
- `ulid/` - id rules
- `cache/` - rebuildable cache shape
- `notifications/` - cross-platform scheduling notes
- `lexicons/` - static data, currently a placeholder shopping lexicon

## Rule

Files on disk are the source of truth. Platform caches are rebuildable.

Some documents still use older "reminder" wording. The iOS app now uses the broader `Item` model. Align wording with the app when touching a specific contract.
