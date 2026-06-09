package io.github.saxonbobart.lists.core

import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemList
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.core.storage.FileStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.time.Instant

class FileStoreTest {

    private val now = Instant.parse("2026-05-09T15:30:00.000Z")

    private fun newStore(): FileStore {
        val dir = Files.createTempDirectory("lists-store").toFile()
        return FileStore(File(dir, "Lists")).also { it.ensureRoot() }
    }

    private fun list(id: String, name: String, parentId: String? = null) = ItemList(
        id = id, name = name, icon = "tray.fill", color = ItemList.ListColor.BLUE,
        createdAt = now, modifiedAt = now, position = 1.0, parentId = parentId,
    )

    private fun task(title: String, listId: String) = Item(
        type = ItemType.TASK, title = title, listId = listId,
        createdAt = now, modifiedAt = now,
    )

    @Test
    fun `write and load a nested library round trips`() {
        val store = newStore()
        store.writeList(list("inbox", "Inbox"))
        store.writeList(list("projects", "Projects"))
        store.writeList(list("sideapp", "Side App", parentId = "projects"))
        store.writeList(list("sprint1", "Sprint 1", parentId = "sideapp"))

        val a = task("Pay phone bill", "inbox")
        val b = task("Design schema", "sprint1").copy(body = "Notes **here**.\n")
        store.writeItem(a)
        store.writeItem(b)

        val fresh = FileStore(store.root)
        val result = fresh.loadAll()
        assertEquals(0, result.quarantined.size)
        assertEquals(4, result.lists.size)

        val byId = result.lists.associateBy { it.list.id }
        assertEquals(listOf(a), byId["inbox"]!!.items)
        assertEquals(listOf(b), byId["sprint1"]!!.items)
        assertEquals("projects", byId["sideapp"]!!.list.parentId)

        // Folder layout: display names, nested.
        assertTrue(File(store.root, "Projects/Side App/Sprint 1/.list.yml").isFile)
    }

    @Test
    fun `renaming a list moves its folder with items and children`() {
        val store = newStore()
        store.writeList(list("work", "Work"))
        store.writeList(list("sub", "Reports", parentId = "work"))
        store.writeItem(task("Submit timesheet", "work"))

        store.writeList(list("work", "Job"))

        assertFalse(File(store.root, "Work").exists())
        assertTrue(File(store.root, "Job/.list.yml").isFile)
        assertTrue(File(store.root, "Job/Reports/.list.yml").isFile)

        val reloaded = FileStore(store.root).loadAll()
        val byId = reloaded.lists.associateBy { it.list.id }
        assertEquals("Job", byId["work"]!!.list.name)
        assertEquals(1, byId["work"]!!.items.size)
    }

    @Test
    fun `a corrupt item file is quarantined while the rest load`() {
        val store = newStore()
        store.writeList(list("inbox", "Inbox"))
        store.writeItem(task("Good", "inbox"))
        val bad = File(store.listDirectory("inbox"), "00000000-0000-0000-0000-00000000DEAD.md")
        bad.writeText("not frontmatter at all")

        val result = FileStore(store.root).loadAll()
        assertEquals(1, result.quarantined.size)
        assertEquals(1, result.lists.single().items.size)
        assertFalse(bad.exists())
        assertTrue(File(store.root, ".quarantine").listFiles()!!.isNotEmpty())
    }

    @Test
    fun `a corrupt list header is quarantined but nested lists survive`() {
        val store = newStore()
        store.writeList(list("outer", "Outer"))
        store.writeList(list("inner", "Inner", parentId = "outer"))
        File(store.listDirectory("outer"), ".list.yml").writeText("{{{{ definitely not yaml")

        val result = FileStore(store.root).loadAll()
        assertEquals(1, result.quarantined.size)
        assertEquals(listOf("inner"), result.lists.map { it.list.id })
    }

    @Test
    fun `legacy id-named folders migrate to sanitized display names`() {
        val store = newStore()
        val legacyDir = File(store.root, "work-7f3a").apply { mkdirs() }
        File(legacyDir, ".list.yml").writeText(
            "id: work\nname: Work\nicon: briefcase.fill\ncolor: orange\n" +
                "created_at: 2026-05-09T15:30:00.000Z\nmodified_at: 2026-05-09T15:30:00.000Z\n" +
                "position: 1.0\nlamport: 0\n",
        )

        val result = FileStore(store.root).loadAll()
        assertEquals("work", result.lists.single().list.id)
        assertTrue(File(store.root, "Work/.list.yml").isFile)
        assertFalse(legacyDir.exists())
    }

    @Test
    fun `underscore-prefixed aux files are not items`() {
        val store = newStore()
        store.writeList(list("inbox", "Inbox"))
        File(store.listDirectory("inbox"), "_heartbeat.md").writeText("agent aux file")

        val result = FileStore(store.root).loadAll()
        assertEquals(0, result.quarantined.size)
        assertEquals(0, result.lists.single().items.size)
    }

    @Test
    fun `sibling name collisions get a numeric suffix`() {
        val store = newStore()
        store.writeList(list("a", "Groceries"))
        store.writeList(list("b", "Groceries"))
        assertTrue(File(store.root, "Groceries/.list.yml").isFile)
        assertTrue(File(store.root, "Groceries (2)/.list.yml").isFile)
    }

    @Test
    fun `moveItem writes to the new list then removes the old file`() {
        val store = newStore()
        store.writeList(list("inbox", "Inbox"))
        store.writeList(list("work", "Work"))
        val item = task("Email Sarah", "inbox")
        store.writeItem(item)

        val moved = item.copy(listId = "work")
        store.moveItem(moved, fromListId = "inbox")

        val result = FileStore(store.root).loadAll()
        val byId = result.lists.associateBy { it.list.id }
        assertEquals(0, byId["inbox"]!!.items.size)
        assertEquals(listOf(moved), byId["work"]!!.items)
    }

    @Test
    fun `sanitize matches the iOS rules`() {
        assertEquals("a-b-c", FileStore.sanitize("a/b:c"))
        assertEquals("hidden", FileStore.sanitize("...hidden"))
        assertEquals("dots", FileStore.sanitize("dots..."))
        assertEquals("spaced", FileStore.sanitize("  spaced  "))
        assertEquals("Untitled", FileStore.sanitize(""))
        assertEquals("Untitled", FileStore.sanitize("..."))
        // Matches iOS: illegal chars become dashes even if that's all there is.
        assertEquals("---", FileStore.sanitize("///"))
        assertEquals(80, FileStore.sanitize("x".repeat(200)).length)
    }
}
