# Android 17 Design References — Current & Official

Compiled 2026-05-30. Confidence: HIGH (core findings verified against official sources; a few preview-only items flagged as unconfirmed).

---

## TL;DR for Saxon

- **"Android 17" is real and current.** It's the live OS release (API level 37, codename "CinnamonBun"), in Beta and heading to a stable launch in Q2 2026. There is no "Android 18" yet — this is the right thing to design against.
- **Android 17 is NOT a new look.** It's an operating-system update (privacy, performance, networking). The actual design language is called **Material 3 Expressive** — the same one introduced with Android 16. Don't think "Android 17 design"; think "Material 3 Expressive, running on Android 17."
- **Material 3 Expressive is the current, official design system.** Google launched it in May 2025 after a large research effort (46 studies, 18,000+ participants). It's about springy motion, bolder/bigger type, morphing shapes, and richer dynamic color.
- **The catch for building it today:** the fancy Expressive UI components are still **alpha** (pre-release) in Google's Compose toolkit. The stable, production-safe version (material3 1.4.0) does NOT include them yet. Adopting them now means opting into pre-release code.
- **If Lists ever targets Android 17,** large screens (tablets, foldables) get a mandatory rule: the app can no longer lock itself to portrait or a fixed aspect ratio on big displays. The app must adapt. Phones are unaffected.
- **The flashy visuals you may have seen in the press** (a fancy color picker, "Neutral/Soft/Bright/Bold" color presets, more system blur) are **leaks, not official.** They are absent from Google's official Android 17 docs. Do not plan around them.
- **Bottom line for planning:** the design target is settled (Material 3 Expressive), but the build-it-in-Compose tooling is mid-transition. That's a "watch and wait for stable" situation, not a "blocked" one.

---

## Detailed Sections

### 1. What "Android 17" actually is

"Android 17" is confirmed by Google's official "First Beta of Android 17" blog (developer.android.com, 2026-02-13):

- **API level 37**, codename **"CinnamonBun"**.
- As of 2026-05-30 it is in the Beta phase, heading toward stable release.
- It is a **platform/OS release**, not a design-system release. The headline additions are platform, privacy, and performance APIs — for example: ProfilingManager triggers, Encrypted Client Hello, a system Contact Picker, Advanced Protection Mode, post-quantum (PQC) APK signing, satellite networking, a Handoff API, and UWB.
- There is **no new design language** in Android 17. The design language remains **Material 3 Expressive (M3E)**.

**The single most important takeaway:** Material 3 Expressive is one design language used across both Android 16 and Android 17. "Android 17" is the OS; "Material 3 Expressive" is the design system. These are two different things and should not be conflated.

### 2. Material 3 Expressive (the actual design language)

- Officially announced **2025-05-13** on blog.google, described by Google as "one of our biggest updates in years."
- Launched alongside **Android 16 + Wear OS 6**.
- Core ideas: **springy, physics-based motion**; **emphasized/expanded typography**; **shape morphing**; **expanded dynamic color**; and a set of **new components**.
- It is **research-backed**: Google's official research write-up (design.google) reports **46 global studies, hundreds of design variations, and 18,000+ participants**, plus findings such as expressive designs helping people spot key UI elements substantially faster. (Bookmark the official research page rather than relying on secondary coverage — see Sources.)

The canonical spec lives at **m3.material.io** (components, motion, color, typography, shapes). Note: those spec pages are JavaScript-rendered and should be read directly in a browser.

### 3. Building Material 3 Expressive in Compose — stable vs. alpha (the practical gate)

This is the part that affects engineering decisions most directly.

- **Stable Compose Material3 = `material3 1.4.0`.** This has been the stable line since **2025-09-24 (~8 months)**. (A "2026-05-19" date appearing on the release-notes page header is a page-republish artifact, not a new release.)
- **Expressive APIs are still ALPHA**, on the separate `1.5.0-alpha` track. As of 2026-05-30 the latest is **1.5.0-alpha20 (2026-05-19)**. `1.5.0` has **not** reached stable.
- To use Expressive components today — **FloatingToolbar, ButtonGroup, SplitButton, FAB Menu, WavyProgressIndicator, LoadingIndicator** — you must opt into the `1.5.0-alpha` track.
- Verified per-version graduations on the alpha track:
  - **alpha15** (2026-02-25): `MotionScheme` graduated; `Scrim` added.
  - **alpha16** (2026-03-25): Typography constructors; `Slider`.
  - **alpha17** (2026-04-08): `TopAppBarScrollBehavior`.
  - **alpha18** (2026-04-22): `materialExpressiveTheme` / `expressiveLightColorScheme`; `WavyProgressIndicator`; `RippleThemeConfiguration`.
  - **alpha19** (2026-05-06): `ToggleButtons` stable.
- `LoadingIndicator` and `MaterialShapes` have **not** graduated to stable (consistent with reports that earlier promotions were reverted).

**Current Compose BOM = `2026.05.01`** (per the official BOM-to-library mapping page, updated 2026-05-19), preceded by 2026.05.00, 2026.04.01/00, and 2026.03.x. Important nuance: **every BOM from 2026.03 through 2026.05.01 still maps `material3` to `1.4.0` stable** — so "expressive APIs are still in alpha" remains true regardless of which recent BOM you pin.

The official Compose Material3 guide (developer.android.com/develop/ui/compose/designsystems/material3, updated 2026-05-19) explicitly introduces Material 3 Expressive as "the next evolution of Material Design… research-backed updates to theming, components, motion, typography," and documents: **dynamic color = Android 12+**, a **type scale of 15 default styles** (5 categories × 3 sizes), **5 shape sizes** (Extra Small → Extra Large), and **tonal-color-overlay elevation**.

### 4. Android 17 behavior changes that affect design/layout

All confirmed on `behavior-changes-17` / the First Beta blog:

- **Mandatory large-screen resizability (the biggest design-relevant change).** For apps **targeting API 37**, on displays **≥ 600dp smallest width**, the platform **ignores** `android:screenOrientation`, `setRequestedOrientation()`, `android:resizeableActivity`, `android:minAspectRatio`, and `android:maxAspectRatio`. Phones (< 600dp) are unaffected. Games (`android:appCategory`) are exempt. Users retain control via system aspect-ratio settings. The SDK 36 opt-out is **gone**.
- **Config-change handling.** By default, activities are **no longer recreated** for `CONFIG_KEYBOARD` / `KEYBOARD_HIDDEN`, `NAVIGATION`, `UI_MODE` (specifically, only when `UI_MODE_TYPE_DESK` changes), `TOUCHSCREEN`, and `COLOR_MODE`. Apps receive `onConfigurationChanged()` instead. To opt back into recreation, use the new `android:recreateOnConfigChanges`.
- **Live Updates Semantic Color API (genuinely new in API 37).** `Notification.createSemanticStyleAnnotation()`, with styles `SEMANTIC_STYLE_UNSPECIFIED`, `_INFO` (blue), `_SAFE` (green), `_CAUTION` (orange), `_DANGER` (red). Supported on `Notification`, `Notification.Metric`, `Notification.ProgressStyle.Point`, and `Notification.ProgressStyle.Segment`. **Scope is notification styling only** — it is not a system-wide design overhaul.

### 5. Enforcement carried over from Android 15/16 (still applies on Android 17)

Confirmed on `behavior-changes-16` and the predictive-back guide. These are correctly attributed to Android 15/16 enforcement that Android 17 continues — there is no Android-16-vs-17 conflation here.

- **Edge-to-edge enforced.** For apps targeting API 36, `windowOptOutEdgeToEdgeEnforcement` is **deprecated and disabled** (it still works only when such an app runs on Android 15).
- **Predictive back default-on.** For apps targeting API 36+ on Android 16+ devices, the system back animations (back-to-home, cross-task, cross-activity) are on by default; `onBackPressed` is no longer called and `KEYCODE_BACK` is no longer dispatched. Migrate to `OnBackInvokedCallback`, or temporarily opt out with `android:enableOnBackInvokedCallback="false"`.
- `elegantTextHeight` is **ignored** when targeting Android 16.

### 6. Google's stated direction (I/O 2026)

From the official "17 things to know for Android developers at Google I/O 2026" (android-developers.googleblog.com, 2026-05):

- **Compose-first:** "Compose is our standard for UI development… moving to a Compose-first approach."
- **Adaptive-by-Default** across phones, foldables, tablets, cars, and XR.
- New **experimental Grid and FlexBox layouts**.
- **Jetpack Navigation 3** is the latest navigation library.
- **580M+ large-screen devices** in the ecosystem — the rationale behind mandatory large-screen resizability.
- "Target Android 17 (API 37)" guidance, paired with the mandatory large-screen resizability rule.
- Peripheral (non-design) but worth knowing: a now-stable Android CLI with agent support (including Claude Code), AI Studio app building, and an iOS/React-Native migration assistant.

For adaptive layouts in Compose, the relevant building blocks are `NavigationSuiteScaffold`, `ListDetailPaneScaffold`, and `SupportingPaneScaffold` (Compose Material3 Adaptive).

### 7. The flashy visuals you may have seen — leaks, not official

These are **leak / secondary-source only** and are **confirmed absent** from the official Android 17 features page. Treat as preview/unconfirmed; do not build on them.

- **Custom color picker** and **wallpaper-untethered manual color** selection.
- **16-tone palettes per color role.**
- **Neutral / Soft / Bright / Bold intensity presets.**
- **Expanded system-UI blur** (notification shade, Quick Settings, volume panel, power menu).

These rest on 9to5google (a 2026-05-12 leak attributed to "Mystic Leaks," and a 2026-05-19 QPR1 Beta 3 blur report), plus AndroidHeadlines, AndroidAuthority, and Tech Advisor. The blur item in particular is a Pixel system-UI change surfaced via QPR1 betas — it is **not an app-facing API**.

### 8. Timeline (officially stated vs. widely reported)

From the official First Beta blog:

- **Beta 1:** 2026-02-13.
- **Platform Stability:** ~March 2026.
- **Stable release:** **Q2 2026** (only planned app-breaking changes after Platform Stability).
- **Minor SDK release:** planned for Q4 2026.

Note: **"Q2 2026" is what developer.android.com states.** "June 2026" is widely reported (PhoneArena, AndroidAuthority, etc.) but is **not** an official calendar date on developer.android.com as of 2026-05-30. Cite the date as "Q2 2026 (June 2026 widely reported, not officially dated)."

---

## Recommendations for Lists

1. **Set the design target to Material 3 Expressive — full stop.** It is the current, official, research-backed design language and it spans Android 16 and 17. Frame all Android design work as "Material 3 Expressive," not "Android 17 design."

2. **Build the production app on stable Compose Material3 (`material3 1.4.0`) via the current BOM (`2026.05.01`).** This is the safe, supported baseline and delivers core Material 3 Expressive theming, type scale, shapes, and dynamic color.

3. **Treat the showy Expressive components as opt-in, not foundational.** FloatingToolbar, ButtonGroup, SplitButton, FAB Menu, WavyProgressIndicator, LoadingIndicator live only on the `1.5.0-alpha` track. Adopt them only if you are comfortable shipping pre-release code; otherwise wait for `1.5.0` stable. Do not block Lists' Android plans on them.

4. **Design Lists to be adaptive from day one.** Google is explicitly "Adaptive-by-Default," and if Lists ever targets API 37, large-screen resizability is mandatory — no portrait/aspect-ratio lock on displays ≥ 600dp. Designing flexible layouts now (responsive panes, no hardcoded orientation) avoids a forced rework later. This aligns naturally with Lists' list/detail structure (`ListDetailPaneScaffold`).

5. **Adopt predictive back and edge-to-edge as baseline expectations**, not afterthoughts — they are already enforced for modern target levels and Android 17 continues them.

6. **Do NOT design around the leaked color picker, color presets, or system blur.** They are unconfirmed and absent from official docs. If Lists wants richer color, rely on the officially documented **dynamic color (Android 12+)** path instead.

7. **Consider the Live Updates Semantic Color API for Android notifications** (info/safe/caution/danger). For a tasks/lists/habits app this could map cleanly to reminder/notification states — but remember its scope is notification styling only.

8. **Re-check version status before committing to Expressive components.** The open question (will `material3 1.5.0` reach stable before/with Android 17 stable?) is unresolved. Revisit the Compose Material3 release notes and BOM-mapping pages before any go/no-go on alpha components.

---

## Sources

Official:

- [official] [high] **First Beta of Android 17** — https://developer.android.com/blog/posts/the-first-beta-of-android-17 — 2026-02-13 (API 37, CinnamonBun, timeline)
- [official] [high] **Android 17 Features and APIs** — https://developer.android.com/about/versions/17/features — 2026, last updated near 2026-05-19 (new APIs incl. Live Updates Semantic Color)
- [official] [high] **Behavior changes: Apps targeting Android 17 or higher** — https://developer.android.com/about/versions/17/behavior-changes-17 — 2026 current (mandatory large-screen resizability; config-change handling)
- [official] [high] **Behavior changes: Apps targeting Android 16 or higher** — https://developer.android.com/about/versions/16/behavior-changes-16 — 2026 current (edge-to-edge enforcement; predictive back default)
- [official] [medium] **Behavior changes: Apps targeting Android 15 or higher** — https://developer.android.com/about/versions/15/behavior-changes-15 — 2025–2026 current
- [official] [high] **17 things to know for Android developers at Google I/O 2026** — https://android-developers.googleblog.com/2026/05/17-things-android-developers-google-io.html — 2026-05 (Compose-first, Adaptive-by-Default direction)
- [official] [high] **Material 3 Expressive launch (Android & Wear OS)** — https://blog.google/products-and-platforms/platforms/android/material-3-expressive-android-wearos-launch/ — 2025-05-13 (M3E launch announcement)
- [official] [high] **Expressive Material Design — Google Research** — https://design.google/library/expressive-material-design-google-research — 2025 (the 46 studies / 18,000+ participant research; bookmark this for the figure)
- [official] [high] **Material Design 3 in Compose** — https://developer.android.com/develop/ui/compose/designsystems/material3 — last updated 2026-05-19 (M3E in Compose; type scale, shapes, dynamic color)
- [official] [high] **Compose Material 3 release notes** — https://developer.android.com/jetpack/androidx/releases/compose-material3 — latest entries 2026-05-19 (exact stable-vs-alpha versions; source of truth)
- [official] [high] **Compose BOM to library version mapping** — https://developer.android.com/develop/ui/compose/bom/bom-mapping — last updated 2026-05-19 (current BOM 2026.05.01 → material3 1.4.0)
- [official] [high] **What's new in the Jetpack Compose April '26 release** — https://android-developers.googleblog.com/2026/04/jetpack-compose-april-2026-updates.html — 2026-04 (latest release announcement; BOM 2026.04.01)
- [official] [high] **What's new in the Jetpack Compose December '25 release** — https://android-developers.googleblog.com/2025/12/whats-new-in-jetpack-compose-december.html — 2025-12-03 (Compose core 1.10, Pausable Composition — valid history, no longer the latest)
- [official] [medium] **Compose Material 3 Adaptive release notes** — https://developer.android.com/jetpack/androidx/releases/compose-material3-adaptive — 2024–2026 current (NavigationSuiteScaffold, ListDetailPaneScaffold, SupportingPaneScaffold)
- [official] [high] **Add support for the predictive back gesture** — https://developer.android.com/guide/navigation/custom-back/predictive-back-gesture — 2026 current (predictive back migration)
- [official] [medium] **m3.material.io — Material 3 / Material 3 Expressive spec** — https://m3.material.io — current (canonical spec; JS-rendered, read in a browser)

Secondary / leaks (corroboration only — do NOT build on these):

- [secondary] [low] **Android 17 custom color picker, preset variants, blur (LEAK)** — https://9to5google.com/2026/05/12/android-17-material-color-picker-blur-leak/ — 2026-05-12 (attributed to "Mystic Leaks"; absent from official docs)
- [secondary] [low] **Android 17 QPR1 Beta 3: System UI adds more blur** — https://9to5google.com/2026/05/19/android-17-beta-1-blur/ — 2026-05-19 (Pixel system-UI change, not an app API)

---

## What couldn't be confirmed

- **Android 17 (API 37) stable calendar date.** Official docs say "Q2 2026" / Platform Stability ~March 2026. "June 2026" is widely reported (PhoneArena, AndroidAuthority) but is **not** confirmed with a specific date on developer.android.com as of 2026-05-30.
- **Reported Android 17 dynamic-color changes** — 16-tone palettes per role, wallpaper-untethered manual color picker, and Neutral/Soft/Bright/Bold intensity presets — are **leak-only** and confirmed **absent** from the official Android 17 features page. Do not build on these.
- **Expanded system-UI blur** (notification shade, Quick Settings, volume panel, power menu) is a Pixel system-UI change surfaced via Android 17 QPR1 betas, corroborated only by 9to5google (2026-05-19), not by app-facing official API docs. It is not an app API.
- **Whether Material 3 Expressive Compose APIs** (FloatingToolbar, ButtonGroup, LoadingIndicator, FAB Menu, MaterialShapes) will reach **stable** (`material3 1.5.0`) before or with Android 17 stable is **unknown**. As of `1.5.0-alpha20` (2026-05-19) they remain alpha, and LoadingIndicator/MaterialShapes have not graduated.
- **The exact Compose BOM edition** that will first ship `material3 1.5.0` stable is **not yet announced**; all BOMs through 2026.05.01 still ship 1.4.0.
- **The canonical m3.material.io spec pages** (including m3.material.io/blog/building-with-m3-expressive) are JavaScript-rendered and could not be extracted programmatically — open them in a browser to read the canonical spec text directly.
