# Icon Composer & Custom Icons — Guide for Lists

Compiled 2026-05-30. Confidence: High on core Apple-primary facts; Medium on practitioner-only build internals.

## TL;DR for Saxon

- **Icon Composer is Apple's free Mac app** for building the new "Liquid Glass" app icons (the layered, glassy look introduced with iOS 26 / macOS 26). It's bundled with Xcode 26 and also downloadable on its own without a paid developer account.
- **You design ONE icon and the system makes all the variations** automatically — light, dark, "clear," and "tinted" looks. You don't hand-draw each version.
- **Don't bake in fancy effects.** Apple explicitly says: no drop shadows, glows, bevels, or blurs in your artwork — the system adds the glassy depth for you. Hand the designer flat, clean shapes.
- **The app icon and the little glyphs inside the app are two different systems.** The app icon = an `.icon` file from Icon Composer. The small symbols next to lists/notes = "custom SF Symbols." Don't mix them up.
- **Practical limit to give a designer:** one background layer plus foreground artwork organized into at most **4 "groups"** (the glass effect is applied per group). Canvas is **1024×1024 px** (Apple Watch is 1088×1088).
- **Timing is fine.** Nothing is about to be replaced. WWDC 2026 (June 8–12) hasn't happened yet and introduces the *next* OS generation (the "27" line); today's Icon Composer and SF Symbols 7 are current and safe to build on.
- **One decision affects you:** if Lists still supports iPhones on iOS 18 or older, we must keep a plain fallback icon image alongside the fancy `.icon` file. If Lists is iOS 26-only, we don't need the fallback.
- **Recommendation:** use Icon Composer for the Lists app icon (and any alternate app icons), and build per-list/per-note glyphs as custom SF Symbols. This is the modern, Apple-blessed path and fits Lists' plain Xcode 26 + SwiftUI setup with no special tooling risk.

## 1. What Icon Composer Is

Icon Composer is a **free macOS app** for building layered "Liquid Glass" app icons from a single design, targeting iPhone, iPad, Mac, and Apple Watch.

- **System requirement (verbatim, Apple):** "Requires macOS Sequoia 15.3 or later."
- **Availability (both confirmed):** bundled with Xcode 26 **and** available as a standalone download from `developer.apple.com/icon-composer/` that does **not** require a paid developer account.
- It also produces a **flattened-image export** for marketing and App Store use.

This is the current shipping tool as of 2026-05-30. There is no announced "Icon Composer 2."

## 2. Temporal Context (is now the right time?)

- Today is **2026-05-30**. **WWDC 2026 runs June 8–12, 2026 — it has not happened yet** (confirmed by Apple Newsroom).
- There is **no announced "Icon Composer 2" or "SF Symbols 8."**
- A naming clarification worth knowing: WWDC26 will introduce the **OS 27 generation** (iOS 27 / macOS 27). The current shipping OSes — **iOS 26 / macOS 26** — are the WWDC25 generation that introduced Liquid Glass. So "iOS 26.x" is the *current* line, not a future one.
- **Bottom line:** the WWDC25-generation tools (Icon Composer, SF Symbols 7) are current and nothing supersedes them today. Re-verify after June 8, 2026.

## 3. The Layer / Group Model (important — commonly misstated)

Apple's authoritative model:

- An icon has a **required background layer** plus **one or more foreground layers**. HIG verbatim: "a background layer and one or more foreground layers that coalesce to create dimensionality."
- In Icon Composer those layers are organized into **GROUPS**, and **the cap is on groups, not layers**: the Xcode doc says to organize layers "into a **maximum of four groups**." WWDC25 session 361: "By default, it'll always be one, but you can go all the way up to four."
- **The glass material is applied at the GROUP level.**
- **Key correction:** a single group can contain *multiple* image layers, so there is **no hard "5-layer" limit**. Total layers can exceed five; they resolve into at most **4 glass groups + 1 background**. (The popular "1 background + up to 4 layers" phrasing is a practitioner simplification — the canonical limit is **4 groups**.)

## 4. Appearance / Rendering Modes (two layers of truth)

There is a difference between what you *edit* and what the system *delivers*.

**What you EDIT / ANNOTATE in Icon Composer — THREE base modes:**
- **Default, Dark, and Mono** (for iOS/macOS).
- Apple Watch has **no appearances** to preview.
- The **Mono** annotation is what the Clear and Tinted variants are derived from (Xcode doc: mono "and clear and tinted variants as well").

**What the SYSTEM GENERATES / what HIG specifies — SIX delivered variants (iOS/iPadOS/macOS):**
- **Default, Dark, Clear Light, Clear Dark, Tinted Light, Tinted Dark.**
- HIG guidance (verbatim): "keep your icon's core visual features the same in the default, dark, clear, and tinted appearances."

**Tint behavior (WWDC25 session 220, verbatim):**
- Dark tint "adds color to the foreground."
- Light tint: "the color gets directly infused into the glass."

(Note: Mono is an *editing annotation* that seeds Clear/Tinted — it is **not itself one of the six delivered variants**.)

## 5. "Don't Bake In Effects" (confirmed verbatim)

- **HIG:** "Let the system handle blurring and other visual effects... there's no need to include specular highlights, drop shadows between layers, beveled edges, blurs, glows, and other effects."
- **WWDC25 session 220:** "we also recommend paring back any built-in static effects in your source artwork."

Give the designer flat, clean source art. The system does the depth and glass.

## 6. Canvas Sizes & the Unified Grid (confirmed)

- **Canvas:** **1024×1024 px** for iPhone, iPad, and Mac; **1088×1088 px** for Apple Watch.
- **Unified grid (WWDC25 s220):** a single "unified iconography language" — a rounded rectangle with "a rounder corner radius" and "a simpler and more evenly spaced structure," abandoning per-device variation. The Watch's circular grid uses 1088 to align with this system.

## 7. The `.icon` File Format

- `.icon` is a **macOS package** — a folder Finder treats as a single file. Inside:
  - **`icon.json`** describing structure (layers/groups, material properties, appearance mappings, fill/canvas), and
  - an **`Assets/`** subfolder of layer images.
  *(Structure: HIGH confidence. Some internal details: practitioner-corroborated.)*
- **Layer source art:** SVG (text converted to outlines, no open paths, no baked effects) **or** PNG. WWDC25 s361 recommends SVG for vectors but uses PNG "since this is a lossless format that can retain a transparent background" when SVG can't express the content.
  - **Caveat (single practitioner opinion, MEDIUM):** one author (Virtual Sanity) reports SVGs "did not get the liquid glass effects as expected" and prefers PNG. This is **anecdotal, not Apple guidance** — Apple's stated position prefers SVG for vectors.
- **Editable group-level material properties (WWDC25 s361):** **Specular highlight, Opacity, Translucency, Shadow (neutral and chromatic), Blend Mode, Fill.**
  - "Blur" is **system-applied**, not a discrete named editable group property (MEDIUM).

## 8. Tooling — `actool` / `ictool` (MEDIUM — practitioner-sourced)

These internals come from practitioner blogs (praeclarum, Virtual Sanity), **not** Apple's primary docs, and may drift across Xcode point releases:

- **`ictool`** lives at `Icon Composer.app/Contents/Executables/ictool` and renders PNG previews from a `.icon`.
- **`actool`** compiles the `.icon` into **`Assets.car`** (the fully layered icon for iOS 26+/macOS 26+) plus **backwards-compatible PNGs (iOS) and `.icns` (macOS)** and an **`assetcatalog_generated_info.plist`** whose entries feed Info.plist.
- The **`--minimum-deployment-target`** parameter governs legacy generation.

## 9. Xcode Integration (high confidence)

Apple's documented workflow:

1. "Drag the Icon Composer file from Finder to the Project navigator" (or use Add Files).
2. In target settings, "ensure that the name in the **App Icon** text field matches the name of the Icon Composer file without the extension."
3. A single `.icon` covers all appearances — **no hand-authoring** of default/dark/tinted asset-catalog entries.
4. Requires **Xcode 26**.

- **Nuance:** Apple names the UI control the **"App Icon" text field** and does *not* name a build setting. The underlying build-setting key is **`ASSETCATALOG_COMPILER_APPICON_NAME`** (practitioner-known via Use Your Loaf, MEDIUM) — accurate, but **not** Apple-documented.

## 10. Back-Deployment / Legacy Fallback (high-to-medium)

- `.icon` icons render **inconsistently below OS 26** (documented example: an iOS 16.4 background failing to render).
- **Fallback mechanism (HIGH):** name the `.icon` to **match** an asset-catalog icon set — e.g., `AppIcon.icon` alongside an `AppIcon` set containing a 1024 PNG. On **iOS 26+** the glass `.icon` is used; on **iOS 18 and earlier** the asset-catalog image is used.
- Practitioners also cite an `actool` flag — `--enable-icon-stack-fallback-generation=disabled` — to control Apple's automatic legacy generation (MEDIUM).
- **Relevance to Lists:** the team considered dropping the deployment floor from iOS 26→18. **If Lists ships an iOS 18-or-lower target, keep the legacy asset-catalog 1024 icon alongside the `.icon`. If Lists is 26-only, this is moot.**

## 11. Alternate / In-App Custom App Icons (high confidence)

`.icon` works beyond the primary icon:

- Create multiple named `.icon` files (`AppIcon.icon`, `AppIcon2.icon`, …) matching asset-catalog names.
- Existing `setAlternateIconName(_:)` code then yields **glass variants on iOS 26** and **legacy variants on iOS 18 and earlier**.
- Names are **case-sensitive**; the primary `.icon` must be selected in **General > App Icons**.

## 12. SF Symbols 7 (the in-app glyph system — current)

The app icon and in-app glyphs are **separate systems**. SF Symbols are for **in-app glyphs**; `.icon` is for the **app icon**.

- **SF Symbols 7:** over **6,900 symbols, nine weights, three scales.**
- New in 7: **Draw animations** (Draw On/Off; playback Whole Symbol / By Layer / Individually), **Variable Draw**, **enhanced Magic Replace** (preserves enclosures, auto Draw transitions), and **automatic gradients** from a system or custom color, plus new and localized symbols.
- Targets iOS/iPadOS/macOS/watchOS/tvOS/visionOS **26**.
- **Requirement asymmetry (both confirmed):** the **SF Symbols app requires macOS Sonoma or later**; **Icon Composer requires macOS Sequoia 15.3 or later**.

## 13. Custom SF Symbols Pipeline (high confidence — Apple UIKit doc)

For Lists' own glyphs (per-list / per-note):

- **Static template = 27 sets of paths + one set of margins** (9 weights × 3 scales = 27).
- **Variable template = three sets of paths + three sets of margins**, source weights **Ultralight-S, Regular-S, Black-S**, interpolated to the full range.
- **Path-based requirement (verbatim):** a symbol is path-based "if all the shapes within it have solid color fills, and don't have strokes or other graphical features"; "Convert any strokes to paths." (No open paths; strokes → outlines.)
- **Asset catalog workflow (HIGH):** **Editor > Add New Asset > Symbol Image Set**, drag the SVG into the Symbol SVG section; Xcode validates. (This produces a `.symbolset`; the `.symbolset` / `Contents.json` / `symbol-rendering-intent` internal naming is practitioner-corroborated — MEDIUM.)
- **Runtime:** use `Image(named:)` / `UIImage(named:)` for **custom** symbols; `Image(systemName:)` is only for **system** symbols.
- **Gotcha (MEDIUM):** mismatched node counts across the 3 variable weights produce a "not interpolatable" error — keep the three weights geometrically consistent.

## 14. Build-Chain Gotchas (MEDIUM — and not a concern for Lists)

As of Sept 2025, some **non-Xcode** build chains (.NET/MAUI, XcodeGen, Cordova, Capacitor) had open issues handling the layered `.icon`. **Lists is plain Xcode 26 + SwiftUI, so this does not apply.** (Point-in-time; may be resolved by now.)

## Recommendations for Lists

**App icon — use Icon Composer.**
1. Design a **background layer + foreground layers** organized into **up to 4 glass groups** on a **1024×1024** template (start from Apple's Design Resources templates for Figma/Sketch/Illustrator).
2. **Hand the designer flat art** — no shadows, glows, bevels, or blurs. The system adds glass depth.
3. Import to Icon Composer, tune the **six group material properties**, and annotate **Default / Dark / Mono**.
4. Export the `.icon`, drag it into **Xcode 26**, and set the **App Icon** text field to the filename (no extension).
5. **Deployment-target decision:** if Lists keeps an **iOS 18-or-lower** floor, **also** keep a matching legacy asset-catalog **1024 PNG** for fallback. If Lists goes **26-only**, just ship the `.icon`. (Recommendation: decide the floor first — it removes the fallback chore entirely if 26-only, but check your installed-base data before cutting iOS 18 users.)

**In-app glyphs (per-list / per-note) — use custom SF Symbols, not `.icon`.**
1. Build them from the **variable template** (3 weights, geometrically interpolatable) so they **tint, scale, animate, and align** exactly like system symbols.
2. Reference with **`Image("name")`** — **never** `systemName` for custom symbols.
3. Reserve `.icon` strictly for the **primary and alternate app icons**.

**Alternate app icons (optional, low effort later):** if Lists ever offers icon choices, add `AppIcon2.icon`, `AppIcon3.icon`, etc., matching asset-catalog names, and drive them with `setAlternateIconName(_:)`.

**Tooling risk:** none specific to Lists — the plain Xcode 26 + SwiftUI stack avoids the non-Xcode build-chain issues entirely.

## Sources

- [official] Icon Composer (product overview) — https://developer.apple.com/icon-composer/ — 2025 (WWDC25), current as of 2026-05-30 — **high**
- [official] Creating your app icon using Icon Composer (Xcode docs) — https://developer.apple.com/documentation/Xcode/creating-your-app-icon-using-icon-composer — 2025, current — **high** (read via Sosumi Markdown mirror; see gaps)
- [official] App icons — Human Interface Guidelines — https://developer.apple.com/design/human-interface-guidelines/app-icons — current — **high**
- [official] Create icons with Icon Composer — WWDC25 session 361 — https://developer.apple.com/videos/play/wwdc2025/361/ — 2025-06 — **high**
- [official] Say hello to the new look of app icons — WWDC25 session 220 — https://developer.apple.com/videos/play/wwdc2025/220/ — 2025-06 — **high**
- [official] SF Symbols (product overview) — https://developer.apple.com/sf-symbols/ — 2025 (SF Symbols 7), current — **high**
- [official] Creating custom symbol images for your app (UIKit docs) — https://developer.apple.com/documentation/uikit/creating-custom-symbol-images-for-your-app — current — **high**
- [official] Configuring your app to use alternate app icons (Xcode docs) — https://developer.apple.com/documentation/xcode/configuring-your-app-to-use-alternate-app-icons — current — **high**
- [official] Apple kicks off Worldwide Developers Conference on June 8 (Newsroom) — https://www.apple.com/newsroom/2026/05/apple-kicks-off-worldwide-developers-conference-on-june-8/ — 2026-05 — **high**
- [official] WWDC26 — Apple Developer — https://developer.apple.com/wwdc26/ — 2026-05 — **high**
- [secondary] Updating App Icons for iOS and macOS 26 — Frank Krueger (praeclarum.org) — https://praeclarum.org/2025/09/12/app-icons.html — 2025-09-12 — **medium**
- [secondary] Icon Composer Notes — John Brayton (Virtual Sanity) — https://www.virtualsanity.com/202507/icon-composer-notes/ — 2025-07 — **medium**
- [secondary] Adding Icon Composer icons to Xcode — Keith Harrison (Use Your Loaf) — https://useyourloaf.com/blog/adding-icon-composer-icons-to-xcode/ — 2025 — **medium**

## What Couldn't Be Confirmed

- **Raw-Apple byte verification of the Xcode doc.** Apple's primary Xcode page renders empty via direct fetch (JavaScript SwiftDocC); it was read via the Sosumi Markdown mirror (sosumi.ai). The content is Apple's, but exact wording is high-confidence-via-mirror, **not** raw-Apple-verbatim.
- **`actool` / `ictool` internals** (`Assets.car`, `.icns`, `assetcatalog_generated_info.plist`, the `ictool` path, `--minimum-deployment-target`, `--enable-icon-stack-fallback-generation`) are corroborated only by practitioner blogs — **not** Apple primary docs. MEDIUM; may drift across Xcode point releases (the cited `ictool` path referenced an Xcode 26.4-RC).
- **Exact `.symbolset` / `Contents.json` / `symbol-rendering-intent` key names** are practitioner-corroborated; Apple's UIKit doc describes the workflow but the fetched version didn't surface those internal filenames. MEDIUM.
- **The precise Mono → Clear/Tinted derivation chain.** Apple bundles "mono … and clear and tinted variants as well," implying mono-seeded, but whether Mono strictly generates *both* Clear and Tinted (vs. Clear being a separate transparency annotation) is not 100% pinned across sources.
- **Any WWDC 2026 / "next-gen" claims.** The event is June 8–12, 2026 and has not occurred; nothing about a future Icon Composer or "SF Symbols 8" exists yet. Re-verify after June 8, 2026.
- **Current status of non-Xcode build-chain issues** (.NET MAUI, XcodeGen, Capacitor, Cordova) — point-in-time as of Sept 2025, not re-verified. Not relevant to Lists' plain Xcode 26 + SwiftUI stack.
