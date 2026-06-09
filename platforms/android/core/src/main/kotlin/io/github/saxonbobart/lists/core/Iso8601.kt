package io.github.saxonbobart.lists.core

import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale

/**
 * Single source of truth for date <-> string conversion at the file-format
 * boundary. The on-disk format is ISO 8601 internet date-time with fractional
 * seconds (e.g. `2026-05-09T15:30:00.000Z`) — byte-identical to what the iOS
 * app's `ISO8601DateFormatter` writes, so the two platforms can share a library.
 */
object Iso8601 {
    private val writer: DateTimeFormatter =
        DateTimeFormatter.ofPattern("uuuu-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT)
            .withZone(ZoneOffset.UTC)

    /** Date-only form used by habit day-grouping and `due_all_day` items. */
    private val dayWriter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("uuuu-MM-dd", Locale.ROOT).withZone(ZoneOffset.UTC)

    fun string(from: Instant): String = writer.format(from)

    fun dayString(from: Instant): String = dayWriter.format(from)

    /**
     * Parse an on-disk date. Accepts the canonical fractional-seconds UTC form,
     * any ISO instant/offset form (tolerant superset of iOS), and the date-only
     * `yyyy-MM-dd` form (midnight UTC, matching iOS's day formatter).
     */
    fun instant(from: String): Instant? {
        try {
            return Instant.parse(from)
        } catch (_: DateTimeParseException) {
        }
        try {
            return OffsetDateTime.parse(from).toInstant()
        } catch (_: DateTimeParseException) {
        }
        return try {
            LocalDate.parse(from).atStartOfDay(ZoneOffset.UTC).toInstant()
        } catch (_: DateTimeParseException) {
            null
        }
    }
}
