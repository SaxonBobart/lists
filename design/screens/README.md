# Screens — current-app reference

Full-resolution screenshots of the **live iOS app** (iPhone 17 Pro, light mode),
captured from a fresh install seeded with `SampleData`. This is the source of
truth for *what the app looks like today* — the starting point for design work.
Re-capture after visible UI changes (erase the sim, relaunch with
`--ui-testing-reset-data`, screenshot each screen).

| File | Screen |
|------|--------|
| `01-home-sidebar.png` | Home — smart-list tiles + My Lists |
| `01b-sidebar-expanded.png` | Sidebar with Projects expanded to its sub-lists |
| `02-smartlist-today.png` | Today — Overdue + Today, mixing tasks and events |
| `03-smartlist-scheduled.png` | Scheduled — upcoming dated items |
| `04-smartlist-flagged.png` | Flagged |
| `05-smartlist-alarms.png` | Alarms — items with an alarm trigger |
| `06-smartlist-all.png` | All |
| `07-smartlist-completed.png` | Completed |
| `08-tags-overview.png` | Tags overview |
| `09-tag-detail.png` | Items for a single tag |
| `10-list-work.png` | Work — sections, nested sub-items, recurrence badges, events |
| `11-task-detail.png` | Task — full-screen document view (title, fact strip, body) |
| `12-task-details.png` | Task — Details sheet (date, time, reminder, alarm, repeat, early reminder, type, flag) |
| `13-list-personal.png` | Personal — Health/Admin sections with habits |
| `14-habit-overview.png` | Habit — Overview (streak, flexible weekly goal, 52-week heatmap, recent log) |
| `15-habit-log.png` | Habit — full completion log (timestamped entries) |
| `16-habit-edit.png` | Habit — Details/Edit (frequency, flexible goal, reminder, show streak, etc.) |
| `17-list-groceries.png` | Groceries — shopping-list type |
| `18-list-travel.png` | Travel — events list |
| `19-event-detail.png` | Event — document view (start → end time span) |
| `20-note-detail.png` | Note — markdown document view (headings, bullets, checkboxes) |

The seed data behind these screens deliberately exercises every shipped feature:
the four item types (task / habit / note / event), sections, 3-level list
nesting, a shopping list, priorities, flags, reminders with early offsets,
recurrence, alarm triggers, all-day and timed/timezoned events, multi-day
events, habits with months of real completion history, and markdown notes.
