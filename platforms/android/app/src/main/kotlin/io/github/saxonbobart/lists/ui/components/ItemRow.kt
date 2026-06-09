package io.github.saxonbobart.lists.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Notes
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.core.model.Priority
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * One item row: task checkbox / habit ring / note glyph, title, and a meta
 * line (due, repeat, flag, priority, tags). Swipe end-to-start soft-deletes.
 */
@Composable
fun ItemRow(
    item: Item,
    onClick: () -> Unit,
    onToggleTask: () -> Unit,
    onTapHabitRing: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val dismissState = rememberSwipeToDismissBoxState()
    LaunchedEffect(dismissState.currentValue) {
        if (dismissState.currentValue == SwipeToDismissBoxValue.EndToStart) {
            onDelete()
            dismissState.snapTo(SwipeToDismissBoxValue.Settled)
        }
    }

    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(MaterialTheme.colorScheme.errorContainer)
                    .padding(end = 24.dp),
                contentAlignment = Alignment.CenterEnd,
            ) {
                Icon(
                    Icons.Filled.Delete,
                    contentDescription = "Delete",
                    tint = MaterialTheme.colorScheme.onErrorContainer,
                )
            }
        },
        modifier = modifier,
    ) {
        RowContent(item, onClick, onToggleTask, onTapHabitRing)
    }
}

@Composable
private fun RowContent(
    item: Item,
    onClick: () -> Unit,
    onToggleTask: () -> Unit,
    onTapHabitRing: () -> Unit,
) {
    val complete = remember(item) { item.isComplete() }
    val contentAlpha = if (complete) 0.55f else 1f

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    ) {
        when (item.type) {
            ItemType.TASK -> IconButton(onClick = onToggleTask) {
                if (item.done) {
                    Icon(
                        Icons.Filled.CheckCircle,
                        contentDescription = "Completed",
                        tint = MaterialTheme.colorScheme.primary,
                    )
                } else {
                    Icon(
                        Icons.Outlined.Circle,
                        contentDescription = "Not completed",
                        tint = MaterialTheme.colorScheme.outline,
                    )
                }
            }

            ItemType.HABIT -> IconButton(onClick = onTapHabitRing) {
                HabitRing(progress = item.habitProgress(), complete = complete)
            }

            ItemType.NOTE -> IconButton(onClick = onClick) {
                Icon(
                    Icons.AutoMirrored.Outlined.Notes,
                    contentDescription = "Note",
                    tint = MaterialTheme.colorScheme.tertiary,
                )
            }
        }

        Column(Modifier.weight(1f).padding(start = 4.dp)) {
            Text(
                item.title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                textDecoration = if (complete && item.type == ItemType.TASK) {
                    TextDecoration.LineThrough
                } else {
                    TextDecoration.None
                },
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = contentAlpha),
            )
            MetaLine(item, contentAlpha)
        }
    }
}

@Composable
private fun MetaLine(item: Item, contentAlpha: Float) {
    val parts = mutableListOf<@Composable () -> Unit>()
    val due = item.due
    if (due != null) {
        val overdue = !item.isComplete() && due < Instant.now()
        parts.add {
            Text(
                dueLabel(due, item.dueAllDay),
                style = MaterialTheme.typography.labelMedium,
                color = if (overdue) {
                    MaterialTheme.colorScheme.error
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = contentAlpha)
                },
            )
        }
    }
    if (item.recurrence != null) {
        parts.add {
            Icon(
                Icons.Filled.Repeat,
                contentDescription = "Repeats",
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = contentAlpha),
                modifier = Modifier.padding(top = 1.dp),
            )
        }
    }
    if (item.flagged) {
        parts.add {
            Icon(
                Icons.Filled.Flag,
                contentDescription = "Flagged",
                tint = MaterialTheme.colorScheme.error.copy(alpha = contentAlpha),
            )
        }
    }
    if (item.priority != Priority.NONE) {
        parts.add {
            Text(
                when (item.priority) {
                    Priority.HIGH -> "!!!"
                    Priority.MEDIUM -> "!!"
                    else -> "!"
                },
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.error.copy(alpha = contentAlpha),
            )
        }
    }
    for (tag in item.tags.take(3)) {
        parts.add {
            Text(
                "#$tag",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary.copy(alpha = contentAlpha),
            )
        }
    }

    if (parts.isEmpty()) return
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.padding(top = 2.dp),
    ) {
        parts.forEach { it() }
    }
}

/** Current-cycle progress 0..1 for habit rings. */
fun Item.habitProgress(zone: ZoneId = ZoneId.systemDefault()): Float {
    val frequency = frequency ?: return 0f
    val key = io.github.saxonbobart.lists.core.habits.HabitCycle.key(frequency, Instant.now(), zone)
    val count = completionLog(zone)[key] ?: 0
    if (goalPerCycle <= 0) return 1f
    return (count.toFloat() / goalPerCycle).coerceIn(0f, 1f)
}

/** "Today 15:00", "Tomorrow", "Mon 15 Jun", "9 May" — calm and short. */
fun dueLabel(due: Instant, allDay: Boolean, zone: ZoneId = ZoneId.systemDefault()): String {
    val date = due.atZone(zone).toLocalDate()
    val today = LocalDate.now(zone)
    val time = if (allDay) "" else due.atZone(zone).format(DateTimeFormatter.ofPattern("HH:mm", Locale.getDefault()))
    val day = when (date) {
        today -> "Today"
        today.plusDays(1) -> "Tomorrow"
        today.minusDays(1) -> "Yesterday"
        else -> date.format(
            DateTimeFormatter.ofPattern(
                if (date.year == today.year) "EEE d MMM" else "d MMM yyyy",
                Locale.getDefault(),
            ),
        )
    }
    return if (time.isEmpty()) day else "$day $time"
}
