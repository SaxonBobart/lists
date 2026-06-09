package io.github.saxonbobart.lists.ui.detail

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
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
import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemList
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.core.model.ListSection
import io.github.saxonbobart.lists.core.query.SortMode
import io.github.saxonbobart.lists.core.query.sortedByMode
import io.github.saxonbobart.lists.ui.ListsViewModel
import io.github.saxonbobart.lists.ui.components.ItemRow
import io.github.saxonbobart.lists.ui.components.listIconFor
import io.github.saxonbobart.lists.ui.theme.accent
import java.time.Instant
import java.util.UUID

/** A user list: sectioned items, nested sub-lists, quick-add at the bottom. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ListDetailScreen(
    viewModel: ListsViewModel,
    listId: String,
    onBack: () -> Unit,
    onOpenList: (ItemList) -> Unit,
    onOpenHabit: (Item) -> Unit,
) {
    val library by viewModel.library.collectAsState()
    val list = library.list(listId) ?: return
    var showCompleted by rememberSaveable { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }
    var renameDialog by remember { mutableStateOf(false) }
    var deleteDialog by remember { mutableStateOf(false) }
    var quickTitle by rememberSaveable { mutableStateOf("") }

    val allItems = library.itemsIn(listId)
        .filter { it.parentId == null }
        .let { items -> if (showCompleted) items else items.filterNot { it.isComplete() } }
        .sortedByMode(SortMode.CREATED)
    val children = library.childLists(listId)

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(list.name, fontWeight = FontWeight.SemiBold)
                        Text(
                            "${allItems.size} items",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "List options")
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text(if (showCompleted) "Hide completed" else "Show completed") },
                            onClick = {
                                showCompleted = !showCompleted
                                menuOpen = false
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Rename list") },
                            onClick = {
                                renameDialog = true
                                menuOpen = false
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Delete list") },
                            onClick = {
                                deleteDialog = true
                                menuOpen = false
                            },
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
        bottomBar = {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .imePadding()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
            ) {
                OutlinedTextField(
                    value = quickTitle,
                    onValueChange = { quickTitle = it },
                    placeholder = { Text("Add to ${list.name}…") },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                IconButton(
                    onClick = {
                        viewModel.quickAdd(
                            quickTitle, listId,
                            list.defaultItemType ?: ItemType.TASK,
                        )
                        quickTitle = ""
                    },
                    enabled = quickTitle.isNotBlank(),
                ) {
                    Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Add item")
                }
            }
        },
    ) { padding ->
        LazyColumn(contentPadding = padding) {
            // Items with no section first, then each section by position.
            val sections: List<ListSection?> =
                listOf<ListSection?>(null) + list.sections.sortedBy { it.position }
            sections.forEach { section ->
                val sectionItems = allItems.filter {
                    it.section == section?.id?.toString()?.lowercase()
                }
                if (section != null && sectionItems.isNotEmpty()) {
                    item(key = "section-${section.id}") {
                        Text(
                            section.name,
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(start = 20.dp, top = 16.dp, bottom = 4.dp),
                        )
                    }
                }
                items(sectionItems.size, key = { i -> "item-${sectionItems[i].id}" }) { i ->
                    val item = sectionItems[i]
                    Column {
                        ItemRow(
                            item = item,
                            onClick = {
                                if (item.type == ItemType.HABIT) onOpenHabit(item) else viewModel.edit(item.id)
                            },
                            onToggleTask = { viewModel.toggleDone(item.id) },
                            onTapHabitRing = { viewModel.incrementHabit(item.id) },
                            onDelete = { viewModel.softDeleteItem(item.id) },
                        )
                        ThreadChildren(
                            library = library,
                            parent = item,
                            showCompleted = showCompleted,
                            onToggle = { viewModel.toggleDone(it) },
                            onEdit = { viewModel.edit(it) },
                        )
                    }
                }
            }

            if (children.isNotEmpty()) {
                item(key = "sublists-header") {
                    Text(
                        "Sub-Lists",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 20.dp, top = 20.dp, bottom = 4.dp),
                    )
                }
                items(children.size, key = { i -> "sublist-${children[i].id}" }) { i ->
                    val child = children[i]
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onOpenList(child) }
                            .padding(horizontal = 20.dp, vertical = 10.dp),
                    ) {
                        Surface(
                            shape = CircleShape,
                            color = child.color.accent().copy(alpha = 0.18f),
                            modifier = Modifier.size(32.dp),
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(
                                    listIconFor(child.icon),
                                    contentDescription = null,
                                    tint = child.color.accent(),
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                        }
                        Spacer(Modifier.width(12.dp))
                        Text(child.name, modifier = Modifier.weight(1f))
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowForward,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.outlineVariant,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                }
            }

            item { Spacer(Modifier.height(24.dp)) }
        }
    }

    if (renameDialog) {
        var name by remember { mutableStateOf(list.name) }
        AlertDialog(
            onDismissRequest = { renameDialog = false },
            title = { Text("Rename list") },
            text = {
                OutlinedTextField(value = name, onValueChange = { name = it }, singleLine = true)
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.updateList(list.copy(name = name.trim(), modifiedAt = Instant.now()))
                        renameDialog = false
                    },
                    enabled = name.isNotBlank(),
                ) { Text("Rename") }
            },
            dismissButton = { TextButton(onClick = { renameDialog = false }) { Text("Cancel") } },
        )
    }

    if (deleteDialog) {
        AlertDialog(
            onDismissRequest = { deleteDialog = false },
            title = { Text("Delete \"${list.name}\"?") },
            text = { Text("The list, its sub-lists, and their items move to Recently Deleted.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        deleteDialog = false
                        viewModel.softDeleteList(list.id)
                        onBack()
                    },
                ) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { deleteDialog = false }) { Text("Cancel") } },
        )
    }
}

/** Sub-items of a thread parent, indented beneath it. */
@Composable
private fun ThreadChildren(
    library: io.github.saxonbobart.lists.data.Library,
    parent: Item,
    showCompleted: Boolean,
    onToggle: (UUID) -> Unit,
    onEdit: (UUID) -> Unit,
) {
    val children = library.items
        .filter { it.parentId == parent.id && it.deletedAt == null }
        .let { if (showCompleted) it else it.filterNot { c -> c.isComplete() } }
    if (children.isEmpty()) return
    Column(Modifier.padding(start = 40.dp)) {
        children.forEach { child ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onEdit(child.id) }
                    .padding(vertical = 2.dp),
            ) {
                androidx.compose.material3.Checkbox(
                    checked = child.done,
                    onCheckedChange = { onToggle(child.id) },
                )
                Text(
                    child.title,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(
                        alpha = if (child.done) 0.55f else 1f,
                    ),
                )
            }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.surfaceVariant)
    }
}
