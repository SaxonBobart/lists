# Recurrence — golden examples

Each example has the form: input rule + start anchor → expected occurrences
in a window. Every platform's RRULE expander must produce exactly these
outputs.

The "anchor" is the date the recurring reminder was first set for. RFC 5545
calls this `DTSTART`; in Lists it's the reminder's `date` field.

## Daily

```
FREQ=DAILY
anchor: 2026-05-04
window: [2026-05-04, 2026-05-10)
expected:
    2026-05-04
    2026-05-05
    2026-05-06
    2026-05-07
    2026-05-08
    2026-05-09
```

```
FREQ=DAILY;INTERVAL=3
anchor: 2026-05-04
window: [2026-05-04, 2026-06-01)
expected:
    2026-05-04
    2026-05-07
    2026-05-10
    2026-05-13
    2026-05-16
    2026-05-19
    2026-05-22
    2026-05-25
    2026-05-28
    2026-05-31
```

## Weekly

```
FREQ=WEEKLY;BYDAY=MO,WE,FR
anchor: 2026-05-04   (Monday)
window: [2026-05-04, 2026-05-18)
expected:
    2026-05-04   Mon
    2026-05-06   Wed
    2026-05-08   Fri
    2026-05-11   Mon
    2026-05-13   Wed
    2026-05-15   Fri
```

```
FREQ=WEEKLY;INTERVAL=2;BYDAY=SA
anchor: 2026-05-09   (Saturday)
window: [2026-05-09, 2026-07-01)
expected:
    2026-05-09
    2026-05-23
    2026-06-06
    2026-06-20
```

## Monthly

```
FREQ=MONTHLY;BYMONTHDAY=1
anchor: 2026-05-01
window: [2026-05-01, 2026-12-01)
expected:
    2026-05-01
    2026-06-01
    2026-07-01
    2026-08-01
    2026-09-01
    2026-10-01
    2026-11-01
```

Edge case: short months. `BYMONTHDAY=31` skips months that don't have a 31st.

```
FREQ=MONTHLY;BYMONTHDAY=31
anchor: 2026-01-31
window: [2026-01-31, 2026-12-31]
expected:
    2026-01-31
    2026-03-31
    2026-05-31
    2026-07-31
    2026-08-31
    2026-10-31
    2026-12-31
```

## Yearly

```
FREQ=YEARLY
anchor: 2026-05-04
window: [2026-05-04, 2031-05-05)
expected:
    2026-05-04
    2027-05-04
    2028-05-04
    2029-05-04
    2030-05-04
```

Edge case: Feb 29 anniversary. In v1, occurrences fall on Feb 28 in non-leap
years (NOT Mar 1; "rolling backward" to the closest valid date).

```
FREQ=YEARLY
anchor: 2024-02-29
window: [2024-02-29, 2029-03-01)
expected:
    2024-02-29
    2025-02-28
    2026-02-28
    2027-02-28
    2028-02-29
```

## Bounded recurrence

```
FREQ=DAILY;COUNT=5
anchor: 2026-05-04
expected (all):
    2026-05-04
    2026-05-05
    2026-05-06
    2026-05-07
    2026-05-08
```

```
FREQ=WEEKLY;BYDAY=FR;UNTIL=2026-06-15T23:59:59Z
anchor: 2026-05-08   (Friday)
expected (all):
    2026-05-08
    2026-05-15
    2026-05-22
    2026-05-29
    2026-06-05
    2026-06-12
```

## Invalid inputs (must be rejected at write time)

```
FREQ=HOURLY                       — sub-day frequency, not supported
FREQ=DAILY;BYSETPOS=1             — BYSETPOS not in subset
FREQ=MONTHLY;BYDAY=1MO            — offset weekday not supported
FREQ=DAILY;COUNT=5;UNTIL=2027-01-01T00:00:00Z   — COUNT and UNTIL mutually exclusive
FREQ=MONTHLY;BYMONTHDAY=-1        — negative month-day not supported
```

Every platform's editor must reject these at user-input time. Files on disk
that contain them are accepted on read (so partner apps that emit richer
RRULEs don't break Lists), but the affected reminder schedules its
next occurrence using the safest interpretation: the editor sees the warning,
the alarm-scheduler treats the rule as one-shot.

## Test harness (suggested)

A platform's test for the recurrence engine reads this file, parses each
example block, and asserts the engine's output matches. The format is loose
enough to be parsed by a 30-line script in any language.
