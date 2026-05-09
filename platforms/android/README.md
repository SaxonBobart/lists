# Android — Lists

Native Android client for the markdown-on-disk reminders app. Skeleton only.
Full reasoning behind every choice: [`research/android-stack.md`](../../research/android-stack.md).

## Stack

| Layer | Choice |
|---|---|
| Language | Kotlin 2.x |
| UI | Jetpack Compose + Material 3 (Compose BOM 2025.12+) |
| DI | Hilt |
| Async | Coroutines + StateFlow |
| Persistence (rebuildable cache) | Room 2.7+ |
| YAML | snakeyaml-engine-kmp |
| Markdown render | Markwon (wrapped in `AndroidView`) |
| File watching | `FileObserver` for app-private dir + `ContentObserver` for SAF dirs + WorkManager periodic rescan failsafe |
| Notifications | `NotificationCompat` + per-channel + runtime `POST_NOTIFICATIONS` grant |
| Urgent alarms (AlarmKit equivalent) | `AlarmManager.setAlarmClock` + full-screen-intent `Activity` + `USE_FULL_SCREEN_INTENT` permission |
| Build | Gradle 8.x with Kotlin DSL + version catalogs |
| Tests | JUnit 4 (instrumented) + JUnit 5 (unit) + Robolectric + Compose UI test + Turbine + MockK |
| Packaging | AAB → Play Store; APK → GitHub Releases + F-Droid (reproducible) |

## Bundle ID

`io.github.saxonbobart.lists` (matches the iOS bundle id so the markdown
on-disk format is exchangeable across platforms by file).

## Targets

- **`compileSdk` / `targetSdk`**: 35 (Android 15)
- **`minSdk`**: 31 (Android 12) — required for `setAlarmClock` exemption + Material You

## Storage layout

V1 ships with files under **app-private external storage**:

```
/Android/data/io.github.saxonbobart.lists/files/Lists/
├── 00000000000000000000INBOX0/
│   ├── .list.yml
│   └── <ulid>.md
└── …
```

This dodges the Play-review risk of `MANAGE_EXTERNAL_STORAGE` and keeps the
folder visible-but-isolated. v1.1 adds a Storage Access Framework folder
picker so users who want their `Lists/` in a Syncthing/Obsidian/Dropbox vault
can opt in.

## Build commands (once scaffolded)

```sh
# Debug build & install on a connected device
./gradlew :app:installDebug

# Run unit tests
./gradlew :app:testDebugUnitTest

# Run instrumented tests on connected device/emulator
./gradlew :app:connectedDebugAndroidTest

# Lint + Detekt + format checks
./gradlew check

# Release AAB (signed)
./gradlew :app:bundleRelease

# Release APK for F-Droid / GitHub Releases
./gradlew :app:assembleRelease
```

## First-tasks checklist (when building begins)

1. **Generate the Gradle wrapper** — `gradle wrapper --gradle-version 8.x` (run once on a machine with Gradle installed).
2. **Wire the `libs.versions.toml` version catalog** with the Compose BOM, M3, Hilt, Room, snakeyaml-engine-kmp, Markwon, Coroutines, JUnit5, Robolectric, Turbine, MockK.
3. **Port the iOS `FrontmatterCodec` + `YAMLCodec`** to Kotlin (`data/storage/FrontmatterCodec.kt`). Use the `shared/fixtures/` corpus as the parity test set.
4. **Define the Room schema** mirroring the YAML fields. Table names match `shared/cache/schema.sql`.
5. **Implement `FileStore`** as a coroutine-flowing `actor`-equivalent over `getExternalFilesDir(null)/Lists/`.
6. **Implement the cache rebuild walk** (cold-start: walk tree, stat each file, re-parse on mtime mismatch).
7. **Build the home grid + lists screen** in Compose with the Adwaita-equivalent Material 3 token map (the design folder has Android JSX mockups under `design/project/src-android/`).
8. **Wire `setAlarmClock` + a full-screen-intent activity** for urgent reminders. Test on Android 14 (the calling-and-alarm exemption took effect Jan 2025).
9. **Add the three notification channels** (`urgent_alarms`, `reminders_with_time`, `reminders_date_only`) at first launch.
10. **Set up `flatpak`-equivalent**: GitHub Releases workflow that emits a signed APK + AAB on tag push.

## Permissions (will go in `AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
<!-- intentionally NOT requesting MANAGE_EXTERNAL_STORAGE in v1 -->
```

## Status

**Not yet built.** This directory contains only structural placeholders so the
intended layout is reviewable. No buildable code lives here yet.

## See also

- [`research/android-stack.md`](../../research/android-stack.md) — full reasoning, alternatives, gotchas
- [`design/project/src-android/`](../../design/project/src-android/) — Material 3 wireframes (read-only reference)
- [`shared/`](../../shared/) — cross-platform format spec, fixtures, and lexicons
