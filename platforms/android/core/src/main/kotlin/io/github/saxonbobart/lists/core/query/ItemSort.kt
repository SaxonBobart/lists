package io.github.saxonbobart.lists.core.query

import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.Priority
import java.time.Instant

enum class SortMode { MANUAL, DUE, ALPHABETICAL, CREATED, PRIORITY }

enum class SortDirection { ASCENDING, DESCENDING }

/**
 * Re-sorts items by a user-chosen [SortMode]. MANUAL preserves drag order
 * (`sortIndex`, direction ignored); the others apply the named comparator
 * with a stable title tiebreaker for PRIORITY.
 */
fun List<Item>.sortedByMode(
    mode: SortMode,
    direction: SortDirection = SortDirection.ASCENDING,
): List<Item> {
    val ascending = when (mode) {
        SortMode.MANUAL -> return sortedBy { it.sortIndex }
        SortMode.DUE -> sortedBy { it.due ?: Instant.MAX }
        SortMode.ALPHABETICAL -> sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.title })
        SortMode.CREATED -> sortedBy { it.createdAt }
        SortMode.PRIORITY -> sortedWith(
            compareBy<Item> { priorityRank(it.priority) }
                .thenBy(String.CASE_INSENSITIVE_ORDER) { it.title },
        )
    }
    return if (direction == SortDirection.DESCENDING) ascending.reversed() else ascending
}

private fun priorityRank(p: Priority): Int = when (p) {
    Priority.HIGH -> 0
    Priority.MEDIUM -> 1
    Priority.LOW -> 2
    Priority.NONE -> 3
}
