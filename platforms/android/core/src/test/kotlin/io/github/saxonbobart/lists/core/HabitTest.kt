package io.github.saxonbobart.lists.core

import io.github.saxonbobart.lists.core.habits.HabitCycle
import io.github.saxonbobart.lists.core.habits.HabitStats
import io.github.saxonbobart.lists.core.model.HabitCompletion
import io.github.saxonbobart.lists.core.model.HabitFrequency
import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneOffset

class HabitTest {

    private val utc = ZoneOffset.UTC
    private val now = Instant.parse("2026-06-09T12:00:00.000Z")

    private fun habit(
        frequency: HabitFrequency = HabitFrequency.DAILY,
        goal: Int = 1,
        completions: List<Instant> = emptyList(),
        flexible: Boolean = false,
    ) = Item(
        type = ItemType.HABIT, title = "Habit", listId = "inbox",
        createdAt = now, modifiedAt = now,
        frequency = frequency, goalPerCycle = goal, flexibleGoal = flexible,
        completions = completions.map { HabitCompletion(at = it) },
    )

    private fun day(d: String): Instant = Instant.parse("${d}T10:00:00.000Z")

    @Test
    fun `cycle keys match the iOS formats`() {
        val at = Instant.parse("2026-05-09T23:30:00.000Z")
        assertEquals("2026-05-09", HabitCycle.key(HabitFrequency.DAILY, at, utc))
        assertEquals("2026-05", HabitCycle.key(HabitFrequency.MONTHLY, at, utc))
        assertEquals("2026", HabitCycle.key(HabitFrequency.YEARLY, at, utc))
        // 2026-01-04 is a Sunday — still ISO week 1.
        assertEquals("2026-W01", HabitCycle.key(HabitFrequency.WEEKLY, Instant.parse("2026-01-04T10:00:00.000Z"), utc))
        // 2026-01-05 is a Monday — ISO week 2.
        assertEquals("2026-W02", HabitCycle.key(HabitFrequency.WEEKLY, Instant.parse("2026-01-05T10:00:00.000Z"), utc))
        assertEquals("2026-Q2", HabitCycle.key(HabitFrequency.EVERY_THREE_MONTHS, at, utc))
        assertEquals("2026-H1", HabitCycle.key(HabitFrequency.EVERY_SIX_MONTHS, at, utc))
    }

    @Test
    fun `completionLog groups events per cycle`() {
        val h = habit(
            frequency = HabitFrequency.DAILY, goal = 2,
            completions = listOf(day("2026-06-09"), day("2026-06-09"), day("2026-06-08")),
        )
        val log = h.completionLog(utc)
        assertEquals(2, log["2026-06-09"])
        assertEquals(1, log["2026-06-08"])
        assertTrue(h.isComplete(now, utc))
    }

    @Test
    fun `streak steps over a single missed day but breaks on two`() {
        // Missed 06-07 only -> forgiven.
        val forgiving = habit(
            completions = listOf(day("2026-06-09"), day("2026-06-08"), day("2026-06-06"), day("2026-06-05")),
        )
        assertEquals(4, HabitStats.streak(forgiving, now, utc))

        // Missed 06-08 and 06-07 -> streak is just today.
        val broken = habit(
            completions = listOf(day("2026-06-09"), day("2026-06-05"), day("2026-06-04")),
        )
        assertEquals(1, HabitStats.streak(broken, now, utc))
    }

    @Test
    fun `the in-progress cycle neither counts nor penalizes`() {
        val h = habit(completions = listOf(day("2026-06-08"), day("2026-06-07")))
        assertEquals(2, HabitStats.streak(h, now, utc))
        assertFalse(h.isComplete(now, utc))
    }

    @Test
    fun `flexible goal keeps the streak alive with one completion per cycle`() {
        val h = habit(
            frequency = HabitFrequency.WEEKLY, goal = 3, flexible = true,
            completions = listOf(day("2026-06-09"), day("2026-06-02")),
        )
        assertEquals(2, HabitStats.streak(h, now, utc))
    }

    @Test
    fun `bestStreak finds the longest historical run`() {
        val h = habit(
            completions = listOf(
                day("2026-06-09"),
                day("2026-06-01"), day("2026-05-31"), day("2026-05-30"), day("2026-05-29"),
            ),
        )
        // 05-29..06-01 = 4 consecutive + forgiven single misses around them;
        // the old run is at least as long as the current one.
        assertTrue(HabitStats.bestStreak(h, now, utc) >= 4)
    }

    @Test
    fun `consistency counts scheduled cycles in the window`() {
        val h = habit(
            completions = listOf(day("2026-06-09"), day("2026-06-08"), day("2026-06-07")),
        )
        val stat = HabitStats.consistency(h, days = 7, now = now, zone = utc)
        assertEquals(7, stat.window)
        assertEquals(3, stat.shown)
        assertEquals(3.0 / 7.0, stat.rate, 1e-9)
    }

    @Test
    fun `recentCycles normalizes cadence and is oldest first`() {
        val h = habit(
            frequency = HabitFrequency.WEEKLY,
            completions = listOf(day("2026-06-09"), day("2026-06-02"), day("2026-06-02")),
        )
        val cells = HabitStats.recentCycles(h, limit = 3, now = now, zone = utc)
        assertEquals(3, cells.size)
        assertEquals(listOf(0, 2, 1), cells.map { it.count })
        assertEquals("2026-W24", cells.last().key)
    }

    @Test
    fun `completionsByDay groups by UTC day independent of cadence`() {
        val h = habit(
            frequency = HabitFrequency.WEEKLY,
            completions = listOf(day("2026-06-09"), day("2026-06-09"), day("2026-06-02")),
        )
        assertEquals(mapOf("2026-06-09" to 2, "2026-06-02" to 1), HabitStats.completionsByDay(h))
    }
}
