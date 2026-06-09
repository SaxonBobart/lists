package io.github.saxonbobart.lists.core.storage

import io.github.saxonbobart.lists.core.model.ItemList
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.core.model.ListSection

/**
 * ItemList <-> `.list.yml` mapping. Mirrors `ItemList` Codable on iOS:
 * same key names, field order, defaults, and strictness.
 */
internal object ListYaml {

    fun encode(list: ItemList): String {
        val b = StringBuilder()
        fun line(key: String, value: String) = b.append(key).append(": ").append(value).append('\n')

        line("id", Yamls.scalar(list.id))
        line("name", Yamls.scalar(list.name))
        line("icon", Yamls.scalar(list.icon))
        line("color", list.color.raw)
        list.defaultItemType?.let { line("default_item_type", it.raw) }
        if (list.groceryMode) line("grocery_mode", "true")
        line("created_at", Yamls.date(list.createdAt))
        line("modified_at", Yamls.date(list.modifiedAt))
        line("position", list.position.toString())
        list.parentId?.let { line("parent_id", Yamls.scalar(it)) }
        list.deletedAt?.let { line("deleted_at", Yamls.date(it)) }
        line("lamport", list.lamport.toString())
        if (list.sections.isNotEmpty()) {
            b.append("sections:\n")
            for (s in list.sections) {
                b.append("- id: ").append(Yamls.uuid(s.id)).append('\n')
                b.append("  name: ").append(Yamls.scalar(s.name)).append('\n')
                b.append("  position: ").append(s.position).append('\n')
            }
        }
        return b.toString()
    }

    fun decode(yaml: String): ItemList {
        val map = Yamls.load(yaml)
        return ItemList(
            id = Yamls.requireString(map, "id"),
            name = Yamls.requireString(map, "name"),
            icon = Yamls.optString(map, "icon") ?: "tray",
            color = Yamls.optString(map, "color")?.let {
                ItemList.ListColor.fromRawOrNull(it)
                    ?: throw YamlCodecException("Unknown list color '$it'")
            } ?: ItemList.ListColor.GREY,
            // Item.ItemType decodes permissively on iOS (unknown -> task);
            // the same applies when it appears as a list's default type.
            defaultItemType = Yamls.optString(map, "default_item_type")?.let { ItemType.fromRaw(it) },
            groceryMode = Yamls.optBool(map, "grocery_mode", false),
            createdAt = Yamls.requireInstant(map, "created_at"),
            modifiedAt = Yamls.requireInstant(map, "modified_at"),
            position = Yamls.optDouble(map, "position", 0.0),
            parentId = Yamls.optString(map, "parent_id"),
            deletedAt = Yamls.optInstant(map, "deleted_at"),
            lamport = Yamls.optLong(map, "lamport", 0),
            sections = decodeSections(map),
        )
    }

    private fun decodeSections(map: Map<*, *>): List<ListSection> {
        val v = map["sections"] ?: return emptyList()
        val list = v as? List<*> ?: throw YamlCodecException("'sections' is not a list")
        return list.map { el ->
            val m = el as? Map<*, *> ?: throw YamlCodecException("Section is not a mapping")
            ListSection(
                id = Yamls.uuidOrThrow(Yamls.requireString(m, "id"), "sections.id"),
                name = Yamls.requireString(m, "name"),
                position = Yamls.doubleOf(m["position"])
                    ?: throw YamlCodecException("sections.position missing or not a number"),
            )
        }
    }
}
