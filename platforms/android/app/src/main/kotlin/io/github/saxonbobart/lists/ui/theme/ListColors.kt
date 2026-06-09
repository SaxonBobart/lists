package io.github.saxonbobart.lists.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.graphics.Color
import io.github.saxonbobart.lists.core.model.ItemList.ListColor

/** Accent colors for user lists, tuned per light/dark like the iOS palette. */
@Composable
fun ListColor.accent(): Color = accent(isSystemInDarkTheme())

fun ListColor.accent(dark: Boolean): Color = when (this) {
    ListColor.SAGE -> if (dark) Color(0xFFA9C2A0) else Color(0xFF7C9473)
    ListColor.BLUE -> if (dark) Color(0xFF8AB4F8) else Color(0xFF3B82F6)
    ListColor.TEAL -> if (dark) Color(0xFF6EE7DA) else Color(0xFF0D9488)
    ListColor.GREEN -> if (dark) Color(0xFF86EFAC) else Color(0xFF16A34A)
    ListColor.AMBER -> if (dark) Color(0xFFFCD34D) else Color(0xFFD97706)
    ListColor.ORANGE -> if (dark) Color(0xFFFDBA74) else Color(0xFFEA580C)
    ListColor.PINK -> if (dark) Color(0xFFF9A8D4) else Color(0xFFDB2777)
    ListColor.PURPLE -> if (dark) Color(0xFFC4B5FD) else Color(0xFF7C3AED)
    ListColor.GREY -> if (dark) Color(0xFFB0B7C3) else Color(0xFF6B7280)
    ListColor.RED -> if (dark) Color(0xFFFCA5A5) else Color(0xFFDC2626)
    ListColor.INDIGO -> if (dark) Color(0xFFA5B4FC) else Color(0xFF4F46E5)
    ListColor.BROWN -> if (dark) Color(0xFFD6BCA6) else Color(0xFF92642E)
}
