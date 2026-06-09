package io.github.saxonbobart.lists.core.storage

import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemList
import java.io.File
import java.io.IOException
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID

/**
 * Owns all file I/O against the on-disk Lists library. Ported 1:1 from the
 * iOS `FileStore` actor; see PRODUCT-SPEC.md "Storage".
 *
 * Layout:
 * ```
 * <root>/<sanitized list name>/.list.yml
 * <root>/<sanitized list name>/<itemId>.md
 * <root>/<parent name>/<child name>/.list.yml      (nested lists)
 * ```
 *
 * Folder names mirror the list's display name (sanitized); the list's stable
 * id lives inside `.list.yml`. The store keeps a `listId -> File` map
 * populated by [loadAll] and kept in sync by [writeList] / [deleteList].
 *
 * Not thread-safe by itself — callers (the repository) serialize access on a
 * single dispatcher, mirroring the Swift actor's isolation.
 */
class FileStore(val root: File) {

    class StoreException(message: String) : IOException(message)

    private val pathById = mutableMapOf<String, File>()

    fun ensureRoot() {
        if (!root.isDirectory && !root.mkdirs()) {
            throw StoreException("Could not create library root at $root")
        }
    }

    // MARK: - Lists

    fun writeList(list: ItemList) {
        val targetDir = resolveTargetDir(list)
        val existingDir = pathById[list.id]

        if (existingDir != null && existingDir != targetDir) {
            // Rename / reparent: move the existing folder (items + children).
            if (existingDir.exists()) {
                targetDir.parentFile?.mkdirs()
                if (!existingDir.renameTo(targetDir)) {
                    throw StoreException("Could not move ${existingDir.name} to ${targetDir.name}")
                }
            } else {
                targetDir.mkdirs()
            }
        } else {
            targetDir.mkdirs()
        }

        atomicWrite(File(targetDir, ".list.yml"), ListYaml.encode(list))
        pathById[list.id] = targetDir
        if (existingDir != null && existingDir != targetDir) {
            refreshDescendantPaths(targetDir)
        }
    }

    fun readList(file: File): ItemList = ListYaml.decode(file.readText())

    // MARK: - Items

    fun writeItem(item: Item) {
        val dir = listDirectory(item.listId)
        dir.mkdirs()
        atomicWrite(File(dir, fileName(item.id)), FrontmatterCodec.encode(item))
    }

    /**
     * Move an item's file from [fromListId]'s folder to its current `listId`
     * folder. Write-then-delete, so a crash in between leaves a recoverable
     * duplicate, never a lost item.
     */
    fun moveItem(item: Item, fromListId: String) {
        writeItem(item)
        if (fromListId == item.listId) return
        val oldDir = pathById[fromListId] ?: return
        existingItemFile(oldDir, item.id)?.delete()
    }

    fun readItem(file: File): Item = FrontmatterCodec.decode(file.readText())

    fun deleteItem(item: Item) {
        existingItemFile(listDirectory(item.listId), item.id)?.delete()
    }

    /** Hard-deletes an entire list folder, including nested sub-lists. */
    fun deleteList(list: ItemList) {
        val dir = pathById.remove(list.id) ?: return
        if (dir.exists()) dir.deleteRecursively()
        // Drop descendants whose path is under the removed folder.
        val removedPrefix = dir.path + File.separator
        pathById.entries.removeIf { it.value.path.startsWith(removedPrefix) }
    }

    // MARK: - Bulk load

    data class LoadedList(val list: ItemList, val items: List<Item>)

    /** A file that failed to parse and was moved into `<root>/.quarantine/`. */
    data class QuarantinedFile(val originalPath: String, val reason: String)

    data class LoadResult(val lists: List<LoadedList>, val quarantined: List<QuarantinedFile>)

    /**
     * Walks the on-disk tree from [root]. Any directory containing `.list.yml`
     * is a list folder; its `*.md` files (skipping `_`-prefixed aux files) are
     * its items; sub-directories are recursed into for nested lists.
     *
     * Loading is per-file resilient (DI-1): a corrupt file is quarantined —
     * moved aside, never deleted — while the rest of the library loads.
     * Also silently migrates legacy id-named folders to sanitized-name folders.
     */
    fun loadAll(): LoadResult {
        if (!root.isDirectory) return LoadResult(emptyList(), emptyList())
        pathById.clear()

        val results = mutableListOf<LoadedList>()
        val quarantined = mutableListOf<QuarantinedFile>()
        walk(root, results, quarantined)
        return LoadResult(results, quarantined)
    }

    private fun walk(
        dir: File,
        results: MutableList<LoadedList>,
        quarantined: MutableList<QuarantinedFile>,
    ) {
        // Never descend into the quarantine bin.
        if (dir.name == ".quarantine") return

        val listFile = File(dir, ".list.yml")
        val isListFolder = dir != root && listFile.isFile

        if (!isListFolder) {
            walkSubdirsOnly(dir, results, quarantined)
            return
        }

        val list = try {
            readList(listFile)
        } catch (e: Exception) {
            // No valid list header: quarantine it, but still recurse into
            // subdirectories so nested lists aren't stranded.
            quarantine(listFile, e, quarantined)
            walkSubdirsOnly(dir, results, quarantined)
            return
        }

        // Migration: rename the folder when its basename doesn't match the
        // sanitized display name (the legacy layout used raw list ids).
        var effectiveDir = dir
        val desiredBase = sanitize(list.name)
        if (dir.name != desiredBase) {
            val parentDir = dir.parentFile
            if (parentDir != null) {
                var candidate = desiredBase
                var suffix = 2
                var target = File(parentDir, candidate)
                while (target.exists() && target != dir) {
                    candidate = "$desiredBase ($suffix)"
                    suffix += 1
                    target = File(parentDir, candidate)
                }
                // Best-effort: a failed rename keeps the old path rather than
                // failing the entire load.
                if (target != dir && dir.renameTo(target)) effectiveDir = target
            }
        }

        val entries = effectiveDir.listFiles()
        if (entries == null) {
            // PERSIST-1: header parsed but the folder can't be listed. Surface
            // the folder and keep the (itemless) list; don't abort the load.
            recordUnreadable(effectiveDir, quarantined)
            results.add(LoadedList(list, emptyList()))
            pathById[list.id] = effectiveDir
            return
        }

        // Skip `_`-prefixed aux files (AGENT-2); they are not items.
        val items = entries
            .filter { it.isFile && it.extension == "md" && !it.name.startsWith("_") }
            .mapNotNull { file ->
                try {
                    readItem(file)
                } catch (e: Exception) {
                    quarantine(file, e, quarantined)
                    null
                }
            }
        results.add(LoadedList(list, items))
        pathById[list.id] = effectiveDir

        entries.filter { it.isDirectory }.forEach { walk(it, results, quarantined) }
    }

    /** Recurse only into sub-directories — used at root, and when a folder's
     *  own `.list.yml` was quarantined but nested lists remain. */
    private fun walkSubdirsOnly(
        dir: File,
        results: MutableList<LoadedList>,
        quarantined: MutableList<QuarantinedFile>,
    ) {
        val entries = dir.listFiles()
        if (entries == null) {
            recordUnreadable(dir, quarantined)
            return
        }
        entries.filter { it.isDirectory }.forEach { walk(it, results, quarantined) }
    }

    /** Move a file that failed to parse into `<root>/.quarantine/`
     *  (best-effort; never overwrites a previously quarantined file). */
    private fun quarantine(file: File, error: Exception, acc: MutableList<QuarantinedFile>) {
        val qDir = File(root, ".quarantine")
        qDir.mkdirs()
        var dest = File(qDir, file.name)
        var n = 2
        while (dest.exists()) {
            val base = file.nameWithoutExtension
            val ext = file.extension
            dest = File(qDir, if (ext.isEmpty()) "$base ($n)" else "$base ($n).$ext")
            n += 1
        }
        val original = file.path
        file.renameTo(dest)
        acc.add(QuarantinedFile(original, error.toString()))
    }

    private fun recordUnreadable(dir: File, acc: MutableList<QuarantinedFile>) {
        acc.add(QuarantinedFile(dir.path, "Could not read directory"))
    }

    // MARK: - Helpers

    /** On-disk folder for a known list (loaded or written previously). */
    fun listDirectory(listId: String): File =
        pathById[listId] ?: throw StoreException("No on-disk folder mapped for list id $listId")

    private fun fileName(itemId: UUID): String = "${itemId.toString().uppercase()}.md"

    /** The item's file if present — canonical uppercase name first, with a
     *  lowercase fallback for hand-made files on case-sensitive filesystems. */
    private fun existingItemFile(dir: File, itemId: UUID): File? {
        val upper = File(dir, fileName(itemId))
        if (upper.exists()) return upper
        val lower = File(dir, "${itemId.toString().lowercase()}.md")
        return if (lower.exists()) lower else null
    }

    /** Desired on-disk dir from the parent chain + sanitized name, resolving
     *  folder-name collisions against siblings. */
    private fun resolveTargetDir(list: ItemList): File {
        val parentDir = list.parentId?.let { pathById[it] } ?: root
        val base = sanitize(list.name)
        val currentDir = pathById[list.id]

        var candidate = base
        var suffix = 2
        while (true) {
            val dir = File(parentDir, candidate)
            if (dir == currentDir) return dir
            if (!dir.exists()) return dir
            candidate = "$base ($suffix)"
            suffix += 1
        }
    }

    /** After a move, repoint descendants' `pathById` entries by re-walking
     *  the subtree and reading `.list.yml`s. */
    private fun refreshDescendantPaths(dir: File) {
        dir.walkTopDown()
            .filter { it.isDirectory && !it.name.startsWith(".") }
            .forEach { sub ->
                val listFile = File(sub, ".list.yml")
                if (listFile.isFile) {
                    try {
                        pathById[readList(listFile).id] = sub
                    } catch (_: Exception) {
                        // Unreadable header — loadAll will quarantine it later.
                    }
                }
            }
    }

    private fun atomicWrite(target: File, content: String) {
        val tmp = File(target.parentFile, target.name + ".tmp")
        tmp.writeText(content)
        try {
            Files.move(
                tmp.toPath(), target.toPath(),
                StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE,
            )
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(tmp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    companion object {
        /**
         * Sanitize a list's display name into a folder-safe component.
         * Strips filesystem-illegal chars, leading dots, trailing
         * whitespace/dots, clamps length. Empty result -> `Untitled`.
         * Identical to the iOS implementation.
         */
        fun sanitize(name: String): String {
            val illegal = setOf('/', '\\', ':', '*', '?', '"', '<', '>', '|', '\u0000')
            var s = buildString {
                for (ch in name) append(if (ch in illegal) '-' else ch)
            }
            s = s.dropWhile { it == '.' }
            while (s.isNotEmpty() && (s.last() == '.' || s.last().isWhitespace())) {
                s = s.dropLast(1)
            }
            s = s.trim()
            if (s.length > 80) s = s.take(80)
            return s.ifEmpty { "Untitled" }
        }
    }
}

