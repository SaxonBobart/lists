package io.github.saxonbobart.lists.core.model

import io.github.saxonbobart.lists.core.habits.HabitCycle
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID

/**
 * A single timestamped habit completion event — the stored source of truth for
 * a habit's history. Per-cycle counts are derived by grouping these events
 * through [HabitCycle.key].
 */
data class HabitCompletion(
    val id: UUID = UUID.randomUUID(),
    /** The absolute instant the completion is attributed to. */
    val at: Instant,
) {
    companion object {
        /**
         * One-way migration from the legacy `completion_log: [cycleKey: count]`
         * shape into timestamped events. Each count becomes that many events at
         * a representative instant inside the original cycle, spread one second
         * apart, so regrouping reproduces the original counts exactly.
         */
        fun migrate(
            legacyLog: Map<String, Int>,
            frequency: HabitFrequency,
            zone: ZoneId = ZoneId.systemDefault(),
        ): List<HabitCompletion> {
            val result = mutableListOf<HabitCompletion>()
            for ((key, count) in legacyLog.entries.sortedBy { it.key }) {
                if (count <= 0) continue
                val base = representativeDate(key, frequency, zone) ?: continue
                for (i in 0 until count) {
                    result.add(HabitCompletion(at = base.plusSeconds(i.toLong())))
                }
            }
            return result
        }

        /**
         * A stable instant guaranteed to land inside the cycle named by [key],
         * matching the calendar/timezone conventions of [HabitCycle.key]
         * (UTC for day/month/year; default-zone for week/quarter/half).
         */
        private fun representativeDate(
            key: String,
            frequency: HabitFrequency,
            zone: ZoneId,
        ): Instant? = when (frequency) {
            HabitFrequency.DAILY, HabitFrequency.WEEKDAYS,
            HabitFrequency.WEEKENDS, HabitFrequency.CUSTOM -> {
                val p = key.split("-")
                if (p.size != 3) null else runCatching {
                    utcNoon(p[0].toInt(), p[1].toInt(), p[2].toInt())
                }.getOrNull()
            }

            HabitFrequency.HOURLY -> {
                val parts = key.split("T")
                if (parts.size != 2) null else runCatching {
                    val day = parts[0].split("-")
                    LocalDateTime.of(
                        day[0].toInt(), day[1].toInt(), day[2].toInt(),
                        parts[1].take(2).toInt(), 30,
                    ).toInstant(ZoneOffset.UTC)
                }.getOrNull()
            }

            HabitFrequency.WEEKLY, HabitFrequency.FORTNIGHTLY -> {
                val p = key.split("-W")
                if (p.size != 2) null else runCatching {
                    // Mid-week (Wednesday) noon in the default zone — matches
                    // HabitCycle.key, which keys weeks in the default zone.
                    LocalDate.of(p[0].toInt(), 1, 4)
                        .plusWeeks(p[1].toInt() - 1L)
                        .with(DayOfWeek.WEDNESDAY)
                        .atTime(12, 0).atZone(zone).toInstant()
                }.getOrNull()
            }

            HabitFrequency.MONTHLY -> {
                val p = key.split("-")
                if (p.size != 2) null else runCatching {
                    utcNoon(p[0].toInt(), p[1].toInt(), 15)
                }.getOrNull()
            }

            HabitFrequency.EVERY_THREE_MONTHS -> {
                val p = key.split("-Q")
                if (p.size != 2) null else runCatching {
                    localNoon(p[0].toInt(), 3 * (p[1].toInt() - 1) + 2, 15, zone)
                }.getOrNull()
            }

            HabitFrequency.EVERY_SIX_MONTHS -> {
                val p = key.split("-H")
                if (p.size != 2) null else runCatching {
                    localNoon(p[0].toInt(), if (p[1].toInt() == 1) 3 else 9, 15, zone)
                }.getOrNull()
            }

            HabitFrequency.YEARLY -> runCatching {
                utcNoon(key.toInt(), 7, 1)
            }.getOrNull()
        }

        private fun utcNoon(year: Int, month: Int, day: Int): Instant =
            LocalDateTime.of(year, month, day, 12, 0).toInstant(ZoneOffset.UTC)

        private fun localNoon(year: Int, month: Int, day: Int, zone: ZoneId): Instant =
            LocalDate.of(year, month, day).atTime(12, 0).atZone(zone).toInstant()
    }
}
