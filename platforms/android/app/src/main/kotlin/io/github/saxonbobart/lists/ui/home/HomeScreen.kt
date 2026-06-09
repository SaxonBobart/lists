package io.github.saxonbobart.lists.ui.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.outlined.Notes
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Loop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.saxonbobart.lists.core.model.ItemList
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.core.query.SmartList
import io.github.saxonbobart.lists.data.Library
import io.github.saxonbobart.lists.ui.ListsViewModel
import io.github.saxonbobart.lists.ui.components.AddFabMenu
import io.github.saxonbobart.lists.ui.components.ListsLoadingIndicator
import io.github.saxonbobart.lists.ui.components.listIconChoices
import io.github.saxonbobart.lists.ui.components.listIconFor
import io.github.saxonbobart.lists.ui.components.smartListIcon
import io.github.saxonbobart.lists.ui.theme.accent

/** The sidebar-equivalent: smart list tiles up top, the list tree below. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    viewModel: ListsViewModel,
    onOpenList: (ItemList) -> Unit,
    onOpenSmart: (SmartList) -> Unit,
    onOpenSearch: () -> Unit,
    onOpenTags: () -> Unit,
    onOpenDeleted: () -> Unit,
) {
    val library by viewModel.library.collectAsState()
    var fabExpanded by rememberSaveable { mutableStateOf(false) }
    var newDialog by remember { mutableStateOf<ItemType?>(null) }
    var newListDialog by remember { mutableStateOf(false) }

    Scaffold(
        floatingActionButton = {
            AddFabMenu(
                expanded = fabExpanded,
                onExpandedChange = { fabExpanded = it },
                entries = listOf(
                    "New task" to Icons.Filled.Check,
                    "New habit" to Icons.Outlined.Loop,
                    "New note" to Icons.AutoMirrored.Outlined.Notes,
                    "New list" to Icons.Filled.Add,
                ),
                onEntry = { index ->
                    when (index) {
                        0 -> newDialog = ItemType.TASK
                        1 -> newDialog = ItemType.HABIT
                        2 -> newDialog = ItemType.NOTE
                        3 -> newListDialog = true
                    }
                },
            )
        },
    ) { padding ->
        if (!library.loaded) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                ListsLoadingIndicator()
            }
            return@Scaffold
        }

        LazyColumn(
            contentPadding = padding,
            modifier = Modifier.fillMaxSize(),
        ) {
            item {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 20.dp, end = 8.dp, top = 16.dp, bottom = 4.dp),
                ) {
                    Text(
                        "Lists",
                        style = MaterialTheme.typography.displaySmall,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(onClick = onOpenSearch) {
                        Icon(Icons.Filled.Search, contentDescription = "Search")
                    }
                    IconButton(onClick = onOpenDeleted) {
                        Icon(Icons.Filled.DeleteOutline, contentDescription = "Recently deleted")
                    }
                }
            }

            // Smart tiles, two per row.
            val tiles = listOf(
                SmartList.TODAY, SmartList.SCHEDULED,
                SmartList.ALL, SmartList.FLAGGED,
                SmartList.COMPLETED, SmartList.TAGS,
            )
            items(tiles.chunked(2).size) { rowIndex ->
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 6.dp),
                ) {
                    tiles.chunked(2)[rowIndex].forEach { smart ->
                        SmartTile(
                            smart = smart,
                            count = smartCount(library, smart),
                            onClick = { if (smart == SmartList.TAGS) onOpenTags() else onOpenSmart(smart) },
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }

            item {
                Text(
                    "My Lists",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 20.dp, top = 20.dp, bottom = 4.dp),
                )
            }

            val rows = flattenListTree(library)
            items(rows.size) { i ->
                val (list, depth) = rows[i]
                ListRow(
                    library = library,
                    list = list,
                    depth = depth,
                    onClick = { onOpenList(list) },
                )
            }

            item { Spacer(Modifier.height(96.dp)) } // room above the FAB
        }
    }

    newDialog?.let { type ->
        QuickAddDialog(
            type = type,
            library = library,
            onAdd = { title, listId -> viewModel.quickAdd(title, listId, type) },
            onDismiss = { newDialog = null },
        )
    }
    if (newListDialog) {
        NewListDialog(
            onCreate = { name, icon, color -> viewModel.createList(name, icon, color) },
            onDismiss = { newListDialog = false },
        )
    }
}

private fun smartCount(library: Library, smart: SmartList): Int =
    if (smart == SmartList.TAGS) library.allTags.size
    else library.items.count { smart.matches(it) }

/** Root lists then children, depth-first, with their indent depth. */
private fun flattenListTree(library: Library): List<Pair<ItemList, Int>> {
    val out = mutableListOf<Pair<ItemList, Int>>()
    fun visit(parentId: String?, depth: Int) {
        for (list in library.childLists(parentId)) {
            out.add(list to depth)
            visit(list.id, depth + 1)
        }
    }
    visit(null, 0)
    return out
}

@Composable
private fun SmartTile(
    smart: SmartList,
    count: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        onClick = onClick,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
        ),
        modifier = modifier,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(14.dp),
        ) {
            Icon(
                smartListIcon(smart),
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    smart.displayName,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            Text(
                "$count",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ListRow(
    library: Library,
    list: ItemList,
    depth: Int,
    onClick: () -> Unit,
) {
    val remaining = library.itemsIn(list.id).count { !it.isComplete() }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(start = (20 + depth * 24).dp, end = 20.dp, top = 10.dp, bottom = 10.dp),
    ) {
        Surface(
            shape = CircleShape,
            color = list.color.accent().copy(alpha = 0.18f),
            modifier = Modifier.size(36.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    listIconFor(list.icon),
                    contentDescription = null,
                    tint = list.color.accent(),
                    modifier = Modifier.size(20.dp),
                )
            }
        }
        Spacer(Modifier.width(14.dp))
        Text(
            list.name,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f),
        )
        Text(
            if (remaining > 0) "$remaining" else "",
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.width(6.dp))
        Icon(
            Icons.AutoMirrored.Filled.ArrowForward,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.outlineVariant,
            modifier = Modifier.size(16.dp),
        )
    }
}

@Composable
private fun QuickAddDialog(
    type: ItemType,
    library: Library,
    onAdd: (title: String, listId: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var title by remember { mutableStateOf("") }
    var listId by remember { mutableStateOf(ItemList.INBOX_ID) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                when (type) {
                    ItemType.TASK -> "New task"
                    ItemType.HABIT -> "New habit"
                    ItemType.NOTE -> "New note"
                },
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it },
                    label = { Text("Title") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Text("List", style = MaterialTheme.typography.labelLarge)
                library.activeLists.forEach { list ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { listId = list.id }
                            .padding(vertical = 4.dp),
                    ) {
                        Icon(
                            listIconFor(list.icon),
                            contentDescription = null,
                            tint = list.color.accent(),
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(list.name, modifier = Modifier.weight(1f))
                        if (listId == list.id) {
                            Icon(
                                Icons.Filled.Check,
                                contentDescription = "Selected",
                                tint = MaterialTheme.colorScheme.primary,
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onAdd(title, listId)
                    onDismiss()
                },
                enabled = title.isNotBlank(),
            ) { Text("Add") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun NewListDialog(
    onCreate: (name: String, icon: String, color: ItemList.ListColor) -> Unit,
    onDismiss: () -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var icon by remember { mutableStateOf(listIconChoices.first()) }
    var color by remember { mutableStateOf(ItemList.ListColor.BLUE) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("New list") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Text("Color", style = MaterialTheme.typography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ItemList.ListColor.entries.take(6).forEach { c -> ColorDot(c, color == c) { color = c } }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ItemList.ListColor.entries.drop(6).forEach { c -> ColorDot(c, color == c) { color = c } }
                }
                Text("Icon", style = MaterialTheme.typography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listIconChoices.take(5).forEach { ic -> IconDot(ic, icon == ic) { icon = ic } }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listIconChoices.drop(5).forEach { ic -> IconDot(ic, icon == ic) { icon = ic } }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onCreate(name, icon, color)
                    onDismiss()
                },
                enabled = name.isNotBlank(),
            ) { Text("Create") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun ColorDot(c: ItemList.ListColor, selected: Boolean, onClick: () -> Unit) {
    Surface(
        shape = CircleShape,
        color = c.accent(),
        modifier = Modifier.size(32.dp).clickable(onClick = onClick),
    ) {
        if (selected) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    Icons.Filled.Check,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.surface,
                    modifier = Modifier.size(18.dp),
                )
            }
        }
    }
}

@Composable
private fun IconDot(iconName: String, selected: Boolean, onClick: () -> Unit) {
    Surface(
        shape = CircleShape,
        color = if (selected) {
            MaterialTheme.colorScheme.primaryContainer
        } else {
            MaterialTheme.colorScheme.surfaceContainerHigh
        },
        modifier = Modifier.size(36.dp).clickable(onClick = onClick),
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(
                listIconFor(iconName),
                contentDescription = iconName,
                modifier = Modifier.size(20.dp),
                tint = if (selected) {
                    MaterialTheme.colorScheme.onPrimaryContainer
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
            )
        }
    }
}
