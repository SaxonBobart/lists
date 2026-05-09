# Windows — Lists

Native Windows client for the markdown-on-disk reminders app. Skeleton only.
Full reasoning behind every choice: [`research/windows-stack.md`](../../research/windows-stack.md).

## Stack

| Layer | Choice |
|---|---|
| Language | C# 12 / .NET 9 |
| UI | Avalonia 11.3 + FluentAvalonia 2.5.1 |
| Persistence (rebuildable cache) | `Microsoft.Data.Sqlite` (ADO.NET, MIT) |
| YAML | `YamlDotNet` |
| Markdown render | `Markdig` (parse + render to inline blocks) |
| Markdown editor | `AvaloniaEdit` |
| File watching | `FileSystemWatcher` + 30s polling failsafe |
| Notifications | Windows App SDK `AppNotificationManager` (works packaged + unpackaged) |
| Urgent alarms (AlarmKit equivalent) | Toast `scenario="alarm"` + `audio loop="true"` + foreground keepalive |
| Build | `dotnet publish -r win-x64 -c Release --self-contained` |
| Tests | xUnit + Avalonia.Headless + Moq |
| Packaging | Portable EXE → GitHub Releases (signed via Azure Artifact Signing); MSIX → Microsoft Store later; winget + Scoop manifests |

## Bundle ID

`io.github.saxonbobart.lists` (matches iOS/Android/Linux so the on-disk
markdown format is exchangeable).

## Targets

- **Min**: Windows 11 22H2 (best path for Mica/Acrylic + modern toast API)
- **Best-effort**: Windows 10 22H2 (ESU through Oct 2026; some chrome effects degrade gracefully)

## Why Avalonia and not WinUI 3 / MAUI

WinUI 3's open-source rollout only completes Q2 2026, NativeAOT is still
warning-laden, the XAML designer was discontinued, and a future Linux client
cannot reuse a single line of it. MAUI's 2026 has been a procession of
breaking regressions. Avalonia is MIT, Win32-native, ships Mica/Acrylic on
Win11, has FluentAvalonia (a faithful port of WinUI controls), and the same
codebase can later be redirected at the Linux client if that path becomes
attractive. Switching from Avalonia → WinUI 3 later is a 4–8 week port, not
a one-way door. Full reasoning in `research/windows-stack.md` §2.

## Storage layout

V1 ships with the `Lists/` folder under the user's Documents directory:

```
%USERPROFILE%\Documents\Lists\
├── 00000000000000000000INBOX0\
│   ├── .list.yml
│   └── <ulid>.md
└── …
```

User-visible (matches the iOS philosophy of "your data is a folder"). Naturally
sync-friendly with OneDrive, Dropbox, Syncthing, etc. The biggest gotcha is
**OneDrive Files-on-Demand**: walking the index over an online-only folder
will hydrate every file synchronously and freeze for minutes on first launch.
The cache rebuilder must check `FileAttributes.Offline` and skip-then-lazy-
hydrate.

## Build commands (once scaffolded)

```sh
# Restore + build all projects in the solution
dotnet build Lists.sln -c Release

# Run the desktop app
dotnet run --project src/Lists.Desktop

# Run tests
dotnet test

# Publish single-file portable EXE for Windows x64
dotnet publish src/Lists.Desktop -c Release -r win-x64 \
    --self-contained -p:PublishSingleFile=true -p:PublishTrimmed=true \
    -o dist/portable

# Publish MSIX (later)
dotnet publish src/Lists.Desktop -c Release -r win-x64 \
    /p:WindowsPackageType=MSIX
```

Cross-compile from macOS works (`dotnet publish -r win-x64` produces a Windows
binary on a Mac), but signing requires either an Azure Artifact Signing
subscription, an EV code-signing cert (~$300/yr), or community-trusted
fallbacks (sigstore, GitHub attestations) for the GitHub Releases path.

## First-tasks checklist (when building begins)

1. **Install .NET 9 SDK** + Avalonia templates (`dotnet new install Avalonia.Templates`).
2. **Create the solution + projects** with `dotnet new sln` + `dotnet new avalonia.app -o src/Lists.Desktop` + `dotnet new classlib -o src/Lists.Core` (replace the placeholders here).
3. **Wire Microsoft.Data.Sqlite, YamlDotNet, Markdig, AvaloniaEdit, FluentAvalonia 2.5.1** in the `.csproj`s.
4. **Port the iOS `FrontmatterCodec` + `YAMLCodec`** to C# in `Lists.Core/Storage/`. Use the `shared/fixtures/` corpus as the parity test set.
5. **Define the SQLite cache schema** mirroring `shared/cache/schema.sql`; codegen-free (raw `Microsoft.Data.Sqlite`).
6. **Implement `FileStore`** with `FileSystemWatcher` + 30s polling failsafe + `FileAttributes.Offline` check for OneDrive on-demand files.
7. **Wire the home grid + lists screen** in Avalonia XAML; FluentAvalonia gives `NavigationView`, `InfoBar`, etc. (Note: no Windows design mockups exist yet — a design pass is a prerequisite.)
8. **Implement the toast `scenario="alarm"`** path via `AppNotificationManager`. Test on Windows 11 22H2 with Focus Assist on.
9. **Hook FocusAssist** detection so the app can warn the user that quiet hours are suppressing alerts.
10. **Set up GitHub Actions** to publish portable EXE on tag, signed with Azure Artifact Signing or community-trusted fallbacks.

## AGPL on Microsoft Store

Microsoft Store policies do not blanket-prohibit AGPL the way the App Store
does. The relevant constraint is the Microsoft Standard Application License
Terms — the binary you ship must be licensable under MS's terms, but those
terms are compatible with AGPL once the source-availability requirement is
satisfied (link to GitHub repo from the Store listing). No "Section 7
exception" required for Windows. Reference: `research/windows-stack.md` §12.

## Status

**Not yet built.** This directory contains only structural placeholders so the
intended layout is reviewable. No buildable code lives here yet.

## See also

- [`research/windows-stack.md`](../../research/windows-stack.md) — full reasoning, alternatives, gotchas (the longest research doc — Windows is the highest-stakes UI choice)
- [`shared/`](../../shared/) — cross-platform format spec, fixtures, and lexicons
- **No design mockups exist for Windows** under `design/project/` (only iPad, macOS, Android, Linux). A Fluent design pass is a prerequisite to UI work.
