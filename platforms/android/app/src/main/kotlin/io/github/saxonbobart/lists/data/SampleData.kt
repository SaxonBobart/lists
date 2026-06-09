package io.github.saxonbobart.lists.data

import io.github.saxonbobart.lists.core.model.HabitCompletion
import io.github.saxonbobart.lists.core.model.HabitFrequency
import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemList
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.core.model.ListSection
import io.github.saxonbobart.lists.core.model.Priority
import io.github.saxonbobart.lists.core.model.Recurrence
import io.github.saxonbobart.lists.core.model.Reminder
import io.github.saxonbobart.lists.core.model.TriggerToggle
import io.github.saxonbobart.lists.core.model.Triggers
import io.github.saxonbobart.lists.core.storage.FileStore
import java.time.Duration
import java.time.Instant
import java.util.UUID

/**
 * First-launch seed — mirrors the iOS `SampleData` shapes (same stable ids)
 * so every surface has visible content out of the box: sections, sub-lists,
 * a habit with history, a thread, and completed-item filtering.
 */
object SampleData {

    private val healthSectionId = UUID.fromString("11111111-0000-0000-0000-000000000001")
    private val adminSectionId = UUID.fromString("11111111-0000-0000-0000-000000000002")

    private fun id(suffix: String) = UUID.fromString("22222222-0000-0000-0000-0000000000$suffix")

    fun seed(store: FileStore, now: Instant = Instant.now()) {
        val day = Duration.ofDays(1)
        val hour = Duration.ofHours(1)

        val lists = listOf(
            ItemList.makeInbox(now),
            ItemList(
                id = "work", name = "Work", icon = "briefcase.fill",
                color = ItemList.ListColor.ORANGE, defaultItemType = ItemType.TASK,
                createdAt = now, modifiedAt = now, position = 1.0,
            ),
            ItemList(
                id = "personal", name = "Personal", icon = "person.fill",
                color = ItemList.ListColor.PURPLE, defaultItemType = ItemType.TASK,
                createdAt = now, modifiedAt = now, position = 2.0,
                sections = listOf(
                    ListSection(healthSectionId, "Health", 1.0),
                    ListSection(adminSectionId, "Admin", 2.0),
                ),
            ),
            // 3-level nesting: Projects -> Side App -> Sprint 1
            ItemList(
                id = "projects", name = "Projects", icon = "folder.fill",
                color = ItemList.ListColor.INDIGO, defaultItemType = ItemType.TASK,
                createdAt = now, modifiedAt = now, position = 3.0,
            ),
            ItemList(
                id = "projects-sideapp", name = "Side App", icon = "hammer.fill",
                color = ItemList.ListColor.TEAL, defaultItemType = ItemType.TASK,
                createdAt = now, modifiedAt = now, position = 1.0, parentId = "projects",
            ),
            ItemList(
                id = "projects-sideapp-sprint1", name = "Sprint 1", icon = "flag.fill",
                color = ItemList.ListColor.PINK, defaultItemType = ItemType.TASK,
                createdAt = now, modifiedAt = now, position = 1.0, parentId = "projects-sideapp",
            ),
        )
        // Children after parents so writeList can resolve parent folders.
        lists.forEach(store::writeList)

        fun item(
            suffix: String, type: ItemType, title: String, listId: String,
            build: (Item) -> Item = { it },
        ) = build(
            Item(
                id = id(suffix), type = type, title = title, listId = listId,
                createdAt = now - day, modifiedAt = now - day,
            ),
        )

        val designSchema = item("0E", ItemType.TASK, "Design storage schema", "projects-sideapp-sprint1") {
            it.copy(body = "One markdown file per item, YAML frontmatter.\n", priority = Priority.HIGH)
        }

        val items = listOf(
            // Inbox
            item("01", ItemType.TASK, "Pay phone bill", "inbox") {
                it.copy(due = now + hour * 3, flagged = true, tags = listOf("bills"))
            },
            item("02", ItemType.TASK, "Email Sarah about the weekend", "inbox") {
                it.copy(due = now - day, triggers = Triggers(urgent = TriggerToggle(true)))
            },
            item("0B", ItemType.TASK, "Call Mum", "inbox") {
                it.copy(due = now + day * 2, reminder = Reminder(enabled = true))
            },
            // Work
            item("04", ItemType.TASK, "Submit timesheet", "work") {
                it.copy(
                    due = now + day, priority = Priority.MEDIUM,
                    recurrence = Recurrence("FREQ=WEEKLY;BYDAY=FR"), tags = listOf("admin"),
                )
            },
            item("03", ItemType.TASK, "Draft reply to design review", "work") {
                it.copy(done = true, completedAt = now - hour * 5)
            },
            // Personal / sections
            item("05", ItemType.HABIT, "Run 5km", "personal") {
                it.copy(
                    section = healthSectionId.toString().lowercase(),
                    frequency = HabitFrequency.WEEKLY, goalPerCycle = 3, flexibleGoal = true,
                    completions = listOf(
                        now - day * 1, now - day * 3, now - day * 6,
                        now - day * 8, now - day * 10, now - day * 13,
                        now - day * 16, now - day * 20, now - day * 22,
                    ).mapIndexed { i, at ->
                        HabitCompletion(UUID.fromString("33333333-0000-0000-0000-0000000000${"%02X".format(i + 1)}"), at)
                    },
                )
            },
            item("07", ItemType.HABIT, "Read 30 minutes", "personal") {
                it.copy(
                    section = healthSectionId.toString().lowercase(),
                    frequency = HabitFrequency.DAILY, goalPerCycle = 1,
                    completions = (1..5).map { d ->
                        HabitCompletion(UUID.fromString("44444444-0000-0000-0000-0000000000%02X".format(d)), now - day * d)
                    },
                )
            },
            item("08", ItemType.TASK, "Book dentist appointment", "personal") {
                it.copy(section = adminSectionId.toString().lowercase(), tags = listOf("health"))
            },
            item("0A", ItemType.TASK, "Renew passport", "personal") {
                it.copy(section = adminSectionId.toString().lowercase(), priority = Priority.LOW, dueAllDay = true, due = now + day * 30)
            },
            // Projects
            item("0D", ItemType.NOTE, "Roadmap ideas", "projects") {
                it.copy(body = "## Next up\n\n- Sync engine\n- Widgets\n- Wear tile\n", tags = listOf("planning"))
            },
            designSchema,
            // Thread children under designSchema
            item("0F", ItemType.TASK, "Spike YAML frontmatter codec", "projects-sideapp-sprint1") {
                it.copy(parentId = designSchema.id, done = true, completedAt = now - day)
            },
            item("10", ItemType.TASK, "Round-trip tests on device", "projects-sideapp-sprint1") {
                it.copy(parentId = designSchema.id)
            },
            item("11", ItemType.TASK, "Build markdown editor", "projects-sideapp") {
                it.copy(tags = listOf("editor"), priority = Priority.MEDIUM)
            },
        )
        items.forEach(store::writeItem)
    }

    private operator fun Instant.plus(d: Duration): Instant = plusSeconds(d.seconds)
    private operator fun Instant.minus(d: Duration): Instant = minusSeconds(d.seconds)
    private operator fun Duration.times(n: Int): Duration = multipliedBy(n.toLong())
}
