# Windows client stack — Lists

_Snapshot date: 2026-05-03. Author: research pass for the Windows client.
Companion to `00-current-state.md`, `android-stack.md`, `linux-stack.md`. Source
of truth for the contract every client must honour: `SPEC.md` §6 (data model),
§7 (storage), §15 (notifications)._

---

## 1. TL;DR

**Build the Windows client in C# 12 / .NET 9 with Avalonia 11.3 + FluentAvalonia 2.5.1.** Not WinUI 3, not MAUI, not Tauri. Avalonia gives a Win32-native window with Skia rendering, has working Mica/Acrylic on Windows 11, ships a Fluent control theme out of the box, has a single binary you can hand to `winget` as a portable EXE today and an MSIX/MSI tomorrow, and — critically for a solo dev — the same codebase can be redirected at the Linux client later with no second framework to learn. WinUI 3 would be the "obvious" pick, but its open-source rollout only finishes Q2 2026, its Native AOT story is still warning-laden, and it's the same XAML stack Microsoft has cycled through three rebrands in five years (UWP → UWP/WinUI 2 → WinUI 3 → ?). Avalonia is the bet that hedges against Microsoft's volatility while still letting you write idiomatic Fluent on Windows 11. Persistence: SQLite via `Microsoft.Data.Sqlite` (MIT, ADO.NET, no surprises); YAML via `YamlDotNet`; markdown via `Markdig`; toasts via the Windows App SDK's `AppNotificationManager` (callable from any Win32 app, packaged or not). **Min target: Windows 11 22H2** with best-effort fallback to Windows 10 22H2 for the ESU window through October 2026.

---

## 2. The hard part: choosing a UI framework on Windows in 2026

Windows is the most volatile UI platform Lists will ship on. In the last
seven years Microsoft has shipped or repositioned: **WPF**, **WinForms**,
**Silverlight (RIP)**, **UWP**, **WinUI 2**, **WinUI 3**, **MAUI**,
**Project Reunion → Windows App SDK**. Picking the wrong horse here is a
multi-month migration tax in two years.

The right way to grade these is on five axes that matter for a solo-maintained
local-first markdown app: **(a) maintenance risk** (will the framework still be
supported in 2028?), **(b) native-feel on Windows 11** (Mica, Acrylic, Segoe
UI Variable, NavView), **(c) deployment story** (signing, packaging, MSIX vs
portable, certificate cost), **(d) AGPL fit** (license of the framework + its
runtime distribution), **(e) cross-platform reuse** (will any of this also run
the Linux client?).

### 2.1 Side-by-side comparison

| Framework | License | Native feel on Win11 | Deployment | Dev experience | Ecosystem health (2026) | Last major | NativeAOT | Packaged size | Solo-maintainable? |
|---|---|:-:|---|---|---|---|:-:|---|:-:|
| **WinUI 3 / Windows App SDK** | MIT (open-sourcing in phased rollout, complete Q2/2026) | Best — native Mica/Acrylic, WinUI controls are Win11 controls | MSIX or unpackaged via Win App SDK; bootstrapper headache | XAML + C#; VS designer was deprecated, "XAML Studio" being open-sourced amid discontent | Active but Microsoft just officially open-sourced after a 17-month "is it dead?" period | Win App SDK 2.0, March 2026 | Supported since 1.6 but COM/WinRT trim warnings persist | ~30 MB self-contained + Win App SDK runtime | Yes, with caveats |
| **WPF** | MIT | Poor by default (no Mica/Acrylic without P/Invoke); themable to feel modern | Plain EXE, MSI, or MSIX | XAML + C#; mature tooling | Boring, mature, in maintenance | .NET 9 (Nov 2024) ongoing | Yes (.NET 8+) | ~25 MB self-contained | Yes |
| **WinForms** | MIT | Bad — unmistakably 2002 | Plain EXE / MSI | C# drag-and-drop, fastest hack-and-ship | In maintenance, "alive" | .NET 9 ongoing | Yes | ~20 MB | Wrong tool |
| **MAUI** | MIT | Mediocre; on Windows it's WinUI 3 underneath but plumbed through MAUI's abstractions | MSIX (no MSIXBUNDLE from VS), CLI required | Cross-platform mobile-first, awkward for desktop | **2026 has been brutal**: Q1 regressions, breaking changes between .NET 9 and 10, VS 2026 broken | .NET 10 (Nov 2025); 10.0.50/51 broke and patched same week | Partial | ~80 MB | **No — avoid** |
| **Avalonia 11** | MIT | Very good — Mica/Acrylic on Win11, Win32 native window, Fluent theme; FluentAvalonia adds the missing WinUI controls | Plain EXE, MSI, MSIX, all driven from `dotnet publish` | XAML + C# (or F#); Rider+Avalonia plugin or VS; Hot Reload | Used by JetBrains, Schneider Electric, Unity, GitHub; 30.3k★, 30k+ commits, last release May 2026 | 11.3.13 (May 2026); 12.0 in preview | Supported, ~18 MB AOT binary | ~25 MB self-contained / ~18 MB AOT | **Yes — top pick** |
| **Uno Platform** | Apache 2.0 | On Windows, it _is_ WinUI 3 (so excellent), or Skia on its own | MSIX / EXE; uses Win App SDK on Win desktop | XAML + C#, WinUI-API surface verbatim cross-platform | Active, 90M+ NuGet downloads, but Skia desktop renderer is newer than Avalonia's | Active 2026 releases | Yes (Windows AOT since 3.8) | ~30 MB | Yes |
| **Tauri 2.0** | MIT/Apache | Native window chrome + WebView2 (Chromium); UI feel is whatever HTML/CSS you write | MSI (WiX) or NSIS .exe; tiny binaries | Rust backend + web frontend; sharp learning curve if you don't already write web | Very active; v2 GA Oct 2024; v2.x throughout 2026 | Mid-2026 stable | N/A (Rust is AOT) | ~5–10 MB MSI (uses system WebView2) | Yes for a web-shaped UI |
| **Flutter desktop** | BSD-3 | Poor — Skia-rendered cross-OS look, doesn't match Win11 chrome at all | EXE / MSIX | Dart; same code as iOS/Android/macOS | Google support is slowing; desktop is "production" but feels like a port | Periodic | N/A (Dart AOT) | ~20 MB | Yes but wrong feel |
| **Slint (Rust)** | GPL/royalty/commercial tri-license | Custom-rendered, not native | Tiny EXE | Rust + .slint DSL | Active, stable 1.x | Active 2026 | Yes | ~10 MB | License conflict — see below |
| **GPUI (Zed's framework)** | Apache 2.0 _but_ "Zed has transparently abandoned GPUI as an open-source endeavour" per community. GPUI Component fork (gpui-component) is an alternative. | Custom-rendered | Tiny EXE | Rust | **Effectively orphaned by upstream** | n/a | Yes | ~10 MB | **No — abandoned** |
| **egui (Rust)** | MIT/Apache | Immediate-mode, looks like a tool not an app | Tiny EXE | Rust | Active but immediate-mode is wrong shape for a productivity app with persistent state and many panes | Active | Yes | ~8 MB | Wrong shape |
| **Native Win32 + Direct2D** | n/a | Pixel-perfect | Tiny EXE | C++ + COM, glacial dev velocity | Always alive | n/a | n/a | ~3 MB | **No — multi-month productivity loss** |
| **Electron** | MIT | Looks like a website pretending to be an app | NSIS/MSI; 100+ MB always | TypeScript + React | Active and dominant | Continuous | n/a | **150+ MB** | **No — violates project ethos** |

Sources for this table are listed in §13 — most rows have at least two
citations.

### 2.2 The verdict on each candidate

**WinUI 3 / Windows App SDK.** The "official" answer, and almost the right one.
What scares me away from picking it as the top recommendation:

- The framework was not open-source until **October 2025**, and the four-phase
  rollout to having GitHub be the primary development hub is **not complete
  until Q2 2026** — i.e. roughly _now_ as I write this. That's brand-new
  infrastructure ([Microsoft's own roadmap](https://github.com/microsoft/microsoft-ui-xaml/discussions/10700)).
- Native AOT on WinUI 3 is "supported since 1.6" but real-world reports show
  WinRT.Runtime trim warnings, COM-related AOT issues, and shipped-PDB bugs as
  recent as late 2024 ([dotnet/runtime#108087](https://github.com/dotnet/runtime/issues/108087)).
- The XAML designer in Visual Studio is still terrible, to the point that
  Microsoft just open-sourced "XAML Studio" in January 2026 because of
  developer discontent ([devclass](https://www.devclass.com/development/2026/01/07/microsoft-open-sources-xaml-studio-amid-developer-discontent-with-visual-studio-designers/4079573)).
- Your Linux client cannot reuse a single line. WinUI 3 is Windows-only.

That said: if Microsoft makes WinUI 3 actually-truly-open-source-and-stable by
EOY 2026, and Avalonia hits a wall with a feature we need, **switching from
Avalonia → WinUI 3 is a 4–8 week port** because the XAML dialects are 90%
overlapping (FluentAvalonia is literally a port of WinUI controls). The reverse
port would be similar. So this is not a one-way door.

**WPF.** Old, reliable, still actively maintained as part of .NET. Loses on
native-feel: Mica and Acrylic require P/Invoke into `DwmSetWindowAttribute`
and the result is non-trivial. There are community packages
(`WPF-UI`, `MaterialDesignInXamlToolkit`) that fill the Fluent gap, but
you're stitching two ecosystems together. Better than WinForms; worse than
Avalonia for a fresh build in 2026.

**WinForms.** Out. Wrong era for a markdown-native productivity app with
animated lists, swipe gestures, and Fluent surfaces.

**MAUI.** **Hard no.** The 2026 record is damning: Q1 had constant
regressions; 10.0.50 introduced a serious regression that was patched a week
later in a release that wasn't publicly available; VS 2026 development of
MAUI mobile apps is broken; and Windows publishing only emits MSIX (not
MSIXBUNDLE) from the IDE, requiring CLI workarounds
([Visual Studio Magazine](https://visualstudiomagazine.com/articles/2025/10/24/windows-11-update-borks-net-maui-projects-built-on-net-8-microsoft-what-have-you-done.aspx);
[dotnet/maui#34171](https://github.com/dotnet/maui/discussions/34171);
[xeladu medium](https://xeladu.medium.com/net-maui-released-as-stable-but-it-absolutely-isnt-735df7e14113)).
Solo dev cannot afford this volatility.

**Avalonia 11.** **Top pick.** See §3.

**Uno Platform.** Strongest runner-up. Honestly very close to Avalonia. The
distinguishing facts: Uno's Windows desktop story _uses Win App SDK / WinUI 3
under the hood_, which means Uno on Windows inherits the WinUI 3 risk profile
above. Their Skia desktop renderer (introduced relatively recently) is the
escape hatch but it's newer and less battle-tested than Avalonia's. Uno's API
parity with WinUI is a feature if you have an existing WinUI app to port; it's
neutral if you're greenfield. Avalonia's slightly more independent stance
(its own renderer, its own widget hierarchy, no WinUI runtime dependency) is
the safer hedge for a project that explicitly wants to **not** depend on
Microsoft picking the right horse.

**Tauri 2.0.** Real candidate, rejected as the primary because:

- The on-screen UI is still HTML/CSS/JS rendered through WebView2. To make it
  feel native on Windows 11 you re-implement Fluent in CSS, which is a project
  in itself, and you still don't get true Mica (you can fake it with
  `backdrop-filter` + `acrylic-window` crates but it's not the OS effect).
- WebView2 is a Microsoft component that gets installed/updated out-of-band
  by the user's machine; you're trading framework-volatility for
  browser-engine-volatility ([webview versions](https://v2.tauri.app/reference/webview-versions/)).
- It's the right answer for a different shape of app (Linear-style, web-first
  product). For a markdown reminders app modelled on Apple Reminders,
  HTML-in-Chromium is the wrong substrate.
- **However** — Tauri is the right pick if the team ever decides to also ship
  a web client and wants the SwiftUI/Avalonia/Tauri triplet to share a TS
  frontend. Worth re-evaluating at the v2 → v3 boundary.

**Flutter desktop.** Out. Skia-rendered cross-OS UI does not feel native on
Windows 11. The reminders app should look like Reminders, not like a Material 3
app pretending to be one.

**Native Win32 + Skia / Slint / GPUI / egui.** Slint has a tri-license that
includes a royalty/commercial tier and a GPL tier; the GPL tier is
**incompatible with AGPL-3.0-or-later** (you'd need a commercial Slint license
to combine with our AGPL code, defeating the purpose). GPUI is effectively
abandoned upstream. egui is immediate-mode, which is the wrong paradigm for
a stateful app with deeply-nested settings panels. Native Win32 + Direct2D is a
multi-month productivity hit a solo dev cannot absorb.

**Electron.** Explicitly out. The product spec says "local-first, lightweight,
no telemetry by default". Shipping a 150+ MB Chromium per-app for a markdown
reminders app is the opposite of that ethos. (To answer the prompt's request
to "confirm or push back": confirm. No reasonable scenario makes Electron the
right pick here.)

---

## 3. Recommendation: Avalonia 11 + .NET 9, Fluent on top

### 3.1 The stack at a glance

| Layer | Choice | Why this and not the alternative | License |
|---|---|---|---|
| Language | **C# 12 (.NET 9 LTS)** | Boring, stable, 9 is the latest LTS-track and Avalonia targets `net9.0`+. F# is workable but doesn't pay off in a UI-heavy app. | MIT (.NET runtime) |
| UI framework | **Avalonia 11.3** | Cross-platform, native window, Mica + Acrylic on Win11, Skia rendering, Fluent theme out of the box. Same codebase reusable on Linux. | MIT |
| Fluent controls | **FluentAvalonia 2.5.1** | NavigationView, TeachingTip, ContentDialog, InfoBar, FAComboBox, etc. — direct ports of the WinUI controls. Active maintainer (`amwx`). | MIT |
| Persistence (cache) | **`Microsoft.Data.Sqlite` 9.x** | ADO.NET provider, no ORM lock-in, MIT, in-tree with .NET. The cache is small and flat — we don't need EF Core's complexity tax. Use `Dapper` if a thin micro-ORM is wanted later. | MIT |
| YAML | **`YamlDotNet` 17.x** | The de-facto .NET YAML library, supports YAML 1.2 parsing, MIT, used by everyone. Match Yams's deterministic-key behaviour by writing the codec to enforce key order on emit. | MIT |
| Markdown rendering | **`Markdig` 0.40+** | CommonMark + extensions, has a built-in `UseYamlFrontMatter()` extension we can reuse for the body-vs-frontmatter split. Maintained by `xoofx` (Lunet, Scriban). | BSD-2 |
| Markdown rendering UI | **Markdig.Avalonia** or in-house Avalonia renderer | Markdig parses to AST; render to Avalonia controls for the detail view. For list-row inline previews, render to attributed runs only. | BSD-2 / MIT |
| File watching | **`FileSystemWatcher` + 30s polling sweep + index `mtime` reconcile on focus-gain** | Hybrid is the only production-grade approach (see §7). Don't even try OneDrive without a polling fallback. | n/a |
| Notifications | **`Microsoft.Windows.AppNotifications` (Win App SDK)** for desktop toasts, with `ToastNotificationManagerCompat` (Community Toolkit) as a fallback for unpackaged builds | The Win App SDK API is the modern path; the Community Toolkit version handles unpackaged scenarios automatically. The COM-server registration is automatic in both. | MIT |
| Alarms (urgent) | **Toast `scenario="urgent"` + `scenario="alarm"` + `audio loop="true"`** | Together these break through Focus Assist on Win11 22H2+ and loop the alarm sound until dismissed. See §5 for the full mapping. | n/a |
| Build | **`dotnet publish -r win-x64 --self-contained -p:PublishAot=false`** initially; AOT after MVP | NativeAOT on Avalonia works but takes more tuning (TrimmerRootAssembly, rd.xml, public ctors); ship without first, optimise later. | MIT |
| Testing | **xUnit + FluentAssertions + Moq** for unit/integration; **FlaUI** for smoke UI tests | xUnit is the .NET default; FlaUI is the actively-maintained UI Automation library after WinAppDriver was paused. | Apache/MIT |
| Packaging | **Portable EXE → MSI (WiX 4) → MSIX** | Ship portable EXE on day one (`winget` accepts portable manifests); add MSI for power users; add MSIX once Azure Trusted/Artifact Signing is set up. | n/a |
| Distribution | **GitHub Releases (primary), `winget`, `Scoop`, `Chocolatey`; Microsoft Store later** | All four manifest formats are easy to maintain from one EXE/MSI. Store comes after MSIX is signed. | n/a |
| Code signing | **Azure Artifact Signing** (formerly Trusted Signing) | The cheap-and-correct path for a solo dev — no $400+/yr cert required, identity-based reputation that accumulates across builds. | n/a |
| File-system root | **`%USERPROFILE%\Documents\Lists\`** with prominent first-run notice about OneDrive Files-on-Demand caveats | User-visible, syncable for free, matches iOS's iCloud Drive shape. See §6. | n/a |

### 3.2 Why Avalonia, in one paragraph the user can repeat to a sceptic

Microsoft has shipped four UI strategies in five years. Avalonia is run by a
small dedicated team, has been MIT and stable for nine years, ships `dotnet
publish`-friendly binaries with no per-platform packaging project, supports
Mica and Acrylic on Windows 11, has a working Fluent control library
(FluentAvalonia, by a single dedicated maintainer for four years), and the
same codebase will run the Linux client. JetBrains ships every IDE on it.
Picking Avalonia is the answer that survives the next Microsoft pivot.

---

## 4. Alternatives considered

### 4.1 Alternative A: WinUI 3 + Windows App SDK + .NET 9

| Layer | Choice |
|---|---|
| Language | C# 12 / .NET 9 |
| UI framework | WinUI 3 / Windows App SDK 2.x |
| Persistence | `Microsoft.Data.Sqlite` |
| YAML | `YamlDotNet` |
| Markdown | `Markdig` |
| File watching | `FileSystemWatcher` + polling fallback (same as primary) |
| Notifications | `Microsoft.Windows.AppNotifications.AppNotificationManager` (native, no compat shim) |
| Alarms | Toast `scenario="urgent"` + `scenario="alarm"` |
| Build | `dotnet publish` + Win App SDK packaging project (or unpackaged) |
| Testing | xUnit + FlaUI |
| Packaging | MSIX (signed) or unpackaged self-contained |
| Distribution | Microsoft Store (MSIX) + GitHub Releases (unpackaged ZIP) + winget |

**Why rejected as primary, but kept as a viable port target:**

- WinUI 3 only has the most native Win11 feel of any option — Mica, Acrylic,
  Segoe UI Variable, NavigationView are all literally the OS's controls.
  That's a real win.
- But the four-phase open-source rollout doesn't complete until **Q2 2026**;
  the AOT story has open trim warnings; the XAML designer is so bad
  Microsoft just open-sourced "XAML Studio" in response to dev backlash; and
  it won't reach Linux ever.
- For a solo dev who needs the Linux client to share code, the calculus
  flips toward Avalonia. **Reconsider this stack at the next major version
  bump** (e.g., if Avalonia stalls or if WinUI 3 ships a credible designer
  in Visual Studio 2027).

### 4.2 Alternative B: Tauri 2.0 + Rust core + Svelte/SolidJS

| Layer | Choice |
|---|---|
| Language | Rust (backend) + TypeScript (frontend) |
| UI framework | Tauri 2.0 (WebView2) + Svelte/SolidJS + Tailwind |
| Persistence | `rusqlite` |
| YAML | `serde_yaml` |
| Markdown | `pulldown-cmark` |
| File watching | `notify` crate (Rust's idiomatic FileSystemWatcher wrapper) |
| Notifications | `tauri-winrt-notification` crate (WinRT toast wrapper) or `tauri-plugin-notifications` (cross-platform) |
| Alarms | Same WinRT toast XML, scenario="urgent" + audio loop |
| Build | `cargo tauri build` → MSI via WiX or NSIS |
| Testing | `cargo test` + Playwright for the WebView |
| Packaging | MSI (WiX) or NSIS .exe, ~5–10 MB with WebView2 bootstrapper |
| Distribution | GitHub Releases + winget (single-EXE), Microsoft Store (MSI) |

**Why rejected:**

- The UI doesn't feel native. To approximate Win11 Fluent in HTML/CSS you
  rebuild the parts of the design system you use (NavView, ContextMenu,
  RippleEffect, Reveal). Real Mica via `backdrop-filter` is approximate.
- WebView2 is an external runtime; if the user doesn't have it,
  the installer must download and install it (Tauri can embed the
  bootstrapper at +1.8 MB or the offline installer at +180 MB).
- The product is not web-shaped. Reminders is a stateful, Fluent-laden,
  list-heavy productivity app; Linear-shaped or Notion-shaped products are
  what Tauri excels at.
- **However** — if the project ever ships a web client, revisit this. The
  Tauri shell + the same web frontend would amortise web client work onto
  every desktop OS for free.

### 4.3 Alternative C: WPF + WPF-UI (FluentWPF)

| Layer | Choice |
|---|---|
| Language | C# 12 / .NET 9 |
| UI framework | WPF + WPF-UI 3.x for Fluent surfaces |
| Persistence | `Microsoft.Data.Sqlite` |
| YAML | `YamlDotNet` |
| Markdown | `Markdig` |
| File watching | `FileSystemWatcher` + polling |
| Notifications | `Microsoft.Toolkit.Uwp.Notifications` (Community Toolkit, the older API) |
| Alarms | Same WinRT toast XML |
| Build | `dotnet publish -r win-x64` |
| Testing | xUnit + FlaUI |
| Packaging | MSI (WiX) or MSIX |
| Distribution | GitHub Releases + winget + Store (MSIX) |

**Why rejected:**

- WPF is rock-solid and you'd ship faster on day one because the tooling is
  the most mature of any option here, but you'd be signing up to lay Mica
  and Acrylic on top of a framework that wasn't designed for them, with
  P/Invoke into `DwmSetWindowAttribute` for every window. WPF-UI papers
  over a lot of this but the seams show.
- WPF is Windows-only. No Linux reuse.
- WPF is in maintenance mode at Microsoft. Avalonia is in active forward
  development with a 12.0 preview shipping. Maintenance mode is fine for
  enterprise apps; for a fresh greenfield in 2026, picking the framework
  with positive momentum is the cheaper long-term call.

---

## 5. Notification + alarm mapping

The iOS reference model:

| iOS construct | When |
|---|---|
| `UNUserNotificationCenter` notification | `has_time && !urgent` |
| `AlarmKit` alarm | `has_time && urgent` (scheduled to break through Focus, loop sound until dismissed) |

The Windows mapping:

| Behaviour | Windows construct (Win App SDK) | Notes |
|---|---|---|
| Plain reminder at a time | `AppNotificationBuilder` with `SetScenario(AppNotificationScenario.Reminder)` | Toast with default sound, persists in Action Center, dismissed on click |
| Urgent reminder ("break-through-Focus") | `AppNotificationBuilder.SetScenario(AppNotificationScenario.Urgent)` if `IsUrgentScenarioSupported()` returns true (Win11 22H2+) | This is the documented break-through-Focus-Assist scenario |
| Alarm — looping sound until user dismisses | `SetScenario(AppNotificationScenario.Alarm)` + `<audio src="ms-winsoundevent:Notification.Looping.Alarm" loop="true"/>` in the toast XML | Required scenario for a looping audio toast — without `scenario="alarm"`, `loop="true"` is ignored. Toast persists with snooze/dismiss buttons. Requires Win10 build 17763+ |
| Combined: urgent + alarm | Set scenario to `Urgent` _or_ `Alarm` (mutually exclusive); for our "urgent && has_time" case, pick **`Alarm`** because it's the one that loops audio. The break-through-Focus behaviour comes from the user setting our app as a "Priority App" in Focus settings | A v1 first-run UX must explain "to ensure your urgent reminders fire even in Do Not Disturb, add Lists to Priority Apps in Focus settings" — Microsoft does not let apps grant themselves this |
| Snooze | Toast XML `<action ... arguments="snooze" hint-inputId="snoozeTime"/>` | Built-in snooze-with-time-picker; we just receive the activation arg |
| Dismiss | Toast XML `<action ... arguments="dismiss"/>` | Same |
| Background firing when app is closed | App must be registered as a COM server for `AppNotificationManager` to be reachable when the app isn't running. `ToastNotificationManagerCompat` does this automatically; the Win App SDK API requires you to do it explicitly | This is mandatory. Without it, scheduled toasts past the next launch don't fire |
| Scheduled delivery while computer is off | **5-minute delivery window** — if the PC is asleep/off at scheduled time + 5 min, the toast is dropped | For guaranteed delivery use a Background Task with a Time Trigger, also part of Win App SDK |

### Focus Assist / Do Not Disturb behaviour, in plain language

Windows 11 calls it **Do Not Disturb**; Win10 calls it **Focus Assist**. Same
mechanism. Two ways to break through:

1. **Be in the Priority Apps list** (set by the user in Settings → System →
   Notifications → Set priority notifications). Apps cannot self-add. The
   first-run flow should walk the user through it.
2. **Use scenario="urgent" or scenario="alarm" or scenario="incomingCall"**
   — these scenarios are documented as breaking through DND when the app is
   on the priority list. Without the user adding you to the priority list,
   the scenario alone is not guaranteed; Microsoft's docs are deliberately
   ambiguous about how strict this is and the answer has changed across
   Win11 builds.

The pragmatic implementation:

- For `urgent && has_time`: use `scenario="alarm"` (so audio loops) and
  prompt the user once on first urgent-reminder creation to add Lists to
  Priority Apps. Don't nag.

### Visibility into the post-Win11 Notifications panel

Windows 11 22H2+ replaced "Action Center" with a unified panel. Toasts persist
there if the toast XML includes `Toast > Visual > Binding` content (default).
The panel respects the user's per-app sort/group settings, so we don't need
extra plumbing. The notification's tag/group, set via
`AppNotificationBuilder.SetTag()` / `.SetGroup()`, lets us update or clear an
existing toast (e.g., remove the toast when the reminder is completed in
another window).

---

## 6. Storage layout — where on disk?

iOS puts the tree at `~/Documents/Lists/` so iCloud Drive picks it up for
free. Windows needs the equivalent answer.

**Recommendation: `%USERPROFILE%\Documents\Lists\`** (default `C:\Users\<user>\Documents\Lists\`).

| Trade-off | `%USERPROFILE%\Documents\Lists\` | `%LOCALAPPDATA%\Lists\` (app-private) |
|---|---|---|
| User-visible / discoverable | **Yes** — they can open it in Explorer, see their notes | No — hidden by default |
| Syncable via OneDrive Known Folder Move | **Yes** (when KFM is on, Documents is auto-redirected to `OneDrive\Documents\Lists\`) | No without extra plumbing |
| Syncable via Dropbox / Drive / iCloud-for-Windows | **Yes** if user manually places `Documents\Lists` inside their sync folder, or symlinks it | No |
| Reset-on-uninstall expectation | User won't expect their notes to vanish on uninstall — Documents is the "right" place | Common app expectation but wrong for user-owned content |
| Subject to Win11 Controlled Folder Access (ransomware protection) | Sometimes, depending on user setup; we may need to be added as an allowed app | No — `LOCALAPPDATA` is unprotected |
| OneDrive Files-on-Demand interaction | **Yes — this is the gotcha** (see below) | No |

### The OneDrive Files-on-Demand gotcha

When OneDrive is set to "save space" (Files-on-Demand), files in
`Documents\Lists\` may be **placeholders** with the `Offline` /
`RECALL_ON_DATA_ACCESS` NTFS attribute. Reading the file triggers
**hydration** — a synchronous network fetch — and the first read can take
seconds. Multiply that by walking the entire tree on launch to rebuild the
index, and the app freezes for minutes on first launch on a sync'd machine.

Mitigation:

- On the index rebuild walk, **check the `FileAttributes.Offline` flag and
  skip files that are not hydrated**. Their `mtime` is still readable
  cheaply (it's in the directory entry, not the file body), so we can
  diff-check them without forcing a download. Only hydrate when the user
  opens or interacts with that reminder.
- Document this prominently in Settings: "files marked online-only in
  OneDrive will not appear in search until you open them. Tip: Right-click
  the Lists folder in Explorer → Always keep on this device".
- The Cloud Filter API ([Microsoft docs](https://learn.microsoft.com/en-us/windows/win32/cfapi/build-a-cloud-file-sync-engine))
  is the official-but-heavy way to be a first-class citizen of the
  placeholder system. Out of scope for v1.

### The KFM-redirect surprise

Some users have Known Folder Move turned on by their org, which transparently
redirects `%USERPROFILE%\Documents` to `OneDrive\Documents`. This is fine for
us — the path the app sees doesn't change. The implications are:
- The folder is on OneDrive, with all the sync caveats above.
- File watching on a OneDrive-backed folder is less reliable than on local
  disk (see §7).

The first-run UX should display the resolved path (`Settings → Storage`
shows the actual folder) so users with KFM understand where their files
live.

---

## 7. File watching

`System.IO.FileSystemWatcher` is famously flaky. The honest summary:

- It is a thin managed wrapper over the Win32 `ReadDirectoryChangesW` API.
  Its problems are inherited from that API, not introduced by .NET.
- **Buffer overflow** under bursts: the default 8 KB internal buffer
  overflows quickly when many files change at once. Increase to 64 KB
  (`InternalBufferSize = 65536`). Even then, on a "Sync Now" of OneDrive
  with hundreds of changed files, you _will_ miss events.
- **Network shares / OneDrive / mounted drives**: notifications are
  unreliable. Microsoft's own docs effectively say "polling required for
  reliability" on these surfaces.
- **Renames and moves**: `FileSystemWatcher` reports them as separate
  Delete + Create events in many cases, losing the link.

### Production-grade approach

**Hybrid: FileSystemWatcher + periodic reconcile + on-focus reconcile.**

```
Layer 1 — FileSystemWatcher (real-time):
  - 64 KB internal buffer
  - Watches Documents\Lists\ recursively
  - Filter: *.md, *.yml only
  - Subscribes to Created, Changed, Deleted, Renamed
  - On Error event (buffer overflow): trigger a full reconcile
  - Coalesces events with a 250ms debounce window per path

Layer 2 — Polling reconcile (safety net):
  - Every 30 seconds while app is foreground
  - Every 5 minutes while app is background
  - Walks the tree, compares `mtime` against the SQLite cache,
    re-parses any mismatched files
  - Cheap because we only `stat()`, we don't read file bodies for
    unchanged files

Layer 3 — Focus-gain reconcile:
  - When the app window becomes active after losing focus, run an
    immediate Layer 2 sweep
  - Catches "I edited a reminder file in VS Code while the app was
    in the background" cases

Layer 4 — Cold-launch reconcile:
  - Always do a full Layer 2 sweep on app startup
  - This is the same algorithm SPEC §7 calls for
```

Libraries to consider for layer 1:

- Stick with **`System.IO.FileSystemWatcher`** as the primary. Don't bring
  in third-party watchers (`MiniFSWatcher`, `EaseFilter`) for v1 — they
  solve narrower problems (rename tracking, kernel-mode filtering) we don't
  need if we have the polling safety net.
- If we hit a wall (e.g., move detection becomes critical), the
  `MiniFSWatcher` package by CenterDevice is the lightest credible upgrade.

`Microsoft.Extensions.FileProviders.PhysicalFileProvider.UsePollingFileWatcher`
is a built-in option in .NET that switches the same API to polling under
the hood, and is meant exactly for this — easy to A/B test.

---

## 8. Shared Rust core verdict

**Verdict: No shared Rust core for Windows.** Pure C#.

Why:

- The shared-core argument is strongest when the parser logic is complex
  and the cost of re-implementing it across N platforms exceeds the
  FFI integration cost. For Lists the parser is **YAML frontmatter
  + a small RRULE subset + a ULID generator + a SQLite cache writer**.
  These are all trivially small in C#.
- C# bindings to Rust via P/Invoke involve writing manual marshalling
  for every type that crosses the boundary. For a YAML object graph this
  is more annoying than just reading the file in C#.
- `YamlDotNet` is the de-facto .NET YAML library, used by everything from
  Azure DevOps to Kubernetes tools. It's not the bottleneck.
- **Counter-argument addressed**: "But you'll have four parsers (Swift,
  Kotlin, C#, Rust)." Yes — and they're each ~200 LOC of declarative
  field-mapping plus a few validators. The marginal cost of a fifth or
  sixth platform is minutes, not hours. The bug surface (each parser
  reading the same YAML differently) is real, and the answer is **a shared
  YAML test corpus** under `shared/fixtures/` that every platform's tests
  load and assert against. That's where the consistency contract lives.

If a future complex piece (RRULE expander, smart-list query engine,
shopping lexicon classifier) becomes load-bearing across platforms,
extract _that piece_ to Rust + FFI and ship it as a NuGet/Maven/Pod
side-by-side. Don't preemptively force everything through FFI.

The Tauri alternative in §4 is the only branch where Rust core makes
strategic sense, and that's because the UI is also web — the Rust core
amortises across all OSes _and_ Linux _and_ a future web client. Outside
the Tauri branch, Rust is a tax.

---

## 9. Build / packaging / distribution

### 9.1 Build pipeline

```
GitHub Actions, single workflow:
  job: build-windows
    runs-on: windows-latest
    steps:
      - dotnet restore
      - dotnet build -c Release
      - dotnet test -c Release
      - dotnet publish -c Release -r win-x64 --self-contained true \
          -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
      - sign the EXE via Azure Artifact Signing
      - package: zip the publish folder for "portable" download
      - package: WiX 4 -> .msi for IT-friendly install
      - package: MSIX (Win App SDK packaging tool) for Microsoft Store
      - upload all three to GitHub Releases
      - update winget/Scoop/Chocolatey manifests in their respective repos
```

### 9.2 Cross-compile from macOS/Linux?

The relevant facts:

- `dotnet publish -r win-x64` from a Mac produces a working Windows EXE
  for self-contained, **non-AOT** builds. Tested in mainline .NET CI for
  years.
- **Native AOT cannot cross-compile** between OS families. There is no
  Windows SDK distribution for macOS/Linux. AOT-compiled Windows binaries
  must be built on Windows.
- MSIX packaging requires Windows-only tooling
  (`makeappx`, `signtool`) — also no Mac/Linux path.
- WiX 4 has a .NET tool that runs cross-platform, so MSI generation
  _can_ be done from a Mac for the unsigned package; signing must happen
  on Windows.

**Practical answer for a solo dev on a Mac**: use a free GitHub Actions
runner with `windows-latest` for all Windows artefact production. Local Mac
dev can run `dotnet build` and `dotnet test` (logic tests) but needs a
Windows VM (Parallels, UTM, free GitHub Actions VM) for actually launching
and clicking through the Avalonia app on Windows. Avalonia has an
"`AvaloniaPreviewer`" XAML preview that helps reduce the round-trip but it
isn't a substitute for actually running on the target.

### 9.3 Distribution surfaces

| Surface | Format | Audience | Signing required | Setup cost |
|---|---|---|---|---|
| GitHub Releases (portable ZIP) | `.zip` of self-contained publish folder | Devs, power users | Optional (SmartScreen warns either way) | Free |
| GitHub Releases (MSI) | `.msi` from WiX 4 | Power users, IT | Strongly recommended | Free + signing cost |
| `winget` (`Microsoft.WinGet`) | Manifest pointing at GitHub Release MSI or portable EXE | All users via `winget install` | Yes for MSI; optional for portable | One PR per release to `microsoft/winget-pkgs` |
| Scoop | Bucket manifest pointing at GitHub Release ZIP | Devs, terminal users | Optional | One PR to a bucket repo |
| Chocolatey | `.nuspec` packaging the install script | IT, enterprise | Recommended | Maintainer onboarding required |
| Microsoft Store | MSIX | Mainstream users | **Required** + Partner Center account ($19 individual, $99 company) | High one-time |

The recommended order:

1. **v0.1 (closed alpha)** — portable ZIP on GitHub Releases, signed with
   Azure Artifact Signing. SmartScreen will warn until reputation
   accumulates; that's normal.
2. **v0.5 (open beta)** — add MSI and `winget` manifest.
3. **v1.0** — add Scoop and Chocolatey manifests.
4. **v1.x** — pursue Microsoft Store with MSIX, only if it's worth the
   continual review pain. A Store presence helps discoverability for a
   reminders app.

### 9.4 Code signing — the cheap path

Azure Artifact Signing (renamed from Trusted Signing in 2026) is the right
answer for a solo developer:

- No upfront $400+/yr EV cert. Pay-as-you-go via Azure
  (~a few dollars per month for low signing volume).
- Reputation is **identity-based**, accumulated across builds; no cert
  rotation pain because Azure rotates the underlying cert daily.
- Integrates with `signtool.exe` and GitHub Actions
  (`Azure/trusted-signing-action`).
- Works for both EXEs and MSIX.

If a signing budget is genuinely zero, a self-signed cert is acceptable for
the portable ZIP audience but **will not work for MSIX or Microsoft Store**.

---

## 10. Testing

A minimal, opinionated stack:

| Layer | Tool | Why |
|---|---|---|
| Unit tests | **xUnit** | The .NET standard. NUnit is fine but xUnit's parallelism defaults are better. MSTest is fine but inferior conventions. |
| Assertions | **FluentAssertions** | Reads better, points at the right line on failure. |
| Mocks | **NSubstitute** (or Moq, but NSubstitute survived the recent Moq controversy with cleaner conscience) | `_mock.GetReminder("x").Returns(reminder)` reads naturally. |
| Integration tests | xUnit + a temp directory + the real `FileStore` actor | We have a clean storage contract; test the real codec end-to-end. |
| UI smoke tests | **FlaUI** with UIA3 | After `WinAppDriver` was paused, FlaUI is the actively-maintained .NET UI Automation library. Strongly typed, abstractions for elements/patterns. |
| UI cross-platform driver (if reused on Linux) | **FlaUI.WebDriver** (W3C WebDriver implementation over UIA) | Lets us write Appium-style tests that we could repoint at Linux later via a different driver |
| Coverage | `coverlet` + `reportgenerator` | Standard pipeline. |

Don't reach for anything else for v1. Two test projects max:
`Lists.Core.Tests` (logic) and `Lists.Windows.UI.Tests` (smoke).

---

## 11. First-month gotchas

A non-exhaustive list of the things that will eat time the first month:

| Gotcha | What goes wrong | Pre-emptive workaround | URL |
|---|---|---|---|
| Packaged-vs-unpackaged distinction | `ToastNotificationManager` throws "element not found" in unpackaged apps; you _must_ use `ToastNotificationManagerCompat` (Community Toolkit) or the Win App SDK's `AppNotificationManager` (which handles both) | Use `Microsoft.Windows.AppNotifications` from day one; never touch `ToastNotificationManager` directly | [Quickstart](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/toast-desktop-apps) |
| MSIX certification quirks | Can't reproduce on dev machine; auto-update only works from Store/sideload-allowed channels | Stay unpackaged or use sparse-package (External Location) for updates outside the Store | [Distribute unpackaged WinUI 3](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/unpackage-winui-app) |
| Toast `audio loop="true"` only works with `scenario="alarm"` | Without the scenario, audio plays once. Easy to miss in docs | Always set scenario explicitly when constructing urgent toasts | [Toast schema](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/toast-schema) |
| Scheduled toast 5-minute delivery window | If PC is off > 5 min after scheduled time, the toast is dropped | Use a Background Task with Time Trigger for guaranteed delivery; for v1 ship without and document the limitation | [Scheduled toast](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/scheduled-toast) |
| AppContainer file-system restrictions | Packaged apps can't write outside their own data folders without `broadFileSystemAccess` capability + user consent | Stay unpackaged for v1 to avoid the consent flow; revisit at Store launch | [Packaging overview](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/packaging/) |
| OneDrive Files-on-Demand causes index walk to hang | `File.ReadAllText` on a placeholder hydrates synchronously and can take seconds | Check `FileAttributes.Offline` before reading; skip + mark for lazy hydration | [Cloud Files API](https://learn.microsoft.com/en-us/windows/win32/cfapi/build-a-cloud-file-sync-engine) |
| Windows Controlled Folder Access blocks writes | Writes to `Documents` may be silently rejected if user has CFA on and we're not allowlisted | Detect on first save, prompt with instructions to add Lists as allowed | [Windows Defender CFA](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/controlled-folders) |
| AOT compilation issues with Avalonia reflection | Bindings disappear at runtime | TrimmerRootAssembly + rd.xml + public ctors on all Views; ship without AOT for MVP | [Avalonia Native AOT](https://docs.avaloniaui.net/docs/deployment/native-aot) |
| `FileSystemWatcher` buffer overflow under load | Silent missed events | 64 KB buffer + polling fallback (§7) | [MS Learn FSW](https://learn.microsoft.com/en-us/dotnet/api/system.io.filesystemwatcher) |
| Win App SDK runtime distribution | Self-contained vs framework-dependent affects size and AppContainer behaviour | Self-contained for portable, MSIX-bundled for Store | [Packaged/Unpackaged/Self-Contained](https://nicksnettravels.builttoroam.com/packaged-unpackaged-self-contained/) |
| SmartScreen "unrecognized app" warning | New EXE without reputation always shows the warning until enough installs | Sign with Azure Artifact Signing; reputation accrues to identity not cert | [Trusted Signing setup](https://weblog.west-wind.com/posts/2025/Jul/20/Fighting-through-Setting-up-Microsoft-Trusted-Signing) |

---

## 12. AGPL on Windows specifically

### 12.1 The .NET runtime question

Concern: AGPL-3.0-or-later is a strong copyleft. Does linking against
`Microsoft.WindowsAppSDK`, `Microsoft.Data.Sqlite`, `Avalonia`, etc.
contaminate distribution?

Answer: **No, with the standard reasoning.**

- The .NET runtime, Avalonia, FluentAvalonia, YamlDotNet, Markdig,
  `Microsoft.Data.Sqlite`, and `Microsoft.WindowsAppSDK` are all **MIT or
  Apache 2.0** licensed. MIT and Apache 2.0 are explicitly compatible with
  AGPL-3.0 in the FSF's compatibility matrix.
- AGPL applies to _our_ code; we ship it under AGPL-3.0-or-later. Users
  receiving the binary can request the source for our application code,
  which is on GitHub. The MIT/Apache 2.0 dependencies remain under their
  original licenses.
- The .NET runtime team explicitly maintains a permissive-licensing policy
  (MIT/BSD only) so that downstream consumers like us don't run into
  unexpected GPL contamination from the runtime itself.

The single AGPL-incompatibility risk in the candidate set is **Slint**'s
GPL/commercial dual-license. We do not pick Slint — confirmed in §2 — so
this is moot for the recommended stack.

### 12.2 The Microsoft Store question

Concern: Apple's App Store has historically been hostile to GPL/AGPL apps
(VLC famously pulled). Does Microsoft Store do the same?

Answer: **No. Microsoft Store explicitly allows open-source apps including
copyleft, and reversed a brief 2022 attempt to ban paid OSS.**

Key facts:

- In July 2022 Microsoft proposed banning developers from selling open-source
  software in the Store. After community pushback, **Microsoft removed that
  policy and explicitly clarified that paid open-source apps are allowed,
  provided they're listed by their original developer or someone with
  appropriate rights**.
- The Microsoft Store policy does not single out GPL/AGPL. The current
  posture is "open source apps are welcome, listed by the original
  developer".
- The mechanical reason Apple's stance was hostile to GPL is the App Store
  Terms restricting redistribution — Microsoft Store's terms are less
  restrictive on this point. There is no reported case of Microsoft pulling
  an AGPL app for license reasons.

The practical implication for Lists:

- We can list the Lists app on Microsoft Store under AGPL-3.0-or-later.
- We must list it ourselves (saxonbobart) — third parties republishing our
  AGPL'd app to the Store would be a Store-policy violation _separate from_
  any AGPL question.
- We do not need to add a Store-specific license exception (unlike the iOS
  App Store, which the SPEC §17 plans for).

### 12.3 The runtime distribution edge case

If we ship as **self-contained** (the .NET runtime is bundled into our EXE),
we are technically distributing third-party software (the runtime). The MIT
license requires us to include the upstream copyright notice. Avalonia,
FluentAvalonia, Markdig, YamlDotNet, etc. all have the same requirement.

Implementation: ship a `Licenses.txt` (or `Settings → About → Licenses`) in
the app that includes the MIT/Apache 2.0 notices for every bundled
dependency. Standard practice; no AGPL-specific friction.

---

## 13. Sources

### Microsoft official

- [WinUI 3 — Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/)
- [Windows App SDK roadmap](https://github.com/microsoft/WindowsAppSDK/blob/main/docs/roadmap.md)
- [microsoft-ui-xaml roadmap](https://github.com/Microsoft/microsoft-ui-xaml/blob/main/docs/roadmap.md)
- [WinUI OSS Phased Rollout discussion](https://github.com/microsoft/microsoft-ui-xaml/discussions/10700)
- [App notification content schema](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/toast-schema)
- [App notification content (adaptive/interactive toasts)](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/adaptive-interactive-toasts)
- [Quickstart: Send and Handle App Notifications](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/toast-desktop-apps)
- [Schedule an app notification](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/scheduled-toast)
- [Toast audio options catalog](https://learn.microsoft.com/en-us/previous-versions/windows/apps/hh761492(v=win.10))
- [Native AOT deployment overview](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
- [Native AOT cross-compilation limits](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/cross-compile)
- [`Microsoft.Data.Sqlite` overview](https://learn.microsoft.com/en-us/dotnet/standard/data/sqlite/)
- [Comparison to System.Data.SQLite](https://learn.microsoft.com/en-us/dotnet/standard/data/sqlite/compare)
- [Build a Cloud Sync Engine that Supports Placeholder Files (CFAPI)](https://learn.microsoft.com/en-us/windows/win32/cfapi/build-a-cloud-file-sync-engine)
- [Set Files On-Demand states in Windows](https://learn.microsoft.com/en-us/sharepoint/files-on-demand-windows)
- [Redirect and move Windows known folders to OneDrive (KFM)](https://learn.microsoft.com/en-us/sharepoint/redirect-known-folders)
- [`FileSystemWatcher` API reference](https://learn.microsoft.com/en-us/dotnet/api/system.io.filesystemwatcher?view=net-10.0)
- [`PhysicalFileProvider.UsePollingFileWatcher` property](https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.fileproviders.physicalfileprovider.usepollingfilewatcher)
- [FileSystemWatcher Follies (MS blog)](https://blogs.msdn.microsoft.com/winsdk/2015/05/19/filesystemwatcher-follies/)
- [Sign your MSIX package — end-to-end guide](https://learn.microsoft.com/en-us/windows/msix/package/sign-msix-package-guide)
- [Trusted/Artifact Signing — signing integrations](https://learn.microsoft.com/en-us/azure/artifact-signing/how-to-signing-integrations)
- [Trusted Signing client tools (winget)](https://winstall.app/apps/Microsoft.Azure.TrustedSigningClientTools)
- [Distribute an unpackaged WinUI 3 app](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/unpackage-winui-app)
- [Packaging overview — Win apps](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/packaging/)
- [.NET MAUI support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/maui)
- [Troubleshoot known issues — .NET MAUI](https://learn.microsoft.com/en-us/dotnet/maui/troubleshooting?view=net-maui-10.0)
- [Windows 10 support has ended (October 2025)](https://support.microsoft.com/en-us/windows/windows-10-support-has-ended-on-october-14-2025-2ca8b313-1946-43d3-b55c-2b95b107f281)
- [Windows 10 22H2 ESU through October 2026](https://learn.microsoft.com/en-us/windows/whats-new/extended-security-updates)
- [Windows 11 system requirements](https://support.microsoft.com/en-us/windows/windows-11-system-requirements-86c11283-ea52-4782-9efd-7674389a7ba3)
- [Modernize your UWP app with .NET 9 and Native AOT](https://devblogs.microsoft.com/ifdef-windows/preview-uwp-support-for-dotnet-9-native-aot/)

### Avalonia & FluentAvalonia

- [Avalonia UI homepage](https://avaloniaui.net/)
- [Avalonia UI for Windows](https://avaloniaui.net/avalonia/windows)
- [Avalonia docs — Windows platform guide](https://docs.avaloniaui.net/docs/platform-specific-guides/windows)
- [Avalonia docs — Native AOT](https://docs.avaloniaui.net/docs/deployment/native-aot)
- [Avalonia docs — Release notes](https://docs.avaloniaui.net/docs/stay-up-to-date/release-notes)
- [Avalonia GitHub repo](https://github.com/AvaloniaUI/Avalonia) — 30.3k stars, last release May 2026
- [Avalonia 11 release announcement (devclass)](https://devclass.com/2023/07/10/avalonia-11-released-cross-platform-framework-gets-new-renderer-plus-ios-and-android-support/)
- [Avalonia Mica support PR (`adirh3`)](https://github.com/AvaloniaUI/Avalonia/pull/12196)
- [FluentAvalonia GitHub](https://github.com/amwx/FluentAvalonia)
- [FluentAvaloniaUI 2.5.1 NuGet](https://www.nuget.org/packages/FluentAvaloniaUI)
- [FluentAvalonia docs](https://amwx.github.io/FluentAvaloniaDocs/)
- [DevToys — cross-platform via Uno (case study)](https://devtoys.app/blog/the-journey-to-devtoys-2.0)
- [Avalonia Native AOT deployment on Windows (DEV)](https://dev.to/chuongmep/avaloniaui-native-aot-deployment-on-windows-2jg1)
- [How to reduce AOT file size — Avalonia discussion](https://github.com/AvaloniaUI/Avalonia/discussions/14219)
- [Avalonia case study — Fluent Search](https://avaloniaui.net/blog/case-study-fluent-search)

### Uno Platform

- [How Uno's UI layer works: WinUI to Native](https://platform.uno/articles/how-uno-platforms-ui-layer-works-winui-to-native/)
- [WinUI 3 and Uno Platform](https://platform.uno/docs/articles/uwp-vs-winui3.html)
- [Best Cross-Platform Frameworks 2026](https://platform.uno/articles/best-cross-platform-frameworks-2026/)
- [The .NET Cross-Platform Showdown — DEV](https://dev.to/biozal/the-net-cross-platform-showdown-maui-vs-uno-vs-avalonia-and-why-avalonia-won-ian)
- [Uno GitHub](https://github.com/unoplatform/uno)

### Tauri

- [Tauri Windows installer guide](https://v2.tauri.app/distribute/windows-installer/)
- [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/)
- [Tauri webview versions](https://v2.tauri.app/reference/webview-versions/)
- [Tauri GitHub](https://github.com/tauri-apps/tauri)
- [tauri-winrt-notification crate](https://crates.io/crates/tauri-winrt-notification)
- [tauri-plugin-notifications crate](https://crates.io/crates/tauri-plugin-notifications)
- [winrt-notification GitHub](https://github.com/tauri-apps/winrt-notification)
- [Scheduling Windows Notifications from Rust (DEV)](https://dev.to/randomengy/scheduling-windows-notifications-from-rust-55b3)
- [Exploring System Webviews in Tauri (DEV)](https://dev.to/shrsv/exploring-system-webviews-in-tauri-native-rendering-for-efficient-cross-platform-apps-9hl)

### MAUI status reports (rejected stack — receipts)

- [Win 11 Update Borks .NET MAUI Projects (Visual Studio Magazine, Oct 2025)](https://visualstudiomagazine.com/articles/2025/10/24/windows-11-update-borks-net-maui-projects-built-on-net-8-microsoft-what-have-you-done.aspx)
- [How are things in 2026? — dotnet/maui discussion](https://github.com/dotnet/maui/discussions/34171)
- [.NET MAUI released as stable but absolutely isn't — xeladu (Medium)](https://xeladu.medium.com/net-maui-released-as-stable-but-it-absolutely-isnt-735df7e14113)
- [VS 2026 development of MAUI mobile apps — broken (MS Q&A)](https://learn.microsoft.com/en-us/answers/questions/5651444/vs-2026-development-of-maui-apps-for-mobile-is-not)

### WinUI 3 status & open-sourcing

- [Microsoft confirms WinUI / WinAppSDK open source — Windows Central](https://www.windowscentral.com/microsoft/windows-11/microsoft-confirms-windows-app-sdk-winui-open-source)
- [Microsoft promises 'truly open source' WinUI — The Register](https://www.theregister.com/2025/08/05/microsoft_winui_open_source/)
- [WinUI 3 Native AOT — discussion #8082](https://github.com/microsoft/microsoft-ui-xaml/discussions/8082)
- [WinUI3 AOT publishes managed pdb — runtime#108087](https://github.com/dotnet/runtime/issues/108087)
- [Microsoft open sources XAML Studio amid VS designer discontent (devclass)](https://www.devclass.com/development/2026/01/07/microsoft-open-sources-xaml-studio-amid-developer-discontent-with-visual-studio-designers/4079573)
- [Windows Community Toolkit v8.2 adds Native AOT](https://visualstudiomagazine.com/articles/2025/04/03/windows-community-toolkit-8-2-adds-native-aot-support.aspx)
- [Packaged, Unpackaged, Self-Contained WinUI 3 Apps (Nick's .NET Travels)](https://nicksnettravels.builttoroam.com/packaged-unpackaged-self-contained/)

### Slint, GPUI, Rust GUI ecosystem

- [Slint GitHub](https://github.com/slint-ui/slint)
- [State of Rust GUI — The Good and Bad (Rust Bytes)](https://weeklyrust.substack.com/p/the-state-of-rust-gui-the-good-and)
- [Tritium: Thanks for All the Frames — Rust GUI Observations](https://tritium.legal/blog/desktop)
- [GPUI Component (BrightCoding)](https://www.blog.brightcoding.dev/2026/02/23/gpui-component-build-stunning-rust-desktop-apps-with-gpu-power)
- [Are we GUI yet?](https://areweguiyet.com/)

### Microsoft Store and licensing

- [Microsoft removes restrictions on open-source apps (Windows Central)](https://www.windowscentral.com/microsoft/microsoft-removes-restrictions-on-generally-free-and-open-source-apps-in-microsoft-store)
- [Now official: paid open-source apps allowed in MS Store (Neowin)](https://www.neowin.net/news/now-official-paid-open-source-apps-are-allowed-in-the-microsoft-store/)
- [Microsoft Store policy reversal (Business Standard)](https://www.business-standard.com/article/technology/microsoft-not-to-ban-commercial-open-source-apps-on-windows-store-122071900739_1.html)
- [Open Source Licenses 2026 Guide (DEV)](https://dev.to/juanisidoro/open-source-licenses-which-one-should-you-pick-mit-gpl-apache-agpl-and-more-2026-guide-p90)
- [.NET Runtime licensing question (dotnet/runtime#89305)](https://github.com/dotnet/runtime/discussions/89305)
- [GNU FAQ on AGPL/GPL/LGPL](https://www.gnu.org/licenses/gpl-faq.html)

### .NET libraries

- [YamlDotNet GitHub](https://github.com/aaubry/YamlDotNet)
- [YamlDotNet 17.0.1 NuGet](https://www.nuget.org/packages/YamlDotNet)
- [YAML 1.2 emitter support tracking issue (#484)](https://github.com/aaubry/YamlDotNet/issues/484)
- [YAML 1.2.2 spec](https://yaml.org/spec/1.2.2/)
- [Markdig GitHub](https://github.com/xoofx/markdig)
- [Markdig YAML frontmatter parser](https://github.com/xoofx/markdig/blob/master/src/Markdig/Extensions/Yaml/YamlFrontMatterParser.cs)
- [Markdig YAML specs test fixtures](https://github.com/xoofx/markdig/blob/master/src/Markdig.Tests/Specs/YamlSpecs.md)
- [sqlite-net GitHub (praeclarum)](https://github.com/praeclarum/sqlite-net)

### File watching / FileSystemWatcher

- [FileSystemWatcher.Error event (MS Learn)](https://learn.microsoft.com/en-us/dotnet/api/system.io.filesystemwatcher.error?view=net-7.0)
- [FileSystemWatcher: Consider polling API (#17111)](https://github.com/dotnet/runtime/issues/17111)
- [Avoiding File Concurrency with FileSystemWatcher (Intertech)](https://www.intertech.com/avoiding-file-concurrency-using-system-io-filesystemwatcher/)
- [FileSystemWatcher InternalBufferSize and network drives (MS Learn archive)](https://learn.microsoft.com/en-us/archive/blogs/kimhamil/filesystemwatcher-doesnt-fire-events-for-monitored-network-drive-after-changing-internalbuffersize)
- [How to use FileSystemWatcher (makolyte)](https://makolyte.com/event-driven-dotnet-use-filesystemwatcher-instead-of-polling-for-new-files/)
- [MiniFSWatcher GitHub (CenterDevice)](https://github.com/CenterDevice/MiniFSWatcher)
- [FileSystemWatcherAlts collection](https://github.com/theXappy/FileSystemWatcherAlts)

### Testing

- [FlaUI (vs WinAppDriver) — issue #226](https://github.com/FlaUI/FlaUI/issues/226)
- [FlaUI.WebDriver](https://github.com/FlaUI/FlaUI.WebDriver)
- [WinAppDriver alternatives 2026 (TestSprite)](https://www.testsprite.com/use-cases/en/the-most-accurate-alternatives-to-winappdriver)
- [Test Windows desktop with Appium-compatible WinAppDriver (BrowserStack)](https://www.browserstack.com/guide/test-windows-desktop-app-using-appium-winappdriver)

### Code signing / packaging

- [MSIX and Code Signing Certificates (Advanced Installer)](https://www.advancedinstaller.com/msix-certificates-developer.html)
- [Trusted Signing setup walkthrough (Rick Strahl)](https://weblog.west-wind.com/posts/2025/Jul/20/Fighting-through-Setting-up-Microsoft-Trusted-Signing)
- [Simplifying signing integration for Trusted Signing (MS Tech Community)](https://techcommunity.microsoft.com/blog/microsoft-security-blog/simplifying-signing-integration-for-trusted-signing/4293292)

### Notification specifics (Focus / Do Not Disturb)

- [Configure Do Not Disturb for Notifications in Windows 11 (NinjaOne)](https://www.ninjaone.com/blog/windows-do-not-disturb-notifications/)
- [Mastering Notifications in Windows 11 (Windows Forum)](https://windowsforum.com/threads/mastering-notifications-in-windows-11-a-complete-customization-guide.349935/)
- [BurntToast PowerShell module](https://github.com/Windos/BurntToast)
- [Crouton #15 — You Can't Silence Toast (ToastIT)](https://toastit.dev/2021/01/31/crouton-15-you-cant-silence-toast/)

### Cross-compilation, dotnet publish

- [`dotnet publish` reference](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-publish)
- [Cross-platform build issues — sdk#25446](https://github.com/dotnet/sdk/issues/25446)
- [.NET application publishing overview](https://learn.microsoft.com/en-us/dotnet/core/deploying/)

### OneDrive / Cloud Files API

- [Cloud Files API FAQ (UserFileSystem)](https://www.userfilesystem.com/programming/faq/)
- [Cloud Filter APIs: Placeholder Files for Better Efficiency (CloudTweaks)](https://cloudtweaks.com/2025/05/filter-apis-placeholder-files-better-efficiency/)
- [Configure OneDrive Files On-Demand states (PowerShell)](https://tech.tristantyson.com/setonedrivefodstatespowershell)
- [Back up your folders with OneDrive (MS Support)](https://support.microsoft.com/en-us/office/back-up-your-folders-with-onedrive-d61a7930-a6fb-4b95-b28a-6552e77c3057)

### Internal references

- `/Users/saxon/Developer/Projects/Lists/SPEC.md` §6, §7, §15, §16, §17
- `/Users/saxon/Developer/Projects/Lists/research/00-current-state.md`
- `/Users/saxon/Developer/Projects/Lists/design/project/docs/app-plan.md`
  (historical multi-platform plan; obsolete on storage but useful for UX)

---

## Appendix A: minimum target Windows version

**Recommendation: Windows 11 22H2 (build 22621) as the supported target;
best-effort fallback to Windows 10 22H2 with feature-detection.**

Why:

- Windows 10 hit end-of-life on October 14, 2025; ESU runs through October
  13, 2026. As of the May 2026 ship date, paying customers exist on Win10
  but Microsoft expects them to migrate.
- The `scenario="urgent"` toast ability we need for breaking through Focus
  Assist requires Win11 22H2+ (`AppNotificationBuilder.IsUrgentScenarioSupported()`
  returns false on Win10).
- Mica and Acrylic require Win11 (Mica needs build 22000+).
- The Win App SDK supports Win10 17763+, so toasts (without urgent
  scenario) and notifications still work on Win10. The fallback story is
  "you get the same app, just without urgent-mode break-through and Mica"
  — this is acceptable.
- Avalonia targets `net9.0`, which runs on Win10 22H2+ without issue.

The pragmatic split:

```
On Windows 11 (build >= 22621):   full Fluent + Mica + scenario="urgent"
On Windows 10 22H2 (build 19045): Acrylic fallback theme + scenario="alarm"
                                  for urgent reminders (no DND override)
On older Windows:                  unsupported, splash screen prompts upgrade
```

Document the differences in Settings → About → Compatibility.

---

## Appendix B: design pass is a prerequisite

The `design/` folder contains wireframes for iPad, macOS, Android, and Linux
(GNOME and KDE). **There are no Windows wireframes.** Before starting the
implementation phase, do a one-day mockup pass that:

- Translates the iOS Reminders idiom to Windows 11 Fluent: NavigationView
  on the left, list-detail-detail tri-pane in expanded mode, NavigationView
  collapsed to icons only on small windows.
- Picks the Mica vs Mica Alt vs Acrylic backdrop per surface (window
  background = Mica; flyouts = Acrylic; sheets = solid surface).
- Defines title-bar treatment — the recommended approach for an Avalonia
  app on Win11 is to use `ExtendClientAreaToDecorationsHint = true` and
  draw the controls into the title bar area, matching modern Win11 apps
  like Settings and File Explorer.
- Specifies the navigation rail widths (compact 48 px, expanded 256 px,
  matching FluentAvalonia's NavigationView defaults).
- Specifies typography — Segoe UI Variable Display for headings, Segoe UI
  Variable Text for body, both shipped with Win11.

This is a 1–2 day pass and is a hard prerequisite for implementation
estimation. It is not in scope for this stack-research document; flag it as
the first task in the Windows milestone.
