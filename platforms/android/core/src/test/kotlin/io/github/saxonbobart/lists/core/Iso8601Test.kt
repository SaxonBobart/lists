package io.github.saxonbobart.lists.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

class Iso8601Test {

    @Test
    fun `writes the canonical fractional-seconds UTC form iOS writes`() {
        assertEquals(
            "2026-05-09T15:30:00.000Z",
            Iso8601.string(Instant.parse("2026-05-09T15:30:00Z")),
        )
        assertEquals(
            "2026-05-09T15:30:00.123Z",
            Iso8601.string(Instant.parse("2026-05-09T15:30:00.123456Z")),
        )
    }

    @Test
    fun `parses fractional, whole-second, offset, and day-only forms`() {
        val expected = Instant.parse("2026-05-09T15:30:00Z")
        assertEquals(expected, Iso8601.instant("2026-05-09T15:30:00.000Z"))
        assertEquals(expected, Iso8601.instant("2026-05-09T15:30:00Z"))
        assertEquals(expected, Iso8601.instant("2026-05-10T01:30:00+10:00"))
        assertEquals(Instant.parse("2026-05-09T00:00:00Z"), Iso8601.instant("2026-05-09"))
        assertNull(Iso8601.instant("not a date"))
    }

    @Test
    fun `round trips through string`() {
        val now = Instant.parse("2026-06-09T01:02:03.456Z")
        assertEquals(now, Iso8601.instant(Iso8601.string(now)))
    }
}
