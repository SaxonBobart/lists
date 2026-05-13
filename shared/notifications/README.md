# Notifications

Notification behavior should match product behavior, but platform APIs will differ.

Current iOS path:

- Standard reminders use `UNUserNotificationCenter`.
- AlarmKit is deferred until a paid Apple Developer Program account exists.
- Scheduling code lives under `platforms/ios/Lists/Core/Notifications/`.

Rules:

- Completion, deletion, and date/time edits cancel stale scheduled events.
- Date-only reminders use the user's default reminder time.
- Recurring reminders should schedule the next occurrence, not every future occurrence.
- Permission-denied states should not corrupt item data.
