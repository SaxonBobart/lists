package io.github.saxonbobart.lists.ui.tags

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.ui.ListsViewModel
import io.github.saxonbobart.lists.ui.components.ItemRow

/** All tags as chips; selecting one filters to its items. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TagsScreen(
    viewModel: ListsViewModel,
    onBack: () -> Unit,
    onOpenHabit: (Item) -> Unit,
) {
    val library by viewModel.library.collectAsState()
    var selected by rememberSaveable { mutableStateOf<String?>(null) }

    val tagged = selected?.let { tag ->
        library.items.filter { it.deletedAt == null && it.tags.contains(tag) }
    } ?: emptyList()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Tags", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(contentPadding = padding) {
            item {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    library.allTags.forEach { tag ->
                        FilterChip(
                            selected = selected == tag,
                            onClick = { selected = if (selected == tag) null else tag },
                            label = { Text("#$tag") },
                        )
                    }
                }
                if (library.allTags.isEmpty()) {
                    Text(
                        "No tags yet. Add one from any item's editor.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(20.dp),
                    )
                }
            }
            items(tagged.size, key = { i -> "tagged-${tagged[i].id}" }) { i ->
                val item = tagged[i]
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
