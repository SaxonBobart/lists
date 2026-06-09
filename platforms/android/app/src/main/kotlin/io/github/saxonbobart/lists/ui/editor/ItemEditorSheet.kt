package io.github.saxonbobart.lists.ui.editor

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.saxonbobart.lists.core.model.HabitFrequency
import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.core.model.Priority
import io.github.saxonbobart.lists.core.model.Recurrence
import io.github.saxonbobart.lists.core.model.Reminder
import io.github.saxonbobart.lists.core.model.TriggerToggle
import io.github.saxonbobart.lists.core.model.Triggers
import io.github.saxonbobart.lists.data.Library
import io.github.saxonbobart.lists.ui.ListsViewModel
import io.github.saxonbobart.lists.ui.components.dueLabel
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset

private val recurrencePresets = listOf(
    "Never" to null,
    "Daily" to "FREQ=DAILY",
    "Weekdays" to "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
    "Weekly" to "FREQ=WEEKLY",
    "Fortnightly" to "FREQ=WEEKLY;INTERVAL=2",
    "Monthly" to "FREQ=MONTHLY",
    "Yearly" to "FREQ=YEARLY",
)

/** Full item editor in a bottom sheet — every field the format supports. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ItemEditorSheet(
    item: Item,
    library: Library,
    viewModel: ListsViewModel,
    onDismiss: () -> Unit,
) {
    val zone = remember { ZoneId.systemDefault() }

    var title by remember(item.id) { mutableStateOf(item.title) }
    var body by remember(item.id) { mutableStateOf(item.body) }
    var type by remember(item.id) { mutableStateOf(item.type) }
    var listId by remember(item.id) { mutableStateOf(item.listId) }
    var due by remember(item.id) { mutableStateOf(item.due) }
    var dueAllDay by remember(item.id) { mutableStateOf(item.dueAllDay) }
    var priority by remember(item.id) { mutableStateOf(item.priority) }
    var flagged by remember(item.id) { mutableStateOf(item.flagged) }
    var urgent by remember(item.id) { mutableStateOf(item.triggers?.urgent?.enabled == true) }
    var reminderOn by remember(item.id) { mutableStateOf(item.reminder?.enabled == true) }
    var tagsText by remember(item.id) { mutableStateOf(item.tags.joinToString(", ")) }
    var rrule by remember(item.id) { mutableStateOf(item.recurrence?.rrule) }
    var frequency by remember(item.id) {
        mutableStateOf((item.frequency ?: HabitFrequency.DAILY).normalizedForHabit)
    }
    var goal by remember(item.id) { mutableStateOf(item.goalPerCycle) }
    var flexible by remember(item.id) { mutableStateOf(item.flexibleGoal) }

    var datePickerOpen by remember { mutableStateOf(false) }
    var timeDialogOpen by remember { mutableStateOf(false) }
    var listMenuOpen by remember { mutableStateOf(false) }
    var repeatMenuOpen by remember { mutableStateOf(false) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            verticalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .navigationBarsPadding()
                .imePadding(),
        ) {
            OutlinedTextField(
                value = title,
                onValueChange = { title = it },
                label = { Text("Title") },
                textStyle = MaterialTheme.typography.titleLarge,
                modifier = Modifier.fillMaxWidth(),
            )

            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                ItemType.entries.forEachIndexed { index, t ->
                    SegmentedButton(
                        selected = type == t,
                        onClick = { type = t },
                        shape = SegmentedButtonDefaults.itemShape(index, ItemType.entries.size),
                    ) {
                        Text(t.raw.replaceFirstChar { it.uppercase() })
                    }
                }
            }

            OutlinedTextField(
                value = body,
                onValueChange = { body = it },
                label = { Text("Notes (markdown)") },
                minLines = 3,
                modifier = Modifier.fillMaxWidth(),
            )

            // List picker
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("List", modifier = Modifier.weight(1f))
                OutlinedButton(onClick = { listMenuOpen = true }) {
                    Text(library.list(listId)?.name ?: listId)
                }
                DropdownMenu(expanded = listMenuOpen, onDismissRequest = { listMenuOpen = false }) {
                    library.activeLists.forEach { list ->
                        DropdownMenuItem(
                            text = { Text(list.name) },
                            onClick = {
                                listId = list.id
                                listMenuOpen = false
                            },
                        )
                    }
                }
            }

            if (type != ItemType.NOTE) {
                // Due date / time
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Due", modifier = Modifier.weight(1f))
                    val currentDue = due
                    if (currentDue != null) {
                        OutlinedButton(onClick = { datePickerOpen = true }) {
                            Text(dueLabel(currentDue, dueAllDay, zone))
                        }
                        if (!dueAllDay) {
                            Spacer(Modifier.height(0.dp))
                            TextButton(onClick = { timeDialogOpen = true }) { Text("Time") }
                        }
                        TextButton(onClick = { due = null }) { Text("Clear") }
                    } else {
                        OutlinedButton(onClick = { datePickerOpen = true }) { Text("Add date") }
                    }
                }
                if (due != null) {
                    LabeledSwitch("All-day", dueAllDay) { dueAllDay = it }
                    LabeledSwitch("Reminder", reminderOn) { reminderOn = it }
                    // Repeat
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Repeat", modifier = Modifier.weight(1f))
                        OutlinedButton(onClick = { repeatMenuOpen = true }) {
                            Text(recurrencePresets.firstOrNull { it.second == rrule }?.first ?: "Custom")
                        }
                        DropdownMenu(
                            expanded = repeatMenuOpen,
                            onDismissRequest = { repeatMenuOpen = false },
                        ) {
                            recurrencePresets.forEach { (label, rule) ->
                                DropdownMenuItem(
                                    text = { Text(label) },
                                    onClick = {
                                        rrule = rule
                                        repeatMenuOpen = false
                                    },
                                )
                            }
                        }
                    }
                }

                // Priority
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Priority", modifier = Modifier.weight(1f))
                }
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    Priority.entries.forEachIndexed { index, p ->
                        SegmentedButton(
                            selected = priority == p,
                            onClick = { priority = p },
                            shape = SegmentedButtonDefaults.itemShape(index, Priority.entries.size),
                        ) {
                            Text(p.raw.replaceFirstChar { it.uppercase() })
                        }
                    }
                }

                LabeledSwitch("Flagged", flagged) { flagged = it }
                LabeledSwitch("Urgent", urgent) { urgent = it }
            }

            if (type == ItemType.HABIT) {
                Text("Habit", style = MaterialTheme.typography.titleSmall)
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    HabitFrequency.habitCadences.forEachIndexed { index, f ->
                        SegmentedButton(
                            selected = frequency == f,
                            onClick = { frequency = f },
                            shape = SegmentedButtonDefaults.itemShape(index, HabitFrequency.habitCadences.size),
                        ) {
                            Text(f.raw.replaceFirstChar { it.uppercase() })
                        }
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Goal per cycle", modifier = Modifier.weight(1f))
                    TextButton(onClick = { if (goal > 1) goal -= 1 }) { Text("−") }
                    Text("$goal", style = MaterialTheme.typography.titleMedium)
                    TextButton(onClick = { goal += 1 }) { Text("+") }
                }
                if (frequency != HabitFrequency.DAILY) {
                    LabeledSwitch("Flexible goal (\"$goal times ${if (frequency == HabitFrequency.WEEKLY) "a week" else "a month"}\")", flexible) {
                        flexible = it
                    }
                }
            }

            OutlinedTextField(
                value = tagsText,
                onValueChange = { tagsText = it },
                label = { Text("Tags (comma separated)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth().padding(bottom = 20.dp),
            ) {
                TextButton(
                    onClick = {
                        viewModel.softDeleteItem(item.id)
                        onDismiss()
                    },
                ) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
                Spacer(Modifier.weight(1f))
                Button(
                    onClick = {
                        viewModel.updateItem(
                            item.copy(
                                title = title.trim().ifEmpty { item.title },
                                body = body,
                                type = type,
                                listId = listId,
                                due = due,
                                dueAllDay = dueAllDay,
                                priority = priority,
                                flagged = flagged,
                                triggers = if (urgent) {
                                    Triggers(urgent = TriggerToggle(true), location = item.triggers?.location)
                                } else {
                                    item.triggers?.copy(urgent = null)
                                        ?.takeIf { t -> t.location != null }
                                },
                                reminder = if (reminderOn) {
                                    Reminder(enabled = true, early = item.reminder?.early)
                                } else {
                                    null
                                },
                                recurrence = rrule?.let(::Recurrence),
                                frequency = if (type == ItemType.HABIT) frequency else item.frequency,
                                goalPerCycle = if (type == ItemType.HABIT) goal else item.goalPerCycle,
                                flexibleGoal = if (type == ItemType.HABIT) flexible else item.flexibleGoal,
                                tags = tagsText.split(",").map { it.trim() }.filter { it.isNotEmpty() },
                            ),
                        )
                        onDismiss()
                    },
                ) { Text("Save") }
            }
        }
    }

    if (datePickerOpen) {
        val state = rememberDatePickerState(
            initialSelectedDateMillis = (due ?: Instant.now()).toEpochMilli(),
        )
        DatePickerDialog(
            onDismissRequest = { datePickerOpen = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        val millis = state.selectedDateMillis
                        if (millis != null) {
                            // The picker returns UTC midnight; keep the prior
                            // time-of-day (or 09:00 default) in the local zone.
                            val date = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                            val time = due?.atZone(zone)?.toLocalTime() ?: LocalTime.of(9, 0)
                            due = date.atTime(if (dueAllDay) LocalTime.MIDNIGHT else time)
                                .atZone(zone).toInstant()
                        }
                        datePickerOpen = false
                    },
                ) { Text("OK") }
            },
            dismissButton = { TextButton(onClick = { datePickerOpen = false }) { Text("Cancel") } },
        ) {
            DatePicker(state = state)
        }
    }

    if (timeDialogOpen) {
        TimeTextDialog(
            initial = due?.atZone(zone)?.toLocalTime() ?: LocalTime.of(9, 0),
            onConfirm = { picked ->
                val date = (due ?: Instant.now()).atZone(zone).toLocalDate()
                due = date.atTime(picked).atZone(zone).toInstant()
                timeDialogOpen = false
            },
            onDismiss = { timeDialogOpen = false },
        )
    }
}

@Composable
private fun LabeledSwitch(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

/** Tiny HH:mm entry dialog (keeps us off still-moving TimePicker APIs). */
@Composable
private fun TimeTextDialog(
    initial: LocalTime,
    onConfirm: (LocalTime) -> Unit,
    onDismiss: () -> Unit,
) {
    var text by remember { mutableStateOf("%02d:%02d".format(initial.hour, initial.minute)) }
    val parsed = runCatching { LocalTime.parse(text) }.getOrNull()

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Time") },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                label = { Text("24-hour, e.g. 09:30") },
                singleLine = true,
                isError = parsed == null,
            )
        },
        confirmButton = {
            TextButton(
                onClick = { parsed?.let(onConfirm) },
                enabled = parsed != null,
            ) { Text("OK") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
