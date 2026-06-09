package io.github.saxonbobart.lists.ui.detail

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.core.query.SmartList
import io.github.saxonbobart.lists.ui.ListsViewModel
import io.github.saxonbobart.lists.ui.components.ItemRow

/** A smart list: the matching items, grouped by their home list. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SmartListScreen(
    viewModel: ListsViewModel,
    smartId: String,
    onBack: () -> Unit,
    onOpenHabit: (Item) -> Unit,
) {
    val library by viewModel.library.collectAsState()
    val smart = SmartList.entries.firstOrNull { it.id == smartId } ?: return
    var includeCompleted by rememberSaveable { mutableStateOf(false) }

    val matches = library.items.filter { smart.matches(it, includeCompleted = includeCompleted) }
    val groups = matches.groupBy { it.listId }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(smart.displayName, fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (smart != SmartList.COMPLETED) {
                        IconButton(onClick = { includeCompleted = !includeCompleted }) {
                            Icon(
                                if (includeCompleted) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                                contentDescription = if (includeCompleted) "Hide completed" else "Show completed",
                            )
                        }
                    }
                },
            )
        },
    ) { padding ->
        if (matches.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text(
                    "Nothing here. Nice.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            return@Scaffold
        }
        LazyColumn(contentPadding = padding) {
            groups.forEach { (listId, items) ->
                item(key = "header-$listId") {
                    Text(
                        library.list(listId)?.name ?: listId,
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 20.dp, top = 16.dp, bottom = 4.dp),
                    )
                }
                items(items.size, key = { i -> "item-${items[i].id}" }) { i ->
                    val item = items[i]
                    ItemRow(
                        item = item,
                        onClick = {
                            if (item.type == ItemType.HABIT) onOpenHabit(item) else viewModel.edit(item.id)
                        },
                        onToggleTask = { viewModel.toggleDone(item.id) },
                        onTapHabitRing = { viewModel.incrementHabit(item.id) },
                        onDelete = { viewModel.softDeleteItem(item.id) },
                    )
                }
            }
        }
    }
}
