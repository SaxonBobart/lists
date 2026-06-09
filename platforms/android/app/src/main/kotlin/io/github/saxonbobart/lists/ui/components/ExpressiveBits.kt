package io.github.saxonbobart.lists.ui.components

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularWavyProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FloatingActionButtonMenu
import androidx.compose.material3.FloatingActionButtonMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.ToggleFloatingActionButton
import androidx.compose.material3.ToggleFloatingActionButtonDefaults.animateIcon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/**
 * Every Material 3 Expressive *alpha* component the app uses lives in this
 * one file (plus MaterialExpressiveTheme in Theme.kt), so an alpha API change
 * is a one-file fix. Stable fallbacks, if ever needed:
 *  - FloatingActionButtonMenu  -> FloatingActionButton + DropdownMenu
 *  - *WavyProgressIndicator    -> the non-wavy equivalents
 *  - LoadingIndicator          -> CircularProgressIndicator
 */

/** A FAB that morphs open into a menu of "new thing" actions. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun AddFabMenu(
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    entries: List<Pair<String, ImageVector>>,
    onEntry: (Int) -> Unit,
) {
    FloatingActionButtonMenu(
        expanded = expanded,
        button = {
            ToggleFloatingActionButton(
                checked = expanded,
                onCheckedChange = onExpandedChange,
            ) {
                val icon = if (expanded) Icons.Filled.Close else Icons.Filled.Add
                Icon(
                    painter = rememberVectorPainter(icon),
                    contentDescription = if (expanded) "Close" else "Add",
                    modifier = Modifier.animateIcon({ checkedProgress }),
                )
            }
        },
    ) {
        entries.forEachIndexed { index, (label, icon) ->
            FloatingActionButtonMenuItem(
                onClick = {
                    onExpandedChange(false)
                    onEntry(index)
                },
                icon = { Icon(icon, contentDescription = null) },
                text = { Text(label) },
            )
        }
    }
}

/**
 * The habit row control: a springy wavy ring while in progress, a filled
 * check at goal — Android's read of the iOS "compact progress ring".
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun HabitRing(
    progress: Float,
    complete: Boolean,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .size(32.dp)
            .semantics { contentDescription = "Habit progress" }
            .animateContentSize(),
        contentAlignment = Alignment.Center,
    ) {
        if (complete) {
            Icon(
                Icons.Filled.Check,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
        } else {
            CircularWavyProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

/** Cycle progress bar on the habit detail screen. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun CycleProgressBar(progress: Float, modifier: Modifier = Modifier) {
    LinearWavyProgressIndicator(progress = { progress }, modifier = modifier)
}

/** First-load spinner (shape-morphing M3E loading indicator). */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun ListsLoadingIndicator(modifier: Modifier = Modifier) {
    LoadingIndicator(modifier = modifier)
}
