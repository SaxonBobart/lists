# Security & Privacy Audit

## Verdict
**Minor issues — the privacy promises mostly hold, with one real leak to close.** The app itself
writes **zero** networking code: no `URLSession`, no `WebKit`, no analytics/crash SDK, no secrets,
no account, and storage is genuinely app-private inside the sandbox. Path-traversal defense in
`FileStore.sanitize` is solid and I could not break it on paper. The one thing that contradicts the
"no network for local use" promise is **transitive**: MarkdownUI renders note bodies with its
default image provider, which fetches remote `![](http…)` images over the network via the bundled
`NetworkImage` library — a silent egress + privacy/IP-leak path triggered by ordinary user content.
Separately, a single malformed or maliciously-crafted `.list.yml`/`.md` (YAML alias bomb or bad
field) aborts the **entire** library load, since `loadAll` has no per-file error isolation.

## Findings

### [P1] Remote markdown images leak over the network, breaking the "no network" promise
- **Where:** `platforms/ios/Lists/Features/MarkdownEditor/MarkdownBodyView.swift:15` (renders
  `Markdown(source)` with no image provider override); reached from
  `platforms/ios/Lists/Features/Thread/ThreadView.swift:67` with `item.body` (user content).
  Default chain confirmed in MarkdownUI source: `Environment+ImageProvider.swift` default =
  `DefaultImageProvider` → `DefaultImageProvider.swift:7` `NetworkImage(url:)` →
  `NetworkImage/NetworkImageLoader.swift:35` `URLSession.data(from:)`.
- **What:** `MarkdownBodyView` is the read-only renderer for note bodies. It never sets
  `.markdownImageProvider(.asset)` or a no-op provider, so MarkdownUI's *default* provider is
  active. Any markdown image with an `http(s)` URL in a note body — e.g. `![](https://x/p.png)` —
  triggers an outbound HTTPS request the moment that note's thread view is shown. The app's own code
  has no networking, but it links MarkdownUI which transitively pulls in `NetworkImage`
  (`Package.resolved` → `networkimage` 6.0.1) and this fires it.
- **Impact:** The product's headline promise ("no network for local use," PRODUCT-SPEC.md) is
  violated on a plausible path. A note created locally, pasted in, or handed over via a future
  sync/import that contains a remote image URL becomes a **tracking pixel / IP-and-timing beacon**:
  viewing the note silently pings an arbitrary third-party server with the user's IP, locale, and
  timestamp. No prompt, no setting, no indication.
- **Confidence:** High (source chain traced end-to-end; provider default verified in the resolved
  package).
- **Fix:** Set an offline image provider on the renderer:
  `Markdown(source).markdownImageProvider(.asset).markdownInlineImageProvider(.asset)` (asset-only,
  never network), or a custom no-op `ImageProvider`. Optionally render `Color.clear` for image nodes
  until a local `Attachments/<uuid>` pipeline ships. This keeps the "no network for local use"
  promise literally true. Also consider whether `NetworkImage` should be linked at all given the
  privacy stance.

### [P1] One bad YAML file aborts the entire library load (DoS-on-load; alias-bomb amplification)
- **Where:** `platforms/ios/Lists/Core/Storage/FileStore.swift:146` (`try readList`), `:176`
  (`try itemFiles.map { try readItem }`) inside `walk`; propagates through `loadAll` to
  `Core/Stores/ItemStore.swift:25` (`try await store.loadAll()`) and is only `print`-logged at
  `App/ListsApp.swift:19`. Both decode sites use a bare `YAMLDecoder()` with no
  `aliasDereferencingStrategy` (`FileStore.swift:72`, `FrontmatterCodec.swift:33`).
- **What:** `walk` decodes every `.list.yml` and `.md` with `try`. A single corrupt file — bad date
  (`Item.swift:251`), missing required key, malformed UUID, or invalid YAML — throws and unwinds the
  whole walk, so `bootstrap` loads **nothing** and `isLoaded` is never set. Worse, because the
  decoder runs with no alias-dereferencing strategy, a YAML **alias bomb** (`a: &a [..]`, `b:
  &b [*a,*a,…]`, `c: &c [*b,*b,…]`, …) placed in any recognized collection field (e.g. `tags`,
  `completion_log`) expands exponentially in memory during parse (`Yams/Parser.swift:335`
  `loadAlias` returns the referenced subtree per reference) — OOM/hang.
- **Impact:** Files are explicitly the source of truth and the spec anticipates hand-editing and a
  future sync/worker writing them. One malformed/hostile file (a botched manual edit, a bad sync
  payload, or leftover sim data — see the team's own `keyNotFound: created_at` note) makes the app
  start up **empty** with only a console message, looking like total data loss to the user; an alias
  bomb can hang or kill the app on launch. This is reachable without any code execution — just a
  file on disk.
- **Confidence:** High for the abort-on-first-bad-file behavior; Med for the alias-bomb severity
  (Yams expands aliases by default, but I did not run it to measure the exact memory ceiling).
- **Fix:** Isolate failures per file in `walk`: wrap each `readList`/`readItem` in `try?` (or
  `do/catch`), skip + collect the failures, and surface them in a "couldn't read N files" UI rather
  than aborting. For the bomb, either cap input size before decode, reject documents containing
  aliases/anchors for these trusted-but-editable files, or set a bounded
  `aliasDereferencingStrategy`. This also de-risks the planned "Rebuild cache" feature.

### [P3] `lists://` URL scheme is declared but has no handler (dead attack surface)
- **Where:** declared in `platforms/ios/Lists/Info.plist:21-31` and `project.yml`
  `CFBundleURLTypes`; **no** `.onOpenURL`, scene delegate, or `UIApplicationDelegateAdaptor` exists
  anywhere (`ListsApp.swift` is a bare `App`/`WindowGroup`; grep for handlers found none).
- **What:** The app registers the `lists://` scheme but nothing consumes an incoming URL. Opening a
  `lists://…` link launches the app and routes nowhere.
- **Impact:** No exploit today (there's no handler to abuse — this is a *strength* in the sense that
  there's no insecure deep-link path). But a registered, unused scheme is surface area: when a
  handler is added later it must validate input from the start, and until then it's an undocumented
  capability. Doc/code drift too — the scheme is "declared" per the brief but unimplemented.
- **Confidence:** High.
- **Fix:** Either remove the `CFBundleURLTypes` entry until deep-linking is actually built, or, when
  you build it, treat the incoming URL as untrusted: whitelist host/path actions, never let a link
  delete/mutate data or navigate to attacker-chosen file paths, and require user intent for
  destructive actions.

### [P3] Test-only data-wipe path ships in the release binary
- **Where:** `platforms/ios/Lists/App/ListsApp.swift:27-28` — `if ProcessInfo…arguments.contains
  ("--ui-testing-reset-data") { try? FileManager.default.removeItem(at: root) }`, not wrapped in
  `#if DEBUG`.
- **What:** A launch-argument-gated `rm -rf Documents/Lists` lives in the shipping app. Launch
  arguments aren't user-settable on a normal release install (they need Xcode/a debugger), so the
  practical risk is low, but the destructive code is present in production.
- **Impact:** Low. A jailbroken device or a developer-tools attach could wipe the library; otherwise
  inert.
- **Confidence:** High.
- **Fix:** Wrap the block in `#if DEBUG` so it's compiled out of release builds.

### [P3] Bootstrap error (which may embed user-file content) is printed to the device console
- **Where:** `platforms/ios/Lists/App/ListsApp.swift:19` `print("Lists.bootstrap failed: \(error)")`.
- **What:** Decode errors can include offending values, e.g. `Invalid ISO 8601 date: <s>`
  (`Item.swift:253`, `ItemList.swift:148`). Interpolating the error can surface fragments of a
  user's file into the unified log.
- **Impact:** Low — it's a single error path, fragments not full bodies, and iOS console isn't
  network-exposed. Still, logging user-derived strings is a habit worth avoiding in a privacy-first
  app, especially before a real error UI lands.
- **Confidence:** Med (depends on which error fires; some include user values, most don't).
- **Fix:** Log the error *type*/category, not the interpolated value; or gate verbose logging behind
  `#if DEBUG`.

## Strengths
- **Genuinely no first-party networking.** Whole-app grep for `URLSession`/`URLRequest`/`import
  Network`/`http(s)://` literals returns nothing in `Lists/` (only one sample link inside a snapshot
  test). Imports are limited to SwiftUI, Foundation, UIKit, Observation, Yams, UserNotifications,
  MarkdownUI. No analytics/crash/telemetry SDK, no `NSUserTrackingUsageDescription`, no ATS
  exceptions in Info.plist.
- **Path-traversal defense is real.** `FileStore.sanitize` (`FileStore.swift:263`) replaces every
  `/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, `|`, `\0` with `-`, strips all leading dots (no hidden
  folders, kills `..`/`.`), trims trailing dots/whitespace, clamps to 80 chars, and falls back to
  `Untitled`. I traced `..`, `../x`, `x/../y`, absolute paths, null bytes — none can inject a path
  separator, and `appendingPathComponent` treats the result as a single component. Item filenames
  use `item.id.uuidString` (a validated `UUID`, `Item.swift:14`), and `listId` is only ever a
  dictionary key into `pathById`, never concatenated into a path — so a hostile `list` field can't
  traverse either.
- **Secrets / WebKit / dynamic-exec all clean.** No API keys/tokens in repo, Info.plist, or
  entitlements (all "secret/token" grep hits were `ListsTokens` design colors). No `WKWebView`,
  `JavaScriptCore`, `Process`, `dlopen`, or `NSClassFromString`. The KaTeX/mermaid-via-WKWebView
  work is **not present yet** (future XSS surface — see Coverage).
- **Entitlements minimal.** Only the App Group is declared (`Lists.entitlements`); no iCloud, push,
  keychain-sharing, or associated domains. The App Group container is **not referenced anywhere in
  code** (no `containerURL(forSecurityApplicationGroupIdentifier:)`, no shared `UserDefaults`) —
  nothing sensitive is shared because it's unused. Storage stays in `Documents/Lists/`,
  app-private. Settings even labels storage "App-private" and Sync "Not yet available."
- **No force-unwraps in the storage/model layer.** Zero `try!`/`as!`/`!.` in `Core/` — malformed
  YAML throws cleanly rather than crashing (the gap is *handling* those throws per-file, the P1
  above, not the decode itself). Export is a "Coming soon" placeholder, so there's no current
  data-egress-to-Files path to misuse.

## Coverage
Read fully: `FileStore.swift`, `StorageRoot.swift`, `FrontmatterCodec.swift`, `Item.swift`,
`ItemList.swift`, `ISO8601.swift`, `ItemStore.bootstrap`, `ListsApp.swift`, `MarkdownBodyView.swift`,
`PasteHandler.swift`, `EditorCoordinator` paste path, `SettingsView` (sync/data/about sections),
`Info.plist`, `Lists.entitlements`, `project.yml`, `Package.resolved`. Inspected the resolved
**MarkdownUI** image-provider chain and **NetworkImage** + **Yams** (alias/merge/decoder) sources in
DerivedData to confirm runtime behavior rather than guessing.

Whole-repo greps performed for: network APIs, WebKit/JS, http literals, secrets/tokens, logging
primitives, dynamic execution, pasteboard writes, App Group usage, URL-scheme handlers,
destructive `FileManager` calls, scene/app delegates.

**In-scope but future (flagged, not present in code):**
- **KaTeX & mermaid via WKWebView** (docs/CURRENT.md "Next Work") — when built, this becomes a real
  XSS/RCE surface. Requirements to set then: load from a bundled local HTML/JS payload only
  (`baseURL` to the app bundle, never remote), disable `allowsContentJavaScript` for any user-HTML
  path you don't control, sanitize/escape user input before injecting into the web context, and
  block navigation (`decidePolicyFor` → cancel non-bundle requests) so a crafted note can't load
  remote script or exfiltrate.

**Could not get to / would need runtime to confirm:** exact memory ceiling of a Yams alias bomb
(decode not executed — READ-ONLY). I did not exercise the markdown remote-image path on a simulator
to capture an actual outbound request (also out of READ-ONLY scope), but the static chain is
conclusive.
