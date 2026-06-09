import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlin.jvm)
}

// Emit Java 17 bytecode from whatever JDK is running the build (17+), rather
// than requiring a pinned 17 toolchain — headless CI images often ship a
// single newer JDK.
java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(libs.snakeyaml)

    testImplementation(libs.junit)
    testImplementation(kotlin("test"))
}
