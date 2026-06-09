package io.github.saxonbobart.lists.core.habits

import io.github.saxonbobart.lists.core.Iso8601
import io.github.saxonbobart.lists.core.model.HabitFrequency
import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemType
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime

/** A calm "showed up X of Y" summary over a recent window. */
data class ConsistencyStat(val shown: Int, val window: Int) {
    val rate: Double get() = if (window == 0) 0.0 else shown.toDouble() / window
}

/** One cell of the per-cycle contribution grid. */
data class CycleCell(val start: Instant, val key: String, val count: Int)

/**
 * Forgiving, consistency-led stats derived from a habit's timestamped
 * completions. The streak tolerates a single missed cycle ("never miss
 * twice"); two consecutive misses break it. Ported from the iOS `HabitStats`.
 */
object HabitStats {

    /** Completions a single cycle needs to count toward the streak. */
    private fun streakThreshold(item: Item): Int =
        if (item.flexibleGoal) 1 else maxOf(1, item.goalPerCycle)

    /**
     * Current streak under the "never miss twice" rule: a single missed cycle
     * is stepped over; two consecutive misses end it. The in-progress current
     * cycle neither counts nor penalizes.
     */
    fun streak(
        item: Item,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): Int {
        if (item.type != ItemType.HABIT) return 0
        val frequency = item.frequency ?: return 0
        val goal = streakThreshold(item)
        val log = item.completionLog(zone)

        var streak = 0
        var consecutiveMisses = 0
        var cursor = now
        var isCurrentCycle = true
        var steps = 0
        while (steps < 3650) {
            steps += 1
            val met = (log[HabitCycle.key(frequency, cursor, zone)] ?: 0) >= goal
            if (met) {
                streak += 1
                consecutiveMisses = 0
            } else if (!isCurrentCycle) {
                consecutiveMisses += 1
                if (consecutiveMisses >= 2) break
            }
            isCurrentCycle = false
            cursor = previousCycleStart(frequency, cursor)
        }
        return streak
    }

    /**
     * "Showed up X of Y" over the last [days] calendar days: Y is the number
     * of scheduled cycles touching that window, X the number of those met.
     */
    fun consistency(
        item: Item,
        days: Int = 30,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): ConsistencyStat {
        if (item.type != ItemType.HABIT || days <= 0) return ConsistencyStat(0, 0)
        val frequency = item.frequency ?: return ConsistencyStat(0, 0)
        val goal = item.goalPerCycle
        val log = item.completionLog(zone)
        val seen = mutableSetOf<String>()
        var shown = 0
        var window = 0
        for (offset in 0 until days) {
            val date = now.atZone(ZoneOffset.UTC).minusDays(offset.toLong()).toInstant()
            if (!isScheduled(frequency, date)) continue
            val key = HabitCycle.key(frequency, date, zone)
            if (!seen.add(key)) continue
            window += 1
            if ((log[key] ?: 0) >= goal) shown += 1
        }
        return ConsistencyStat(shown, window)
    }

    /** Every logged completion event, lifetime. */
    fun totalCompletions(item: Item): Int =
        if (item.type == ItemType.HABIT) item.completions.size else 0

    /** Completion counts grouped by calendar day (UTC `yyyy-MM-dd`),
     *  independent of the habit's cycle — feeds the heatmap. */
    fun completionsByDay(item: Item): Map<String, Int> {
        if (item.type != ItemType.HABIT) return emptyMap()
        return item.completions.groupingBy { Iso8601.dayString(it.at) }.eachCount()
    }

    /**
     * The last [limit] cycles up to and including the one containing [now],
     * oldest -> newest, each with its completion count. The cadence is
     * normalized (daily / weekly / monthly) — the per-cycle contribution grid.
     */
    fun recentCycles(
        item: Item,
        limit: Int,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): List<CycleCell> {
        if (item.type != ItemType.HABIT || limit <= 0) return emptyList()
        val freq = (item.frequency ?: HabitFrequency.DAILY).normalizedForHabit
        val counts = item.completions
            .groupingBy { HabitCycle.key(freq, it.at, zone) }
            .eachCount()

        val anchors = mutableListOf<Instant>()
        var cursor = now
        for (i in 0 until limit) {
            anchors.add(cursor)
            val prev = previousCycleStart(freq, cursor)
            if (prev >= cursor) break
            cursor = prev
        }
        return anchors.reversed().map { date ->
            val key = HabitCycle.key(freq, date, zone)
            CycleCell(date, key, counts[key] ?: 0)
        }
    }

    /** Calm cycle-relative noun for progress copy, e.g. "of 3 this week". */
    fun cycleNoun(frequency: HabitFrequency): String = when (frequency) {
        HabitFrequency.HOURLY -> "this hour"
        HabitFrequency.DAILY, HabitFrequency.CUSTOM,
        HabitFrequency.WEEKDAYS, HabitFrequency.WEEKENDS -> "today"
        HabitFrequency.WEEKLY -> "this week"
        HabitFrequency.FORTNIGHTLY -> "this fortnight"
        HabitFrequency.MONTHLY -> "this month"
        HabitFrequency.EVERY_THREE_MONTHS -> "this quarter"
        HabitFrequency.EVERY_SIX_MONTHS -> "this half-year"
        HabitFrequency.YEARLY -> "this year"
    }

    /** Longest run in the habit's history under the same forgiving rule. */
    fun bestStreak(
        item: Item,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): Int {
        if (item.type != ItemType.HABIT) return 0
        val frequency = item.frequency ?: return 0
        val earliest = item.completions.minOfOrNull { it.at } ?: return 0
        val goal = streakThreshold(item)
        val log = item.completionLog(zone)
        val earliestKey = HabitCycle.key(frequency, earliest, zone)

        val cursors = mutableListOf<Instant>()
        var cursor = now
        var steps = 0
        while (steps < 3650) {
            steps += 1
            cursors.add(cursor)
            if (HabitCycle.key(frequency, cursor, zone) == earliestKey) break
            val prev = previousCycleStart(frequency, cursor)
            if (prev >= cursor) break
            cursor = prev
        }

        var best = 0
        var run = 0
        var misses = 0
        for (c in cursors.reversed()) {
            val met = (log[HabitCycle.key(frequency, c, zone)] ?: 0) >= goal
            if (met) {
                run += 1
                best = maxOf(best, run)
                misses = 0
            } else {
                misses += 1
                if (misses >= 2) {
                    run = 0
                    misses = 0
                }
            }
        }
        return best
    }

    /** Met scheduled cycles / total scheduled cycles since first completion. */
    fun completionRate(
        item: Item,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): Double {
        if (item.type != ItemType.HABIT) return 0.0
        val frequency = item.frequency ?: return 0.0
        val earliest = item.completions.minOfOrNull { it.at } ?: return 0.0
        val goal = item.goalPerCycle
        val log = item.completionLog(zone)
        val earliestKey = HabitCycle.key(frequency, earliest, zone)

        val seen = mutableSetOf<String>()
        var met = 0
        var total = 0
        var cursor = now
        var steps = 0
        while (steps < 3650) {
            steps += 1
            if (isScheduled(frequency, cursor)) {
                val key = HabitCycle.key(frequency, cursor, zone)
                if (seen.add(key)) {
                    total += 1
                    if ((log[key] ?: 0) >= goal) met += 1
                }
            }
            if (HabitCycle.key(frequency, cursor, zone) == earliestKey) break
            val prev = previousCycleStart(frequency, cursor)
            if (prev >= cursor) break
            cursor = prev
        }
        return if (total == 0) 0.0 else met.toDouble() / total
    }

    /** Whether `date` is a scheduled cycle. Only weekdays/weekends constrain
     *  which days count (computed in UTC, matching the iOS stats calendar). */
    private fun isScheduled(frequency: HabitFrequency, date: Instant): Boolean {
        val dow = date.atZone(ZoneOffset.UTC).dayOfWeek
        return when (frequency) {
            HabitFrequency.WEEKDAYS -> dow != DayOfWeek.SATURDAY && dow != DayOfWeek.SUNDAY
            HabitFrequency.WEEKENDS -> dow == DayOfWeek.SATURDAY || dow == DayOfWeek.SUNDAY
            else -> true
        }
    }

    /** Step one cycle back, in the same stable UTC calendar the iOS stats use. */
    private fun previousCycleStart(frequency: HabitFrequency, before: Instant): Instant {
        val z: ZonedDateTime = before.atZone(ZoneOffset.UTC)
        return when (frequency) {
            HabitFrequency.HOURLY -> z.minusHours(1)
            HabitFrequency.DAILY, HabitFrequency.CUSTOM,
            HabitFrequency.WEEKDAYS, HabitFrequency.WEEKENDS -> z.minusDays(1)
            HabitFrequency.WEEKLY -> z.minusWeeks(1)
            HabitFrequency.FORTNIGHTLY -> z.minusWeeks(2)
            HabitFrequency.MONTHLY -> z.minusMonths(1)
            HabitFrequency.EVERY_THREE_MONTHS -> z.minusMonths(3)
            HabitFrequency.EVERY_SIX_MONTHS -> z.minusMonths(6)
            HabitFrequency.YEARLY -> z.minusYears(1)
        }.toInstant()
    }
}
