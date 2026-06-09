package io.github.saxonbobart.lists.core

import io.github.saxonbobart.lists.core.model.ItemList
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.core.model.ListSection
import io.github.saxonbobart.lists.core.storage.FileStore
import io.github.saxonbobart.lists.core.storage.YamlCodecException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.util.UUID

class ListYamlTest {

    private val now = Instant.parse("2026-05-09T15:30:00.000Z")

    private fun store(): FileStore {
        val dir = Files.createTempDirectory("lists-yaml").toFile()
        return FileStore(File(dir, "Lists")).also { it.ensureRoot() }
    }

    private fun roundTrip(list: ItemList): ItemList {
        val store = store()
        store.writeList(list)
        return store.readList(File(store.listDirectory(list.id), ".list.yml"))
    }

    @Test
    fun `round trips a list with sections`() {
        val list = ItemList(
            id = "personal",
            name = "Personal",
            icon = "person.fill",
            color = ItemList.ListColor.PURPLE,
            defaultItemType = ItemType.TASK,
            groceryMode = true,
            createdAt = now,
            modifiedAt = now,
            position = 2.0,
            lamport = 7,
            sections = listOf(
                ListSection(UUID.fromString("11111111-0000-0000-0000-000000000001"), "Health", 1.0),
                ListSection(UUID.fromString("11111111-0000-0000-0000-000000000002"), "Admin", 2.0),
            ),
        )
        assertEquals(list, roundTrip(list))
    }

    @Test
    fun `round trips a nested list with parent linkage`() {
        val store = store()
        val parent = ItemList(
            id = "projects", name = "Projects", icon = "folder.fill",
            color = ItemList.ListColor.INDIGO, createdAt = now, modifiedAt = now, position = 1.0,
        )
        val child = parent.copy(id = "projects-sub", name = "Side App", parentId = "projects")
        store.writeList(parent)
        store.writeList(child)
        val reread = store.readList(File(store.listDirectory("projects-sub"), ".list.yml"))
        assertEquals(child, reread)
        assertEquals("Projects/Side App", store.listDirectory("projects-sub").toRelativeString(store.root).replace('\\', '/'))
    }

    @Test
    fun `missing optional fields fall back to iOS defaults`() {
        val store = store()
        val dir = File(store.root, "Bare").apply { mkdirs() }
        File(dir, ".list.yml").writeText(
            "id: bare\nname: Bare\ncreated_at: 2026-05-09T15:30:00.000Z\n" +
                "modified_at: 2026-05-09T15:30:00.000Z\n",
        )
        val list = store.readList(File(dir, ".list.yml"))
        assertEquals("tray", list.icon)
        assertEquals(ItemList.ListColor.GREY, list.color)
        assertEquals(0.0, list.position, 0.0)
        assertEquals(0L, list.lamport)
        assertEquals(emptyList<ListSection>(), list.sections)
        assertEquals(false, list.groceryMode)
    }

    @Test
    fun `unknown color throws, unknown default item type falls back to task`() {
        val store = store()
        val dir = File(store.root, "X").apply { mkdirs() }
        File(dir, ".list.yml").writeText(
            "id: x\nname: X\ncolor: octarine\ncreated_at: 2026-05-09T15:30:00.000Z\n" +
                "modified_at: 2026-05-09T15:30:00.000Z\n",
        )
        assertThrows(YamlCodecException::class.java) { store.readList(File(dir, ".list.yml")) }

        File(dir, ".list.yml").writeText(
            "id: x\nname: X\ndefault_item_type: starship\ncreated_at: 2026-05-09T15:30:00.000Z\n" +
                "modified_at: 2026-05-09T15:30:00.000Z\n",
        )
        assertEquals(ItemType.TASK, store.readList(File(dir, ".list.yml")).defaultItemType)
    }
}
