package io.github.saxonbobart.lists

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.runtime.collectAsState
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import io.github.saxonbobart.lists.ui.ListsViewModel
import io.github.saxonbobart.lists.ui.deleted.RecentlyDeletedScreen
import io.github.saxonbobart.lists.ui.detail.ListDetailScreen
import io.github.saxonbobart.lists.ui.detail.SmartListScreen
import io.github.saxonbobart.lists.ui.editor.ItemEditorSheet
import io.github.saxonbobart.lists.ui.habit.HabitDetailScreen
import io.github.saxonbobart.lists.ui.home.HomeScreen
import io.github.saxonbobart.lists.ui.search.SearchScreen
import io.github.saxonbobart.lists.ui.tags.TagsScreen
import io.github.saxonbobart.lists.ui.theme.ListsTheme
import java.util.UUID

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            ListsTheme {
                ListsApp()
            }
        }
    }
}

@Composable
private fun ListsApp(viewModel: ListsViewModel = viewModel()) {
    val navController = rememberNavController()
    val library by viewModel.library.collectAsState()

    NavHost(navController = navController, startDestination = "home") {
        composable("home") {
            HomeScreen(
                viewModel = viewModel,
                onOpenList = { navController.navigate("list/${it.id}") },
                onOpenSmart = { navController.navigate("smart/${it.id}") },
                onOpenSearch = { navController.navigate("search") },
                onOpenTags = { navController.navigate("tags") },
                onOpenDeleted = { navController.navigate("deleted") },
            )
        }
        composable(
            "list/{listId}",
            arguments = listOf(navArgument("listId") { type = NavType.StringType }),
        ) { backStack ->
            ListDetailScreen(
                viewModel = viewModel,
                listId = backStack.arguments?.getString("listId").orEmpty(),
                onBack = { navController.popBackStack() },
                onOpenList = { navController.navigate("list/${it.id}") },
                onOpenHabit = { navController.navigate("habit/${it.id}") },
            )
        }
        composable(
            "smart/{smartId}",
            arguments = listOf(navArgument("smartId") { type = NavType.StringType }),
        ) { backStack ->
            SmartListScreen(
                viewModel = viewModel,
                smartId = backStack.arguments?.getString("smartId").orEmpty(),
                onBack = { navController.popBackStack() },
                onOpenHabit = { navController.navigate("habit/${it.id}") },
            )
        }
        composable(
            "habit/{itemId}",
            arguments = listOf(navArgument("itemId") { type = NavType.StringType }),
        ) { backStack ->
            HabitDetailScreen(
                viewModel = viewModel,
                itemId = backStack.arguments?.getString("itemId").orEmpty(),
                onBack = { navController.popBackStack() },
            )
        }
        composable("search") {
            SearchScreen(
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
                onOpenHabit = { navController.navigate("habit/${it.id}") },
            )
        }
        composable("tags") {
            TagsScreen(
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
                onOpenHabit = { navController.navigate("habit/${it.id}") },
            )
        }
        composable("deleted") {
            RecentlyDeletedScreen(
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
            )
        }
    }

    // One editor sheet for the whole app: any screen can request editing.
    val editingId: UUID? = viewModel.editingItemId
    val editingItem = editingId?.let { id -> library.item(id) }
    if (editingItem != null) {
        ItemEditorSheet(
            item = editingItem,
            library = library,
            viewModel = viewModel,
            onDismiss = { viewModel.edit(null) },
        )
    }
}
