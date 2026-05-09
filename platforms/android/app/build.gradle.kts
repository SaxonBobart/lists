// placeholder — see ../README.md
// App module config. Real plugin block, dependencies block, and android {} block
// will be filled in once the version catalog and signing config exist.

plugins {
    // alias(libs.plugins.android.application)
    // alias(libs.plugins.kotlin.android)
    // alias(libs.plugins.kotlin.compose)
    // alias(libs.plugins.hilt)
    // alias(libs.plugins.ksp)
}

android {
    namespace = "io.github.saxonbobart.lists"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.github.saxonbobart.lists"
        minSdk = 31
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0-dev"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    // Compose BOM and M3, Hilt, Room, snakeyaml-engine-kmp, Markwon, etc.
    // Wired through libs.versions.toml once the version catalog is created.
}
