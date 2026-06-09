package io.github.saxonbobart.lists.ui.habit

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.saxonbobart.lists.core.habits.HabitCycle
import io.github.saxonbobart.lists.core.habits.HabitStats
import io.github.saxonbobart.lists.core.model.HabitFrequency
import io.github.saxonbobart.lists.ui.ListsViewModel
import io.github.saxonbobart.lists.ui.components.CycleProgressBar
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

/** Habit overview: streak + cycle cards, contribution grid, recent log. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HabitDetailScreen(
    viewModel: ListsViewModel,
    itemId: String,
    onBack: () -> Unit,
) {
    val library by viewModel.library.collectAsState()
    val id = runCatching { UUID.fromString(itemId) }.getOrNull() ?: return
    val habit = library.item(id) ?: return
    val zone = ZoneId.systemDefault()
    val frequency = habit.frequency ?: HabitFrequency.DAILY

    val cycleKey = HabitCycle.key(frequency, Instant.now(), zone)
    val cycleCount = habit.completionLog(zone)[cycleKey] ?: 0
    val streak = HabitStats.streak(habit, zone = zone)
    val cells = HabitStats.recentCycles(
        habit,
        limit = when (frequency.normalizedForHabit) {
            HabitFrequency.WEEKLY -> 52
            HabitFrequency.MONTHLY -> 12
            else -> 30
        },
        zone = zone,
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(habit.title, fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.edit(habit.id) }) {
                        Icon(Icons.Filled.Edit, contentDescription = "Edit habit")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            contentPadding = padding,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 4.dp),
                ) {
                    // Streak card
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                        ),
                        modifier = Modifier.weight(1f),
                    ) {
                        Column(Modifier.padding(16.dp)) {
                            Icon(
                                Icons.Filled.LocalFireDepartment,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                            )
                            Spacer(Modifier.height(6.dp))
                            Text(
                                "$streak",
                                style = MaterialTheme.typography.displaySmall,
                                fontWeight = FontWeight.Bold,
                            )
                            Text(
                                streakNoun(frequency, streak),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    // This-cycle card with +1 / -1
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                        ),
                        modifier = Modifier.weight(1f),
                    ) {
                        Column(Modifier.padding(16.dp)) {
                            Text(
                                "$cycleCount of ${habit.goalPerCycle}",
                                style = MaterialTheme.typography.headlineSmall,
                                fontWeight = FontWeight.Bold,
                            )
                            Text(
                                HabitStats.cycleNoun(frequency),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(Modifier.height(8.dp))
                            CycleProgressBar(
                                progress = (cycleCount.toFloat() / habit.goalPerCycle.coerceAtLeast(1))
                                    .coerceIn(0f, 1f),
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Spacer(Modifier.height(10.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                FilledTonalIconButton(
                                    onClick = { viewModel.decrementHabit(habit.id) },
                                    enabled = cycleCount > 0,
                                ) { Icon(Icons.Filled.Remove, contentDescription = "Log one less") }
                                FilledTonalIconButton(
                                    onClick = { viewModel.incrementHabit(habit.id) },
                                    enabled = cycleCount < habit.goalPerCycle,
                                ) { Icon(Icons.Filled.Add, contentDescription = "Log one more") }
                            }
                        }
                    }
                }
            }

            item {
                Column(Modifier.padding(horizontal = 16.dp)) {
                    Text(
                        "History",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(8.dp))
                    ContributionGrid(
                        ratios = cells.map { cell ->
                            if (habit.goalPerCycle <= 0) 0f
                            else (cell.count.toFloat() / habit.goalPerCycle).coerceIn(0f, 1f)
                        },
                    )
                }
            }

            item {
                Text(
                    "Recent",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 16.dp, top = 8.dp),
                )
            }
            val recent = habit.completions.sortedByDescending { it.at }.take(10)
            items(recent.size, key = { i -> recent[i].id }) { i ->
                val completion = recent[i]
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                ) {
                    Text(
                        completion.at.atZone(zone).format(
                            DateTimeFormatter.ofPattern("EEE d MMM, HH:mm", Locale.getDefault()),
                        ),
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(onClick = { viewModel.removeCompletion(habit.id, completion.id) }) {
                        Icon(
                            Icons.Filled.DeleteOutline,
                            contentDescription = "Remove this completion",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            if (habit.completions.isEmpty()) {
                item {
                    Text(
                        "No completions yet — tap +1 to start.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

private fun streakNoun(frequency: HabitFrequency, streak: Int): String {
    val unit = when (frequency.normalizedForHabit) {
        HabitFrequency.WEEKLY -> "week"
        HabitFrequency.MONTHLY -> "month"
        else -> "day"
    }
    return if (streak == 1) "$unit streak" else "${unit} streak"
}

/** One square per cycle, coloured by that cycle's completion ratio. */
@Composable
private fun ContributionGrid(ratios: List<Float>) {
    val base = MaterialTheme.colorScheme.surfaceContainerHighest
    val fill = MaterialTheme.colorScheme.primary
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        ratios.forEach { ratio ->
            Spacer(
                Modifier
                    .size(18.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(
                        if (ratio <= 0f) base else fill.copy(alpha = 0.25f + 0.75f * ratio),
                    ),
            )
        }
    }
}
