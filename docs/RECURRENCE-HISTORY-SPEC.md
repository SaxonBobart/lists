# Recurrence and Completion History

Status: settled product behavior, parked until the current Markdown linking work is complete.

## Product model

- A repeating item is one durable Markdown document. Repetition must never clone the document body, attachments, or file for each occurrence.
- Occurrence tracking is the default behavior, not a separate power-user mode or toggle.
- Each scheduled occurrence is lightweight metadata owned by the repeating item. It has a stable occurrence identifier, scheduled date and time, time zone, status, and an optional exact completion timestamp.
- Occurrence status distinguishes at least the current open occurrence, a genuine completion, and a missed occurrence. Skipping or deleting an occurrence must never be recorded as a false completion.
- At the next recurrence boundary, an unresolved occurrence becomes missed and the newly scheduled occurrence becomes current. The primary UI continues to show one item and one checkbox, never a backlog of duplicated rows.

## Completing and notifications

- Completing the current occurrence records exactly one genuine completion at the exact completion time. It never backfills previous missed occurrences as completed.
- Completion advances the item to its next future occurrence, clears every delivered notification belonging to that recurring series, and leaves future reminders scheduled.
- Notifications are prompts, not completion records. Clearing them from Notification Center never completes an occurrence.
- Recurring task notifications may accumulate in Notification Center even though the app still presents one current item.
- Notification requests need occurrence-aware identities beneath a stable root item identity. This lets Lists clear all delivered prompts for a series without cancelling its next pending reminder.
- Correcting an old occurrence to overdue or missed must not fire an old notification retroactively. The current and future notification schedule remains authoritative.

## Habits remain distinct

- Habit reminders are gentle, latest-only nudges and should not accumulate. At most one current habit notification should be visible for a habit.
- Completing a habit clears its current delivered notification while preserving its future schedule.
- Habit notification copy stays neutral, such as “Drink water.” Lists must not display guilt-based backlog language such as “20 reminders missed.”
- Habit history records actual completion timestamps and cycle history; it does not invent completions for missed cycles.

## Completion History

- A recurring item exposes an item-scoped **Completion History** view through progressive disclosure. There is no global History or Missed smart list and no tracking toggle.
- History presents scheduled occurrences chronologically with their exact status, scheduled time, and completion time.
- Only genuine completions appear in the normal Completed experience. Missed occurrences never masquerade as completed items.
- A user can correct a missed occurrence to completed and backdate its completion time, for example when they completed something yesterday but forgot to log it.
- A user can edit a completion timestamp or correct a completed occurrence back to missed.
- Historical corrections update the normal Completed experience but never alter the current occurrence, the future recurrence schedule, or the current notification.
- Changing a recurrence rule affects future occurrences only. Existing history remains intact.
- Uncompleting an historical completion corrects that occurrence to an explicit overdue or missed state without rewinding or rewriting the current schedule.

## Persistence and compatibility

- Occurrence history belongs in the repeating item’s metadata, not in separate cloned Markdown files.
- Lists is pre-version-one and has no released production dataset requiring a general migration framework. During development, compatibility work only needs to preserve Saxon’s simulator and device data plus valuable fixtures.
- Existing development-era successor chains may be converted once into the integrated model. Preserve the latest open occurrence and every genuine prior completion; never infer that missed occurrences were completed.

## Verification still required

- Apple documents that scheduling a notification with an existing request identifier replaces the pending request. That does not by itself prove how multiple already-delivered repeating notifications behave on iOS 27.
- Probe actual iOS 27 behavior before finalizing latest-only habit delivery. Existing mocks that store delivered identifiers in a `Set` can hide duplicate deliveries and are not sufficient evidence.
- The solution remains local-first; recurrence and notification behavior does not require server infrastructure.
