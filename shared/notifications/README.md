# Notifications & alarms — cross-platform parity matrix

This is the contract every platform's notification scheduler must implement.
The contract is described first abstractly, then mapped to each platform's
APIs.

## Abstract model

A reminder produces zero, one, or two scheduled events:

| Reminder state | Event |
|---|---|
| `urgent && has_time` | An **alarm** that breaks through Focus / Do-Not-Disturb, requires explicit dismissal, and persists across app uninstall+reinstall is best-effort. |
| `!urgent && date && time` | A **notification** at exactly `date date time` (local). Standard banner; respects Focus/DND. |
| `!urgent && date && !time` | A **notification** at the user's default-time-of-day on `date` (default 09:00 local; configurable). |
| `!urgent && !date` | **No event.** The reminder is a task without a scheduled trigger. |
| `urgent && !has_time` | **Rejected at edit time.** The UI disables the urgent toggle. |

When a reminder mutates (date, time, urgency, completion, soft-delete), the
existing event is cancelled and (if applicable) a new event scheduled. Event
identity = reminder `id`.

## Platform API mapping

| Concept | iOS | Android | Windows | Linux |
|---|---|---|---|---|
| Notification | `UNUserNotificationCenter` + `UNCalendarNotificationTrigger` | `NotificationCompat` + `setExactAndAllowWhileIdle` | `AppNotificationManager` (Win App SDK) | `GNotification` |
| Alarm (break-through-Focus) | AlarmKit | `AlarmManager.setAlarmClock` + full-screen-intent activity + `USE_FULL_SCREEN_INTENT` | Toast `scenario="alarm"` + `audio loop="true"` + foreground keepalive | `GNotification` `URGENT` + GStreamer audio loop + RTC wake via `systemd-run --timer-property=WakeSystem=true` |
| Permission grant point | First urgent schedule | First notification schedule (`POST_NOTIFICATIONS`) | First notification schedule | First notification schedule (Background Apps portal) |
| Snooze action | Notification action button | Notification action button | Toast action | Notification action |
| Complete action | Notification action button | Notification action button | Toast action | Notification action |
| Boot persistence | OS handles | App must `RECEIVE_BOOT_COMPLETED` and re-arm | OS handles (toasts) / app re-arm (alarm) | Daemon re-arms on user login |

## Edge cases every platform must handle

1. **Permission denied.** Schedule silently skipped; banner offered in
   Settings to reopen the system permission UI.
2. **Time zone changes** (user travels). Re-evaluate scheduled events on
   `UIApplication.didBecomeActive` / equivalent.
3. **Daylight savings** spring-forward and fall-back. A reminder at "02:30"
   on a spring-forward day should fire at "03:30"; on a fall-back day it
   should fire once at the first 02:30, not twice.
4. **Recurrence.** Schedule only the *next* occurrence at any given time.
   On firing (or completion), schedule the following occurrence. This avoids
   materialising hundreds of pending notification requests.
5. **Soft delete.** Cancel any pending event whose reminder id was just
   tombstoned.
6. **Cache rebuild without notification rebuild.** When the cache is wiped
   and rebuilt, the OS-level scheduled notifications are still active. The
   rebuild process must reconcile: walk the `notification_state` table,
   verify each entry corresponds to a reminder still scheduling that event,
   else cancel.

## Default time-of-day for date-only reminders

A reminder with `date` but no `time` fires at the user's default time. The
default is **09:00 local**. Configurable in Settings.

## Quiet-hours interaction

| Platform | Mechanism | Notes |
|---|---|---|
| iOS | Focus + Critical Alert entitlement | AlarmKit bypasses Focus by design. Non-urgent notifications respect Focus. |
| Android | Do Not Disturb | `AlarmManager.setAlarmClock` is exempt; `setExactAndAllowWhileIdle` is not. Notification channel `bypassDnd(true)` for the urgent channel. |
| Windows | Focus Assist | Toast `scenario="alarm"` overrides Focus Assist. App must surface a banner if Focus Assist is enabled and a non-alarm notification was suppressed. |
| Linux | GNOME Do Not Disturb / KDE Focus | `urgency=critical` on `org.freedesktop.Notifications` overrides; lower urgencies are queued. |

## Sources of truth in this repo

- iOS: `platforms/ios/Lists/` (notification code lives in
  `Features/Capture` and the planned `Notifications/` module — not yet built).
- Android: `research/android-stack.md` §5.
- Windows: `research/windows-stack.md` §5.
- Linux: `research/linux-stack.md` §8.
- This document and `research/notification-parity.md` (planned, post-v1) are
  the cross-platform reconciliation.
