# Recurrence

Lists supports a small RRULE subset.

Supported:

- `FREQ`
- `INTERVAL`
- `BYDAY`
- `BYMONTHDAY`
- `COUNT`
- `UNTIL`

Unsupported fields should be rejected or ignored deliberately, not partially implemented by accident.

Use `examples.md` for golden cases.
