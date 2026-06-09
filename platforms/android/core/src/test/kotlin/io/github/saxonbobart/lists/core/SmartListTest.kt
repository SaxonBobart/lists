package io.github.saxonbobart.lists.core

import io.github.saxonbobart.lists.core.model.HabitCompletion
import io.github.saxonbobart.lists.core.model.HabitFrequency
import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.core.model.TriggerToggle
import io.github.saxonbobart.lists.core.model.Triggers
import io.github.saxonbobart.lists.core.query.SmartList
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID

class SmartListTest {

    private val utc = ZoneOffset.UTC
    private val now = Instant.parse("2026-06-09T12:00:00.000Z")

    private fun task(
        due: Instant? = null,
        done: Boolean = false,
        flagged: Boolean = false,
        deletedAt: Instant? = null,
        parentId: UUID? = null,
        triggers: Triggers? = null,
    ) = Item(
        type = ItemType.TASK, title = "T", listId = "inbox",
        createdAt = now, modifiedAt = now,
        due = due, done = done, flagged = flagged, deletedAt = deletedAt,
        parentId = parentId, triggers = triggers,
    )

    private fun SmartList.matchesUtc(item: Item, includeCompleted: Boolean = false) =
        matches(item, now, includeCompleted, utc)

    @Test
    fun `today matches due-today and overdue, hides completed`() {
        assertTrue(SmartList.TODAY.matchesUtc(task(due = now.plusSeconds(3600))))
        assertTrue(SmartList.TODAY.matchesUtc(task(due = now.minusSeconds(5 * 86400))))
        assertFalse(SmartList.TODAY.matchesUtc(task(due = now.plusSeconds(86400 * 2))))
        assertFalse(SmartList.TODAY.matchesUtc(task(due = now, done = true)))
        assertTrue(SmartList.TODAY.matchesUtc(task(due = now, done = true), includeCompleted = true))
        assertFalse(SmartList.TODAY.matchesUtc(task()))
    }

    @Test
    fun `scheduled excludes habits and past-due, includes today onward`() {
        assertTrue(SmartList.SCHEDULED.matchesUtc(task(due = now.plusSeconds(86400 * 3))))
        assertTrue(SmartList.SCHEDULED.matchesUtc(task(due = now)))
        assertFalse(SmartList.SCHEDULED.matchesUtc(task(due = now.minusSeconds(2 * 86400))))
        val habit = task(due = now).copy(type = ItemType.HABIT, frequency = HabitFrequency.DAILY)
        assertFalse(SmartList.SCHEDULED.matchesUtc(habit))
    }

    @Test
    fun `all excludes habits but always includes sub-items`() {
        assertTrue(SmartList.ALL.matchesUtc(task()))
        val habit = task().copy(type = ItemType.HABIT, frequency = HabitFrequency.DAILY)
        assertFalse(SmartList.ALL.matchesUtc(habit))
        // Thread children surface in All even when completed.
        assertTrue(SmartList.ALL.matchesUtc(task(done = true, parentId = UUID.randomUUID())))
    }

    @Test
    fun `completed surfaces done tasks and at-goal habits`() {
        assertTrue(SmartList.COMPLETED.matchesUtc(task(done = true)))
        assertFalse(SmartList.COMPLETED.matchesUtc(task()))
        val habitAtGoal = task().copy(
            type = ItemType.HABIT, frequency = HabitFrequency.DAILY, goalPerCycle = 1,
            completions = listOf(HabitCompletion(at = now)),
        )
        assertTrue(SmartList.COMPLETED.matchesUtc(habitAtGoal))
    }

    @Test
    fun `flagged and urgent filter on their fields`() {
        assertTrue(SmartList.FLAGGED.matchesUtc(task(flagged = true)))
        assertFalse(SmartList.FLAGGED.matchesUtc(task()))
        val urgent = task(triggers = Triggers(urgent = TriggerToggle(true)))
        assertTrue(SmartList.URGENT.matchesUtc(urgent))
        assertFalse(SmartList.URGENT.matchesUtc(task()))
    }

    @Test
    fun `soft-deleted items never appear, even in completed`() {
        val deleted = task(done = true, deletedAt = now)
        for (smart in SmartList.entries) {
            assertFalse(smart.matchesUtc(deleted, includeCompleted = true))
        }
    }

    @Test
    fun `tags and assigned are navigation entries, not item filters`() {
        assertFalse(SmartList.TAGS.matchesUtc(task()))
        assertFalse(SmartList.ASSIGNED.matchesUtc(task()))
    }
}
