package io.github.saxonbobart.lists.ui

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import io.github.saxonbobart.lists.ListsApplication
import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemList
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.data.Library
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.UUID

class ListsViewModel(application: Application) : AndroidViewModel(application) {

    private val repo = (application as ListsApplication).repository

    val library: StateFlow<Library> = repo.library

    /** The item currently open in the global editor sheet, if any. */
    var editingItemId by mutableStateOf<UUID?>(null)
        private set

    init {
        viewModelScope.launch { repo.load() }
    }

    fun edit(id: UUID?) {
        editingItemId = id
    }

    // MARK: - Items

    fun quickAdd(title: String, listId: String, type: ItemType) {
        val trimmed = title.trim()
        if (trimmed.isEmpty()) return
        val item = Item(type = type, title = trimmed, listId = listId)
        viewModelScope.launch { repo.addItem(item) }
    }

    fun updateItem(item: Item) = viewModelScope.launch { repo.updateItem(item) }

    fun toggleDone(id: UUID) = viewModelScope.launch { repo.toggleDone(id) }

    fun incrementHabit(id: UUID) = viewModelScope.launch { repo.incrementHabit(id) }

    fun decrementHabit(id: UUID) = viewModelScope.launch { repo.decrementHabit(id) }

    fun addCompletion(id: UUID, at: Instant) = viewModelScope.launch { repo.addCompletion(id, at) }

    fun removeCompletion(id: UUID, completionId: UUID) =
        viewModelScope.launch { repo.removeCompletion(id, completionId) }

    fun softDeleteItem(id: UUID) = viewModelScope.launch {
        if (editingItemId == id) editingItemId = null
        repo.softDeleteItem(id)
    }

    fun restoreItem(id: UUID) = viewModelScope.launch { repo.restoreItem(id) }

    fun hardDeleteItem(id: UUID) = viewModelScope.launch { repo.hardDeleteItem(id) }

    // MARK: - Lists

    fun createList(
        name: String,
        icon: String,
        color: ItemList.ListColor,
        parentId: String? = null,
    ) = viewModelScope.launch { repo.createList(name, icon, color, parentId) }

    fun updateList(list: ItemList) = viewModelScope.launch { repo.updateList(list) }

    fun softDeleteList(id: String) = viewModelScope.launch { repo.softDeleteList(id) }

    fun restoreList(id: String) = viewModelScope.launch { repo.restoreList(id) }
}
