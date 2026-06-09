package io.github.saxonbobart.lists.core

import io.github.saxonbobart.lists.core.recurrence.RecurrenceEngine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset

class RecurrenceEngineTest {

    private val utc = ZoneOffset.UTC

    private fun next(from: String, rrule: String, zone: ZoneId = utc): Instant? =
        RecurrenceEngine.nextOccurrence(Instant.parse(from), rrule, zone)

    @Test
    fun `daily advances by interval, preserving time of day`() {
        assertEquals(
            Instant.parse("2026-06-02T09:00:00Z"),
            next("2026-06-01T09:00:00Z", "FREQ=DAILY"),
        )
        assertEquals(
            Instant.parse("2026-06-04T09:00:00Z"),
            next("2026-06-01T09:00:00Z", "FREQ=DAILY;INTERVAL=3"),
        )
    }

    @Test
    fun `weekly BYDAY finds the next selected weekday`() {
        // 2026-06-01 is a Monday; MO,FR from Monday -> Friday 06-05.
        assertEquals(
            Instant.parse("2026-06-05T09:00:00Z"),
            next("2026-06-01T09:00:00Z", "FREQ=WEEKLY;BYDAY=MO,FR"),
        )
        // ...and from Friday wraps to next Monday.
        assertEquals(
            Instant.parse("2026-06-08T09:00:00Z"),
            next("2026-06-05T09:00:00Z", "FREQ=WEEKLY;BYDAY=MO,FR"),
        )
    }

    @Test
    fun `weekly INTERVAL counts weeks from the anchor's week`() {
        assertEquals(
            Instant.parse("2026-06-15T09:00:00Z"),
            next("2026-06-01T09:00:00Z", "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO"),
        )
    }

    @Test
    fun `monthly BYMONTHDAY=31 skips short months`() {
        assertEquals(
            Instant.parse("2026-03-31T10:00:00Z"),
            next("2026-01-31T10:00:00Z", "FREQ=MONTHLY;BYMONTHDAY=31"),
        )
    }

    @Test
    fun `monthly ordinal BYDAY lands on the nth weekday`() {
        // Second Sunday of June 2026 is 06-14.
        assertEquals(
            Instant.parse("2026-06-14T10:00:00Z"),
            next("2026-06-01T10:00:00Z", "FREQ=MONTHLY;BYDAY=2SU"),
        )
        // Last Friday of June 2026 is 06-26.
        assertEquals(
            Instant.parse("2026-06-26T10:00:00Z"),
            next("2026-06-01T10:00:00Z", "FREQ=MONTHLY;BYDAY=-1FR"),
        )
    }

    @Test
    fun `yearly BYMONTH keeps the day of month`() {
        assertEquals(
            Instant.parse("2026-12-15T08:00:00Z"),
            next("2026-06-15T08:00:00Z", "FREQ=YEARLY;BYMONTH=6,12"),
        )
    }

    @Test
    fun `UNTIL ends the series`() {
        assertNull(next("2026-06-01T09:00:00Z", "FREQ=DAILY;UNTIL=20260601T235959Z"))
        assertEquals(
            Instant.parse("2026-06-02T09:00:00Z"),
            next("2026-06-01T09:00:00Z", "FREQ=DAILY;UNTIL=20260603T000000Z"),
        )
    }

    @Test
    fun `unparseable rules end the series safely`() {
        assertNull(next("2026-06-01T09:00:00Z", ""))
        assertNull(next("2026-06-01T09:00:00Z", "FREQ=SOMETIMES"))
        assertNull(next("2026-06-01T09:00:00Z", "INTERVAL=2"))
    }

    @Test
    fun `zoneFor falls back to the system zone for unknown identifiers`() {
        assertEquals(ZoneId.of("Australia/Sydney"), RecurrenceEngine.zoneFor("Australia/Sydney"))
        assertEquals(ZoneId.systemDefault(), RecurrenceEngine.zoneFor("Mars/OlympusMons"))
        assertEquals(ZoneId.systemDefault(), RecurrenceEngine.zoneFor(null))
    }

    @Test
    fun `wall-clock time is preserved across a DST change in the stored zone`() {
        val sydney = ZoneId.of("Australia/Sydney")
        // AEDT ends 2026-04-05: 09:00 Sydney is 22:00Z before, 23:00Z after.
        val from = Instant.parse("2026-04-03T22:00:00Z") // Apr 4, 09:00 AEDT
        val result = RecurrenceEngine.nextOccurrence(from, "FREQ=DAILY", sydney)!!
        assertEquals(Instant.parse("2026-04-04T23:00:00Z"), result) // Apr 5, 09:00 AEST
    }
}
