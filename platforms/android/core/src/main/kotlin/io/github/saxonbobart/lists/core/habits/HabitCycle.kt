package io.github.saxonbobart.lists.core.habits

import io.github.saxonbobart.lists.core.model.HabitFrequency
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.temporal.IsoFields

/**
 * Maps a habit's frequency + an instant to a stable cycle-key string, matching
 * the iOS `HabitCycle` conventions exactly: UTC for day/month/year keys,
 * the device's zone for hour/week/quarter/half components.
 */
object HabitCycle {

    fun key(
        frequency: HabitFrequency,
        at: Instant,
        zone: ZoneId = ZoneId.systemDefault(),
    ): String {
        val utc = at.atZone(ZoneOffset.UTC)
        val local = at.atZone(zone)
        return when (frequency) {
            HabitFrequency.HOURLY -> {
                val day = "%04d-%02d-%02d".fmt(utc.year, utc.monthValue, utc.dayOfMonth)
                "${day}T${local.hour.pad2()}:00"
            }

            HabitFrequency.DAILY, HabitFrequency.WEEKDAYS,
            HabitFrequency.WEEKENDS, HabitFrequency.CUSTOM ->
                "%04d-%02d-%02d".fmt(utc.year, utc.monthValue, utc.dayOfMonth)

            HabitFrequency.WEEKLY, HabitFrequency.FORTNIGHTLY -> {
                val weekYear = local.get(IsoFields.WEEK_BASED_YEAR)
                val week = local.get(IsoFields.WEEK_OF_WEEK_BASED_YEAR)
                "$weekYear-W${week.pad2()}"
            }

            HabitFrequency.MONTHLY -> "%04d-%02d".fmt(utc.year, utc.monthValue)

            HabitFrequency.EVERY_THREE_MONTHS -> {
                val q = ((local.monthValue - 1) / 3) + 1
                "${local.year}-Q$q"
            }

            HabitFrequency.EVERY_SIX_MONTHS -> {
                val half = if (local.monthValue <= 6) 1 else 2
                "${local.year}-H$half"
            }

            HabitFrequency.YEARLY -> "%04d".fmt(utc.year)
        }
    }

    private fun Int.pad2(): String = toString().padStart(2, '0')

    private fun String.fmt(vararg args: Any): String = format(java.util.Locale.ROOT, *args)
}
