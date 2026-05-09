# Android Stack Research — Lists

_Phase 2 platform research. Snapshot: 2026-05-03. Companion to `research/00-current-state.md`._

## 1. TL;DR

Build the Android client as a **single-platform Android app** in **Kotlin + Jetpack Compose with Material 3**, targeting **Android 14 (API 34) min / API 35 target**. Persist files to **app-private external storage** (`getExternalFilesDir()/Lists/`) for v1, with a **Storage Access Framework folder picker** as the v1.1 path for users who want their `Lists/` folder visible in any file manager or synced via Syncthing/Dropbox. Cache the file tree in **Room (KMP-ready)**, parse YAML with **snakeyaml-engine-kmp**, render markdown with **Markwon wrapped in `AndroidView`**, and schedule alerts with **AlarmManager.setAlarmClock + USE_FULL_SCREEN_INTENT** for the urgent/AlarmKit equivalent. **No shared Rust core in v1** — pure Kotlin is cheaper for a solo dev given the small surface area, but reserve a `shared/spec/` JSON-Schema + fixtures suite to keep parsers honest across iOS, Android, Windows, Linux.

## 2. Recommendation

| Concern | Choice | License | Why |
|---|---|---|---|
| Language | **Kotlin 2.x** (Swift 6 equivalent) | Apache-2.0 | Default for new Android. Strict null-safety, coroutines, Compose. |
| UI framework | **Jetpack Compose + Material 3 1.4+** | Apache-2.0 | Stable; the `Compose December '25` BOM (Compose 1.10 / M3 1.4) finally matches old `View`-system scroll perf via Pausable Composition. ([Android Devs](https://developer.android.com/blog/posts/whats-new-in-the-jetpack-compose-december-release)) |
| DI | **Hilt** (Dagger-based) | Apache-2.0 | Compile-time graph + first-party Jetpack integration. For a solo dev the boilerplate is paid once and never thought about again; runtime errors that Koin pushes to startup are caught at build. |
| State management | **Compose state holders + Kotlin Coroutines + StateFlow** | Apache-2.0 | Built into Compose; no extra lib. No Rx, no MVI framework. |
| Persistence (cache) | **Room 2.7+ (KMP-capable)** | Apache-2.0 | Schema is a flat denormalised mirror of YAML fields; Room's annotation-driven `@Dao` + Flow integration is faster to write than SQLDelight's `.sq` files for a solo dev. KMP support means we can share schema with a future macOS/Windows/Linux build later. ([Room KMP](https://developer.android.com/kotlin/multiplatform/room)) |
| YAML | **snakeyaml-engine-kmp 2.x** | Apache-2.0 | Active KMP fork of `snakeyaml-engine`. Stable on Android, deterministic emit order (matches iOS Yams behaviour). Avoid kaml — it's archived. ([kaml is archived](https://github.com/charleskorn/kaml)) |
| Markdown render | **Markwon 4.x** wrapped in `AndroidView` | Apache-2.0 | Mature, no WebView, supports the SPEC §11 subset out of the box. Compose-native libs are immature; wrapping Markwon costs ~10 LOC. ([Markwon](https://github.com/noties/Markwon)) |
| File watching | **`FileObserver(File, mask)`** for app-private dir; **`ContentResolver.registerContentObserver(treeUri, true, observer)`** for SAF-picked dirs; **WorkManager periodic rescan** as failsafe | Apache-2.0 | See §7 — Android has no clean cross-API watcher; layer the three. |
| Notifications | **NotificationCompat + per-channel + POST_NOTIFICATIONS runtime grant** | Apache-2.0 | Standard. Channel created lazily on first schedule. |
| Alarms (urgent) | **`AlarmManager.setAlarmClock` + full-screen-intent `Activity` + `USE_FULL_SCREEN_INTENT` permission** | Apache-2.0 | Closest Android primitive to AlarmKit. Bypasses Doze, surfaces over lockscreen. ([Schedule alarms](https://developer.android.com/develop/background-work/services/alarms)) |
| Build tool | **Gradle 8.x with Kotlin DSL (`build.gradle.kts`)** + version catalogs | Apache-2.0 | F-Droid prefers Gradle; Kotlin DSL gives type-safe build logic and is what new templates ship. |
| Testing | **JUnit 4 (instrumented) + JUnit 5 (unit) + Robolectric + Compose UI test + Turbine + MockK** | Apache-2.0 / MIT | See §10. Thin stack, all maintained. |
| Packaging | **AAB → Play Store**, **APK → GitHub Releases + F-Droid** (reproducible build), Android App Bundle for Play, universal APK for sideload | n/a | Tri-channel ship: Play (paid-friendly later), F-Droid (FOSS distribution), GitHub Releases (early-access). |

## 3. Alternatives considered

### UI: Compose vs XML Views vs Compose Multiplatform

| Option | Pro | Con | License | Verdict |
|---|---|---|---|---|
| **Jetpack Compose + M3** ✅ | Modern, fast iteration, future-proof, M3 1.4 ships Sept 2025 with mature primitives. Pausable Composition (Compose 1.10) closes the perf gap to Views. | New paradigm if you've only worked in XML; some legacy widgets need `AndroidView` (Markwon, the markdown editor view). | Apache-2.0 | **Picked.** SPEC §4 mandates "Material 3"; Compose is Google's front of house for it. |
| XML Views + Material Components | Stable, infinite Stack Overflow, every library binds cleanly. | New code in XML feels archaic; ViewBinding is ceremony; testing UI is harder. | Apache-2.0 | Skip. |
| Compose Multiplatform (KMP) | Reuse one Compose codebase across Android, iOS, Desktop; Material 3 built-in; ships ~96% UI sharing for some teams. ([JetBrains 1.8 announcement](https://blog.jetbrains.com/kotlin/2025/05/compose-multiplatform-1-8-0-released-compose-multiplatform-for-ios-is-stable-and-production-ready/)) | iOS reference impl is already pure SwiftUI on iOS 26+ AlarmKit; throwing it away for CMP costs ~50% of v1 iOS work. Accessibility on iOS-CMP is "improving but not at parity with native SwiftUI" ([2025 status](https://www.kmpship.app/blog/compose-multiplatform-ios-stable-2025)). SPEC §4 _explicitly_ asks for "Apple Reminders, replicated using stock SwiftUI". | Apache-2.0 | Skip for v1. Reconsider if/when a Desktop-Linux build needs to share UI with Android — but Linux research has its own GTK/Qt verdict. |

### Persistence: Room vs SQLDelight vs raw `androidx.sqlite`

| Option | Pro | Con | Verdict |
|---|---|---|---|
| **Room 2.7+ (KMP)** ✅ | Annotation-driven, `Flow<List<X>>` returns trigger Compose recomposition for free, integrated with Jetpack, KMP since 2.7. ([Room KMP](https://developer.android.com/kotlin/multiplatform/room)) | Compile-time codegen via KSP adds ~3s to clean build. | **Picked.** Solo-dev productivity wins. |
| SQLDelight | SQL-as-source-of-truth; type-safe queries from `.sq` files; first-class KMP since day one. ([Comparison](https://docs.bswen.com/blog/2026-03-14-room-vs-sqldelight-kmp/)) | Two query styles to maintain (the cache writer in Kotlin + the `.sq` files); less Compose ergonomics. | Skip. Better fit for SQL-first teams. |
| Raw `androidx.sqlite` + hand-rolled DAO | Zero codegen; small dep footprint. | Manual cursor handling, manual migrations, manual everything. | Skip — the cache schema has 8+ tables (lists, reminders, tags, completion_history, recurrences, location_triggers); Room saves weeks. |

### YAML: snakeyaml-engine-kmp vs kaml vs hand-roll

| Option | License | Pro | Con | Verdict |
|---|---|---|---|---|
| **snakeyaml-engine-kmp** ✅ | Apache-2.0 | Active fork of the de facto JVM YAML parser. KMP-ready. Deterministic block emit (matches iOS Yams `sortKeys = false`). | Lower-level API than kaml. | **Picked.** |
| kaml | Apache-2.0 | kotlinx.serialization integration → `@Serializable data class`. | **Archived** — original maintainer stopped Aug 2025. ([kaml repo](https://github.com/charleskorn/kaml)) Still functional, but no upstream fixes. | Skip. |
| Hand-rolled YAML 1.2 subset parser | n/a | Zero dep. | YAML's whitespace-sensitive grammar is a minefield (block scalars, folded strings, anchor refs). Months of edge-case bugs. | Skip. |

### Markdown rendering: Markwon vs Compose-Markdown vs CommonMark-Java vs multiplatform-markdown-renderer

| Option | License | Pro | Con | Verdict |
|---|---|---|---|---|
| **Markwon (Android Views, in `AndroidView{}`)** ✅ | Apache-2.0 | Mature, no WebView, native `Spannable` rendering, matches SPEC §11 subset (tables, task-list checkboxes, code blocks, inline images via plugin), live-formatting editor support via `MarkdownEditText`. ([Markwon](https://github.com/noties/Markwon)) | Not Compose-native — wrap in `AndroidView`. | **Picked.** |
| compose-markdown (`jeziellago/compose-markdown`) | Apache-2.0 | Compose-native API. ([compose-markdown](https://github.com/jeziellago/compose-markdown)) | Internally wraps Markwon already; thin convenience layer, fewer plugin hooks. | Acceptable as a thin wrapper; same dep underneath. |
| multiplatform-markdown-renderer (mikepenz) | Apache-2.0 | KMP — would let us share rendering with Compose Multiplatform if we ever take that path. | Smaller community; less battle-tested for rich tables/images. | Hold for KMP scenarios only. |
| CommonMark-Java (parser only) + custom Compose renderer | BSD-2-Clause | Full control over render. | Reinventing Markwon's `Plugin` ecosystem; weeks of work. | Skip. |
| MarkdownTwain (editor-focused) | Apache-2.0 | Compose UI editor for markdown, syntax-highlight while typing. ([MarkdownTwain](https://github.com/colintheshots/MarkdownTwain)) | Maintained by ex-Meetup; archived under `meetuparchive/`. Forks active but no first-party releases. | Use as reference; vendor the editor view if needed. |

All Apache-2.0, all AGPL-compatible (Apache-2.0 → AGPL-3.0 is one-way compatible per FSF).

### Alarms: AlarmManager vs WorkManager vs AlarmManager.setAlarmClock

| Option | Use case | Verdict for Lists |
|---|---|---|
| **`setAlarmClock(AlarmClockInfo, PendingIntent)`** ✅ | Treated by the system as a user-visible alarm; bypasses Doze; surfaces in the system "Next alarm" UI; **automatically grants the equivalent of exact-alarm permission** under the Android 14 calling-and-alarm exemption. ([setAlarmClock](https://developer.android.com/reference/android/app/AlarmManager#setAlarmClock(android.app.AlarmManager.AlarmClockInfo,%20android.app.PendingIntent))) | **Picked.** AlarmKit-equivalent. |
| `setExactAndAllowWhileIdle` | Exact firing while in Doze, but requires `SCHEDULE_EXACT_ALARM` (denied by default since Android 14). ([Android 14 change](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms)) | Use only as a fallback if `setAlarmClock` quota is hit. |
| `WorkManager` `OneTimeWorkRequest` with initial delay | Battery-friendly; deferred execution under Doze. | Use for non-urgent date-only reminders ("Today at 09:00") where ±10min slop is fine. |
| `WorkManager` periodic worker | Background polling. | Use for the file-watcher rescan failsafe (§7). |

## 4. Why the recommendation wins (local-first, markdown+SQLite, solo, AGPL)

1. **Local-first.** Every chosen library works fully offline; nothing in the stack assumes a network. Room, snakeyaml-engine-kmp, Markwon, AlarmManager all run in-process.
2. **Markdown + SQLite contract preserved.** Files stay the source of truth (per SPEC §7); Room is just a rebuildable cache. The cache schema mirrors YAML fields one-to-one; on cold start, walk `Lists/`, `stat()` each `.md`, re-parse on `mtime` mismatch. Same algorithm as iOS — different language.
3. **Solo-dev maintenance.** Every dep is Apache-2.0 (zero license friction with AGPL — Apache-2.0 is one-way GPL/AGPL compatible per [FSF table](https://www.gnu.org/licenses/license-list.html#apache2)) and has either Google or a >5-yr OSS maintainer behind it. Replacing any single dep is a weekend, not a quarter.
4. **AGPL compatibility.** AGPL-3.0 forbids combining with GPL-incompatible code in the same binary. All chosen libraries are Apache-2.0, BSD, or MIT — all GPL-compatible. The AlarmKit-equivalent path uses Android framework APIs (no extra dep). The Compose / AndroidX libraries are Apache-2.0 too.
5. **Schema is forward-compatible with sync.** `lamport`, `deleted_at`, `modified` are first-class columns in the Room schema; the day a sync transport is added, only the diff/merge logic is new code.

## 5. Notification + alarm mapping (AlarmKit equivalent on Android)

iOS routes `urgent && has_time` reminders to AlarmKit, everything else dated to UNUserNotificationCenter (SPEC §14). Android equivalent:

| iOS state | iOS API | Android equivalent |
|---|---|---|
| `urgent && has_time` | `AlarmManager.AlarmConfiguration<...>` (AlarmKit) | `AlarmManager.setAlarmClock(AlarmClockInfo(triggerAtMillis, showIntent), pendingIntent)` + a high-importance notification with `setFullScreenIntent(Intent, true)` that launches a full-screen `Activity` rendering "snooze / stop" buttons. The `USE_FULL_SCREEN_INTENT` permission (manifest) plus the system's calling-and-alarm exemption (since Jan 22 2025) means the app needs no extra grant flow. ([USE_FULL_SCREEN_INTENT](https://developer.android.com/reference/android/Manifest.permission#USE_FULL_SCREEN_INTENT), [Play policy](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en)) |
| `!urgent && date+time` | `UNCalendarNotificationTrigger` | `AlarmManager.setExactAndAllowWhileIdle(RTC_WAKEUP, …, pendingIntent)` that posts a normal-importance notification on fire. If `SCHEDULE_EXACT_ALARM` denied, downgrade to `set()` (best-effort, can slip ±15min). |
| `!urgent && date only` | calendar trigger at default time | `WorkManager.OneTimeWorkRequest` scheduled for the user's default-time-of-day on the date; no exact-alarm needed. |
| `urgent && !has_time` | rejected at edit time | Same — UI disables the urgent toggle when no time is set (matches SPEC §14). |

### Permissions to declare in `AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" /> <!-- runtime grant on Android 13+ -->
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" /> <!-- granted by default to alarm apps since Jan 2025 -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" /> <!-- denied by default Android 14+; only need if not using setAlarmClock -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" /> <!-- re-arm alarms on reboot -->
<uses-permission android:name="android.permission.WAKE_LOCK" /> <!-- needed by AlarmManager wakeup -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" /> <!-- for full-screen alarm activity -->
```

The full-screen alarm `Activity` must opt into showing over the lockscreen via `setShowWhenLocked(true)` and `setTurnScreenOn(true)`, plus `setFullScreenIntent` on the notification.

### Notification channels (mandatory since Android 8)

Create three channels at first launch (SPEC §15 has one category; Android needs separate channels because the user controls importance per-channel):

- `urgent_alarms` — `IMPORTANCE_HIGH`, sound = system alarm tone, bypass DND.
- `reminders_with_time` — `IMPORTANCE_DEFAULT`, default sound.
- `reminders_date_only` — `IMPORTANCE_LOW`, no sound (silent banner).

`POST_NOTIFICATIONS` runtime permission requested at first attempt to schedule (mirrors iOS pattern in SPEC §15). ([POST_NOTIFICATIONS docs](https://developer.android.com/develop/ui/views/notifications/notification-permission))

## 6. Storage layout — where does `Lists/` live?

This is the single hardest call on Android. Three options, ordered by privacy:

### Option A — App-private external storage ✅ (v1 default)

`getExternalFilesDir(null)` → `/storage/emulated/0/Android/data/io.github.saxonbobart.lists/files/Lists/`

| Pro | Con |
|---|---|
| **No permission dialog at all.** Android grants the app's own external dir freely. | **Invisible in any modern file manager** unless the user enables hidden files and digs into `Android/data/`. Effectively private. |
| Survives app updates. | **Wiped on uninstall.** User loses files unless they exported first. |
| Compatible with **any Android 4.4+** without scoped-storage gymnastics. | No third-party sync (Syncthing, Dropbox) can see the folder. |
| Backed up by Android Auto-Backup if user enabled it. | Auto-Backup quota is 25MB/app; large habit histories blow past this. |

### Option B — User-picked SAF folder (v1.1)

User picks a directory once via `ACTION_OPEN_DOCUMENT_TREE`, app stores the persistable URI grant, all I/O goes through `DocumentFile` / `DocumentsContract`.

| Pro | Con |
|---|---|
| **Folder is wherever the user wants it** — Documents, Downloads, a cloud-sync folder, an SD card. | I/O is **slower** than direct file APIs (every read is a content-provider RPC). |
| **Visible in Files app, syncable by Syncthing/Dropbox/Drive.** | **No `FileObserver`** — must poll or use the limited `ContentResolver.registerContentObserver(treeUri, true, observer)` (which fires only for changes made through SAF, not external writes). ([SAF docs](https://developer.android.com/training/data-storage/shared/documents-files)) |
| Survives uninstall (if user puts it outside `Android/data`). | **No mtime in `DocumentsContract.Document.COLUMN_LAST_MODIFIED` guarantees** — provider can return 0. Index-rebuild heuristics need a fallback. |
| No `MANAGE_EXTERNAL_STORAGE` needed; **passes Play Store review.** | Re-grant needed if URI is invalidated (rare but possible). |

### Option C — `MANAGE_EXTERNAL_STORAGE` ❌

Old-style write-everywhere root access. Granted via `Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`.

| Pro | Con |
|---|---|
| Plain `File` APIs work everywhere. | **Play Store rejects** apps requesting this permission unless they're explicitly file-management / backup tools. ([Play policy](https://support.google.com/googleplay/android-developer/answer/10467955?hl=en)) A reminders app does not qualify. |
| No SAF complexity. | F-Droid users will accept it; Play users won't see the app at all. |

### Recommendation

**Ship A in v1.** The storage contract is simple, no permission dialogs, no Play Store risk. Pair it with a **prominent Settings → "Export Lists folder…"** action that copies the tree into a SAF-picked destination (one-shot). This addresses the data-portability concern without taking on SAF's I/O tax for every read.

**Add B in v1.1** as opt-in: Settings → "Use a custom folder…" → SAF picker → app migrates the tree and switches the storage backend. This unlocks Syncthing/Dropbox/Drive/Obsidian-vault use cases without forcing them on day-one users.

**Never ship C.** The Play review risk is asymmetric — gain a slightly nicer file API, lose the entire Play distribution channel.

### API-level differences (gotchas)

- **Android 11+** (API 30): All apps targeting API 30+ are forced into scoped storage; `requestLegacyExternalStorage` is honoured only on API 29. ([Storage updates Android 11](https://developer.android.com/about/versions/11/privacy/storage))
- **Android 11+** also blocks reading other apps' `Android/data/<pkg>/` dirs from any FileProvider that isn't the owning app, so iCloud-Drive-style "Files app shows our folder under Reminders" requires us to ship a `DocumentsProvider`. v1.1 work, not v1.
- **Android 12L (API 32)** introduced the storage permissions split (`READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`); irrelevant for `.md` files but worth knowing.
- **Android 13** (API 33): notification runtime permission. **Android 14** (API 34): exact-alarm denied by default; full-screen-intent restricted to alarm/calling apps.

## 7. File watching — is it possible?

Brutally honest: **Android's file-watching story is broken for our use case** if we go SAF (Option B). It's adequate for app-private (Option A).

### Option A (app-private external)

Use `android.os.FileObserver(File, mask)` (the API 29+ constructor; the `String` ctor is deprecated, the `File` overload is current). ([FileObserver](https://developer.android.com/reference/android/os/FileObserver))

```kotlin
class ListsObserver(root: File) : FileObserver(root, CREATE or DELETE or MODIFY or MOVED_TO or MOVED_FROM) {
    override fun onEvent(event: Int, path: String?) { /* enqueue rescan of `path` */ }
}
```

**Caveats:**
- `FileObserver` does not recurse into subdirectories. Need a per-list-folder observer; spawn one when a new list folder appears, kill it when it disappears.
- The instance must be referenced by a live object (it's GC-collectable).
- `inotify` watch limits (`fs.inotify.max_user_watches`) are platform-set; for a few hundred list folders we are nowhere near.
- Events fire on whatever process touched the file; ours included. Need to ignore self-writes (track an in-flight write set).

### Option B (SAF-picked tree)

`FileObserver` won't work — we don't have direct paths. Options, all imperfect:

1. **`ContentResolver.registerContentObserver(treeUri, /*notifyForDescendants=*/true, observer)`** — fires when the documents provider notifies. But: only providers that call `ContentResolver.notifyChange()` after writes trigger it. The system DocumentsProvider for primary external **does** call this; third-party providers (cloud, Syncthing) **may not**.
2. **`WorkManager` periodic rescan** every N minutes (15 min minimum for periodic work). Compares `COLUMN_LAST_MODIFIED` per file; rescans changed/new/missing. Acceptable but has a worst-case 15min lag.
3. **`OnResume` rescan** — every time the user opens the app, walk the tree. Cheap (just `stat`-ish via `DocumentsContract.queryChildDocuments`), catches any edits made while the app was backgrounded.

**Recommended layering** (works for both A and B):
- **A:** `FileObserver` per list folder (fast-path) + `WorkManager` periodic 30-min rescan (failsafe).
- **B:** `ContentObserver(treeUri, notifyForDescendants=true)` + `WorkManager` periodic 15-min rescan + `onResume` rescan.

iOS uses `DispatchSource` over `kqueue` for the same role and has the same kind of caveats; Android is just lossier in scoped-storage land.

## 8. Shared Rust core — verdict

**No shared Rust core in v1.** Recommendation matches the iOS doc.

### Why pure Kotlin wins for Android

- The shared logic is **a YAML parser + an RRULE expander + a ULID generator + a cache-write algorithm + a markdown subset renderer**. The first three are commodity libraries on every platform (snakeyaml-engine-kmp, custom rrule parser <500 LOC, in-house ULID <50 LOC). The cache-write algorithm is dialect-specific to each SQLite binding anyway. The markdown renderer is per-platform regardless because each OS has its own native rendering layer.
- A Rust core via UniFFI ([mozilla/uniffi-rs](https://github.com/mozilla/uniffi-rs)) on Android adds: cargo-ndk in CI, NDK toolchain, JNI marshalling overhead, and ~3-5 MB of native lib per ABI (× armeabi-v7a / arm64-v8a / x86_64 = ~12 MB). For five small algorithms this is bad ROI.
- A solo dev who is not already deep in Rust pays a learning + tooling tax that beats any DRY win on these surfaces.

### What _is_ shared, in lieu of code

A **`shared/spec/`** directory containing:
- `reminder.schema.json` — JSON Schema for the YAML frontmatter; every platform validates against it.
- `list.schema.json` — same for `.list.yml`.
- `rrule-subset.md` — exact subset definition.
- `fixtures/` — golden files (input `.md` → expected parsed JSON) every platform must round-trip identically.
- `lexicons/shopping.en.json` — the bundled grocery taxonomy (SPEC §13).

This is what keeps the iOS / Android / Windows / Linux parsers in lockstep without code-sharing infrastructure.

### When to revisit Rust

If a post-v1 sync layer (CRDT diff/merge per SPEC §16) is introduced, that algorithm is genuinely complex and benefits from being written once. A Rust crate exposed via UniFFI for the merge-only layer would be a good 2027 project; v1 ships without it.

## 9. Build / packaging

### Build

- **Gradle 8.x** with **Kotlin DSL** (`build.gradle.kts`, `settings.gradle.kts`).
- **Version catalogs** (`gradle/libs.versions.toml`) — single source of truth for dep versions across modules.
- Modules: `:app` (UI), `:core:domain` (models), `:core:storage` (file + Room), `:core:rrule`, `:feature:capture`, `:feature:list`, `:feature:detail`, `:feature:smartlists`. Same shape as iOS `Projects/Features/`.
- KSP for Hilt + Room codegen.
- R8 enabled in release; ProGuard rules for Markwon + snakeyaml.

### Packaging — three channels

| Channel | Format | Signing | Build |
|---|---|---|---|
| **Google Play** | AAB (Android App Bundle) | Play App Signing (Google holds upload key) | CI tag → `./gradlew bundleRelease` → upload. Target API 35 (mandatory for new submissions in 2025). ([Play target API](https://developer.android.com/google/play/requirements/target-sdk)) |
| **F-Droid** | APK, built on F-Droid's build server | F-Droid signs (initial submission), then we can opt into reproducible-builds + dev-signing where they verify our APK matches theirs. ([F-Droid Reproducible Builds](https://f-droid.org/docs/Reproducible_Builds/)) | Submit a `metadata/io.github.saxonbobart.lists.yml` to `fdroiddata`; F-Droid pulls our git tag and runs `./gradlew assembleRelease`. **No Google services**, no Firebase, no closed-source deps — every choice in §2 satisfies this. |
| **GitHub Releases** | Universal APK, our keystore | Self-signed; signature stable across releases (otherwise users can't update). | CI tag → `./gradlew assembleRelease` → upload to GH release. |

### F-Droid reproducibility checklist (relevant for AGPL/FOSS distribution)

- No closed-source deps (we have none).
- Pin Gradle/AGP/Kotlin/JDK versions exactly in `gradle-wrapper.properties` and `libs.versions.toml`.
- Disable build-time timestamp injection (`android.defaultConfig.versionNameSuffix` based on date is the usual trap).
- Disable R8 minification non-determinism: pin R8 version, set `android.enableR8.fullMode=false` initially (full mode has known reproducibility issues), revisit when R8 lands a fix.
- Strip ABI-specific build paths from manifest. F-Droid's [reproducible builds page](https://f-droid.org/docs/Reproducible_Builds/) lists current pitfalls.

As of end-2025 only ~21% of F-Droid apps are reproducibly built; aiming for that is a v1.1 polish item, not a v1 blocker. ([F-Droid 2025 status](https://f-droid.org/en/2026/01/23/fdroid-in-2025-strengthening-our-foundations-in-a-changing-mobile-landscape.html))

## 10. Testing

Thin stack, all maintained:

| Layer | Tool | Why |
|---|---|---|
| Unit (pure Kotlin) | **JUnit 5** + **MockK** + **Turbine** (for `Flow`) + **kotest assertions** | JUnit 5 is the modern test runner; MockK is Kotlin-native (no `mockito-kotlin` ceremony); Turbine is the canonical Flow-test helper. ([Turbine usage](https://github.com/cashapp/turbine)) |
| Local-JVM Android tests (Robolectric) | **Robolectric 4.x** with `@Config(application = HiltTestApplication::class)` | Test Compose UI without a device — 12s vs 5min for instrumented runs. ([Compose+Robolectric perf](https://medium.com/@sebaslogen/blazing-fast-compose-tests-with-robolectric-b059f5471495)) |
| Compose UI | **`androidx.compose.ui:ui-test-junit4`** with `createComposeRule()` | First-party. Tag every interactive node with `Modifier.testTag(...)` per SPEC accessibility rules. |
| Instrumented (device/emulator) | **AndroidX Test Runner** + the Compose test rule above | Run on CI with Gradle Managed Devices on a single API 34 emulator config. |
| End-to-end | None in v1 | Solo dev; over-investment. |

The tests/ directory mirrors `app/src/main/kotlin/...` exactly the way iOS's `ListsTests/` mirrors `Lists/` (per `00-current-state.md`).

Match the iOS rule from `CLAUDE.md`: **every new feature ships with a test file**.

## 11. First-month gotchas (URLs included)

1. **Exact-alarm permission denied by default since Android 14.** Use `setAlarmClock` (auto-exempt) and avoid `setExactAndAllowWhileIdle` for the urgent path. If you need both, check `AlarmManager.canScheduleExactAlarms()` and gate UI off it; listen for `ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED`. ([Android 14 change](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms))

2. **`USE_FULL_SCREEN_INTENT` restricted as of Jan 22, 2025.** Only "calling and alarm" apps get it pre-granted. We qualify, but Play Console requires a Declaration. ([Play Console policy](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en)) Required filing: tick "alarm" use-case in the Play Console "App content" → "Notification permissions" page.

3. **Scoped storage migrations.** Starting v1 with app-private storage means no migration. If/when v1.1 introduces SAF, write a one-shot migration step (copy app-private tree → user-picked URI; switch storage strategy; mark migration complete in DataStore prefs). ([Storage updates Android 11](https://developer.android.com/about/versions/11/privacy/storage))

4. **Doze mode + App Standby buckets.** `WorkManager` periodic jobs are deferred under Doze; the rare bucket caps a job to 10 min/day. The notification + alarm path uses `setAlarmClock` which **bypasses Doze**, so the user-visible alerting is unaffected. The 30-min file-watcher rescan **will** be deferred to the next maintenance window — that's fine, we don't depend on it being on time. ([Doze/standby docs](https://developer.android.com/training/monitoring-device-state/doze-standby), [App Standby Buckets](https://developer.android.com/topic/performance/appstandby))

5. **Notification channels mandatory since Android 8.** Create at first launch, never delete (deleted channels stay deleted forever once seen by the user). Use stable channel IDs `urgent_alarms`, `reminders_with_time`, `reminders_date_only`.

6. **`POST_NOTIFICATIONS` runtime permission since Android 13.** Request at first attempt to schedule (matches iOS UNUserNotificationCenter pattern). Handle denial gracefully — show a settings deep-link banner. ([POST_NOTIFICATIONS](https://developer.android.com/develop/ui/views/notifications/notification-permission))

7. **`FileObserver` events fire for our own writes.** Track an in-flight write set keyed on file path; ignore the next event for any path we just wrote. Otherwise the index rebuilder will chase its own tail.

8. **Android 14 foreground-service types are mandatory.** If we use a foreground service for the full-screen alarm activity (we shouldn't need to — `setShowWhenLocked(true)` on the activity covers it), declare `android:foregroundServiceType="specialUse"` and the matching permission. ([Foreground service requirements](https://developer.android.com/about/versions/14/changes/fgs-types-required))

9. **`BOOT_COMPLETED` re-arm.** Alarms set via `AlarmManager` are wiped on reboot. A `BootReceiver` must walk the cache and re-schedule every pending alarm. Easy to forget; users will report "alarms stop after restart" if missed.

10. **OEM background-killers (Xiaomi, Huawei, Oppo).** These OEMs aggressively kill background apps and break alarms. Direct users to Settings → Battery → "Don't optimize" for our app via an in-app banner. Document this in onboarding for v1.1.

11. **`COLUMN_LAST_MODIFIED` may be 0 on third-party SAF providers.** When in v1.1 SAF mode, fall back to a content-hash compare on small files, or trust the index until a write event nudges us. ([SAF docs](https://developer.android.com/training/data-storage/shared/documents-files))

12. **Auto-Backup quota (25MB).** Disable Auto-Backup explicitly via `android:allowBackup="false"` and `android:fullBackupContent="@xml/backup_rules"`; provide our own Settings → "Export…" path. Otherwise a year-3 habit user with photos-in-markdown blows the quota and gets silent backup failures.

## 12. Confirming the min-API call

SPEC says "Android 14+" (API 34). That recommendation holds:

- API 34 was the **mandatory target** for Play Store updates as of Aug 31, 2025; new app submissions now require **API 35 target**. ([Target API requirements](https://developer.android.com/google/play/requirements/target-sdk))
- Setting **min API 34** drops support for ~25% of active devices (Android 13 and lower). Setting **min API 31 (Android 12)** would cover ~85%. The UI/alarm/permission code is much simpler on API 33+ (POST_NOTIFICATIONS is one path, not two), and a brand-new FOSS app doesn't have a legacy user base to retain.
- **Recommendation:** **`minSdk = 31` (Android 12), `targetSdk = 35` (Android 15).** `minSdk = 31` keeps `setAlarmClock` working on every device, includes the bulk of the active install base, and avoids the SCHEDULE_EXACT_ALARM denial-by-default behaviour of Android 14+ for users who reach `setExact` paths. SPEC's "Android 14+" was a defensive guess; bumping the floor below it adds modest complexity for a much wider audience. If solo-dev capacity is the binding constraint, **`minSdk = 34`** is also defensible and matches SPEC verbatim.

## 13. Sources

- [SPEC.md §6, §7, §11, §14, §15, §16](file:///Users/saxon/Developer/Projects/Lists/SPEC.md) — internal contract.
- [research/00-current-state.md](file:///Users/saxon/Developer/Projects/Lists/research/00-current-state.md) — Phase 1 findings.
- [Jetpack Compose December '25 release notes](https://developer.android.com/blog/posts/whats-new-in-the-jetpack-compose-december-release)
- [Compose Material 3 release notes](https://developer.android.com/jetpack/androidx/releases/compose-material3)
- [Room KMP guide](https://developer.android.com/kotlin/multiplatform/room)
- [Room vs SQLDelight in 2025](https://docs.bswen.com/blog/2026-03-14-room-vs-sqldelight-kmp/)
- [snakeyaml-engine-kmp](https://github.com/krzema12/snakeyaml-engine-kmp)
- [kaml (archived)](https://github.com/charleskorn/kaml)
- [Markwon repo](https://github.com/noties/Markwon)
- [compose-markdown (jeziellago)](https://github.com/jeziellago/compose-markdown)
- [MarkdownTwain](https://github.com/colintheshots/MarkdownTwain)
- [multiplatform-markdown-renderer (mikepenz)](https://github.com/mikepenz/multiplatform-markdown-renderer)
- [Hilt vs Koin 2025 perspectives](https://medium.com/@hiren6997/dependency-injection-wars-koin-vs-hilt-in-modern-android-projects-60ab6320b613)
- [AlarmManager API reference](https://developer.android.com/reference/android/app/AlarmManager)
- [Schedule alarms guide](https://developer.android.com/develop/background-work/services/alarms)
- [Android 14: schedule exact alarms denied by default](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms)
- [USE_FULL_SCREEN_INTENT permission](https://developer.android.com/reference/android/Manifest.permission#USE_FULL_SCREEN_INTENT)
- [Play Console: Foreground service and full-screen intent requirements](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en)
- [POST_NOTIFICATIONS runtime permission](https://developer.android.com/develop/ui/views/notifications/notification-permission)
- [Notification permission AOSP overview](https://source.android.com/docs/core/display/notification-perm)
- [FileObserver API reference](https://developer.android.com/reference/android/os/FileObserver)
- [ContentObserver API reference](https://developer.android.com/reference/android/database/ContentObserver)
- [Storage Access Framework: shared documents and files](https://developer.android.com/training/data-storage/shared/documents-files)
- [Storage Access Framework overview](https://developer.android.com/guide/topics/providers/document-provider)
- [Storage updates in Android 11](https://developer.android.com/about/versions/11/privacy/storage)
- [Manage all files on a storage device](https://developer.android.com/training/data-storage/manage-all-files)
- [Play Store: All files access policy](https://support.google.com/googleplay/android-developer/answer/10467955?hl=en)
- [Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)
- [App Standby Buckets](https://developer.android.com/topic/performance/appstandby)
- [Android 14 foreground service types](https://developer.android.com/about/versions/14/changes/fgs-types-required)
- [Target API level requirements (Play Store)](https://developer.android.com/google/play/requirements/target-sdk)
- [F-Droid Reproducible Builds](https://f-droid.org/docs/Reproducible_Builds/)
- [F-Droid Inclusion How-To](https://f-droid.org/en/docs/Inclusion_How-To/)
- [F-Droid 2025 retrospective](https://f-droid.org/en/2026/01/23/fdroid-in-2025-strengthening-our-foundations-in-a-changing-mobile-landscape.html)
- [mozilla/uniffi-rs](https://github.com/mozilla/uniffi-rs)
- [UniFFI on Android intro (sal.dev)](https://sal.dev/android/intro-rust-android-uniffi/)
- [JetBrains: Compose Multiplatform 1.8.0 stable](https://blog.jetbrains.com/kotlin/2025/05/compose-multiplatform-1-8-0-released-compose-multiplatform-for-ios-is-stable-and-production-ready/)
- [Compose Multiplatform iOS stable in 2025](https://www.kmpship.app/blog/compose-multiplatform-ios-stable-2025)
- [Turbine repo](https://github.com/cashapp/turbine)
- [Robolectric repo](https://github.com/robolectric/robolectric)
- [Compose + Robolectric performance writeup](https://medium.com/@sebaslogen/blazing-fast-compose-tests-with-robolectric-b059f5471495)
- [FSF GPL-compatible licenses (Apache-2.0 entry)](https://www.gnu.org/licenses/license-list.html#apache2)
