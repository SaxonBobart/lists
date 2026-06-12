# Accessibility & iOS 26 Platform Best Practices — Research

## Bottom line (plain English, for a non-technical product owner)

Lists has a quietly strong foundation: text scales with the system font-size
setting almost everywhere (including the custom Markdown editor), and colors are
mostly Apple's own "semantic" colors that adapt to dark mode and high-contrast
for free. But the app is **not yet usable end-to-end by a blind person**, and
several screens fall short of Apple's stated bar. The custom editor reads its
text to VoiceOver as raw Markdown ("dash bracket space bracket do the laundry")
instead of "checkbox, unchecked, do the laundry," and its tap-only checkboxes are
invisible to the screen reader. The two main list screens (Today and any smart
list, plus a list's detail view) are built on a UIKit engine where the swipe
actions (Delete / Flag / Details / Indent) are **not announced** to VoiceOver,
and drag-to-reorder has **no non-drag alternative** — a motor- or vision-impaired
user simply can't reorder. The habit progress ring and the year-long habit
heatmap convey everything through shape and color with no spoken description.
None of the app's fade/linger/drag animations check the "Reduce Motion" setting.
The good news: most of this is **labels and small wiring**, not redesign — a
focused pass plus two genuinely deeper pieces (the editor and an accessible
reorder path) would get Lists to a credible, "calm and accessible" state. The
iOS 26-only deployment target is *fine* for this (≈two-thirds of all iPhones,
~74% of recent models, by early 2026) and actually *gives* Lists modern
accessibility APIs to lean on.

---

## What best practice looks like (May 2026)

### Apple's stated bar (Human Interface Guidelines)

From Apple's HIG Accessibility page (current, fetched May 2026):

- **Hit targets:** default **44×44 pt**; absolute minimum **28×28 pt**. "Controls
  that are too small are hard for many people to interact with."
- **Contrast (WCAG AA):** text ≤17 pt → **4.5:1**; text ≥18 pt or bold → **3:1**.
- **Dynamic Type:** support it system-wide; give people the option to **enlarge
  text by at least 200%**. iOS body default is 17 pt.
- **Reduce Motion:** "reduce automatic and repetitive animations" — avoid zoom,
  scale, and peripheral motion.
- **Increase Contrast:** "provide a higher contrast color scheme when the system
  setting Increase Contrast is turned on" if the default isn't sufficient.
- **Differentiate Without Color:** "Convey information with more than color
  alone" — use distinct shapes/icons in addition to color.
- **VoiceOver:** "Describe your app's interface and content for VoiceOver" — every
  interactive element needs a label, the right trait (button/selected/etc.), and,
  where a row has multiple actions, **custom actions** (VoiceOver announces
  "Actions available… swipe up or down").

These are the table stakes Apple holds App Store apps to, and what assistive-tech
users expect from a "native, calm" app.

### iOS 26 "Liquid Glass" specifics

- Apple's Materials HIG says Liquid Glass variants "differ in response to … 
  accessibility settings that **reduce transparency or increase contrast**," and
  the regular variant "blurs and adjusts the luminosity of background content to
  maintain legibility." In other words: **the system chrome adapts for you** as
  long as you use the standard toolbar/sheet/material components rather than
  hand-rolled translucent surfaces.
- iOS 26 shipped with real-world legibility complaints about Liquid Glass; Apple
  responded by surfacing **Settings → Accessibility → Display & Text Size →
  Reduce Transparency** (opaque backgrounds) and **Increase Contrast**, and
  **Accessibility → Motion → Reduce Motion** (Liquid Glass "lensing" animations
  collapse to simple crossfades). Reduce Transparency was prominent enough that a
  later point release reportedly added a more direct toggle.
- Practical implication: translucency is an Apple-managed concern **if you stay on
  system components**. Custom-drawn translucent panels or low-contrast brand tints
  are where an app re-introduces the problem.

### How custom UITextView + UIKit collection bridges commonly break VoiceOver

This is the well-documented failure mode that maps directly onto Lists:

- **A `UITextView` exposes its `text` to VoiceOver verbatim.** If you hide markup
  by giving glyphs a zero-width font / `.clear` color (display-only tricks),
  VoiceOver still reads the underlying characters — the hidden `#`, `- [ ]`, `**`,
  ```` ``` ```` all get spoken. The visual "clean" rendering and the spoken
  rendering diverge.
- **Custom glyph drawing is invisible to VoiceOver.** Anything painted in
  `NSLayoutManager.drawGlyphs`/`drawBackground` (Lists' SF Symbol checkboxes,
  code-block panels, the horizontal rule) has no accessibility representation —
  Apple's own guidance is that custom-drawn views "do not support VoiceOver"
  unless you add it explicitly.
- **`UIHostingConfiguration` only auto-bridges SwiftUI semantics that live inside
  the hosted SwiftUI view.** Swipe actions declared with SwiftUI's `.swipeActions`
  *inside* the cell are converted to VoiceOver custom actions automatically.
  Swipe actions declared at the **UIKit layer** (a
  `UICollectionLayoutListConfiguration` swipe-actions provider) are **not** — they
  have no `accessibilityCustomActions` unless you add them by hand.
- **Drag-and-drop is a pure gesture.** UIKit drag/drop and SwiftUI `.onMove` give
  VoiceOver users nothing unless you provide custom actions ("Move up", "Move to
  section…") or keep a menu-based alternative.

Sources for the above are listed at the end.

---

## Implications for Lists ← most important

I read the actual code. Here's where Lists stands and what to do, marked
**[Quick win]** (labels / small wiring, hours) vs **[Deeper]** (design or
structural work).

### What Lists already does right (keep it)

- **Dynamic Type is broadly honored.** `ListsTypography` is pass-throughs to
  SwiftUI text styles (`.body`, `.headline`, …), and the **custom editor scales
  too**: `MarkdownStyler` builds every font from
  `UIFont.preferredFont(forTextStyle:)` and `MarkdownTextView` sets
  `adjustsFontForContentSizeCategory = true`. This is the single hardest thing to
  retrofit, and it's already there. (Caveat below on fixed-size glyphs.)
- **Colors are mostly semantic.** `Tokens.swift` is built on `.primary`,
  `.secondary`, `Color(.tertiaryLabel)`, `Color(.systemGroupedBackground)`,
  `Color(.separator)`, `*SystemFill`, etc. — these adapt to dark mode **and**
  Increase Contrast automatically. The editor's panels use `.secondarySystemFill`
  / `.tertiarySystemFill` / `.separator`. Good instinct; consistent with the
  repo's own "prefer semantic system colors" rule.
- **No hand-rolled translucency.** I found no custom Liquid-Glass / blur surfaces;
  the app leans on standard toolbars and sheets, so iOS 26 handles Reduce
  Transparency / Increase Contrast for the chrome.
- **Some labels exist.** Checkboxes, the habit ring, sheet header glyphs, and the
  select-mode circle have `accessibilityLabel`s. This is a partial base to build
  on, not a blank slate.

### Highest-risk spots (in priority order)

**1. The custom Markdown editor — VoiceOver reads raw Markdown; checkboxes are invisible. [Deeper]**
`MarkdownTextView` is a vanilla `UITextView` with no accessibility customization.
Because markers are hidden visually (zero-width font / `.clear` color in
`MarkdownStyler`) but remain in the backing string, VoiceOver speaks the literal
source. The task checkboxes are drawn as SF Symbol *images* in
`MarkdownLayoutManager.drawGlyphs` over cleared glyphs, so VoiceOver never sees
"checkbox." Worst-immediate offender: a hidden **1×1 pt, alpha-0 `UILabel`**
(`markdown.editor.cursor`) is marked `isAccessibilityElement = true` purely as an
XCUITest hook — VoiceOver can land focus on this empty element. *Actions:* set
`isAccessibilityElement = false` on that test label **[Quick win]**; then plan a
real editor accessibility story **[Deeper]** — at minimum an
`accessibilityLabel`/`accessibilityValue` representation that reads the *rendered*
text (markers spoken as structure: "heading", "checkbox unchecked", "link to …"),
and ideally per-element custom rotors. This is the single biggest gap and the
hardest; it should be scoped deliberately, not bolted on.

**2. The two UIKit collection bridges — swipe actions silent, drag unreachable. [Mixed]**
`SmartListCollectionView` (used by **Today** and **every smart list** — the
most-visited screens) and `ListDetailCollectionView` (list detail, **1,880 lines**,
with hierarchical drag-to-reorder) host `ItemRow` in `UIHostingConfiguration` but
define swipe actions at the **UIKit layer** (`trailingSwipeActions` /
`leadingSwipeActions` providers). Those Delete / Flag / Details / Indent / Outdent
actions get **no VoiceOver custom actions**. Note the inconsistency:
`SearchResultsView` renders the *same* `ItemRow` inside a SwiftUI `List`, so there
the `.swipeActions` *are* announced — the row is accessible in Search but its
actions vanish in Today/SmartList/ListDetail.
*Actions:* attach `accessibilityCustomActions` to each hosted cell mirroring the
swipe/context-menu actions **[Quick win–Medium]**; group each cell's content into
one VoiceOver element with a sensible combined label + `.isButton` trait
**[Quick win]**. For `ListDetailCollectionView`'s **drag-to-reorder, there is no
accessible alternative at all [Deeper]** — add custom actions ("Move up", "Move
down", "Indent", "Outdent", "Move to section…") so reordering and nesting are
reachable without a drag. (Leading-swipe Indent/Outdent already exist as logic —
exposing them as custom actions is most of the win.)

**3. Tap-only habit progress ring + color-only heatmap. [Quick win]**
In `ItemRow`, the habit ring has a label ("Increment habit"/"Habit complete") but
**no `accessibilityValue`** — VoiceOver can't say "2 of 3." In `HabitDetailView`
the large ring (`Circle().trim`) has *no* label or value. `HabitHeatmap` renders
**~371 cells** (53 weeks × 7) whose only meaning is fill color, with no labels and
no `accessibilityHidden` — VoiceOver will crawl hundreds of unlabeled rectangles,
and the "Less → More" legend is color-only.
*Actions:* add `accessibilityValue("\(currentCount) of \(goal)")` to both rings;
give the heatmap a single summary element (e.g. "Habit heatmap, completed N of
last 365 days") and mark the individual cells `accessibilityHidden(true)`; this
also satisfies **Differentiate Without Color**, since the heatmap currently
encodes streak strength purely as opacity.

**4. Reduce Motion is never checked. [Quick win]**
The "linger/Held Stun" fade (`withAnimation(.easeInOut(duration: 0.4))` in
TodayView/SmartListScreen/ListDetailView), expand/collapse animations, and the
custom drag-cue cell `transform` shifts in `ListDetailCollectionView` all run
unconditionally. No file reads `accessibilityReduceMotion` /
`UIAccessibility.isReduceMotionEnabled`. *Actions:* read
`@Environment(\.accessibilityReduceMotion)` (SwiftUI) /
`UIAccessibility.isReduceMotionEnabled` (UIKit) and degrade to instant or simple
crossfade. Cheap, and squarely on Apple's list for iOS 26.

**5. Fixed-size glyphs / hit targets to audit. [Quick win]**
36 uses of `.font(.system(size:))` for *glyphs* (chevrons, flags, the 22 pt
checkbox, the 10 pt ring count) don't scale with Dynamic Type. Body text scales,
so this is lower-severity, but at the largest accessibility sizes the controls
won't grow with the text. The checkbox button frame is **28×28 pt** — exactly
Apple's absolute minimum, fine but not generous; the editor's checkbox tap zone
and the collapse chevron should be spot-checked against 44×44.

### "Calm + accessible" — what it looks like for Lists

"Calm" and "accessible" are the same goal here, not a trade-off:

- **No strikethrough on done items** (Saxon's existing rule) is *good* for low
  vision — but that means done-ness is then carried by a tertiary-gray title +
  blue check. Make sure the **VoiceOver label says "completed"** and that the
  done state survives Increase Contrast (the tertiary gray must stay distinguishable).
- **Inline `#tags`** are plain text in a dusty purple-blue (`#6A84B8`) — a *custom*
  color, so it won't shift under Increase Contrast and tag-vs-body is color-only.
  Verify ~4.5:1 against the background, or add a non-color cue / ensure VoiceOver
  reads "tag: groceries."
- **Priority `!`/`!!`/`!!!`** is *already* the right pattern — it's a glyph, not a
  color-only pip, so it survives color blindness and reads naturally in VoiceOver.
  Keep it.
- **Calm motion** means honoring Reduce Motion (#4) — the linger fade is a lovely
  default *and* should collapse to instant when the user asked for less motion.
- A genuinely calm app is one a screen-reader user can move through without
  surprises: every row one focus stop with a clear label, actions on swipe-up,
  no empty/phantom focus stops (the editor cursor label, #1).

### On the iOS 26-only deployment target

This is a *help*, not a risk, for accessibility. By early 2026 iOS 26 sat at
≈64–66% of all active iPhones and ~74% of models from the last four years
(Apple/TelemetryDeck), in line with prior cycles — a normal, healthy base, not a
niche bet. iOS 26-only means Lists can rely on the **latest** accessibility and
SwiftUI APIs (modern accessibility modifiers, system Liquid Glass that auto-adapts
to Reduce Transparency/Increase Contrast) with no back-deployment caveats. No
action; just don't hand-roll anything the platform now gives you.

---

## Open questions / things to validate

- **Editor VoiceOver scope.** How far to go: a read-only spoken representation of
  rendered text (achievable) vs. fully navigable editing with VoiceOver (hard with
  a custom TextKit stack). Recommend validating the *minimum* that makes notes
  *readable* aloud first, before investing in editable-with-VoiceOver.
- **Contrast of the custom hues.** Measure `tagAccent` (#6A84B8), the soft-sky teal,
  slate grey, tan brown, and the urgent dusty red against light/dark backgrounds
  for 4.5:1 / 3:1. The semantic colors are safe; these five custom values aren't
  guaranteed.
- **Heatmap opacity levels under Increase Contrast.** `Heatmap.level1–4` are
  `accentColor.opacity(0.25…1.0)` — opacity steps may not be distinguishable at
  low vision; consider distinct hues/patterns or rely on the summary label.
- **VoiceOver pass on a device.** None of this is provable from static reading at
  the spoken level — a real VoiceOver walkthrough of Today, a list detail, a
  habit, and the editor is the validation step. (Repo's verification workflow is
  simulator + logs + ≤2 screenshots; VoiceOver specifically needs an on-device or
  Accessibility Inspector audit.)
- **Largest Dynamic Type sizes.** Verify `ItemRow` (checkbox title-center
  alignment, 2-line title, meta + tags) and the editor don't clip or overlap at
  the AX5 accessibility text sizes, given the fixed-size glyphs.

---

## Sources

- [Apple HIG — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) (via [sosumi.ai mirror](https://sosumi.ai/design/human-interface-guidelines/accessibility)) — hit-target 28/44 pt, contrast 4.5:1 & 3:1, 200% text, Reduce Motion, Increase Contrast, Differentiate Without Color, VoiceOver.
- [Apple HIG — Materials (Liquid Glass)](https://developer.apple.com/design/human-interface-guidelines/materials) (via [sosumi.ai mirror](https://sosumi.ai/design/human-interface-guidelines/materials)) — Liquid Glass adapts to Reduce Transparency / Increase Contrast; regular variant maintains legibility.
- [Supporting VoiceOver on Custom UIViews — Anurag Ajwani](https://anuragajwani.medium.com/supporting-voiceover-on-custom-uiviews-4b7d142b3477) — Apple-provided views support VoiceOver; custom views do not unless configured.
- [iOS Text Kit Basics — thoughtbot](https://thoughtbot.com/blog/ios-text-kit-basics) and [Recreating UITextView — uvolchyk](https://uvolchyk.medium.com/recreating-uitextview-part-i-9d95236b4366) — NSTextStorage/NSLayoutManager/drawGlyphs model behind the custom editor.
- [Using SwiftUI inside UICollectionView and UITableView — Appcircle](https://appcircle.io/blog/using-swiftui-inside-uicollectionview-and-uitableview) and [Handling Cell Interactions with UIHostingConfiguration — Swift Senpai](https://swiftsenpai.com/development/uihostingconfiguration-cell-interactions/) — UIHostingConfiguration auto-bridges SwiftUI `.swipeActions`; UIKit-layer actions are separate.
- [Preparing your App for VoiceOver: Accessibility Actions — Create with Swift](https://www.createwithswift.com/accessibility-actions/) — custom actions for multi-action rows; VoiceOver swipe-up/down behavior.
- [iOS 26: Reduce Transparency of Liquid Glass — MacRumors](https://www.macrumors.com/how-to/ios-reduce-transparency-liquid-glass-effect/) and [Liquid Glass iOS 26: Reduce Transparency — 3Zebras](https://3zebras.com/tech/liquid-glass-ios-26-customize-reduce-transparency/15386/) — what Reduce Transparency / Increase Contrast / Reduce Motion do to Liquid Glass; legibility complaints.
- [iOS 26 Adoption Reaches 74% on Recent iPhones, 66% Overall — iClarified](https://www.iclarified.com/99920/ios-26-adoption-reaches-74-on-recent-iphones-66-overall-chart) and [Daring Fireball — iOS 26 adoption in line with prior years](https://daringfireball.net/2026/02/apple_releases_ios_26_adoption_rates) and [TelemetryDeck iOS version share](https://telemetrydeck.com/survey/apple/iOS/majorSystemVersions/) — deployment-target adoption context.
