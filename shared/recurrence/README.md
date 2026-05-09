# Recurrence — RRULE subset

Reminders that recur use the `recurrence` field, an RFC 5545 RRULE string.
**Every platform must implement the same subset**; reminders that use a rule
outside the subset are accepted on read but write a console warning, and the
editor UI does not generate them.

## Supported RRULE keywords

| Keyword | Cardinality | Values | Notes |
|---|---|---|---|
| `FREQ` | required | `DAILY`, `WEEKLY`, `MONTHLY`, `YEARLY` | `HOURLY` / `MINUTELY` / `SECONDLY` rejected |
| `INTERVAL` | optional | positive integer ≥ 1 | default 1 |
| `BYDAY` | optional | `MO,TU,WE,TH,FR,SA,SU` (no offset prefix in v1) | offsets like `1MO` (first Monday) rejected |
| `BYMONTHDAY` | optional | `1`–`31` (positive only in v1) | negative offsets like `-1` rejected |
| `COUNT` | optional | positive integer | mutually exclusive with `UNTIL` |
| `UNTIL` | optional | ISO 8601 datetime UTC | mutually exclusive with `COUNT` |

That's it. **No `BYMONTH`, no `BYYEARDAY`, no `BYWEEKNO`, no `BYSETPOS`,
no `WKST`, no `BYHOUR`, no `BYMINUTE`, no `BYSECOND`, no `EXDATE`, no
`RDATE`.** The `examples.md` file in this directory is the conformance suite
every platform must pass.

## Examples (the canonical set)

```
FREQ=DAILY                                  every day
FREQ=DAILY;INTERVAL=3                       every 3 days
FREQ=WEEKLY                                 every 7 days
FREQ=WEEKLY;BYDAY=MO,WE,FR                  Mon, Wed, Fri
FREQ=WEEKLY;INTERVAL=2;BYDAY=SA             every other Saturday
FREQ=MONTHLY;BYMONTHDAY=1                   first of every month
FREQ=MONTHLY;BYMONTHDAY=15;INTERVAL=2       15th of every other month
FREQ=YEARLY                                 once a year on the start date
FREQ=DAILY;COUNT=30                         every day for 30 occurrences
FREQ=WEEKLY;BYDAY=FR;UNTIL=2027-12-31T23:59:59Z   every Friday until end of 2027
```

## What "expand" means

Each platform's recurrence engine has two operations:

1. **`nextOccurrence(rrule, after)`** — given the rule and a timestamp, return
   the next occurrence at or after that timestamp. Used to schedule the next
   alarm/notification. Returns `null` if the rule is exhausted.
2. **`occurrencesInRange(rrule, start, end)`** — return all occurrences in a
   half-open interval. Used to render the Scheduled view's calendar pane.
   Bounded by some sane maximum (e.g., 5 years of daily) to avoid infinite
   loops.

Recurrence is **never** materialised on disk. There is no `recurrences/` table
in the cache; rules expand lazily.

## Rationale for the subset

The full RFC 5545 RRULE grammar has corner cases that have produced bugs in
every major calendar implementation (Apple Calendar, Google Calendar, even
the reference `dateutil.rrule` Python implementation has `BYSETPOS` quirks).
A small subset is testable, verifiable, and covers the patterns a reminders
app actually needs:

- Daily / weekday / "every 3 days" recurrence
- Specific weekdays
- Monthly on day-N
- Yearly anniversary
- Bounded by count or end date

Anything more elaborate — "the last Monday of the month at 3pm except in
August" — belongs in a calendar app, not a reminders app.

## Test-suite location

`examples.md` in this directory contains golden input/output pairs. Every
platform's RRULE implementation runs them. A platform that fails any of
them is not standards-compliant for Lists.
