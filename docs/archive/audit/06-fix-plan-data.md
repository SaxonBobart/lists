# Fix Plan — Data Integrity & Persistence

Ready-to-implement specs for the data-layer findings, in priority order. Each section gives **Where**
(exact `file:line` + current shape), **Change** (before→after Swift), **Test**, and **Regression risk**.

All paths are under `platforms/ios/Lists/` unless noted. Line numbers are from the audited revision
(`dev` @ `2b224f3`); re-confirm by eye before editing.

> **Sequencing note:** `BUILD-1` (last section) must land **first** so the snapshot/XCTest target compiles —
> otherwise none of the tests below can run. The functional order remains DI-1 → DI-2 → TASK-1/REM-1 → DI-3.

---

## 0. BUILD-1 — make the test target compile (do this first)

The whole `ListsTests` target currently fails to build, so every test below is dead until this is fixed.

### Where
`platforms/ios/ListsTests/SnapshotTests/SettingsViewSnapshotTests.swift:9-10`

```swift
private func host(store: ItemStore) -> UIHostingController<some View> {
    let view = SettingsView(store: store)      // ← stale: one-arg init
```

`SettingsView` now requires a second parameter (added in `2b224f3`):
`Features/Settings/SettingsView.swift:6-8`

```swift
struct SettingsView: View {
    let store: ItemStore
    @Bindable var autoListPrefs: AutoListPreferences   // ← new, no default
```

`AutoListPreferences` has a zero-arg init (`Core/Preferences/AutoListPreferences.swift:38`,
`init(defaults: UserDefaults = .standard)`), so a default-constructed instance is valid for a snapshot.

### Change
```swift
// before
let view = SettingsView(store: store)
// after
let view = SettingsView(store: store, autoListPrefs: AutoListPreferences())
```
(Optionally construct it against an ephemeral `UserDefaults(suiteName:)` so the snapshot isn't perturbed by
on-device prefs, but `.standard` matches the other snapshot hosts and is fine.)

### Test
This *is* the test fix. After it, run the full suite (`/test` skill → `ListsTests` + `ListsUITests`). Record
fresh reference images only if the Settings snapshot intentionally changed; otherwise existing references
should still match.

### Regression risk
None functional — test-only. If `__Snapshots__/SettingsViewSnapshotTests/` references were captured with the
old single-section view they may differ; treat a diff as "re-record", not "regression".

---

## 1. DI-1 — one bad file must not brick the whole library  *(P0, first)*

**Goal:** loading is per-file resilient. A single corrupt/truncated/unknown file is **quarantined** (moved
aside, not dropped), the rest of the library always loads, `isLoaded` is always set, and a banner surfaces the
problem instead of an eternal "Loading your lists…". Folds in **AGENT-2** (skip `_`-prefixed files) and
**AGENT-1** (permissive `ItemType` decode) so one bad value can never cascade into a full-library failure.

This is four coordinated edits: (1a) permissive `ItemType`, (1b) per-file isolation + quarantine in
`FileStore.walk`, (1c) carry quarantine info up through `ItemStore.bootstrap` and never wedge `isLoaded`,
(1d) surface a banner in `ContentView`.

### 1a — Permissive `ItemType` decoding (fixes AGENT-1)

#### Where
`Core/Models/Item.swift:58-60` (declaration) and `:174` (decode site).

```swift
public enum ItemType: String, Codable, Sendable, CaseIterable {
    case task, habit, note
}
...
self.type = try c.decode(ItemType.self, forKey: .type)   // throws on unknown "type:"
```
An unknown `type:` (e.g. a future `question`) throws `DataCorrupted`, which today aborts the whole load.

#### Change
Give `ItemType` a custom decoder that maps any unknown raw value to a safe fallback. Keep `task` as the
fallback (a stray unknown item then shows as an ordinary task rather than vanishing or bricking load). Add an
explicit `unknown`-tracking only if a later milestone needs round-trip fidelity; for now fallback-to-`task`
is the minimal safe change.

```swift
public enum ItemType: String, Codable, Sendable, CaseIterable {
    case task, habit, note

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ItemType(rawValue: raw) ?? .task   // unknown → safe fallback
    }
}
```
> The synthesized `encode(to:)` stays correct (writes the known raw value). A fallback-decoded item will be
> re-encoded as `task` only if it's edited+saved; until then its file is untouched, so no silent rewrite.

#### Test
`ItemTypeDecodingTests`:
- decode frontmatter with `type: question` → succeeds, `item.type == .task`.
- decode with `type: task|habit|note` → exact case preserved.

#### Regression risk
Very low. The only behavior change is "unknown type no longer throws." A malformed-but-known schema is
unaffected. Verify a normal seeded library still decodes all three real types unchanged (the decoding test
above covers it).

### 1b — Per-file isolation + quarantine in `FileStore.walk` (fixes DI-1 core + AGENT-2)

#### Where
`Core/Storage/FileStore.swift:130-195`. The all-or-nothing reads:
```swift
// :146
let list = try readList(at: listFile)
...
// :175-176
let itemFiles = entries.filter { $0.pathExtension == "md" }
let items = try itemFiles.map { try readItem(at: $0) }   // one throw aborts everything
```
There is no `_`-prefix filter (AGENT-2: a `_status.md` heartbeat decodes as an item and throws).

#### Change
Introduce a quarantine accumulator and a quarantine folder, isolate each `readList`/`readItem` in its own
`do/catch`, skip non-item dotfiles/`_`-prefixed files, and move offenders into `<root>/.quarantine/`
**(moved, never deleted)** so they don't re-fail every launch but remain recoverable.

Add to the type, near `LoadedList` (`:116-119`):
```swift
public struct QuarantinedFile: Sendable {
    public let originalPath: String   // pre-move path, for the banner/log
    public let reason: String         // error description
}
```

Change `loadAll()` to thread an accumulator and to return it alongside results:
```swift
// before  (:130-138)
public func loadAll() throws -> [LoadedList] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: root.path) else { return [] }
    pathById.removeAll()
    var results: [LoadedList] = []
    try walk(root, into: &results)
    return results
}

// after
public struct LoadResult: Sendable {
    public let lists: [LoadedList]
    public let quarantined: [QuarantinedFile]
}

public func loadAll() throws -> LoadResult {
    let fm = FileManager.default
    guard fm.fileExists(atPath: root.path) else { return LoadResult(lists: [], quarantined: []) }
    pathById.removeAll()
    var results: [LoadedList] = []
    var quarantined: [QuarantinedFile] = []
    try walk(root, into: &results, quarantined: &quarantined)   // dir enumeration may still throw — see risk
    return LoadResult(lists: results, quarantined: quarantined)
}
```

Rewrite the item-reading and list-reading portions of `walk` (signature gains
`quarantined: inout [QuarantinedFile]`):
```swift
// list read (:145-146) — isolate so a bad .list.yml quarantines the WHOLE folder's .list.yml
// but still lets sibling folders load
let list: ItemList
do {
    list = try readList(at: listFile)
} catch {
    quarantine(listFile, error: error, into: &quarantined)
    // No valid list header for this folder: skip it as a list, but still
    // recurse into subdirectories so nested lists aren't lost.
    try walkSubdirsOnly(dir, into: &results, quarantined: &quarantined)
    return
}

// item reads (:175-176)
let itemFiles = entries.filter {
    $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix("_")   // AGENT-2: skip heartbeats/aux
}
var items: [Item] = []
for url in itemFiles {
    do {
        items.append(try readItem(at: url))
    } catch {
        quarantine(url, error: error, into: &quarantined)   // bad item → aside, keep loading the rest
    }
}
```

Add the quarantine helper + a small subdir-only walker (so a bad `.list.yml` doesn't strand nested lists):
```swift
private func quarantine(_ url: URL, error: Error, into acc: inout [QuarantinedFile]) {
    let fm = FileManager.default
    let qDir = root.appendingPathComponent(".quarantine", isDirectory: true)
    try? fm.createDirectory(at: qDir, withIntermediateDirectories: true)
    // Preserve a unique name; never overwrite a previously-quarantined file.
    var dest = qDir.appendingPathComponent(url.lastPathComponent)
    var n = 2
    while fm.fileExists(atPath: dest.path) {
        let base = url.deletingPathExtension().lastPathComponent
        let ext  = url.pathExtension
        dest = qDir.appendingPathComponent("\(base) (\(n)).\(ext)")
        n += 1
    }
    let original = url.path
    try? fm.moveItem(at: url, to: dest)   // best-effort; if move fails the file simply stays put
    acc.append(QuarantinedFile(originalPath: original, reason: String(describing: error)))
}

private func walkSubdirsOnly(_ dir: URL, into results: inout [LoadedList],
                             quarantined: inout [QuarantinedFile]) throws {
    let fm = FileManager.default
    let entries = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
    for sub in entries where (try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
        try walk(sub, into: &results, quarantined: &quarantined)
    }
}
```
Also ensure the `.quarantine` directory itself is **not** walked as a list folder: at the top of `walk`, add
`if dir.lastPathComponent == ".quarantine" { return }` (it has no `.list.yml`, so today it's harmless, but
the guard makes intent explicit and stops a stray `.list.yml` dropped there from re-importing junk).

#### Test
`FileStoreQuarantineTests` (drive `FileStore`/`ItemStore` against a temp root, following `TestStore.seeded()`):
- **bad item** — write one valid item + one `.md` with no frontmatter into a list folder; `loadAll()` returns
  the valid item, `quarantined.count == 1`, the bad file now lives under `<root>/.quarantine/`, and the
  original path is gone.
- **unknown type** — with 1a in place, `type: question` is *not* quarantined (it loads as `.task`); a file
  with a missing required key (e.g. no `id`) *is* quarantined. Asserts the two paths differ.
- **`_`-prefixed file** — a `_status.md` is ignored entirely (not loaded, not quarantined).
- **bad `.list.yml`** — corrupt one list's header but leave a nested child list valid; assert the child still
  loads and the parent's `.list.yml` is quarantined.
- **no false quarantine** — a fully-valid seeded library yields `quarantined.isEmpty` and no `.quarantine`
  folder is created.

#### Regression risk
- **Re-seed guard.** `bootstrap` seeds sample data when `loadAll()` returns empty (`ItemStore.swift:27`). After
  this change, a library that is *all-bad* would return empty `lists` and could get re-seeded on top of the
  user's (broken) data. Mitigation: gate seeding on `loaded.lists.isEmpty && loaded.quarantined.isEmpty`
  (see 1c) so a quarantine-only load never re-seeds.
- **Directory enumeration** (`contentsOfDirectory`) still uses `try`; a folder that can't be listed at all
  still throws out of `walk`. That's an OS/permissions failure, not file corruption, and is acceptable for
  now — but note it so the banner copy doesn't over-promise "we recovered everything."
- The legacy folder-rename migration block (`:152-172`) is untouched; it already swallows its own errors.
- Quarantine moves mutate the user's tree during load. It only ever *moves into* `.quarantine` (never deletes),
  and only files that already failed to parse, so blast radius is contained.

### 1c — `ItemStore.bootstrap`: consume quarantine, never wedge `isLoaded`

#### Where
`Core/Stores/ItemStore.swift:23-49`. Today a throw before `:48` leaves `isLoaded == false` forever.

```swift
let loaded = try await store.loadAll()        // :25  (now returns LoadResult)
if loaded.isEmpty { ...seed... }              // :27
...
self.isLoaded = true                          // :48  (unreachable on throw)
```

#### Change
Add a published quarantine surface, adapt to `LoadResult`, guard seeding, and **always** set `isLoaded` via
`defer` so the app can never sit on the placeholder permanently.

```swift
public private(set) var isLoaded: Bool = false
public private(set) var loadIssues: [String] = []   // original paths of quarantined files; drives the banner

public func bootstrap() async throws {
    defer { self.isLoaded = true }                  // app is never permanently wedged, even on partial failure
    try await store.ensureRoot()
    let loaded = try await store.loadAll()
    self.loadIssues = loaded.quarantined.map(\.originalPath)

    if loaded.lists.isEmpty && loaded.quarantined.isEmpty {   // only seed a genuinely-empty library
        let inbox = ItemList.makeInbox()
        let extraLists = SampleData.seedLists()
        let allLists = [inbox] + extraLists
        for list in allLists { try await store.writeList(list) }
        let samples = SampleData.seedItems(inboxId: inbox.id)
        for sample in samples { try await store.writeItem(sample) }
        self.lists = allLists
        self.items = samples
    } else {
        self.lists = loaded.lists.map(\.list)
        self.items = loaded.lists.flatMap(\.items)
    }
    try await purgeExpiredTombstones()
    for list in self.lists where list.deletedAt == nil {
        try? await migrateLegacySectionsIfNeeded(listId: list.id)
    }
}
```
> `defer { isLoaded = true }` runs even if `ensureRoot()` / `purgeExpiredTombstones()` throws. That's the
> intended safety property: show *something* (an empty sidebar + banner) over hanging forever. The `ListsApp`
> `.task` `catch` (`App/ListsApp.swift:16-20`) still logs the throw.

#### Test
- `bootstrap` over a temp root containing one good + one corrupt item: after it, `isLoaded == true`,
  `loadIssues.count == 1`, the good item is in `items`, no sample data was seeded.
- `bootstrap` over an empty root: seeds as before (`loadIssues.isEmpty`, sample lists present).

#### Regression risk
- The seed condition tightened from `loaded.isEmpty` to `lists.isEmpty && quarantined.isEmpty`. Confirm
  first-run on a clean device still seeds (covered by the empty-root test).
- `defer`-setting `isLoaded` means a hard failure now shows an empty UI rather than a spinner — intended, but
  verify the empty-state UI is acceptable (it is reachable today via the all-deleted-lists path).

### 1d — Surface a banner in `ContentView` instead of silence

#### Where
`App/ContentView.swift:6-13`. Currently binary: `SidebarView` once loaded, else `BootstrapPlaceholder`.

#### Change
When `store.isLoaded` and `!store.loadIssues.isEmpty`, render the sidebar with a dismissible banner overlay.
Minimal version (no new files):
```swift
struct ContentView: View {
    @Bindable var store: ItemStore     // was: let store — needs binding to observe loadIssues/dismissal
    @State private var bannerDismissed = false

    var body: some View {
        if store.isLoaded {
            SidebarView(store: store)
                .safeAreaInset(edge: .top) {
                    if !store.loadIssues.isEmpty && !bannerDismissed {
                        QuarantineBanner(count: store.loadIssues.count) { bannerDismissed = true }
                    }
                }
        } else {
            BootstrapPlaceholder()
        }
    }
}
```
`QuarantineBanner` is a tiny view: a warning row "N item(s) couldn't be opened and were set aside" + a
"Dismiss" button, styled with existing `ListsTokens`/`ListsTypography`. Keep copy non-technical (Saxon is
non-technical — frame as a product effect, not "decode error"). Wording suggestion: *"N notes couldn't be
opened and were moved to a safe place. The rest of your lists loaded normally."*

> `ListsApp.swift:11` passes `store` positionally — `ContentView(store: store)` still compiles against the
> `@Bindable var store`. No call-site change needed.

#### Test
Snapshot `ContentView` (or just `QuarantineBanner`) in a `loadIssues = ["…"]` state — but `ContentView`
takes a live `ItemStore`, so the cheapest test is a `QuarantineBanner` snapshot following the existing
`SnapshotEnvironment` pattern (`ListsTests/SnapshotTests/`). Optionally a UI test asserting the banner's
accessibility id appears after launching with a seeded-then-corrupted container.

#### Regression risk
Low. `let store` → `@Bindable var store` is the only structural change; `@Bindable` requires the type be
`@Observable` (it is, `ItemStore.swift:7`). The banner is additive and dismissible. Verify VoiceOver reads
the banner (per the A11Y findings, give the row a clear label and the button a `.isButton` trait).

---

## 2. DI-2 — cross-list move must delete the old file  *(P0)*

**Goal:** changing an item's `listId` deletes `<oldList>/<id>.md` after the new file is written, so a reload
can never read two copies.

### Where
- `Core/Stores/ItemStore.swift:185-195` (`update`) and `:200-212` (`applyUpdateSync`) — both only write the
  new file; neither knows the old `listId`.
- `Core/Storage/FileStore.swift:77-96` — `writeItem` derives the path from `item.listId`; `deleteItem` exists
  and deletes `<listId>/<id>.md` for a given item. No `moveItem(_:fromListId:)`.
- User triggers: `Features/ItemDetail/ItemDetailSheet.swift:1045` (`item.listId = listId`) and `:702` (list
  picker); `Features/Habits/HabitDetailView.swift:376` (`draft.listId = list.id`).

```swift
// ItemStore.update — current
public func update(_ item: Item) async throws {
    var updated = item
    updated.modifiedAt = .now
    try await store.writeItem(updated)
    if let idx = items.firstIndex(where: { $0.id == item.id }) { items[idx] = updated }
    else { items.append(updated) }
    await scheduler.schedule(updated)
}
```

### Change
Detect a `listId` change against the **in-memory** copy (the source of truth for the old path), write the new
file, then delete the stale one. Add a dedicated `FileStore` helper so the delete-then-state is explicit and
reusable, and route both `update` and `applyUpdateSync` through it.

`FileStore` (after `writeItem`, ~`:83`):
```swift
/// Move an item's file from `oldListId`'s folder to its current `listId`
/// folder. Writes the new file first, then removes the old one (write-then-
/// delete: a crash between the two leaves a recoverable duplicate, never a
/// lost item). No-op delete if old == new.
public func moveItem(_ item: Item, fromListId oldListId: String) throws {
    try writeItem(item)                       // new path = item.listId
    guard oldListId != item.listId else { return }
    if let oldDir = pathById[oldListId] {
        let oldURL = oldDir.appendingPathComponent("\(item.id.uuidString).md")
        if FileManager.default.fileExists(atPath: oldURL.path) {
            try FileManager.default.removeItem(at: oldURL)
        }
    }
}
```

`ItemStore.update`:
```swift
public func update(_ item: Item) async throws {
    var updated = item
    updated.modifiedAt = .now
    let oldListId = items.first(where: { $0.id == item.id })?.listId   // in-memory = current on-disk path
    if let oldListId, oldListId != updated.listId {
        try await store.moveItem(updated, fromListId: oldListId)
    } else {
        try await store.writeItem(updated)
    }
    if let idx = items.firstIndex(where: { $0.id == item.id }) { items[idx] = updated }
    else { items.append(updated) }
    await scheduler.schedule(updated)
}
```

`ItemStore.applyUpdateSync` (mirror the same logic; capture `oldListId` *before* the in-memory assignment):
```swift
public func applyUpdateSync(_ item: Item) {
    var updated = item
    updated.modifiedAt = .now
    let oldListId = items.first(where: { $0.id == item.id })?.listId
    if let idx = items.firstIndex(where: { $0.id == item.id }) { items[idx] = updated }
    else { items.append(updated) }
    Task {
        if let oldListId, oldListId != updated.listId {
            try? await store.moveItem(updated, fromListId: oldListId)
        } else {
            try? await store.writeItem(updated)
        }
        await scheduler.schedule(updated)
    }
}
```

### Test
`CrossListMoveTests`:
- Seed two lists A, B; add item to A; `update` a copy with `listId = B`. Assert: exactly one `.md` for that
  id exists on disk, under B's folder; A's folder has none. Then call `loadAll()` and assert the item appears
  exactly once with `listId == B`.
- Same via `applyUpdateSync`, awaiting a short settle (the write is fire-and-forget; in the test, expose or
  await the in-flight `Task`, or assert against `loadAll()` after a yield).
- No-op case: `update` without changing `listId` leaves a single file and never calls delete (assert one file,
  unchanged path).

### Regression risk
- `moveItem` requires `oldListId` to be in `pathById`. If the old list was never mapped (e.g. it failed to load
  under DI-1), the delete is skipped — the new file still writes, so no data loss, just a possible residual old
  file. Acceptable and strictly better than today.
- Order is **write-new then delete-old**: a crash in between yields a duplicate (recoverable, and DI-1 won't
  brick on it) rather than an orphaned/lost item. Do not reorder to delete-first.
- `incrementHabit`/`setHabitCount`/`toggleDone`/`softDelete`/`restore` never change `listId`, so they keep
  calling `writeItem` directly — no change needed there. Only the two general `update` paths route through
  `moveItem`.

---

## 3. TASK-1 + REM-1 — recurrence expansion engine  *(P1, highest functional value)*

**Goal:** completing a recurring **task** generates the next occurrence from its stored RRULE (TASK-1), and
because a future `due` then exists, the reminder re-arms naturally on the new item (REM-1). One engine resolves
both. Do **not** just flip `repeats:false` → `true` (it would misfire — see verification REM-1).

### Where the RRULE already lives (reuse, don't reinvent)
- Model: `Core/Models/Reminder.swift:76-82` — `Recurrence { var rrule: String }`. Comment at `:74-75` says
  "expansion lives elsewhere (out of scope for M0)" — **this is that elsewhere.**
- Compose/parse vocabulary already implemented:
  - `Features/QuickCapture/QuickCaptureSheet.swift:1199-1265` — `RepeatPreset` with `.rrule` producing
    `FREQ=HOURLY|DAILY|WEEKLY|MONTHLY|YEARLY`, `INTERVAL=N`, `BYDAY=MO,TU,WE,TH,FR` / `SA,SU`.
  - `Features/QuickCapture/RepeatCustomSheet.swift:99-141` — `CustomRRule.make`/`parse` for
    `FREQ=…;INTERVAL=…;UNTIL=…`.
  - `Features/ItemDetail/ItemDetailSheet.swift:1063-1075,1114-1145` — `composeRRule`/`parseRecurrence`
    (handles `;UNTIL=yyyyMMdd'T'HHmmss'Z'`).
- Consumption point: `Core/Stores/ItemStore.toggleDone:77-91` — flips `done`, never reads `recurrence`.

### Change — new file `Core/Recurrence/RecurrenceEngine.swift`
A small pure function: given a fired `due` date and an RRULE string, return the next `due` (or `nil` when the
series has ended). Keep it dependency-free and total (never throws; unparseable → `nil` = series ends safely).

Parse only the fields the app emits today (`FREQ`, `INTERVAL`, `BYDAY`, `UNTIL`); unknown fields ignored.
```swift
import Foundation

enum RecurrenceEngine {
    /// Next occurrence strictly after `from`, advancing by the rule. Returns
    /// nil when the rule is unparseable or the next date would be past UNTIL.
    static func nextOccurrence(after from: Date, rrule: String,
                               calendar: Calendar = .current) -> Date? {
        let parts = Dictionary(uniqueKeysWithValues: rrule
            .split(separator: ";")
            .compactMap { p -> (String, String)? in
                let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                return kv.count == 2 ? (kv[0].uppercased(), kv[1]) : nil
            })
        guard let freq = parts["FREQ"] else { return nil }
        let interval = max(1, Int(parts["INTERVAL"] ?? "1") ?? 1)
        let until = parts["UNTIL"].flatMap(Self.parseUntil)

        let next: Date?
        switch freq {
        case "HOURLY":  next = calendar.date(byAdding: .hour,  value: interval, to: from)
        case "DAILY":   next = calendar.date(byAdding: .day,   value: interval, to: from)
        case "WEEKLY":
            if let byday = parts["BYDAY"] {            // e.g. weekdays / weekends
                next = nextWeekday(after: from, byday: byday, intervalWeeks: interval, calendar: calendar)
            } else {
                next = calendar.date(byAdding: .weekOfYear, value: interval, to: from)
            }
        case "MONTHLY": next = calendar.date(byAdding: .month, value: interval, to: from)
        case "YEARLY":  next = calendar.date(byAdding: .year,  value: interval, to: from)
        default:        next = nil
        }
        guard let n = next else { return nil }
        if let until, n > until { return nil }         // series ended
        return n
    }

    private static func parseUntil(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)
    }

    /// Smallest date after `from` whose weekday ∈ byday set, preserving the
    /// time-of-day of `from`. `intervalWeeks` is honored for plain weekly
    /// rules; for BYDAY sets (weekdays/weekends) interval is typically 1.
    private static func nextWeekday(after from: Date, byday: String,
                                    intervalWeeks: Int, calendar: Calendar) -> Date? {
        let map: [String: Int] = ["SU":1,"MO":2,"TU":3,"WE":4,"TH":5,"FR":6,"SA":7]
        let wanted = Set(byday.split(separator: ",").compactMap { map[$0.uppercased()] })
        guard !wanted.isEmpty else { return nil }
        // Step day-by-day up to 7*intervalWeeks+7 days; first matching future day wins.
        for offset in 1...(7 * max(1, intervalWeeks) + 7) {
            guard let cand = calendar.date(byAdding: .day, value: offset, to: from) else { continue }
            if wanted.contains(calendar.component(.weekday, from: cand)) { return cand }
        }
        return nil
    }
}
```
> Time-of-day: `calendar.date(byAdding:.day/.month/...)` preserves the wall-clock components of `from`, so a
> 9:00 AM due stays 9:00 AM. For `BYDAY`, stepping by whole days from `from` likewise preserves the time. Good
> enough for the rules the UI can currently produce; richer RRULE (BYMONTHDAY, COUNT) is out of scope until the
> compose UI emits them.

### Change — wire it into completion (`ItemStore.toggleDone`)
Only **tasks** spawn a next occurrence (habits track via `completionLog`, not duplication; notes don't
complete). Generate the next item only on the *completing* transition, and only when a future occurrence
exists.

`Core/Stores/ItemStore.swift:77-91`:
```swift
public func toggleDone(_ id: UUID) async throws {
    guard var item = items.first(where: { $0.id == id }) else { return }
    item.done.toggle()
    item.completedAt = item.done ? .now : nil
    item.modifiedAt = .now
    try await store.writeItem(item)
    if let idx = items.firstIndex(where: { $0.id == id }) { items[idx] = item }

    if item.done {
        await scheduler.cancel(item.id)
        // Recurrence expansion: spawn the next occurrence for a completed task.
        if item.type == .task,
           let rrule = item.recurrence?.rrule,
           let base = item.due,                 // need an anchor date to advance from
           let nextDue = RecurrenceEngine.nextOccurrence(after: base, rrule: rrule) {
            var next = item
            next.id = UUID()                     // new item = new file (basename is the id)
            next.done = false
            next.completedAt = nil
            next.due = nextDue
            next.createdAt = .now
            next.modifiedAt = .now
            try await add(next)                  // writes file + schedules its reminder (REM-1 re-arms here)
        }
    } else {
        await scheduler.schedule(item)
    }
}
```
> Using `add(next)` (`:126-132`) reuses the existing write+`scheduler.schedule` path, so the new occurrence's
> reminder is scheduled exactly like any dated item — that *is* the REM-1 fix. No change to
> `NotificationScheduler` is required; `repeats:false` stays correct because each occurrence is now a discrete
> dated item.

**Design choices to confirm with Saxon (product, plain language):**
- *"When you tick off a repeating task, should the next one appear right away?"* — this plan: **yes**, the
  next dated copy is created immediately on completion (matches Reminders/Things behavior).
- A repeating task **with no due date** can't advance (no anchor) — it just completes once. If desired, fall
  back to "advance from `.now`" instead of bailing; the code above bails (safer/clearer). Flag for decision.
- `UNTIL` in the past or unparseable RRULE → no next occurrence (series quietly ends) — intended.

### Test
`RecurrenceEngineTests` (pure, fast — no store needed):
- `FREQ=DAILY` from a fixed date → +1 day; `INTERVAL=2` → +2 days; same for WEEKLY/MONTHLY/YEARLY/HOURLY.
- `FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR` from a Friday → next Monday; from a Tuesday → Wednesday.
- `FREQ=WEEKLY;BYDAY=SA,SU` from a Sunday → next Saturday.
- `UNTIL` earlier than the next computed date → `nil`; `UNTIL` later → returns the date.
- Garbage / missing `FREQ` → `nil`. Time-of-day preserved (assert hour/minute equal across the advance).

`ToggleDoneRecurrenceTests` (store-level, temp root):
- Complete a `FREQ=MONTHLY` task with a due date → a *second* item exists with `done==false`, `due` one month
  later, a **different** id; original stays `done==true`. Assert `items` count grew by exactly one.
- Complete a non-recurring task → no new item.
- Complete a recurring task whose `UNTIL` has passed → no new item.
- Un-complete (toggle back to not-done) → never spawns (only the `done==true` branch spawns).
- Recurring **habit** completion (via `incrementHabit`) → no duplicate item (habits use `completionLog`).

### Regression risk
- **Duplicate spawning on rapid double-toggle.** Two `toggleDone` calls landing both as `done==true` could
  spawn two next occurrences (compounded by CONC-1's await window). Low odds on single-device tap-once usage;
  if it bites, guard with "only spawn when the *transition* was false→true" by reading the pre-toggle `done`
  (already implied since we toggle a local copy — capture `let wasDone = item.done` before `toggle()` and gate
  on `!wasDone && item.done`). Recommended to add that guard.
- **Editing the original after completion** doesn't retro-edit the spawned occurrence — expected (they're
  independent items, like Reminders).
- New file `RecurrenceEngine.swift` must be added to the Lists target membership (Xcode project); otherwise it
  won't compile into the app. Mirror the folder convention under `Core/`.
- No change to encode/decode, so on-disk format is unchanged and backward-compatible.

---

## 4. DI-3 — a present-but-invalid `deleted_at` must fail safe  *(P1)*

**Goal:** a tombstone that is *present but unparseable* must not silently resurrect a deleted item. Treat
"present + invalid" as an error so DI-1's per-file quarantine catches it, rather than mapping to `nil` (= live).

### Where
- `Core/Models/Item.swift:259-265` — `decodeDateIfPresent` returns `nil` on a present-but-bad string:
```swift
private static func decodeDateIfPresent(
    _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
) throws -> Date? {
    guard let s = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
    return ISO8601.date(from: s)     // bad string → nil → "not deleted" / value silently dropped
}
```
Used for `completedAt` (`:185`), `due` (`:186`), `deletedAt` (`:198`).
- Identical code in `Core/Models/ItemList.swift:153-159`, used for `deletedAt` (`:113`).

### Change
Make the helper distinguish **absent** (→ `nil`, fine) from **present-but-invalid** (→ throw
`dataCorruptedError`). The throw is then caught by DI-1's per-file `do/catch` and the file is quarantined —
the item stays *out* of the live set (fail-safe) and the user is told via the banner, instead of a deleted
note silently reappearing.

`Item.swift`:
```swift
private static func decodeDateIfPresent(
    _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
) throws -> Date? {
    guard let s = try c.decodeIfPresent(String.self, forKey: key) else { return nil }  // absent → nil
    guard let date = ISO8601.date(from: s) else {
        throw DecodingError.dataCorruptedError(
            forKey: key, in: c,
            debugDescription: "Invalid ISO 8601 date: \(s)")
    }
    return date
}
```
Apply the **same** edit to `ItemList.decodeDateIfPresent` (`ItemList.swift:153-159`).

> This deliberately makes `completed_at`/`due`/`deleted_at` strict-when-present. A corrupt optional date now
> quarantines the file rather than silently dropping the value — consistent with the required-date behavior at
> `Item.swift:245-257` and `ItemList.swift:139-151`.

### Sequencing
**Depends on DI-1 (1b/1c).** If this lands *before* per-file quarantine, a single mangled optional date would
throw straight out of `loadAll` and brick the whole library — exactly the failure DI-1 fixes. Ship DI-1 first,
or ship them together. Do **not** ship DI-3 alone.

### Test
`OptionalDateDecodingTests`:
- Frontmatter with `deleted_at:` set to a garbage string → `Item` decode **throws** (assert
  `DecodingError.dataCorrupted`). With DI-1 wired, a `loadAll` over such a file quarantines it and the item is
  absent from `lists`/`items` (i.e. stays deleted-from-view), with `quarantined.count == 1`.
- Frontmatter with **no** `deleted_at` → decodes fine, `deletedAt == nil` (regression guard that "absent"
  still means "live").
- Same two cases for `due` and `completed_at`, and for `ItemList.deleted_at`.

### Regression risk
- Any genuinely-malformed optional date that previously loaded "successfully" (with the value silently
  dropped) will now route the file to quarantine. That's the intended stricter behavior, but it widens what
  gets quarantined — verify a normal seeded library (all dates valid) has zero quarantine (covered by the
  DI-1 "no false quarantine" test). 
- Export round-trips / future sync that emit non-standard date strings would now quarantine instead of silently
  degrading. Confirm `ISO8601.string(from:)`'s own output (`.withInternetDateTime, .withFractionalSeconds`)
  round-trips through `ISO8601.date(from:)` — it does (datetime formatter), and date-only `yyyy-MM-dd` is also
  accepted (`ISO8601.swift:28-30`), so app-written files are never self-quarantined.

---

## Suggested landing order (one branch each, all behind the test target)
1. **BUILD-1** — unblock the test target. *(prerequisite for everything below)*
2. **DI-1** (1a→1b→1c→1d) — read-path resilience + permissive type + skip `_` files + banner.
3. **DI-3** — strict-when-present optional dates *(rides on DI-1's quarantine; never ship alone)*.
4. **DI-2** — `moveItem` delete-old-on-list-change.
5. **TASK-1 + REM-1** — `RecurrenceEngine` + `toggleDone` wiring (+ false→true transition guard).

Each step ships with its tests green (`/test`). DI-3 is grouped right after DI-1 because it *requires* the
quarantine net to be safe.
