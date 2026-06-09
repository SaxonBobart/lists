package io.github.saxonbobart.lists.data

import io.github.saxonbobart.lists.core.habits.HabitCycle
import io.github.saxonbobart.lists.core.model.HabitCompletion
import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemList
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.core.recurrence.RecurrenceEngine
import io.github.saxonbobart.lists.core.storage.FileStore
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** The whole in-memory library: every list and item that parsed off disk. */
data class Library(
    val lists: List<ItemList> = emptyList(),
    val items: List<Item> = emptyList(),
    val quarantined: List<FileStore.QuarantinedFile> = emptyList(),
    val loaded: Boolean = false,
) {
    fun list(id: String): ItemList? = lists.firstOrNull { it.id == id }
    fun item(id: UUID): Item? = items.firstOrNull { it.id == id }

    /** Active (non-tombstoned) lists, sidebar order. */
    val activeLists: List<ItemList>
        get() = lists.filter { it.deletedAt == null }.sortedBy { it.position }

    fun childLists(parentId: String?): List<ItemList> =
        activeLists.filter { it.parentId == parentId }

    fun itemsIn(listId: String): List<Item> =
        items.filter { it.listId == listId && it.deletedAt == null }

    val allTags: List<String>
        get() = items.filter { it.deletedAt == null }
            .flatMap { it.tags }
            .distinct()
            .sortedWith(String.CASE_INSENSITIVE_ORDER)
}

/**
 * Single mutation point over the shared [FileStore], mirroring the iOS
 * `ItemStore`'s rules: memory first, then disk (CONC-1); completing a
 * recurring task spawns the next occurrence (TASK-1); writes are serialized
 * the way the Swift actor serializes them.
 */
class ListsRepository(
    private val rootDir: File,
    private val zone: ZoneId = ZoneId.systemDefault(),
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    private val store = FileStore(rootDir)
    private val mutex = Mutex()

    private val _library = MutableStateFlow(Library())
    val library: StateFlow<Library> = _library.asStateFlow()

    private suspend fun <T> locked(block: () -> T): T =
        withContext(io) { mutex.withLock { block() } }

    // MARK: - Load / seed

    suspend fun load() = locked {
        store.ensureRoot()
        var result = store.loadAll()
        if (result.lists.isEmpty()) {
            SampleData.seed(store)
            result = store.loadAll()
        }
        if (result.lists.none { it.list.id == ItemList.INBOX_ID }) {
            store.writeList(ItemList.makeInbox())
            result = store.loadAll()
        }
        publish(result)
    }

    private fun publish(result: FileStore.LoadResult) {
        _library.value = Library(
            lists = result.lists.map { it.list },
            items = result.lists.flatMap { it.items },
            quarantined = result.quarantined,
            loaded = true,
        )
    }

    // MARK: - Items

    suspend fun addItem(item: Item) = locked {
        store.writeItem(item)
        _library.value = _library.value.copy(items = _library.value.items + item)
    }

    suspend fun updateItem(updated: Item) = locked {
        val old = _library.value.item(updated.id)
        val stamped = updated.copy(modifiedAt = Instant.now())
        replaceInMemory(stamped)
        if (old != null && old.listId != stamped.listId) {
            store.moveItem(stamped, fromListId = old.listId)
        } else {
            store.writeItem(stamped)
        }
    }

    /**
     * Toggle a task done. On the completing transition of a recurring task,
     * spawn the next occurrence as a fresh dated item (TASK-1) — recurrence
     * math runs in the task's stored zone (REC-1).
     */
    suspend fun toggleDone(id: UUID) = locked {
        val item = _library.value.item(id) ?: return@locked
        val wasDone = item.done
        val now = Instant.now()
        val toggled = item.copy(
            done = !item.done,
            completedAt = if (!item.done) now else null,
            modifiedAt = now,
        )
        replaceInMemory(toggled)
        store.writeItem(toggled)

        if (toggled.done && !wasDone && toggled.type == ItemType.TASK) {
            val rrule = toggled.recurrence?.rrule ?: return@locked
            val base = toggled.due ?: return@locked
            val nextDue = RecurrenceEngine.nextOccurrence(
                base, rrule, RecurrenceEngine.zoneFor(toggled.dueTimeZone),
            ) ?: return@locked
            val next = toggled.copy(
                id = UUID.randomUUID(),
                done = false,
                completedAt = null,
                due = nextDue,
                createdAt = now,
                modifiedAt = now,
            )
            store.writeItem(next)
            _library.value = _library.value.copy(items = _library.value.items + next)
        }
    }

    /** +1 on the current cycle, capped at the goal (the row's ring tap). */
    suspend fun incrementHabit(id: UUID, now: Instant = Instant.now()) = locked {
        val item = _library.value.item(id) ?: return@locked
        if (item.type != ItemType.HABIT) return@locked
        val key = HabitCycle.key(item.frequency ?: return@locked, now, zone)
        if ((item.completionLog(zone)[key] ?: 0) >= item.goalPerCycle) return@locked
        mutateHabitLocked(item) { it.copy(completions = it.completions + HabitCompletion(at = now)) }
    }

    /** -1 on the current cycle: removes that cycle's most recent event. */
    suspend fun decrementHabit(id: UUID, now: Instant = Instant.now()) = locked {
        val item = _library.value.item(id) ?: return@locked
        if (item.type != ItemType.HABIT) return@locked
        val frequency = item.frequency ?: return@locked
        val key = HabitCycle.key(frequency, now, zone)
        val target = item.completions
            .filter { HabitCycle.key(frequency, it.at, zone) == key }
            .maxByOrNull { it.at } ?: return@locked
        mutateHabitLocked(item) { it.copy(completions = it.completions - target) }
    }

    /** Log a completion at an arbitrary instant (the Log's "add entry"). */
    suspend fun addCompletion(id: UUID, at: Instant) = locked {
        val item = _library.value.item(id) ?: return@locked
        if (item.type != ItemType.HABIT) return@locked
        mutateHabitLocked(item) { it.copy(completions = it.completions + HabitCompletion(at = at)) }
    }

    suspend fun removeCompletion(id: UUID, completionId: UUID) = locked {
        val item = _library.value.item(id) ?: return@locked
        mutateHabitLocked(item) { h -> h.copy(completions = h.completions.filterNot { it.id == completionId }) }
    }

    suspend fun softDeleteItem(id: UUID) = locked {
        val item = _library.value.item(id) ?: return@locked
        val tombstoned = item.copy(deletedAt = Instant.now(), modifiedAt = Instant.now())
        replaceInMemory(tombstoned)
        store.writeItem(tombstoned)
    }

    suspend fun restoreItem(id: UUID) = locked {
        val item = _library.value.item(id) ?: return@locked
        val restored = item.copy(deletedAt = null, modifiedAt = Instant.now())
        replaceInMemory(restored)
        store.writeItem(restored)
    }

    suspend fun hardDeleteItem(id: UUID) = locked {
        val item = _library.value.item(id) ?: return@locked
        store.deleteItem(item)
        _library.value = _library.value.copy(items = _library.value.items.filterNot { it.id == id })
    }

    // MARK: - Lists

    suspend fun createList(
        name: String,
        icon: String = "tray.fill",
        color: ItemList.ListColor = ItemList.ListColor.BLUE,
        parentId: String? = null,
        defaultItemType: ItemType? = ItemType.TASK,
    ): ItemList {
        val now = Instant.now()
        val position = (library.value.lists.maxOfOrNull { it.position } ?: 0.0) + 1.0
        val list = ItemList(
            id = UUID.randomUUID().toString().lowercase(),
            name = name.ifBlank { "Untitled" },
            icon = icon,
            color = color,
            defaultItemType = defaultItemType,
            createdAt = now,
            modifiedAt = now,
            position = position,
            parentId = parentId,
        )
        locked {
            store.writeList(list)
            _library.value = _library.value.copy(lists = _library.value.lists + list)
        }
        return list
    }

    suspend fun updateList(updated: ItemList) = locked {
        val stamped = updated.copy(modifiedAt = Instant.now(), lamport = updated.lamport + 1)
        store.writeList(stamped)
        _library.value = _library.value.copy(
            lists = _library.value.lists.map { if (it.id == stamped.id) stamped else it },
        )
    }

    /** Soft-delete a list: tombstones the list, its descendants, and items. */
    suspend fun softDeleteList(id: String) = locked {
        val now = Instant.now()
        val doomedIds = descendantIds(id) + id
        val lists = _library.value.lists.map {
            if (it.id in doomedIds && it.deletedAt == null) {
                it.copy(deletedAt = now, modifiedAt = now)
            } else it
        }
        val items = _library.value.items.map {
            if (it.listId in doomedIds && it.deletedAt == null) {
                it.copy(deletedAt = now, modifiedAt = now)
            } else it
        }
        _library.value = _library.value.copy(lists = lists, items = items)
        lists.filter { it.id in doomedIds }.forEach(store::writeList)
        items.filter { it.listId in doomedIds }.forEach(store::writeItem)
    }

    /** Restore a tombstoned list; if its parent is still tombstoned, detach
     *  to the sidebar root (matching iOS restore semantics). */
    suspend fun restoreList(id: String) = locked {
        val list = _library.value.list(id) ?: return@locked
        val parentDeleted = list.parentId?.let { pid ->
            _library.value.list(pid)?.deletedAt != null
        } ?: false
        val restored = list.copy(
            deletedAt = null,
            parentId = if (parentDeleted) null else list.parentId,
            modifiedAt = Instant.now(),
        )
        store.writeList(restored)
        _library.value = _library.value.copy(
            lists = _library.value.lists.map { if (it.id == id) restored else it },
        )
    }

    private fun descendantIds(rootId: String): Set<String> {
        val byParent = _library.value.lists.groupBy { it.parentId }
        val out = mutableSetOf<String>()
        fun visit(id: String) {
            byParent[id]?.forEach { child ->
                if (out.add(child.id)) visit(child.id)
            }
        }
        visit(rootId)
        return out
    }

    // MARK: - Internals

    private fun mutateHabitLocked(item: Item, change: (Item) -> Item) {
        val mutated = change(item).copy(modifiedAt = Instant.now())
        replaceInMemory(mutated)
        store.writeItem(mutated)
    }

    private fun replaceInMemory(item: Item) {
        _library.value = _library.value.copy(
            items = _library.value.items.map { if (it.id == item.id) item else it },
        )
    }
}
