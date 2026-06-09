pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
    }
}

rootProject.name = "lists-android"

include(":core")

// The :app module needs the Android SDK and Google's Maven repository.
// Headless/CI environments without an SDK can still build and test :core
// (the entire data layer is pure JVM Kotlin).
val localProps = file("local.properties")
val hasSdkDir = localProps.exists() && localProps.readLines().any { it.trim().startsWith("sdk.dir") }
val hasAndroidSdk = hasSdkDir || System.getenv("ANDROID_HOME") != null || System.getenv("ANDROID_SDK_ROOT") != null
if (hasAndroidSdk) {
    include(":app")
} else {
    logger.lifecycle("Android SDK not found - skipping :app (only :core is configured).")
}
