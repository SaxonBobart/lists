package io.github.saxonbobart.lists.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

/**
 * Material 3 Expressive theme with Material You dynamic color.
 *
 * This file is part of the deliberately small alpha-API surface (see
 * platforms/android/README.md): `MaterialExpressiveTheme` + `MotionScheme`
 * are on the material3 1.5.0-alpha track. If a future alpha breaks the
 * signature, swap `MaterialExpressiveTheme(...)` for `MaterialTheme(...)`
 * minus `motionScheme` and everything else keeps compiling.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun ListsTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val colorScheme = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        darkTheme -> darkColorScheme(primary = Color(0xFFB6C4FF))
        else -> lightColorScheme(primary = Color(0xFF3D5AFE))
    }
    MaterialExpressiveTheme(
        colorScheme = colorScheme,
        motionScheme = MotionScheme.expressive(),
        content = content,
    )
}
