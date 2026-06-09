package io.github.saxonbobart.lists.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.outlined.Notes
import androidx.compose.material.icons.filled.Alarm
import androidx.compose.material.icons.filled.AllInbox
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Tag
import androidx.compose.material.icons.filled.Today
import androidx.compose.material.icons.filled.Work
import androidx.compose.ui.graphics.vector.ImageVector
import io.github.saxonbobart.lists.core.query.SmartList

/**
 * The on-disk format stores iOS SF Symbol names (shared data!), so Android
 * maps the known ones onto Material symbols and falls back to a generic list.
 */
fun listIconFor(sfSymbolName: String): ImageVector = when (sfSymbolName) {
    "tray", "tray.fill" -> Icons.Filled.Inbox
    "briefcase.fill" -> Icons.Filled.Work
    "person.fill" -> Icons.Filled.Person
    "folder.fill" -> Icons.Filled.Folder
    "hammer.fill" -> Icons.Filled.Build
    "flag.fill" -> Icons.Filled.Flag
    "cart.fill" -> Icons.Filled.ShoppingCart
    "heart.fill" -> Icons.Filled.Favorite
    "book.fill" -> Icons.Filled.MenuBook
    "star.fill" -> Icons.Filled.Star
    "note.text", "doc.text" -> Icons.AutoMirrored.Outlined.Notes
    else -> Icons.AutoMirrored.Filled.List
}

/** Choices offered when creating a list on Android (stored as SF names). */
val listIconChoices = listOf(
    "tray.fill", "briefcase.fill", "person.fill", "folder.fill", "hammer.fill",
    "flag.fill", "cart.fill", "heart.fill", "book.fill", "star.fill",
)

fun smartListIcon(smart: SmartList): ImageVector = when (smart) {
    SmartList.TODAY -> Icons.Filled.Today
    SmartList.SCHEDULED -> Icons.Filled.CalendarMonth
    SmartList.ALL -> Icons.Filled.AllInbox
    SmartList.COMPLETED -> Icons.Filled.DoneAll
    SmartList.FLAGGED -> Icons.Filled.Flag
    SmartList.URGENT -> Icons.Filled.Alarm
    SmartList.TAGS -> Icons.Filled.Tag
    SmartList.ASSIGNED -> Icons.Filled.Person
}
