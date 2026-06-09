package io.github.saxonbobart.lists.core.model

import io.github.saxonbobart.lists.core.habits.HabitCycle
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * The single primitive in Lists, ported 1:1 from the iOS model
 * (`platforms/ios/Lists/Core/Models/Item.swift`). One markdown file per item:
 * these fields are the YAML frontmatter, [body] is the markdown after the
 * closing `---` and is intentionally not part of the frontmatter encoding.
 */
data class Item(
    // Identity
    val id: UUID = UUID.randomUUID(),
    val type: ItemType,
    val title: String,
    val body: String = "",

    // Placement
    val listId: String,
    val section: String? = null,
    val parentId: UUID? = null,
    val tags: List<String> = emptyList(),
    /** Manual ordering within a list; only honored by manual sort mode. */
    val sortIndex: Int = 0,

    // Provenance
    val createdAt: Instant = Instant.now(),
    val modifiedAt: Instant = createdAt,
    val createdBy: String = "human",

    // Task-shared fields
    val done: Boolean = false,
    val completedAt: Instant? = null,
    val due: Instant? = null,
    val dueAllDay: Boolean = false,
    val dueTimeZone: String? = null,
    val priority: Priority = Priority.NONE,
    val flagged: Boolean = false,

    // Reminder + trigger blocks
    val reminder: Reminder? = null,
    val recurrence: Recurrence? = null,
    val triggers: Triggers? = null,

    // Habit fields (only meaningful when type == HABIT)
    val frequency: HabitFrequency? = null,
    val goalPerCycle: Int = 1,
    /** Stored source of truth for habit history: one timestamped event each. */
    val completions: List<HabitCompletion> = emptyList(),
    val showStreak: Boolean = true,
    /** Weekly/monthly "N times across the cycle" goals. */
    val flexibleGoal: Boolean = false,

    // Soft delete
    val deletedAt: Instant? = null,
) {
    /**
     * Per-cycle completion counts, derived by grouping [completions] through
     * [HabitCycle.key]. Mirrors `Item.completionLog` on iOS.
     */
    fun completionLog(zone: ZoneId = ZoneId.systemDefault()): Map<String, Int> {
        val frequency = frequency ?: return emptyMap()
        return completions.groupingBy { HabitCycle.key(frequency, it.at, zone) }.eachCount()
    }

    /**
     * Unified completion check. Tasks use [done]; habits compare the current
     * cycle's count against [goalPerCycle]; notes are never complete.
     */
    fun isComplete(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Boolean =
        when (type) {
            ItemType.TASK -> done
            ItemType.HABIT -> {
                val frequency = frequency ?: return false
                val key = HabitCycle.key(frequency, now, zone)
                (completionLog(zone)[key] ?: 0) >= goalPerCycle
            }
            ItemType.NOTE -> false
        }
}

enum class ItemType(val raw: String) {
    TASK("task"), HABIT("habit"), NOTE("note");

    companion object {
        /**
         * Permissive decode (DI-1): an unknown raw value maps to TASK instead
         * of failing, so one stray value can't abort a whole-library load.
         */
        fun fromRaw(raw: String): ItemType = entries.firstOrNull { it.raw == raw } ?: TASK
    }
}

enum class Priority(val raw: String) {
    NONE("none"), LOW("low"), MEDIUM("medium"), HIGH("high");

    companion object {
        fun fromRawOrNull(raw: String): Priority? = entries.firstOrNull { it.raw == raw }
    }
}
