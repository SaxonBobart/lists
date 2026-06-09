package io.github.saxonbobart.lists.core.model

import java.time.Instant
import java.util.UUID

/**
 * A list — a container holding items, ported 1:1 from the iOS model. Lists
 * nest arbitrarily deep; `parentId == null` means the list lives at the
 * sidebar root. On disk this is the `.list.yml` inside the list's folder.
 */
data class ItemList(
    val id: String,
    val name: String,
    val icon: String,
    val color: ListColor,
    val defaultItemType: ItemType? = null,
    val groceryMode: Boolean = false,
    val createdAt: Instant,
    val modifiedAt: Instant,
    val position: Double,
    val parentId: String? = null,
    val deletedAt: Instant? = null,
    val lamport: Long = 0,
    /** Named sub-groups; items reference them by [ListSection.id]. */
    val sections: List<ListSection> = emptyList(),
) {
    enum class ListColor(val raw: String) {
        SAGE("sage"), BLUE("blue"), TEAL("teal"), GREEN("green"), AMBER("amber"),
        ORANGE("orange"), PINK("pink"), PURPLE("purple"), GREY("grey"),
        RED("red"), INDIGO("indigo"), BROWN("brown");

        companion object {
            fun fromRawOrNull(raw: String): ListColor? = entries.firstOrNull { it.raw == raw }
        }
    }

    companion object {
        const val INBOX_ID = "inbox"

        fun makeInbox(now: Instant = Instant.now()): ItemList = ItemList(
            id = INBOX_ID,
            name = "Inbox",
            icon = "tray.fill",
            color = ListColor.BLUE,
            defaultItemType = ItemType.TASK,
            createdAt = now,
            modifiedAt = now,
            position = 0.0,
        )
    }
}

/** A named section inside a user list. */
data class ListSection(
    val id: UUID = UUID.randomUUID(),
    val name: String,
    val position: Double,
)
