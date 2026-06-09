package io.github.saxonbobart.lists.ui.deleted

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.RestoreFromTrash
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

import io.github.saxonbobart.lists.ui.ListsViewModel

/** Tombstoned lists and items: restore, or delete forever. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecentlyDeletedScreen(
    viewModel: ListsViewModel,
    onBack: () -> Unit,
) {
    val library by viewModel.library.collectAsState()
    val deletedLists = library.lists.filter { it.deletedAt != null }
    val deletedItems = library.items.filter { it.deletedAt != null }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Recently Deleted", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(contentPadding = padding) {
            if (deletedLists.isEmpty() && deletedItems.isEmpty()) {
                item {
                    Text(
                        "Nothing deleted recently.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(20.dp),
                    )
                }
            }

            if (deletedLists.isNotEmpty()) {
                item {
                    Text(
                        "Lists",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 20.dp, top = 16.dp, bottom = 4.dp),
                    )
                }
                items(deletedLists.size, key = { i -> "dl-${deletedLists[i].id}" }) { i ->
                    val list = deletedLists[i]
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 20.dp, vertical = 6.dp),
                    ) {
                        Text(
                            list.name,
                            modifier = Modifier.weight(1f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        IconButton(onClick = { viewModel.restoreList(list.id) }) {
                            Icon(Icons.Filled.RestoreFromTrash, contentDescription = "Restore list")
                        }
                    }
                }
            }

            if (deletedItems.isNotEmpty()) {
                item {
                    Text(
                        "Items",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 20.dp, top = 16.dp, bottom = 4.dp),
                    )
                }
                items(deletedItems.size, key = { i -> "di-${deletedItems[i].id}" }) { i ->
                    val item = deletedItems[i]
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 20.dp, vertical = 2.dp),
                    ) {
                        Text(
                            item.title,
                            modifier = Modifier.weight(1f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        IconButton(onClick = { viewModel.restoreItem(item.id) }) {
                            Icon(Icons.Filled.RestoreFromTrash, contentDescription = "Restore item")
                        }
                        IconButton(onClick = { viewModel.hardDeleteItem(item.id) }) {
                            Icon(
                                Icons.Filled.DeleteForever,
                                contentDescription = "Delete forever",
                                tint = MaterialTheme.colorScheme.error,
                            )
                        }
                    }
                }
            }
        }
    }
}
