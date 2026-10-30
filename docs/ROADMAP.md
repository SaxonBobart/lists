# Lists Roadmap

Updated: 27 October 2026

Lists is unpublished and in development. The local iOS implementation is the
source of truth. Current capabilities are summarized in [README](../README.md)
and specified in [PRODUCT-SPEC](../PRODUCT-SPEC.md).

## Before a release

- Run the final Release build on a supported physical iPhone.
- Verify notification authorization, delivery and recurrence across app
  suspension/relaunch, including distinct delivered and future occurrences.
- Exercise camera/video capture, scanning, audio interruptions/recovery, Files
  import, Quick Look, export and recoverable deletion on a device.
- Verify incoming Calendar permission, refresh, local/source conflicts,
  disconnect and unavailable-source behavior against a disposable calendar.
- Exercise Columns, nested-list reveal, file/item moves, Month drag/drop and
  timeline create/move/resize with recurring-item scope choices.
- Check VoiceOver, accessibility Dynamic Type and hardware keyboards across
  documents, tables, Calendar and Columns.

Simulator tests and snapshots protect substantial behavior, but do not replace
these device checks. The dated [audit record](AUDIT-2026-10-27.md) records the
cleanup's actual verification and remaining limits.

## Distribution, when requested

App Store Connect setup, privacy answers, screenshots, signing, archive/upload
and internal TestFlight installation still need an explicit release task.
Decide version/build numbers against the actual distribution record then.
No release, push or change to `main` is implied by this roadmap.

## Deferred capabilities

- Cloud sync, collaboration and other platform clients.
- Two-way calendar writes and invitation responses. Incoming EventKit
  connections already exist and remain read-only toward the source.
- AlarmKit alarms beyond ordinary local notifications.
- Drawing/canvas creation and in-app agent integrations.

External-link previews and remote metadata fetching remain excluded. Any new
feature should preserve portable files, native interaction and data recovery.
