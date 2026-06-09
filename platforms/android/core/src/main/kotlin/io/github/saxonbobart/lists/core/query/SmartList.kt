package io.github.saxonbobart.lists.core.query

import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemType
import java.time.Instant
import java.time.ZoneId

/** Built-in smart lists — queries over items, not stored collections. */
enum class SmartList(val id: String, val displayName: String) {
    TODAY("today", "Today"),
    SCHEDULED("scheduled", "Scheduled"),
    ALL("all", "All"),
    COMPLETED("completed", "Completed"),
    FLAGGED("flagged", "Flagged"),
    URGENT("urgent", "Urgent"),
    TAGS("tags", "Tags"),
    ASSIGNED("assigned", "Assigned");

    /**
     * Filter predicate, ported 1:1 from iOS. [now] is injectable for testing.
     * [includeCompleted] keeps complete items in non-Completed lists (the
     * per-list "Show Completed" toggle).
     */
    fun matches(
        item: Item,
        now: Instant = Instant.now(),
        includeCompleted: Boolean = false,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Boolean {
        // Soft-deleted items live in Recently Deleted; never in smart lists.
        if (item.deletedAt != null) return false
        // Sub-items always count in All (thread children surface there).
        if (item.parentId != null && this == ALL) return true

        // Visibility rule: Completed is the only smart list that surfaces
        // ticked items by default.
        val completed = item.isComplete(now, zone)
        val today = now.atZone(zone).toLocalDate()
        val startOfDay = today.atStartOfDay(zone).toInstant()

        return when (this) {
            TODAY -> {
                if (!includeCompleted && completed) return false
                val due = item.due ?: return false
                due.atZone(zone).toLocalDate() == today || due < startOfDay
            }

            SCHEDULED -> {
                if (!includeCompleted && completed) return false
                if (item.type == ItemType.HABIT) return false
                val due = item.due ?: return false
                due >= startOfDay
            }

            ALL -> {
                if (!includeCompleted && completed) return false
                item.type != ItemType.HABIT
            }

            COMPLETED -> completed

            FLAGGED -> {
                if (!includeCompleted && completed) return false
                item.flagged
            }

            URGENT -> {
                if (!includeCompleted && completed) return false
                item.triggers?.urgent?.enabled == true
            }

            // Not item-filter lists: Tags navigates to the Tags overview and
            // Assigned is a placeholder.
            TAGS, ASSIGNED -> false
        }
    }
}
