# Linux client stack for Lists

_Phase 5 research, 2026-05-03. Author: overnight research run. Reviewer: solo dev._

## 1. TL;DR

**Ship one client: GTK4 + libadwaita + Vala, packaged as a Flatpak on Flathub
first, plus a thin D-Bus-activatable daemon (`io.github.saxonbobart.Lists.Daemon`) for
the alarm scheduler and file watcher.** The Linux design assets are already
Adwaita-shaped (Adwaita Dark surfaces, AdwHeaderBar, AdwBoxedList, GNOME 47
accent palette); matching them with libadwaita is essentially free, and a
libadwaita app feels correct on every modern GNOME-aligned desktop while
remaining tolerable on KDE Plasma 6 (GTK4 apps are now well-behaved Plasma
guests). Vala speaks GObject natively — no FFI tax, no introspection
penalty — and elementary OS proves a small team can ship polished apps in
it. Rust + `gtk4-rs` + `relm4` is the only serious challenger; it gets the
nod **only** if a shared Rust core for markdown/YAML/RRULE is committed to
across iOS, Android, Windows and Linux. Don't ship a second KDE client; if
KDE users want a Plasma-shaped variant, they can fork.

## 2. The single-client-vs-two-clients question

Three honest options.

### Option A: Two clients (one GNOME, one KDE — the old `app-plan.md` proposal)

| Pros | Cons |
|---|---|
| Each client is pixel-perfect on its native desktop. Adwaita on GNOME, Breeze on KDE. | **2x maintenance forever**, in two languages and two toolkits. Solo-dev death sentence. |
| KDE users feel respected, not "GNOME users in disguise". | Two completely different parsers, schedulers, file watchers — every bug fix is shipped twice. |
| Each port can use its desktop's idioms directly (`KNotification` vs `GNotification`, `KIO` vs GIO). | Two CI matrices, two Flatpak manifests, two release cadences, two issue trackers, two translation pipelines. |
| Honest UX. | Risk that one falls behind and rots — at which point you have one client and a dead branch. |

### Option B: One adaptive client (single codebase, runs everywhere)

| Sub-option | Pros | Cons |
|---|---|---|
| **GTK4 + libadwaita** on KDE | Single codebase. GTK4 apps render cleanly under Plasma 6 with KDE's improved cross-toolkit handling ([KDE Discuss thread](https://discuss.kde.org/t/gtk4-and-inconsistent-themeing-question/6286)). Window controls and CSD are now handled. | Doesn't follow the user's KDE accent / global theme exactly; Adwaita styling is recognisably non-Plasma. |
| **Qt6 + KDE Frameworks** on GNOME | Same single-codebase win in reverse. Kirigami can adapt to mobile. | Looks alien on GNOME (Qt theming hack required). Most GNOME users will react badly. KDE Frameworks is heavyweight relative to vanilla Qt6. |
| **Tauri / Electron / Avalonia / Slint / Iced** | Truly identical on every distro. Tauri/Avalonia bundle their own runtime so distro fragmentation matters less. | Feels like a port. Tauri uses `WebKitGTK` on Linux (memory issues, slow). Slint uses its own DSL — high learning cost. Iced is intentionally non-native. Avalonia is .NET (heavy runtime). All of them lose the "feels native" pitch. |

### Option C: Pragmatic split — Adwaita-native first, KDE deferred to community

| Pros | Cons |
|---|---|
| Single codebase to maintain. **Solo dev capacity matches commitment.** | KDE users get a less-than-perfect experience until/unless someone contributes a Plasma port. |
| The design assets already exist for Adwaita; matching them is effectively free. | If no contributor steps up, the KDE story stays "tolerable Adwaita app". |
| Building one client well > shipping two clients badly. | Requires honest "KDE port wanted, contributors welcome" messaging in the README. |
| AGPL means any community KDE port stays open and upstreamable. | None that aren't restating the above. |

### Recommendation

**Option C.** The mockups under `design/project/src-linux/` are unambiguously
libadwaita (AdwHeaderBar, AdwBoxedList, GNOME-47 accent palette, sidebar at
260 px with `AdwNavigationSplitView` proportions). Half the work of a GTK4
port is already done in JSX. A second native KDE port doubles the surface
area in toolkit, build, packaging, language, notification API, and theming —
for an audience that's a smaller slice of the polished-FOSS early adopters
who file useful issues and PRs. A solo dev picking "two clients" ships zero
good clients. Picking "one Adwaita client done well" ships one good client
and an AGPL codebase a KDE contributor can fork — without forking the data
model, since that lives in plain markdown files (Linux's universal sync
currency).

## 3. Stack recommendation

Single client. GTK4 + libadwaita + Vala.

| Concern | Choice | Why |
|---|---|---|
| Language | **Vala 0.56+** | GObject-native. No FFI, no introspection layer, no borrow-checker tax. Compiles to C, ABI-compatible with the GTK ecosystem. |
| UI toolkit | **GTK4 4.16+** ([winter 2025 update](https://blogs.gnome.org/gtk/2025/02/01/whats-new-in-gtk-winter-2025-edition/)) | Mockups assume it. Vulkan renderer; cheap scrolling boxed-lists. |
| Adwaita | **libadwaita 1.7** ([release notes](https://nyaa.place/blog/libadwaita-1-7/)) | `AdwNavigationSplitView`, `AdwToggleGroup`, `AdwBanner`, system accent colours, adaptive preview mode — all match design tokens directly. |
| UI markup | **Blueprint** ([compiler docs](https://jwestman.pages.gitlab.gnome.org/blueprint-compiler/)) | `.blp` over GtkBuilder XML; in the GNOME 49 SDK; halves markup boilerplate. |
| Persistence | **`sqlite3` via Vala VAPI** (rebuildable cache only) | ~200 LOC for the cache schema. `libgda` overkill, `tracker-sparql` wrong abstraction. Bundle SQLite in the Flatpak. |
| YAML | **libfyaml** via Vala VAPI ([GitHub](https://github.com/pantoniou/libfyaml)) | YAML 1.2 conformant; 24× faster than libyaml on streaming; actively maintained (libyaml hasn't been). |
| Markdown | **cmark-gfm** ([GitHub](https://github.com/github/cmark-gfm)) → WebKitGTK reader pane; **GtkSourceView 5** ([wiki](https://wiki.gnome.org/Projects/GtkSourceView)) editor with [ThiefMD lang spec](https://github.com/ThiefMD/custom-gtksourceview-languages) | cmark-gfm matches GitHub semantics; WebKitGTK already in `org.gnome.Platform`. |
| File watching | **GIO `GFileMonitor`** with inotify backend ([docs](https://docs.gtk.org/gio/class.FileMonitor.html)) | Async, mainloop-integrated. Fallback rescan on FUSE backends — see §7. |
| Notifications | **`GNotification`** ([send_notification](https://docs.gtk.org/gio/method.Application.send_notification.html)) routed through the [Notification portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Notification.html) under Flatpak | One API; both GNOME and KDE honour `priority=URGENT` as critical. |
| Urgent alarms | GNotification URGENT + GStreamer audio loop; daemon arms next RTC wake via `systemd-run … --timer-property=WakeSystem=true` (polkit helper) | See §8/§10. |
| Background | **D-Bus-activatable user service** + autostart `.desktop`, with [Background Apps portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.background.Monitor.html) permission. | Same model as `evolution-alarm-notify`. |
| Packaging | **Flatpak/Flathub primary, AUR secondary, Debian stretch.** | §11. No Snap, no AppImage. |
| Build | **Meson 1.4+** ([docs](https://mesonbuild.com/)) | Standard; `flatpak-builder` consumes natively. |
| Tests | **GLib `GTestSuite`** + **Workbench** ([apps.gnome.org](https://apps.gnome.org/Workbench/)) for visuals + **dogtail** (X11 AT-SPI) + **ydotool** (Wayland CI). | §12. |

## 4. Alternatives considered

### A. GTK4 + libadwaita language choices

| Stack | Verdict | Notes |
|---|---|---|
| **Vala** ([home](https://vala.dev/), [Wikipedia](https://en.wikipedia.org/wiki/Vala_(programming_language))) | **Pick.** | GObject-native; reads like C#; compiles to C (fast startup); smallest per-line overhead for libadwaita. Mature tooling, language servers, Builder templates. |
| **Rust + gtk4-rs + Relm4** ([gtk4-rs](https://github.com/gtk-rs/gtk4-rs), [Relm4](https://relm4.org/), [libadwaita crate](https://crates.io/crates/libadwaita)) | Pick if shared Rust core wins (§9). | 100+ apps shipped with gtk4-rs. libadwaita-rs at 0.9.x, synced to gtk4-rs releases. Standalone, boilerplate ratio is worse than Vala. |
| **Python + PyGObject** ([docs](https://pygobject.gnome.org/)) | Backup. | Fastest prototyping; used by Apostrophe, Iotas. No type hints over GObject; ~300 ms slower startup than Vala/Rust. |
| **Plain C** | Don't. | Manual GObject ref-counting; productivity penalty too large for an app this size. |

### B. Qt6 alternatives (only if KDE-first was the goal)

| Stack | Verdict |
|---|---|
| **C++ + Qt6 + Kirigami** ([KDE Plasma 6](https://en.wikipedia.org/wiki/KDE_Plasma_6)) | Mature. KDE-native ceiling is high; cognitive load is highest in this list. Reasonable for a Plasma-first project; not this one. |
| **PyQt6 / PySide6** | Fine; doesn't change the "doesn't match the design assets" point. |
| **Rust + CXX-Qt** ([CXX-Qt](https://github.com/KDAB/cxx-qt), [KDE Rust+Kirigami](https://develop.kde.org/docs/getting-started/rust/rust-app/)) | Production-stable as of 2024; KDAB-maintained. Strong choice for a contributor-built Plasma port later. |

### C. Cross-toolkit options

| Stack | Licence | Verdict |
|---|---|---|
| **Slint** ([slint.dev](https://slint.dev/)) | GPLv3 + commercial | Skip. Own DSL; doesn't pick up Adwaita/Breeze themes; <300 KiB runtime is impressive but irrelevant here. |
| **Iced** ([iced](https://github.com/iced-rs/iced)) | MIT | Skip. Intentionally non-native; every chrome detail hand-painted. |
| **Tauri** ([distribute docs](https://v2.tauri.app/distribute/)) | Apache 2.0 / MIT | Skip. WebKitGTK on Linux is heavy; tray icon is broken in Flatpak ([#13599](https://github.com/tauri-apps/tauri/issues/13599)). |
| **Avalonia** ([avaloniaui.net](https://avaloniaui.net/), [Register coverage](https://www.theregister.com/2025/11/13/dotnet_maui_linux_avalonia/)) | MIT | Skip on Linux. Reconsider only if Windows research picks Avalonia — then one C# codebase covers two platforms (with a .NET runtime + 60 MB Flatpak tax). |

### Licence and ecosystem maturity table

| Stack | Licence | Compatible with AGPL-3.0-or-later? | Linux apps shipping it (sample) |
|---|---|---|---|
| GTK4 + libadwaita + Vala | LGPL-2.1 | Yes | Files, Calendar, Music, Vocal, Folio, Apostrophe (Python), Gapless |
| GTK4 + libadwaita + Rust | LGPL-2.1 + MIT/Apache | Yes | Fractal, Health, Spot, Loupe, Decoder |
| Qt6 + Kirigami | LGPL-3.0 / GPL / commercial | Yes | KDE PIM suite, Marble, NeoChat |
| Slint | GPLv3 + commercial | Yes (with caveats — see Slint licence FAQ) | Embedded use mostly; few flagship Linux apps |
| Iced | MIT | Yes | A few utilities; no flagship reminders-class app |
| Tauri | MIT/Apache | Yes | Various small utilities; not native-feeling |
| Avalonia | MIT | Yes | Small but growing; no major Linux-first reminders app |

## 5. Why the recommendation wins

For a solo dev shipping AGPL-licensed FOSS that needs to feel native on
Linux, GTK4 + libadwaita + Vala is the lowest-friction choice the GNOME
community will accept as "one of theirs":

1. **Design assets already match.** Mockups use Adwaita Dark surfaces
   (`#222226 / #1c1c20 / #2a2a2e / #303034`), `AdwHeaderBar`, `AdwBoxedList`,
   `AdwNavigationSplitView` at 260 px sidebar, the literal GNOME 47 accent
   hex values, and the Inter/Adwaita Sans font stack. Any other toolkit means
   redrawing them; libadwaita means transliterating them.
2. **Adaptive layouts free.** `AdwNavigationSplitView` collapses to single
   pane on narrow windows ([Adaptive Layouts docs](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.7/adaptive-layouts.html));
   1.7's adaptive preview mode lets you test phone form factor in inspector.
   Linux phones (PinePhone, Librem 5) get the UI for free.
3. **System accent colours.** libadwaita 1.7 reads the system accent and
   applies it ([Alice's blog](https://nyaa.place/blog/libadwaita-1-7/),
   [GNOME 47 coverage](https://www.osnews.com/story/140769/gnome-47-released-with-accent-colours-and-completely-new-open-save-file-dialogs/)).
4. **Vala minimises code-per-feature.** GObject inheritance, signals, and
   property bindings are first-class. No `#[derive(GObject)]` boilerplate,
   no PyGObject introspection. Compiles to C — fast startup, low memory,
   suited to a long-running daemon.
5. **Notifications cross-desktop by default.** `GNotification` routes through
   the XDG portal in Flatpak and `libnotify` outside it; GNOME and KDE
   Plasma 6 both honour critical urgency ([freedesktop spec](https://specifications.freedesktop.org/notification/latest-single/),
   [Plasma Notifications wiki](https://community.kde.org/Plasma/Notifications)).
6. **Storage contract is cheap.** GIO async APIs + `GFileMonitor` + a Vala
   wrapper around `libfyaml` covers the entire filesystem story in a few
   hundred lines.
7. **AGPL-friendly licences end-to-end.** Vala + GTK4 + libadwaita are
   LGPL-2.1, libfyaml MIT, cmark-gfm BSD-2, SQLite public domain, Meson
   Apache 2.0. Nothing to launder.

## 6. Storage layout — where does `Lists/` live?

| Location | Recommended? | Notes |
|---|---|---|
| `$XDG_DATA_HOME/lists/Lists/` (default `~/.local/share/...`) ([XDG spec](https://specifications.freedesktop.org/basedir/latest/)) | **Default.** | Hidden from file managers; covered by every backup tool. |
| `~/Documents/Lists/` (`XDG_DOCUMENTS_DIR`) | **Configurable opt-in.** | Visible; user edits `.md` directly; what Nextcloud/Syncthing/Dropbox sync by default. |
| `~/Sync/Lists/` | **Don't default.** | Don't presume Syncthing is installed. |
| Flatpak data dir (`~/.var/app/.../data/Lists/`) | **No.** | Defeats markdown-native interoperability with the user's editor and sync tools. |

**Recommendation:** Default to `$XDG_DATA_HOME/lists/Lists/`. Offer a
"Move library" preference that relocates via the [FileChooser portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.FileChooser.html)
with presets for `~/Documents/Lists/`, `~/Sync/Lists/`, `~/Nextcloud/Lists/`.
Persist the chosen path in `$XDG_CONFIG_HOME/lists/config.toml`; on
launch, request a [Documents portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Documents.html)
token to retain access across sessions (the portal hands out persistent file
IDs at `/run/user/$UID/doc/$DOC_ID/`). Outside Flatpak, paths are bare. A
single `LibraryRoot.url()` abstracts the difference.

## 7. File watching — inotify, GIO, and the sync-folder tax

GIO `GFileMonitor` is the right primary API. It hides backend differences,
integrates with the GLib mainloop, and gives us `created/changed/deleted/moved`
events directly. ([GFileMonitor docs](https://docs.gtk.org/gio/class.FileMonitor.html))

But we have to be honest about the edge cases:

### inotify watch limit

Default `fs.inotify.max_user_watches` is **8192** per user. Syncthing,
Nextcloud, VS Code, Obsidian routinely exhaust it; Syncthing asks for
204 800–524 288 ([Syncthing FAQ](https://docs.syncthing.net/users/faq.html#inotify-limits)),
Nextcloud documents 524 288 ([Nextcloud FAQ](https://docs.nextcloud.com/server/latest/user_manual/en/desktop/faq.html)).
Mitigations:

1. **Watch directories, not files.** One watch per list folder + one for
   `Lists/` root. ~50 lists = ~51 watches, well under any budget.
2. **Detect failure.** On `G_IO_ERROR_TOO_MANY_OPEN_FILES`, surface a banner
   pointing at `/etc/sysctl.d/99-inotify.conf` with the canonical
   `fs.inotify.max_user_watches=524288` (same UX Syncthing shows).
3. **Periodic rescan fallback.** Walk every 60 s foregrounded, 5 min
   backgrounded. Cache invalidates on mtime mismatch per SPEC §7.

### FUSE / network mounts

`inotify` is inode-bound, so local-side writes always fire. FUSE filesystems
frequently **don't** propagate remote-side changes because FUSE doesn't know
a watch was set ([libfuse wiki](https://github.com/libfuse/libfuse/wiki/Fsnotify-and-FUSE),
[linux-fsdevel](https://www.spinics.net/lists/linux-fsdevel/msg32789.html)).
Practical:

- **Syncthing / Nextcloud client**: local write fires inotify — works.
- **sshfs / WebDAV**: remote write doesn't fire local inotify — periodic
  rescan is the only honest answer.
- **Bind mount of Syncthing folder into Flatpak sandbox**: works (same
  inodes — [linux-fsdevel](https://linux-fsdevel.vger.kernel.narkive.com/anoWCkQj/question-about-inotify-and-bind-mount)).

GIO's `smb://`, `dav://`, `ftp://`, `mtp://` URLs are **not supported** as
library roots in v1 — `GFileMonitor` semantics on GVfs are unreliable. Use
a real sync tool that materialises files locally.

## 8. Notifications + alarms

### Non-urgent: GNotification + portal (one API, both desktops)

```vala
var notification = new GLib.Notification ("Take out the bins");
notification.set_body ("Tonight, 8 pm");
notification.set_icon (new ThemedIcon ("io.github.saxonbobart.lists"));
notification.set_priority (NotificationPriority.NORMAL);
notification.set_default_action ("app.complete-reminder::01HX2A9F3K…");
GLib.Application.get_default ().send_notification ("01HX2A9F3K…", notification);
```

GTK transparently routes through the [XDG Notification portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Notification.html)
when sandboxed. Outside the sandbox it talks to `org.freedesktop.Notifications`
directly. Both GNOME's `gnome-shell` and KDE's `plasma-notifier` honour the
priority field.

### Urgent: critical urgency + audio loop

freedesktop urgency levels are Low (0), Normal (1), Critical (2)
([spec](https://specifications.freedesktop.org/notification/1.2/urgency-levels.html)).
Critical notifications **don't auto-expire**, **bypass DND on both GNOME and
KDE** ([Plasma wiki](https://community.kde.org/Plasma/Notifications)), and
are **timeout-immune** (GNOME always ignores `expire-timeout`; KDE ignores
it for criticals — [ArchWiki](https://wiki.archlinux.org/title/Desktop_notifications)).
In `GNotification` terms, set `priority = URGENT`.

**Audio loop.** The `sound-name` hint plays once. For AlarmKit-equivalent
behaviour we run our own loop:

1. On alarm fire, the daemon sends the urgent notification *and* starts a
   GStreamer pipeline (`filesrc … ! oggdemux ! pulsesink`, `gst_element_seek(loop=true)`).
2. The notification carries an action button `app.silence-alarm::<id>`.
3. Click tears down the GStreamer pipeline.
4. After 60 s of no acknowledgement, fall back to a single chime.

`pulsesink` auto-routes through PipeWire's pulse-server shim on PipeWire
systems. `libcanberra` is unmaintained since 2012 and breaks on
PipeWire-without-pulse-shim — skip; use GStreamer directly.

### Wake from sleep

iOS has AlarmKit; Linux equivalents:

- **`systemd-run` with `WakeSystem=true`** ([systemd.timer manpage](https://manpages.debian.org/testing/systemd/systemd.timer.5.en.html)) —
  wakes the system from suspend when the timer elapses. Catch: requires
  `CAP_WAKE_ALARM`, which user-level units don't get by default.
- **`rtcwake -m no -t <timestamp>`** ([rtcwake manpage](https://www.man7.org/linux/man-pages/man8/rtcwake.8.html)) —
  programs the RTC alarm. Same privilege requirement.
- **Clean path**: a tiny polkit-elevated helper that the daemon invokes to
  schedule the next RTC wake. User grants once during onboarding; daemon
  re-arms silently thereafter.

**v1 compromise:** alarms only fire while the system is awake. Document
honestly in the README — many Linux apps make exactly this trade-off
(Evolution Reminders being the most prominent). **v1.5 stretch:** the
polkit helper, gated behind a "Wake my computer for urgent reminders"
setting.

## 9. Shared Rust core verdict

Linux is the cleanest fit for a shared Rust core:

| Concern | No Rust core | With Rust core |
|---|---|---|
| YAML parse/emit | Vala VAPI over libfyaml — ~80 LOC | Reuse iOS/Android shared parser |
| RRULE expansion | Vala port of iOS parser — ~250 LOC | One impl, all platforms |
| ULID generation | Wrap 30-line `ulid.c` from Vala | One impl |
| Cache writer | Vala + sqlite3 — ~200 LOC | One impl |
| Markdown parse | cmark-gfm wrap | cmark-gfm wraps from Rust too |
| Cost | Lockstep maintenance across N languages | One impl, FFI boundary; daemon links via `extern "C"` |

**If Phase 5 picks shared Rust core:** Linux is Rust + gtk4-rs + relm4 +
libadwaita-rs, linking the core directly (no FFI boundary). Cleanest
cross-platform story.

**If Phase 5 picks native-everywhere:** Linux is Vala + libfyaml directly;
re-implement parser/RRULE in ~600 LOC of Vala. The Rust core wins iff iOS,
Android, **and** Windows all use it.

**My vote** (iOS already uses Swift+Yams natively, user is solo): no shared
core for v1. Re-implement per language. Reassess at v1.5 when "fix landed
on iOS, port to 3 other languages" becomes painful.

## 10. Background service question

Yes, a daemon. Layout:

```
io.github.saxonbobart.lists
├── /usr/bin/lists               (GUI)
├── /usr/bin/lists-daemon        (scheduler + file watcher)
├── /usr/share/applications/io.github.saxonbobart.lists.desktop
├── /usr/share/dbus-1/services/io.github.saxonbobart.Lists.Daemon.service
└── /etc/xdg/autostart/io.github.saxonbobart.lists-daemon.desktop
```

The daemon owns `io.github.saxonbobart.Lists.Daemon` on the session bus, is
**D-Bus-activatable** ([Desktop Entry Spec](https://specifications.freedesktop.org/desktop-entry/1.3/dbus.html)),
and has an `X-GNOME-Autostart-enabled=true` autostart entry so it starts at
login. It watches `Lists/`, maintains the SQLite cache, schedules
in-session alarms via `GNotification`, and calls the polkit helper for
wake-from-sleep RTC alarms (§8). Under Flatpak it requests the
[Background Apps portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.background.Monitor.html)
on first run — without it, GNOME may kill the Flatpak when the GUI closes.

The GUI talks to the daemon over D-Bus for everything except rendering
cached data, so closing the window doesn't lose alarms and the daemon's
footprint stays constant.

**Why not a pure systemd user service?** Three reasons: (1) systemd user
services need `loginctl enable-linger` to auto-start, which desktop users
don't set — autostart `.desktop` files Just Work; (2) D-Bus activation is
the right model for event-driven services; (3) systemd user services from
inside a Flatpak are awkward, portal-routed D-Bus is supported.

We do use `systemd-run --user --on-calendar=… --timer-property=WakeSystem=true`
as the alarm scheduler backend — only thing on Linux that wakes the system
from sleep at a specific time without writing `/dev/rtc0` directly. Polkit
helper bridges the privilege gap.

## 11. Packaging

| Format | Verdict | Effort |
|---|---|---|
| **Flatpak (Flathub)** ([docs](https://docs.flatpak.org/en/latest/), [submission](https://docs.flathub.org/docs/for-app-authors/submission)) | **Primary.** Biggest distribution channel for new desktop apps. | One manifest, GH-Actions submission, auto-build on tag. |
| **AUR** ([Rust pkg guidelines](https://wiki.archlinux.org/title/Rust_package_guidelines)) | **Secondary.** ~10–15 % desktop installs. | One PKGBUILD; community usually maintains. |
| **Reproducible .deb** ([Debian Repro wiki](https://wiki.debian.org/ReproducibleBuilds/Howto)) | **v1.1 stretch.** Flatpak covers Ubuntu in practice. | DEP-5 + debian/control + sponsor. Significant. |
| **Snap, AppImage, RPM** | **Skip for v1.** | Flatpak covers same users; revisit if a community PR appears. |

**Reproducible builds for Debian** are non-trivial but achievable: use
`--locked` for Cargo deps ([Debian Rust packaging wiki](https://wiki.debian.org/Teams/RustPackaging)),
set `SOURCE_DATE_EPOCH` consistently, ensure deterministic Vala `--vapidir`/`--header`
flags, run `dh_strip_nondeterminism` before `dh_compress`. Track upstream
[gtk4 trixie reproducibility report](https://tests.reproducible-builds.org/debian/rb-pkg/trixie/amd64/gtk4.html)
to avoid pinning a non-reproducible runtime.

## 12. Testing

Thin stack:

| Layer | Tool | Notes |
|---|---|---|
| Unit (parser, RRULE, cache) | `gtester` ([GTest docs](https://docs.gtk.org/glib/testing.html)) | GLib-native, no extra deps. Vala uses it via `g_test_add_func()`. CI on every push. |
| Visual prototyping | [Workbench](https://apps.gnome.org/Workbench/) | Live-iterate `.blp` files without a full rebuild. |
| GUI smoke (X11) | [dogtail](https://gitlab.com/dogtail/dogtail) | AT-SPI driven; navigates by widget label/role; survives themes. |
| GUI smoke (Wayland) | [ydotool](https://github.com/ReimuNotMoe/ydotool) | uinput-based; only thing that works under Wayland ([tutorial](https://gabrielstaples.com/ydotool-tutorial/)). |
| Storage integration | tmpdir + Vala test | Fake `Lists/`, mutate, assert. |
| Notification integration | `python-dbusmock` | No real notification daemon in CI. |

Skip pytest-qt and Catch2 (wrong toolkit). Resist screenshot-diff suites —
maintenance cost too high for solo dev.

## 13. First-month gotchas

| Gotcha | URL |
|---|---|
| Wayland breaks `xdotool`. Use `ydotool` (uinput), `wtype`, or AT-SPI. CI on Xvfb hides this. | [Wayland fragmentation](https://www.semicomplete.com/blog/xdotool-and-exploring-wayland-fragmentation/) |
| Flatpak sandboxing blocks `~/Documents`. Use FileChooser/Documents portal — `--filesystem=home` will be rejected by Flathub reviewers. | [Sandbox Permissions](https://docs.flatpak.org/en/latest/sandbox-permissions.html) |
| GNOME notification icons must be themed or bytes; `GFileIcon` silently fails. | [xdg-desktop-portal#317](https://github.com/flatpak/xdg-desktop-portal/issues/317) |
| GNOME ignores `expire-timeout`; KDE ignores it for criticals. Control persistence via urgency, not timeout. | [ArchWiki notifications](https://wiki.archlinux.org/title/Desktop_notifications) |
| Plasma 6 (Qt6 + KF6, Feb 2024). GTK4 looks fine; GTK3 looks ugly. Don't ship GTK3. | [Plasma 6 Wikipedia](https://en.wikipedia.org/wiki/KDE_Plasma_6) |
| libadwaita 1.7 tinted dark-mode slightly blue vs 1.6 grey. Pin `org.gnome.Platform//47` (or //48) consciously. | [1.7 notes](https://nyaa.place/blog/libadwaita-1-7/) |
| `AdwNavigationSplitView` defaults: 25% width, 180sp min / 280sp max. Lock 260px explicitly for ultrawide. | [docs](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.7/class.NavigationSplitView.html) |
| `inotify` 8192 default; commonly exhausted. Detect failure, banner the user. | [Syncthing FAQ](https://docs.syncthing.net/users/faq.html#inotify-limits) |
| FUSE may not propagate remote inotify events. Periodic rescan only honest answer for sshfs/WebDAV. | [libfuse wiki](https://github.com/libfuse/libfuse/wiki/Fsnotify-and-FUSE) |
| Background Apps portal can kill your Flatpak when GUI closes. Request the permission, or run daemon as a separate D-Bus service. | [Background portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.background.Monitor.html) |
| `WakeSystem=true` needs `CAP_WAKE_ALARM`; user services don't get it. Polkit helper or document the limitation. | [systemd.timer(5)](https://manpages.debian.org/testing/systemd/systemd.timer.5.en.html), [rtcwake(8)](https://www.man7.org/linux/man-pages/man8/rtcwake.8.html) |
| `libcanberra` unmaintained since 2012; breaks on PipeWire-without-pulse-shim. Use GStreamer. | [Arch libcanberra](https://wiki.archlinux.org/title/Libcanberra) |
| `serde-yaml` deprecated. If Rust, use `saphyr`, `serde-yaml-bw`, or `fyaml`. | [Rust forum](https://users.rust-lang.org/t/serde-yaml-deprecation-alternatives/108868) |
| GTK4 + Plasma 6 + Wayland CSD/SSD edge cases mostly fixed in 6.2+ but still diverge sometimes. Test on KDE neon or Fedora KDE Spin. | [Manjaro thread](https://forum.manjaro.org/t/poor-integration-of-gtk-window-decoration-under-plasma-wayland/154263) |

## 14. Sources

### Toolkits and bindings

- [libadwaita 1.7 release notes — Alice's blog](https://nyaa.place/blog/libadwaita-1-7/)
- [libadwaita on GitLab](https://gitlab.gnome.org/GNOME/libadwaita)
- [libadwaita NEWS / changelog](https://github.com/GNOME/libadwaita/blob/main/NEWS)
- [Adw.NavigationSplitView (1.7)](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.7/class.NavigationSplitView.html)
- [Adaptive Layouts in libadwaita](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.7/adaptive-layouts.html)
- [GNOME 47 release coverage — OSnews](https://www.osnews.com/story/140769/gnome-47-released-with-accent-colours-and-completely-new-open-save-file-dialogs/)
- [What's new in GTK, winter 2025 edition](https://blogs.gnome.org/gtk/2025/02/01/whats-new-in-gtk-winter-2025-edition/)
- [GTK 4 documentation](https://docs.gtk.org/gtk4/)
- [Vala home](https://vala.dev/)
- [Vala on Wikipedia](https://en.wikipedia.org/wiki/Vala_(programming_language))
- [Awesome Vala project list](https://github.com/vala-lang/awesome-vala)
- [Vala GTK4 samples](https://github.com/vala-lang/gtk4-samples)
- [Vala + GTK4 + LibAdwaita + Blueprints template](https://github.com/thetek42/vala-gtk4-template)
- [PyGObject home](https://pygobject.gnome.org/)
- [PyGObject GTK4 Getting Started](https://pygobject.gnome.org/getting_started.html)
- [gtk4-rs on GitHub](https://github.com/gtk-rs/gtk4-rs)
- [gtk-rs project home](https://gtk-rs.org/)
- [libadwaita-rs crate](https://crates.io/crates/libadwaita)
- [Relm4 home](https://relm4.org/)
- [Relm4 book](https://relm4.org/book/stable/)
- [CXX-Qt on GitHub](https://github.com/KDAB/cxx-qt)
- [KDE Rust + Kirigami tutorial](https://develop.kde.org/docs/getting-started/rust/rust-app/)
- [KDE Plasma 6 — Wikipedia](https://en.wikipedia.org/wiki/KDE_Plasma_6)
- [Blueprint compiler](https://jwestman.pages.gitlab.gnome.org/blueprint-compiler/)
- [Blueprint markup language announcement](https://www.jwestman.net/2021/10/22/a-markup-language-for-gtk.html)
- [Workbench](https://apps.gnome.org/Workbench/)
- [GtkSourceView wiki](https://wiki.gnome.org/Projects/GtkSourceView)
- [ThiefMD custom GtkSourceView markdown lang spec](https://github.com/ThiefMD/custom-gtksourceview-languages)

### Cross-toolkit options

- [Slint home](https://slint.dev/)
- [Iced GitHub](https://github.com/iced-rs/iced)
- [Tauri home](https://v2.tauri.app/)
- [Tauri Linux distribute docs](https://v2.tauri.app/distribute/)
- [Tauri Flatpak distribution](https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/distribute/flatpak.mdx)
- [Tauri tray icon Flatpak issue](https://github.com/tauri-apps/tauri/issues/13599)
- [Avalonia UI](https://avaloniaui.net/)
- [Avalonia for Linux](https://avaloniaui.net/avalonia/linux)
- [.NET MAUI Linux via Avalonia — The Register](https://www.theregister.com/2025/11/13/dotnet_maui_linux_avalonia/)
- [2025 survey of Rust GUI libraries](https://www.boringcactus.com/2025/04/13/2025-survey-of-rust-gui-libraries.html)

### Storage, file watching

- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest/)
- [XDG user directories — ArchWiki](https://wiki.archlinux.org/title/XDG_user_directories)
- [GFileMonitor — GIO 2.0 docs](https://docs.gtk.org/gio/class.FileMonitor.html)
- [Syncthing inotify limits FAQ](https://docs.syncthing.net/users/faq.html#inotify-limits)
- [Nextcloud Desktop FAQ](https://docs.nextcloud.com/server/latest/user_manual/en/desktop/faq.html)
- [libfuse fsnotify wiki](https://github.com/libfuse/libfuse/wiki/Fsnotify-and-FUSE)
- [linux-fsdevel inotify + bind-mount thread](https://www.spinics.net/lists/linux-fsdevel/msg32789.html)
- [GVfs on Wikipedia](https://en.wikipedia.org/wiki/GVfs)

### YAML, markdown, SQLite

- [libfyaml on GitHub](https://github.com/pantoniou/libfyaml)
- [serde-yaml deprecation alternatives](https://users.rust-lang.org/t/serde-yaml-deprecation-alternatives/108868)
- [fyaml Rust crate](https://crates.io/crates/fyaml)
- [cmark-gfm on GitHub](https://github.com/github/cmark-gfm)
- [rusqlite GitHub](https://github.com/rusqlite/rusqlite)
- [SQLite home](https://sqlite.org/)

### Notifications, alarms, audio

- [Desktop Notifications Specification (latest)](https://specifications.freedesktop.org/notification/latest-single/)
- [Urgency Levels — freedesktop spec](https://specifications.freedesktop.org/notification/1.2/urgency-levels.html)
- [ArchWiki Desktop notifications](https://wiki.archlinux.org/title/Desktop_notifications)
- [Plasma Notifications wiki](https://community.kde.org/Plasma/Notifications)
- [Next-gen Plasma Notifications — Kai Uwe's blog](https://blog.broulik.de/2019/05/next-generation-plasma-notifications/)
- [GNOME Discourse — detect DND via D-Bus](https://discourse.gnome.org/t/how-do-detect-do-not-disturb-via-dbus/17783)
- [GNotification — Gio.Notification docs](https://docs.gtk.org/gio/class.Notification.html)
- [Gio.Application.send_notification](https://docs.gtk.org/gio/method.Application.send_notification.html)
- [XDG Notification Portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Notification.html)
- [xdg-desktop-portal-gtk source](https://github.com/flatpak/xdg-desktop-portal-gtk)
- [Notification portal v2 proposal](https://github.com/flatpak/xdg-desktop-portal/issues/983)
- [notify-rust crate](https://crates.io/crates/notify-rust)
- [Notification icon Flatpak issue (GFileIcon)](https://github.com/flatpak/xdg-desktop-portal/issues/317)
- [Arch libcanberra page](https://wiki.archlinux.org/title/Libcanberra)
- [libnotify GitHub mirror](https://github.com/GNOME/libnotify)

### Wake-from-sleep, daemons, autostart

- [systemd.timer(5) manpage](https://manpages.debian.org/testing/systemd/systemd.timer.5.en.html)
- [rtcwake(8) manpage](https://www.man7.org/linux/man-pages/man8/rtcwake.8.html)
- [LWN — Waking systems from suspend](https://lwn.net/Articles/429925/)
- [joeyh — programmable alarm clock using systemd](https://joeyh.name/blog/entry/a_programmable_alarm_clock_using_systemd/)
- [Automatically wake Linux from sleep — ostechnix](https://ostechnix.com/automatically-wake-linux-system-sleep-hibernation-mode/)
- [D-Bus Activation — Desktop Entry Spec](https://specifications.freedesktop.org/desktop-entry/1.3/dbus.html)
- [KDE D-Bus autostart services tutorial](https://develop.kde.org/docs/features/d-bus/dbus_autostart_services/)
- [GApplication / Gio.Application docs](https://docs.gtk.org/gio/class.Application.html)
- [Background Apps Monitor portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.background.Monitor.html)
- [xdg-desktop-portal "improve background apps" issue](https://github.com/flatpak/xdg-desktop-portal/issues/899)

### Packaging

- [Flatpak documentation](https://docs.flatpak.org/en/latest/)
- [Flathub publishing guide](https://docs.flathub.org/docs/for-app-authors/submission)
- [Sandbox Permissions](https://docs.flatpak.org/en/latest/sandbox-permissions.html)
- [Documents Portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Documents.html)
- [FileChooser portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.FileChooser.html)
- [Debian Rust packaging wiki](https://wiki.debian.org/Teams/RustPackaging)
- [Debian GNOME Rust packaging wiki](https://wiki.debian.org/Gnome/Rust_Packaging)
- [Debian ReproducibleBuilds Howto](https://wiki.debian.org/ReproducibleBuilds/Howto)
- [gtk4 trixie reproducible-builds report](https://tests.reproducible-builds.org/debian/rb-pkg/trixie/amd64/gtk4.html)
- [Arch Linux Rust package guidelines](https://wiki.archlinux.org/title/Rust_package_guidelines)

### Wayland, GUI testing, theming

- [ydotool on GitHub](https://github.com/ReimuNotMoe/ydotool)
- [ydotool tutorial — Gabriel Staples](https://gabrielstaples.com/ydotool-tutorial/)
- [Exploring Wayland fragmentation — semicomplete](https://www.semicomplete.com/blog/xdotool-and-exploring-wayland-fragmentation/)
- [Wayland — ArchWiki](https://wiki.archlinux.org/title/Wayland)
- [Uniform look for Qt and GTK applications — ArchWiki](https://wiki.archlinux.org/title/Uniform_look_for_Qt_and_GTK_applications)
- [GTK4 themeing on KDE thread](https://discuss.kde.org/t/gtk4-and-inconsistent-themeing-question/6286)
- [Manjaro forum — GTK window decoration on Plasma Wayland](https://forum.manjaro.org/t/poor-integration-of-gtk-window-decoration-under-plasma-wayland/154263)

### Reference apps

- [Apostrophe — markdown editor (Python + GTK4 + libadwaita)](https://apps.gnome.org/Apostrophe/)
- [Iotas — markdown notes (Python + GTK4 + libadwaita)](https://gitlab.gnome.org/World/Iotas)
- [Folio — markdown notes (Vala + GTK4 + libadwaita)](https://gitlab.gnome.org/World/Iotas) (sample Vala-based reference app)
- [elementary blog — May 2025](https://blog.elementary.io/updates-for-may-2025/)
- [Awesome GTK applications](https://github.com/valpackett/awesome-gtk)
- [Workbench demos](https://github.com/workbenchdev/demos)
