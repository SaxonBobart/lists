package io.github.saxonbobart.lists.ui.search

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.unit.dp
import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.ui.ListsViewModel
import io.github.saxonbobart.lists.ui.components.ItemRow

/** Live search over titles, bodies, and tags. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(
    viewModel: ListsViewModel,
    onBack: () -> Unit,
    onOpenHabit: (Item) -> Unit,
) {
    val library by viewModel.library.collectAsState()
    var query by rememberSaveable { mutableStateOf("") }
    val focusRequester = remember { FocusRequester() }
    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    val results = if (query.isBlank()) {
        emptyList()
    } else {
        val q = query.trim()
        library.items.filter { item ->
            item.deletedAt == null && (
                item.title.contains(q, ignoreCase = true) ||
                    item.body.contains(q, ignoreCase = true) ||
                    item.tags.any { it.contains(q, ignoreCase = true) }
                )
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it },
                        placeholder = { Text("Search items…") },
                        singleLine = true,
                        trailingIcon = {
                            if (query.isNotEmpty()) {
                                IconButton(onClick = { query = "" }) {
                                    Icon(Icons.Filled.Close, contentDescription = "Clear")
                                }
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(end = 8.dp)
                            .focusRequester(focusRequester),
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(contentPadding = padding) {
            val groups = results.groupBy { it.listId }
            groups.forEach { (listId, items) ->
                item(key = "header-$listId") {
                    Text(
                        library.list(listId)?.name ?: listId,
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 20.dp, top = 16.dp, bottom = 4.dp),
                    )
                }
                items(items.size, key = { i -> "result-${items[i].id}" }) { i ->
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
            if (query.isNotBlank() && results.isEmpty()) {
                item {
                    Text(
                        "No matches for \"$query\".",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(20.dp),
                    )
                }
            }
        }
    }
}
