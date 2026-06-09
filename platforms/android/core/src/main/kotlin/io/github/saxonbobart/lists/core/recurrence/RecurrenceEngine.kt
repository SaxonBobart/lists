package io.github.saxonbobart.lists.core.recurrence

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.YearMonth
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.Locale

/**
 * Pure recurrence expansion, ported from the iOS `RecurrenceEngine`. Given a
 * fired due date and the stored RRULE string, computes the next occurrence —
 * or null when the rule is unparseable or the series has ended.
 *
 * Handles `FREQ`, `INTERVAL`, `UNTIL`, weekly/monthly/yearly `BYDAY`
 * (incl. ordinal prefixes like `2SU` / `-1FR`), `BYMONTHDAY`, and `BYMONTH`.
 * Unknown fields are ignored; never throws.
 */
object RecurrenceEngine {

    /**
     * Next occurrence strictly after [from], advancing by the rule. [from] is
     * the anchor occurrence, so INTERVAL counts from it. [zone] plays the role
     * of the iOS calendar parameter — see [zoneFor].
     */
    fun nextOccurrence(
        from: Instant,
        rrule: String,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Instant? {
        val parts = rrule.split(";").mapNotNull { part ->
            val kv = part.split("=", limit = 2)
            if (kv.size == 2) kv[0].uppercase() to kv[1] else null
        }.toMap()

        val freq = parts["FREQ"] ?: return null
        val interval = maxOf(1, parts["INTERVAL"]?.toIntOrNull() ?: 1)
        val until = parts["UNTIL"]?.let(::parseUntil)
        val start = from.atZone(zone)

        val next: Instant? = when (freq) {
            "HOURLY" -> start.plusHours(interval.toLong()).toInstant()
            "DAILY" -> start.plusDays(interval.toLong()).toInstant()
            "WEEKLY" -> {
                val byday = parts["BYDAY"]
                if (byday != null) {
                    nextWeekly(start, byday, interval)
                } else {
                    start.plusWeeks(interval.toLong()).toInstant()
                }
            }

            "MONTHLY" -> {
                val bymd = parts["BYMONTHDAY"]
                val ordinal = parts["BYDAY"]?.let(::parseOrdinalDay)
                when {
                    bymd != null -> nextMonthlyByDay(start, parseInts(bymd), interval)
                    ordinal != null -> nextMonthlyOrdinal(start, ordinal.first, ordinal.second, interval)
                    else -> start.plusMonths(interval.toLong()).toInstant()
                }
            }

            "YEARLY" -> {
                val months = (parts["BYMONTH"]?.let(::parseInts) ?: emptyList()).sorted()
                if (months.isEmpty()) {
                    start.plusYears(interval.toLong()).toInstant()
                } else {
                    nextYearly(start, months, parts["BYDAY"]?.let(::parseOrdinalDay), interval)
                }
            }

            else -> null
        }

        if (next == null) return null
        if (until != null && next > until) return null
        return next
    }

    /**
     * The zone a stored `dueTimeZone` identifier pins recurrence math to
     * (REC-1), so a repeating task advances in the zone it was authored in.
     * Falls back to the system zone when null or unrecognised.
     */
    fun zoneFor(identifier: String?): ZoneId {
        if (identifier == null) return ZoneId.systemDefault()
        return try {
            ZoneId.of(identifier)
        } catch (_: Exception) {
            ZoneId.systemDefault()
        }
    }

    // MARK: Parsing helpers

    // RFC 5545 weekday codes -> Calendar-style weekday numbers (1=SU..7=SA),
    // matching the iOS implementation.
    private val weekdayMap = mapOf(
        "SU" to 1, "MO" to 2, "TU" to 3, "WE" to 4, "TH" to 5, "FR" to 6, "SA" to 7,
    )

    private fun calWeekday(dow: DayOfWeek): Int = dow.value % 7 + 1

    private fun parseInts(s: String): List<Int> = s.split(",").mapNotNull { it.toIntOrNull() }

    /** Parse an ordinal BYDAY token ("2SU", "-1FR") -> (ordinal, weekday).
     *  Returns null for plain weekday codes. */
    private fun parseOrdinalDay(byday: String): Pair<Int, Int>? {
        val token = byday.split(",").firstOrNull() ?: byday
        if (token.length < 3) return null
        val code = token.takeLast(2).uppercase()
        val n = token.dropLast(2).toIntOrNull() ?: return null
        val wd = weekdayMap[code] ?: return null
        return n to wd
    }

    private val untilFormat = DateTimeFormatter.ofPattern("uuuuMMdd'T'HHmmss'Z'", Locale.ROOT)

    private fun parseUntil(s: String): Instant? = try {
        LocalDateTime.parse(s, untilFormat).toInstant(ZoneOffset.UTC)
    } catch (_: DateTimeParseException) {
        null
    }

    // MARK: Frequency expanders

    /** WEEKLY + BYDAY: next selected weekday, honouring INTERVAL weeks
     *  measured from `from`'s week. Day-stepping preserves wall-clock time. */
    private fun nextWeekly(from: ZonedDateTime, byday: String, interval: Int): Instant? {
        val wanted = byday.split(",").mapNotNull { weekdayMap[it.uppercase()] }.toSet()
        if (wanted.isEmpty()) return null
        val firstDay = WeekFields.of(Locale.getDefault()).firstDayOfWeek
        val fromWeek = from.toLocalDate().with(TemporalAdjusters.previousOrSame(firstDay))
        for (offset in 1..(7 * interval + 7)) {
            val cand = from.plusDays(offset.toLong())
            if (calWeekday(cand.dayOfWeek) !in wanted) continue
            val candWeek = cand.toLocalDate().with(TemporalAdjusters.previousOrSame(firstDay))
            val weeks = ChronoUnit.DAYS.between(fromWeek, candWeek) / 7
            if (weeks % interval == 0L) return cand.toInstant()
        }
        return null
    }

    /** MONTHLY + BYMONTHDAY: next listed day-of-month, honouring INTERVAL. */
    private fun nextMonthlyByDay(from: ZonedDateTime, days: List<Int>, interval: Int): Instant? {
        val sortedDays = days.filter { it in 1..31 }.sorted()
        if (sortedDays.isEmpty()) return null
        for (k in 0..24) {
            val ym = YearMonth.from(from.toLocalDate()).plusMonths((k * interval).toLong())
            for (d in sortedDays) {
                if (d > ym.lengthOfMonth()) continue
                val cand = dateAt(ym.year, ym.monthValue, d, from)
                if (cand.toInstant() > from.toInstant()) return cand.toInstant()
            }
        }
        return null
    }

    /** MONTHLY + ordinal BYDAY (e.g. "2SU"): Nth weekday of each active month. */
    private fun nextMonthlyOrdinal(
        from: ZonedDateTime,
        ordinal: Int,
        weekday: Int,
        interval: Int,
    ): Instant? {
        for (k in 0..24) {
            val ym = YearMonth.from(from.toLocalDate()).plusMonths((k * interval).toLong())
            val cand = nthWeekday(ordinal, weekday, ym.year, ym.monthValue, from) ?: continue
            if (cand.toInstant() > from.toInstant()) return cand.toInstant()
        }
        return null
    }

    /** YEARLY + BYMONTH, optionally refined by an ordinal weekday. Without an
     *  ordinal, keeps `from`'s day-of-month (clamped to the month's length). */
    private fun nextYearly(
        from: ZonedDateTime,
        months: List<Int>,
        ordinalDay: Pair<Int, Int>?,
        interval: Int,
    ): Instant? {
        val fromYear = from.year
        val fromDay = from.dayOfMonth
        for (k in 0..20) {
            val y = fromYear + k * interval
            for (m in months) {
                val cand = if (ordinalDay != null) {
                    nthWeekday(ordinalDay.first, ordinalDay.second, y, m, from)
                } else {
                    val d = minOf(fromDay, YearMonth.of(y, m).lengthOfMonth())
                    dateAt(y, m, d, from)
                }
                if (cand != null && cand.toInstant() > from.toInstant()) return cand.toInstant()
            }
        }
        return null
    }

    // MARK: Date math helpers

    /** A date at year/month/day with the time-of-day copied from [timeFrom]. */
    private fun dateAt(year: Int, month: Int, day: Int, timeFrom: ZonedDateTime): ZonedDateTime =
        LocalDate.of(year, month, day)
            .atTime(LocalTime.of(timeFrom.hour, timeFrom.minute, timeFrom.second))
            .atZone(timeFrom.zone)

    /** Date of the Nth `weekday` in a month (1..5, or negative for "last"). */
    private fun nthWeekday(
        ordinal: Int,
        weekday: Int,
        year: Int,
        month: Int,
        timeFrom: ZonedDateTime,
    ): ZonedDateTime? {
        val dim = YearMonth.of(year, month).lengthOfMonth()
        if (ordinal < 0) {
            for (d in dim downTo 1) {
                val cand = dateAt(year, month, d, timeFrom)
                if (calWeekday(cand.dayOfWeek) == weekday) return cand
            }
            return null
        }
        var count = 0
        for (d in 1..dim) {
            val cand = dateAt(year, month, d, timeFrom)
            if (calWeekday(cand.dayOfWeek) == weekday) {
                count += 1
                if (count == ordinal) return cand
            }
        }
        return null
    }
}
