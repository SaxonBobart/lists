# Recurrence Examples

Golden examples for the supported RRULE subset.

```text
Daily:
RRULE:FREQ=DAILY

Every 2 days:
RRULE:FREQ=DAILY;INTERVAL=2

Weekly on Monday and Friday:
RRULE:FREQ=WEEKLY;BYDAY=MO,FR

Monthly on the 1st:
RRULE:FREQ=MONTHLY;BYMONTHDAY=1

Ten occurrences:
RRULE:FREQ=DAILY;COUNT=10

Until date:
RRULE:FREQ=DAILY;UNTIL=20261231T235959Z
```

Add concrete input/output expansion cases here when recurrence implementation becomes active.
