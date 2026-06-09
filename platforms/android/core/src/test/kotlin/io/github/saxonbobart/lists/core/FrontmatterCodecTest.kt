package io.github.saxonbobart.lists.core

import io.github.saxonbobart.lists.core.model.EarlyReminder
import io.github.saxonbobart.lists.core.model.HabitCompletion
import io.github.saxonbobart.lists.core.model.HabitFrequency
import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.core.model.LocationTrigger
import io.github.saxonbobart.lists.core.model.Priority
import io.github.saxonbobart.lists.core.model.Recurrence
import io.github.saxonbobart.lists.core.model.Reminder
import io.github.saxonbobart.lists.core.model.TriggerToggle
import io.github.saxonbobart.lists.core.model.Triggers
import io.github.saxonbobart.lists.core.storage.FrontmatterCodec
import io.github.saxonbobart.lists.core.storage.YamlCodecException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.util.UUID

class FrontmatterCodecTest {

    private val createdAt = Instant.parse("2026-05-09T15:30:00.000Z")

    private fun baseTask(body: String = "") = Item(
        id = UUID.fromString("22222222-0000-0000-0000-000000000001"),
        type = ItemType.TASK,
        title = "Pay phone bill",
        body = body,
        listId = "inbox",
        createdAt = createdAt,
        modifiedAt = createdAt,
    )

    @Test
    fun `round trips a fully loaded task`() {
        val item = baseTask(body = "Some **markdown** body.\n\n- bullet\n").copy(
            section = "11111111-0000-0000-0000-000000000001",
            parentId = UUID.fromString("22222222-0000-0000-0000-00000000000D"),
            tags = listOf("bills", "home admin"),
            done = true,
            completedAt = createdAt.plusSeconds(3600),
            due = createdAt.plusSeconds(86400),
            dueAllDay = true,
            dueTimeZone = "Australia/Sydney",
            priority = Priority.HIGH,
            flagged = true,
            reminder = Reminder(enabled = true, early = EarlyReminder(30, EarlyReminder.Unit.MINUTE)),
            recurrence = Recurrence("FREQ=WEEKLY;BYDAY=MO,FR"),
            triggers = Triggers(
                urgent = TriggerToggle(true),
                location = LocationTrigger(
                    enabled = true, latitude = -33.86, longitude = 151.21,
                    radius = 100.0, fire = LocationTrigger.Direction.ARRIVE,
                ),
            ),
            sortIndex = 4,
        )
        val decoded = FrontmatterCodec.decode(FrontmatterCodec.encode(item))
        assertEquals(item, decoded)
    }

    @Test
    fun `round trips a habit with completions`() {
        val item = baseTask().copy(
            type = ItemType.HABIT,
            title = "Run 5km",
            frequency = HabitFrequency.WEEKLY,
            goalPerCycle = 3,
            flexibleGoal = true,
            showStreak = false,
            completions = listOf(
                HabitCompletion(UUID.fromString("33333333-0000-0000-0000-000000000001"), createdAt),
                HabitCompletion(UUID.fromString("33333333-0000-0000-0000-000000000002"), createdAt.plusSeconds(60)),
            ),
        )
        val decoded = FrontmatterCodec.decode(FrontmatterCodec.encode(item))
        assertEquals(item, decoded)
    }

    @Test
    fun `round trips titles with yaml-hostile characters`() {
        for (title in listOf(
            "Call: mum #urgent",
            "true",
            "2026-05-09",
            "- leading dash",
            "trailing space ",
            "quote \" and \\ backslash",
            "emoji ✅ ok",
        )) {
            val decoded = FrontmatterCodec.decode(FrontmatterCodec.encode(baseTask().copy(title = title)))
            assertEquals(title, decoded.title)
        }
    }

    @Test
    fun `decodes an iOS-written file with unquoted plain-scalar dates`() {
        val source = """
            ---
            id: 22222222-0000-0000-0000-000000000005
            type: habit
            title: Run 5km
            list: personal
            tags:
            - health
            created_at: 2026-05-09T15:30:00.000Z
            modified_at: 2026-05-09T15:30:00.000Z
            created_by: human
            frequency: weekly
            goal_per_cycle: 3
            completions:
            - id: 33333333-0000-0000-0000-000000000001
              at: 2026-05-09T15:30:00.000Z
            show_streak: true
            ---
            Couch-to-5k notes.
        """.trimIndent() + "\n"

        val item = FrontmatterCodec.decode(source)
        assertEquals(ItemType.HABIT, item.type)
        assertEquals("Run 5km", item.title)
        assertEquals(listOf("health"), item.tags)
        assertEquals(createdAt, item.createdAt)
        assertEquals(HabitFrequency.WEEKLY, item.frequency)
        assertEquals(3, item.goalPerCycle)
        assertEquals(1, item.completions.size)
        assertEquals(createdAt, item.completions[0].at)
        assertEquals("Couch-to-5k notes.\n", item.body)
    }

    @Test
    fun `unknown item type falls back to task`() {
        val source = "---\nid: ${UUID.randomUUID()}\ntype: starship\ntitle: T\nlist: inbox\n" +
            "created_at: 2026-05-09T15:30:00.000Z\nmodified_at: 2026-05-09T15:30:00.000Z\n---\n"
        assertEquals(ItemType.TASK, FrontmatterCodec.decode(source).type)
    }

    @Test
    fun `defaults apply when optional fields are absent`() {
        val item = FrontmatterCodec.decode(FrontmatterCodec.encode(baseTask()))
        assertEquals(false, item.done)
        assertEquals(Priority.NONE, item.priority)
        assertEquals("human", item.createdBy)
        assertEquals(1, item.goalPerCycle)
        assertEquals(true, item.showStreak)
        assertEquals(emptyList<String>(), item.tags)
        assertEquals(0, item.sortIndex)
    }

    @Test
    fun `a malformed completion event is skipped, not fatal`() {
        val source = """
            ---
            id: 22222222-0000-0000-0000-000000000005
            type: habit
            title: Run
            list: inbox
            created_at: 2026-05-09T15:30:00.000Z
            modified_at: 2026-05-09T15:30:00.000Z
            frequency: daily
            goal_per_cycle: 1
            completions:
            - id: 33333333-0000-0000-0000-000000000001
              at: not-a-date
            - id: 33333333-0000-0000-0000-000000000002
              at: 2026-05-09T15:30:00.000Z
            ---
        """.trimIndent() + "\n"
        val item = FrontmatterCodec.decode(source)
        assertEquals(1, item.completions.size)
    }

    @Test
    fun `legacy completion_log migrates to timestamped events`() {
        val source = """
            ---
            id: 22222222-0000-0000-0000-000000000005
            type: habit
            title: Read
            list: inbox
            created_at: 2026-05-09T15:30:00.000Z
            modified_at: 2026-05-09T15:30:00.000Z
            frequency: daily
            goal_per_cycle: 2
            completion_log:
              2026-05-08: 2
              2026-05-09: 1
            ---
        """.trimIndent() + "\n"
        val item = FrontmatterCodec.decode(source)
        assertEquals(3, item.completions.size)
        // Regrouping the migrated events must reproduce the original counts.
        val regrouped = item.completionLog(java.time.ZoneOffset.UTC)
        assertEquals(2, regrouped["2026-05-08"])
        assertEquals(1, regrouped["2026-05-09"])
    }

    @Test
    fun `present but invalid deleted_at throws (quarantine, not resurrect)`() {
        val source = "---\nid: ${UUID.randomUUID()}\ntype: task\ntitle: T\nlist: inbox\n" +
            "created_at: 2026-05-09T15:30:00.000Z\nmodified_at: 2026-05-09T15:30:00.000Z\n" +
            "deleted_at: garbage\n---\n"
        assertThrows(YamlCodecException::class.java) { FrontmatterCodec.decode(source) }
    }

    @Test
    fun `missing opener and closer both throw`() {
        assertThrows(YamlCodecException::class.java) { FrontmatterCodec.decode("id: x\n") }
        assertThrows(YamlCodecException::class.java) { FrontmatterCodec.decode("---\nid: x\n") }
    }

    @Test
    fun `BOM-prefixed files and closer-at-EOF are accepted`() {
        val yaml = "id: ${UUID.randomUUID()}\ntype: task\ntitle: T\nlist: inbox\n" +
            "created_at: 2026-05-09T15:30:00.000Z\nmodified_at: 2026-05-09T15:30:00.000Z"
        val bom = FrontmatterCodec.decode("﻿---\n$yaml\n---\nbody\n")
        assertEquals("body\n", bom.body)
        val eof = FrontmatterCodec.decode("---\n$yaml\n---")
        assertEquals("", eof.body)
    }

    @Test
    fun `empty body encodes without trailing content and decodes empty`() {
        val encoded = FrontmatterCodec.encode(baseTask())
        assertTrue(encoded.endsWith("---\n"))
        assertEquals("", FrontmatterCodec.decode(encoded).body)
    }
}
