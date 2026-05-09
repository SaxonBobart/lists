# Linux — Lists

Native Linux client for the markdown-on-disk reminders app. Skeleton only.
Full reasoning behind every choice: [`research/linux-stack.md`](../../research/linux-stack.md).

## Stack

| Layer | Choice |
|---|---|
| Language | Vala 0.56+ |
| UI toolkit | GTK4 4.16+ |
| Widget set | libadwaita 1.7 (`AdwNavigationSplitView`, `AdwBoxedList`, `AdwBanner`, system accent colours) |
| UI markup | Blueprint (`.blp`) |
| Persistence (rebuildable cache) | `sqlite3` via Vala VAPI |
| YAML | `libfyaml` (YAML 1.2 conformant; faster + better maintained than `libyaml`) |
| Markdown render | `cmark-gfm` → WebKitGTK reader pane |
| Markdown editor | GtkSourceView 5 |
| File watching | GIO `GFileMonitor` (inotify backend) + scheduled rescan failsafe on FUSE backends |
| Notifications | `GNotification` routed via the [Notification portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Notification.html) under Flatpak |
| Urgent alarms | GNotification `URGENT` + GStreamer audio loop; daemon arms next RTC wake via `systemd-run --timer-property=WakeSystem=true` |
| Background service | D-Bus-activatable user service (`io.github.saxonbobart.Lists.Daemon`) + autostart `.desktop` + Background Apps portal |
| Build | Meson 1.4+ (consumed natively by `flatpak-builder`) |
| Tests | GLib `GTestSuite` + Workbench (visual) + dogtail (X11 AT-SPI) + ydotool (Wayland CI) |
| Packaging | **Flatpak / Flathub primary**; AUR (community-maintained) secondary; .deb best-effort. **No Snap, no AppImage.** |

## Single client, not two

The Linux design assets in `design/project/src-linux/` are unambiguously
libadwaita (Adwaita Dark surfaces, AdwHeaderBar, AdwBoxedList, GNOME 47 accent
palette). One libadwaita client matches them transliterally and renders
acceptably under KDE Plasma 6. A second native KDE/Qt6 port doubles the
maintenance surface for a smaller audience; if KDE users want a Plasma-shaped
variant they can fork (the data layer is plain markdown — every fork inherits
the same on-disk format). Full reasoning in `research/linux-stack.md` §2.

## App ID and bundle conventions

- **App ID**: `io.github.saxonbobart.Lists` (reverse-DNS, capitalised name segment matches Flathub convention)
- **D-Bus daemon**: `io.github.saxonbobart.Lists.Daemon`
- **Flatpak ref**: `io.github.saxonbobart.Lists` on Flathub
- **AUR package name**: `lists` (bin) and `lists-git` (HEAD)

## Storage layout

V1 ships with the `Lists/` folder under the user's `XDG_DATA_HOME`:

```
$XDG_DATA_HOME/lists/Lists/  (default: ~/.local/share/lists/Lists/)
├── 00000000000000000000INBOX0/
│   ├── .list.yml
│   └── <ulid>.md
└── …
```

A first-run prompt offers to relocate to `~/Documents/Lists/` (Syncthing-friendly)
or any user-chosen folder. The chosen location is stored in `GSettings`
(`/io/github/saxonbobart/lists/library-path`).

## Build commands (once scaffolded)

```sh
# Set up build directory + configure
meson setup build

# Compile
meson compile -C build

# Run from build tree (no install)
./build/src/lists

# Run unit tests
meson test -C build --print-errorlogs

# Install to /usr/local (system) or $HOME/.local (user)
meson install -C build --destdir="$DESTDIR"

# Build a Flatpak bundle locally
flatpak-builder --user --install --force-clean build-flatpak \
    flatpak/io.github.saxonbobart.Lists.json
```

Cross-compile from macOS for Linux is not directly supported by Vala; use a
Linux VM or a GitHub Actions runner for the actual build.

## First-tasks checklist (when building begins)

1. **Install build deps** on a Linux dev machine: `meson`, `valac`, `gtk4-devel`, `libadwaita-devel`, `gtksourceview5-devel`, `webkitgtk6-devel`, `sqlite-devel`, `libfyaml-devel`, `blueprint-compiler`, `appstream-glib`.
2. **Generate the GResource manifest** from the Blueprint UI files; wire `gnome.compile_resources()` in `src/meson.build`.
3. **Port the iOS `FrontmatterCodec` + `YAMLCodec`** to Vala using libfyaml. Use the `shared/fixtures/` corpus as parity tests.
4. **Define the SQLite cache schema** in `src/cache/schema.vala`, mirroring `shared/cache/schema.sql`.
5. **Implement `FileStore`** with GIO `GFileMonitor`. Add a "FUSE detection" path that falls back to scheduled rescans for Syncthing/Nextcloud directories where inotify is flaky.
6. **Wire the libadwaita home grid + lists screen** in Blueprint, matching the JSX mockups under `design/project/src-linux/`.
7. **Build the daemon** as a separate binary (`src/daemon/`) registered with D-Bus user-bus and an autostart `.desktop`. The daemon owns the SQLite cache and arms wake-from-suspend timers via `systemd-run`.
8. **Wire `GNotification` URGENT**; verify both GNOME 47 and KDE Plasma 6 honour the criticality.
9. **Set up Flathub submission**: Flatpak manifest, `metainfo.xml.in` with full release notes, screenshots, OARS rating, AppStream validation passing under `appstream-util`.
10. **CI**: GitHub Actions matrix building on Fedora + Ubuntu LTS + Arch (containers), running `meson test`, plus a `flatpak-builder` job that publishes the Flatpak bundle on tag.

## Status

**Not yet built.** This directory contains only structural placeholders so the
intended layout is reviewable. No buildable code lives here yet.

## See also

- [`research/linux-stack.md`](../../research/linux-stack.md) — full reasoning, alternatives, gotchas
- [`design/project/src-linux/`](../../design/project/src-linux/) — Adwaita wireframes (read-only reference)
- [`shared/`](../../shared/) — cross-platform format spec, fixtures, and lexicons
- [Flathub submission docs](https://docs.flathub.org/docs/for-app-authors/submission)
- [GNOME HIG](https://developer.gnome.org/hig/) — visual ground-truth
