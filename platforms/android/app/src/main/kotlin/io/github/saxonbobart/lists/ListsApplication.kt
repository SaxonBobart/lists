package io.github.saxonbobart.lists

import android.app.Application
import io.github.saxonbobart.lists.data.ListsRepository
import java.io.File

class ListsApplication : Application() {

    lateinit var repository: ListsRepository
        private set

    override fun onCreate() {
        super.onCreate()
        // Same shape as iOS: an app-private `Lists/` library of folders,
        // .list.yml headers, and one markdown file per item.
        repository = ListsRepository(File(filesDir, "Lists"))
    }
}
