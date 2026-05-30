# Agent-Lists — Code-Grounded Feasibility & Architecture-Fit Analysis

*Read-only audit. Scope: does the "agent list" idea (`_agent-lists-handoff.md`) fit the* **real** *Lists
codebase as it stands today? Maps each handoff element onto actual files, judges effort, and flags
what MUST be fixed first. The handoff is a direction to pressure-test, not a spec.*

## Bottom line (for a non-technical product owner)

The agent-list idea is **architecturally compatible** with how Lists already stores data — files of
Markdown-with-YAML, one item per file, smart lists as live queries. Most of the *data* work (new
fields, a `question` type, four status sections) is **small**. But the headline premise — "an external
worker process reads and writes the list's files directly" — **cannot work on iOS today**, full stop:
an iOS app's `Documents` folder is sandboxed and no outside process can reach it. So the protocol can
be designed now, but a real worker needs *either* the deferred desktop client *or* the deferred sync
layer to have anywhere to run. On top of that, the moment two writers (the app + a worker) touch the
same files you hit the exact lost-update problem the audit already flagged (CONC-1, DI-1, DI-2), and
the proposed file-lock ("claim") is **not safe** over async iCloud. Recurring agent jobs depend on a
feature (recurrence) that is currently **broken** (TASK-1). My recommendation: treat this as a
**desktop/sync-era feature**, and the smallest honest experiment today is a *read-only* "agent status"
view inside the app driven by files a first-party helper writes — not an open "bring your own
OpenClaw" protocol.

---

## 1. The iOS sandbox blocker (lead with this)

**The core premise of the handoff does not hold on iOS as the app is built today.** The handoff
imagines "an external agent process (OpenClaw, Hermes, etc.) that reads and writes the list's markdown
files directly… files-only; no custom API." On iOS that arbitrary external process **does not exist
and cannot exist** for these files:

- The library lives at `<app sandbox>/Documents/Lists/` — confirmed in
  `Core/Storage/StorageRoot.swift` (`documentDirectory` + `"Lists"`), and its own doc-comment says
  *"app-private (NOT in Files.app, NOT iCloud Drive)."* Project memory (`project_sync_model`) reinforces
  this: "iOS = app-private storage at `Documents/Lists/` (NOT in Files.app)."
- iOS has no general-purpose background daemons or cross-app filesystem access. Nothing outside the
  Lists app — certainly not a third-party CLI agent — can `open()` a file under another app's
  container. There is no path to "OpenClaw running on your phone tailing the folder." This is a
  platform guarantee, not a missing feature.

So "files-only, worker-agnostic, no API" is a **desktop/server mental model** that has been dropped
onto an iOS-only app. The real question is *where could a worker actually run, and what does each
option cost?* Four candidate paths:

### (a) macOS / desktop client with a user-chosen folder (security-scoped bookmarks) — **viable, but gated on the desktop client**

On macOS an app *can* be granted persistent access to a user-picked folder via a security-scoped
bookmark, and a separate local worker process the user runs could read/write that same folder. This is
the **only** path where the handoff's "external process touches the files directly" is literally true
and OS-blessed. **But Lists has no desktop client** — per `project_multi_platform_plan` memory, all
cross-platform scaffolding was retired (commit 57fb450) and "iOS-only for now." So this path is real
in principle but **entirely gated on building a Mac app first** — a large, deferred undertaking. Not
near-term.

### (b) iOS App Group container + app extension — **partially viable, but it is NOT an "arbitrary external worker"**

The app already declares `group.io.github.saxonbobart.lists` in `Lists.entitlements`. An App Group
gives a shared container that the main app *and a first-party app extension* (or a future widget /
App Intent / Background Task) can both read. **Two hard caveats:**

1. **It is still your own signed code.** An App Group is shared only among extensions of the *same*
   developer's app. It can never host "OpenClaw / Hermes" or any third-party binary. The "worker" here
   would be first-party Swift you write and ship — the opposite of the handoff's "app is
   worker-agnostic, conforms to a documented file protocol" framing.
2. **It is not currently used at all.** I grepped the whole iOS target: there are **zero** references
   to the App Group identifier or `containerURL(forSecurityApplicationGroupIdentifier:)` in code, and
   the store reads/writes `Documents/Lists/`, *not* the group container. The entitlement is dead
   scaffolding today. To use it you'd first have to **migrate the library into the group container**
   (a real, careful data move) — otherwise an extension literally can't see the files.
   - And even then, iOS extensions/background tasks are **short-lived and OS-scheduled** — you cannot
     run a persistent agent loop. At best you get brief, opportunistic execution (a Background Task
     waking for seconds). A *local* LLM agent doing real work in that window is not realistic; the
     extension could at most ferry results an external service produced.

**Verdict:** useful as the *plumbing* for a first-party helper or a "sync results in" mechanism, but it
does **not** deliver the handoff's vision of an arbitrary external worker, and it needs a data
migration before it does anything.

### (c) Via the future sync layer — worker runs on a server/desktop copy, changes sync back — **the most credible path, but gated on sync**

This is the cleanest fit with both the platform reality and the existing design. Per
`local-first-sync.md`, the planned model is CloudKit/CKSyncEngine (or an eventual server). If sync
exists, a worker can operate on a **server-side or desktop-side replica** of the user's library and its
writes propagate back to the phone like any other device's edits. The phone app stays a pure reader of
the worker's results; it never needs the worker to touch its sandbox.

This reframes "agent list" from *"an external process edits my phone's files"* (impossible) to *"a
worker is just another sync peer"* (natural). **But:** sync is the deferred, likely-paid feature; it
does not exist yet, and it requires a paid Apple Developer account the repo doesn't have
(`local-first-sync.md`; `project_m6_deferred`). So this is **gated on Lists Sync shipping** — and it
inherits every concurrency hazard in §2 below, because the worker becomes a genuine concurrent writer.

### (d) Files.app / File Provider exposure — **viable as plumbing, but explicitly against current policy and still doesn't host a worker**

Lists could opt into Files.app visibility (`LSSupportsOpeningDocumentsInPlace` /
`UIFileSharingEnabled`, or a File Provider extension) so the library appears in Files and, via
iCloud Drive, on a Mac where a worker could run. **Two problems:** (1) it's a deliberate **non-goal**
today — memory and `StorageRoot`'s own comment say the data is intentionally *not* in Files.app; (2)
on its own it still doesn't give you an on-device worker — it just relocates the "worker runs on the
Mac" story, i.e. it collapses into path (a)/(c). The `storage-format.md` research is relevant here:
exposing the raw folder also raises the bar on file-format robustness (DI-1/DI-2 become user-facing).

### The unused `lists://` scheme — minor, not a worker channel

`Info.plist` declares a `lists://` URL scheme, and like the App Group it has **zero code references**
(no `onOpenURL`, no handler). It could let a *local* worker hand a small payload *back* to the app
(e.g. "open this list / I answered a question") via a custom URL, but it's a thin signalling channel,
not a data path, and it's entirely unbuilt.

### §1 verdict

| Path | Hosts an *arbitrary* worker? | Near-term on iOS-only? | Gated on |
|---|---|---|---|
| (a) macOS + security-scoped bookmarks | Yes (local process) | **No** | Desktop client (deferred) |
| (b) App Group + extension | **No** (first-party code only; short-lived) | Plumbing only; needs data migration | — (but limited) |
| (c) Future sync layer (worker = sync peer) | Yes (off-device) | **No** | Lists Sync (deferred, paid) |
| (d) Files.app / File Provider | No (relocates to (a)/(c)) | Against current policy | Desktop/iCloud |

**The "files-only external worker" cannot be delivered on the current iOS-only app. It gates on the
deferred desktop client or the deferred sync layer.** Anything shippable *now* is necessarily a
**first-party** helper writing files the app reads — not the open protocol the handoff describes.

---

## 2. Concurrency & data safety

The handoff introduces a **second writer** (the worker) to files the app already writes. This collides
head-on with hazards the audit has already documented for the *single*-writer case:

- **CONC-1 (concurrency.md):** actor-reentrancy "lost update" across the `await` in every `ItemStore`
  mutator (`toggleDone`, `update`, `incrementHabit`, …). Today this is low-frequency because the UI
  drives one action at a time; the audit explicitly warns it "will rise sharply once background sync
  writes concurrently." A worker is exactly that concurrent writer.
- **DI-1 (data-integrity.md, P0):** one bad file makes the *whole* library unloadable. `loadAll` →
  `walk` reads every `.md` with `try` and no per-file `do/catch` (`FileStore.swift:176`), and bootstrap
  never sets `isLoaded = true` on failure. **A worker that writes one malformed or half-written file
  bricks the entire app** until the file is removed — and the user has no in-app recovery.
- **DI-2 (data-integrity.md, P0):** cross-writer races aside, the read path is fragile to partial
  writes. The app's *own* writes are atomic (`write(to:atomically:true)`, `FileStore.swift:82`), but a
  third-party worker writing files with the same name has **no obligation** to be atomic — a
  non-atomic worker write observed mid-flight is a torn frontmatter, which trips DI-1.
- **Sync research field-merge recommendation:** `local-first-sync.md` already prescribes "merge the
  Markdown body as text; last-write-wins per structured field; `completion_log` must union, not
  overwrite." Two writers on the body without that contract = **silent prose loss**.

### Is the proposed claim mechanism a safe lease?

The handoff proposes `claimed_by` / `claimed_at` in frontmatter, with "stale claims auto-release after
N minutes." As a **file-based advisory lease**:

- **On a single plain filesystem (one machine, e.g. a desktop worker + a desktop app):** it can be made
  *reasonably* safe but only with care. The classic correct primitive is **atomic create-exclusive of a
  separate lock file** (`O_CREAT|O_EXCL`) or an atomic rename, *not* "read the frontmatter, see it's
  empty, write my id" — that read-modify-write is itself a race (two workers both read "unclaimed" and
  both write their own claim). Crucially, **the current `writeItem` always overwrites the whole file**
  (`FileStore.swift:77-83`); it has **no compare-and-set** ("write only if `claimed_by` is still
  empty"). So the claim would have to be enforced by a *new* atomic primitive, not the existing write
  path. Even then it's *advisory* — it only works if every writer voluntarily checks it, and a stale
  release window (worker died mid-task) can hand the same item to two workers.

- **Over async iCloud / CloudKit (the realistic multi-writer transport, per §1c):** **the claim is not
  safe and largely cannot be made safe as a plain file.** Reasons, all grounded in `local-first-sync.md`:
  - **No atomic compare-and-set across devices.** iCloud/CloudKit reconcile *eventually*; there is no
    distributed lock. Two peers can both write a claim while offline.
  - **Propagation lag.** A claim written on the worker may not reach the phone for seconds-to-minutes;
    "others skip claimed items" fails when others can't yet *see* the claim.
  - **Conflict copies.** iCloud Drive produces conflicted-copy files on simultaneous edits; CloudKit
    rejects stale writes and hands you both versions to merge (`local-first-sync.md`). A "claim" caught
    in a conflict is meaningless as a lock.
  - **Clock skew.** "Stale after N minutes" relies on `claimed_at` timestamps from *different machines*;
    skew makes the release window unreliable.
  A file-as-lock over eventual-consistency storage is a known anti-pattern; real leases need a single
  authoritative coordinator (a server with CAS), which Lists does not have and the local-first model
  resists.

### What becomes mandatory before any second writer touches these files

1. **DI-1 read-path hardening is a hard prerequisite** (per-file `do/catch` + quarantine + always set
   `isLoaded`). Non-negotiable: without it, *any* worker misstep is a total-data lockout.
2. **DI-2 / atomic-write contract for the worker** — the file protocol must *mandate* atomic
   writes (temp-file + rename) and a strict schema, or the app must treat all externally-authored files
   as untrusted and validate-then-quarantine.
3. **Field-level merge policy written down first** (`local-first-sync.md`): which fields are LWW, that
   the body needs text-merge, that `completion_log` unions. The worker writing `status`/`answer` while
   the user edits the body is the data-loss trigger.
4. **The claim must be a real atomic primitive, not the current whole-file overwrite** — and even then
   it is only sound on a single filesystem, *not* over async sync. Honest conclusion: **safe claiming is
   a property of the transport, not of the frontmatter.** On a local desktop filesystem: achievable with
   care. Over iCloud: treat "claim" as a soft hint at best, and assume last-write-wins will occasionally
   double-assign or clobber.

---

## 3. Model fit (each handoff element → real code, small vs large)

| Handoff element | Maps onto | Change size | Notes |
|---|---|---|---|
| **New frontmatter fields** (`status`, `claimed_by`, `claimed_at`, `scheduled_at`, worker fields) | `Item.swift` `CodingKeys` + `init(from:)` | **Small** | The decoder is forward-tolerant: every optional field uses `decodeIfPresent` with a default (`Item.swift:178-199`). Adding scalar fields is backward/forward compatible by construction. Encoder mirrors with `encodeIfPresent`. |
| **New item type `question`** | `Item.ItemType` enum (`Item.swift:58`) | **Small-to-medium, with a real hazard** | Adding a case is trivial. **But `ItemType` is a raw-`String` `Codable` enum decoded with `c.decode(ItemType.self)` (`Item.swift:174`) — a *non-optional* decode that THROWS on an unknown value.** An older app build (or a non-updated sync peer) reading a `type: question` file would throw → trip DI-1 → brick the library. Forward-compat for *types* is not handled (unlike fields). Mitigation: a permissive `init(from:)` for `ItemType` (unknown → a fallback case), which is a deliberate schema decision. |
| **`question` child rendering** (tick/cross, choice chips, "other" text; answer unblocks parent) | New UI in `Features/…`; `parentId` already exists (`Item.swift:21`) and is used for sub-items | **Medium** (pure UI/UX build) | The data shape (parent/child via `parentId`, free fields) is already there; this is net-new view + interaction work, not a model rework. The "on answer, write file, parent transitions back to Working" is an `ItemStore` mutator — but see CONC-1: that write races with worker writes. |
| **Four status sections** (Needs Attention / Working / Scheduled / Completed) as live queries over `status` | `SmartList.swift` is exactly this pattern | **Small-to-medium** | `SmartList.matches(_:now:includeCompleted:)` already filters the in-memory `items` array by predicate (`ItemStore.items(for:)`). Four agent sections = four predicates on a new `status` field. The enum is `CaseIterable`/`Identifiable` and drives sidebar UI already. Caveat: `status` derivation (e.g. "Working = in_progress + valid claim") must encode the claim-validity logic, and "Scheduled = future `scheduled_at` **or** recurring habit" pulls in the recurrence gap below. |
| **Recurring agent jobs reuse habits** | `Item` habit fields + `HabitCycle` + `NotificationScheduler` | **LARGE — blocked on TASK-1** | **Recurrence is non-functional today.** Confirmed in code: `NotificationScheduler.schedule` only ever builds `UNCalendarNotificationTrigger(…, repeats: false)` from `item.due` and **never reads `item.recurrence`** at all; `ItemStore.toggleDone` just flips `done`/`completedAt`. `Recurrence.swift` itself says *"recurrence expansion lives elsewhere (out of scope for M0)"* — and there is **no expander anywhere** (grep: `rrule` appears only in models + capture UI). This is logged as **TASK-1** (`audit/_PROGRESS.md:33`) and is prioritized in STRAT-4. The handoff's "habit's recurrence machinery handles scheduling; each fire spawns a child task" **assumes machinery that does not exist.** Also note: iOS can't run the spawn-on-schedule loop in the background anyway (§1b). So "recurring agent jobs" depends on (a) fixing TASK-1 *and* (b) a place for the scheduler to actually run (sync/desktop). |
| **`_status.md` heartbeat** (`current_task`, `next_scheduled`, `last_active`, `summary`; status dot from freshness) | New: a per-list sidecar file + a reader; **no existing analogue** | **Medium** | `FrontmatterCodec` already parses Markdown-with-YAML generically, so reading `_status.md` reuses that codec. But it's a **new file kind** outside the item/list model — `loadAll`/`walk` currently recognize only `.list.yml` (list folders) and `*.md` (items). `_status.md` would be read by `walk` as if it were an *item* (it has `.md` extension) and **fail to decode** (no `id`/`type`/`created_at`) → DI-1 brick. So this needs `walk` taught to skip/redirect `_status.md`, plus a small watcher to re-read on change. Live file-watching on iOS (the "app reads file directly on change") is itself non-trivial for an *external* writer, and impossible if the writer can't reach the sandbox (§1). |
| **Worker config in `.list.yml`** (`worker_type`, `worker_endpoint`) | `ItemList.swift` `CodingKeys` + `init(from:)` | **Small** | Same forward-tolerant decoder pattern as `Item` (`ItemList.swift:101-116`, all `decodeIfPresent`). Adding optional list-level config fields is cheap and safe to roll out. |
| **Worker/agent provenance** | `Item.createdBy` **already exists** (`Item.swift:33`, defaults `"human"`) | **Trivial / already there** | A nice latent fit: the schema already anticipates non-human authorship (`createdBy: "human"`). A worker's items/answers could set `createdBy: "agent:<id>"` with zero schema change. |

**Net:** the *data model* absorbs this idea with surprisingly little friction (one primitive +
forward-tolerant frontmatter + smart-list queries is a good substrate). The **large**, blocking pieces
are not modeling at all — they're (1) the missing **recurrence engine** (TASK-1), (2) the **read-path
robustness** required before any second writer or new file kind exists (DI-1), and (3) the **runtime/
transport** to host a worker (§1). Two smaller schema landmines: `ItemType` decode throws on unknown
(forward-compat for new types), and `_status.md` would be mis-read as an item by `walk`.

---

## 4. Product fit

**Where it strengthens the positioning:** the *files-as-protocol* instinct is genuinely on-brand. "Your
agent and your app talk through plain Markdown you own" is a beautiful expression of the "you own your
data, local-first, no proprietary API" promise (`_BRIEF.md`). A *calm, read-only* "what is my agent
doing" surface — a status bubble, a Needs-Attention queue you answer with a tick — is differentiated and
fits the "calm, native, personal" feel. No competitor in the audit's set (Things, NotePlan, Obsidian,
TickTick — `market-competitors.md`) frames agent work as "items in your own file-based list."

**Where it dilutes / risks scope-explosion (candidly, the larger column):**

- **It imports a multi-process, networked, concurrent-writer mental model into an app whose entire
  current value is being a calm, single-user, single-device, local store.** That is a *category* change,
  not a feature. The audit's two **P0** data-loss bugs (DI-1, DI-2) and the CONC-1 lost-update class all
  get **worse** under a second writer; shipping agent-lists before those are fixed actively endangers the
  core promise. `monetization.md` is blunt about the adjacent version of this: "do not charge a cent
  until the data-loss bug is fixed (DI-1) and sync works… a trust-destroying betrayal."
- **"Worker-agnostic, bring your own OpenClaw/Hermes" is at odds with the native-only, no-third-party,
  curated-feel ethos** (`feedback_editor_pure_swift_native`, the calm brand). An open file protocol for
  arbitrary external binaries is a *developer-tool* posture, not a *calm-consumer-app* posture. The user
  base implied by "configure your worker endpoint" is a tiny power-user slice, while the cost lands on
  everyone's data-integrity surface.
- **It competes for the same scarce build budget as the things the research says actually move the
  needle.** `task-ux.md` / STRAT-4 rank the high-leverage work as: **fix recurrence (TASK-1) →
  natural-language capture → widgets/App Intents**. Recurrence is *also* a hard dependency of
  agent-lists, so fixing it is doubly justified — but the *rest* of agent-lists is a large detour from
  the table-stakes a tasks/habits/notes app still lacks.
- **Honest risk:** done eagerly on the current iOS-only base, this is a **differentiator on paper that
  becomes a scope-explosion and a data-safety liability in practice**, because the platform won't host
  the worker and the foundations aren't hardened.

**Verdict:** the *idea* is on-brand; the *current-app implementation* is premature. It is a credible
**desktop/sync-era flagship feature**, not a near-term iOS feature.

---

## Phased recommendation

**MUST be fixed first (independent of agent-lists, and prerequisites for it):**
1. **DI-1 read-path hardening** (per-file quarantine; always set `isLoaded`). Hard gate — any second
   writer or new file kind can otherwise brick the whole library.
2. **TASK-1 recurrence engine.** Required for "recurring agent jobs," and the #1 product gap anyway
   (STRAT-4). Fixing it is the one piece of agent-lists work that pays for itself immediately.
3. **Decide the field-level merge contract** (`local-first-sync.md`) on paper — *before* any concurrent
   writer exists.

**Smallest viable experiment (shippable-ish on iOS, honest about the sandbox):**
A **first-party, read-mostly "Agent view."** Add the forward-compatible fields (`status`,
`scheduled_at`, optional `claimed_by/at`, list-level `worker_*`) and a `question` type (with a permissive
`ItemType` decoder so old builds don't brick). Render the four status sections as `SmartList`-style
queries and the `_status.md` bubble (teach `walk` to skip `_status.md`). The *writer* is **not** an
arbitrary external process — it's either (i) a first-party helper via the App Group container (after the
data migration), or (ii) deferred entirely to a manual/dev harness on the simulator for the experiment.
This proves the *UX* of "answer your agent's question with a tick" without pretending an external worker
can reach the sandbox. **Crucially, the app's writes stay authoritative; the "worker" is a stub.**

**Full vision (gated, desktop/sync era):**
The handoff as written — arbitrary external worker, files-only protocol, claim-based leases, hosted
vs local workers — becomes realistic **only** once *either* (a) a **macOS client** exists (worker as a
local process on a user-chosen folder via security-scoped bookmarks), *or* (b) **Lists Sync** ships
(worker as just another sync peer; the phone never needs the worker to touch its sandbox). Both are
explicitly deferred. At that point, treat the claim as a transport property: enforceable with atomic
file-locking on a single desktop filesystem, but only a soft hint over async iCloud — so design for
last-write-wins + conflict surfacing, not for distributed locks.

**Top risks (ranked):**
1. **Sandbox reality vs the premise** — the whole "external worker edits the files" idea has no home on
   iOS-only; it silently presumes desktop or sync.
2. **Data-loss amplification** — a second writer turns DI-1/DI-2 from latent P0s into routine outages,
   and CONC-1 lost-updates from rare into common.
3. **Claim-as-file-lock is unsafe over async sync** — no CAS, propagation lag, conflict copies, clock
   skew; will double-assign / clobber.
4. **Recurrence dependency (TASK-1)** — "recurring agent jobs" is built on machinery that doesn't exist.
5. **`ItemType` forward-compat** — unknown `type: question` throws on decode and bricks older/peer
   builds unless the decoder is made permissive first.
6. **Scope dilution** — a power-user/developer-tool posture competing for budget against the table-stakes
   (NL capture, widgets) the app still lacks, while the calm/native/private brand argues against an open
   "bring-your-own-binary" protocol.

---

## Coverage / what I verified

Read in full: `Core/Models/Item.swift`, `ItemList.swift`, `HabitCycle.swift`, `Reminder.swift`
(holds `Recurrence`, `Triggers`); `Core/Storage/FileStore.swift`, `FrontmatterCodec.swift`,
`StorageRoot.swift`; `Core/Stores/ItemStore.swift`; `Core/Queries/SmartList.swift`;
`Core/Notifications/NotificationScheduler.swift`; `Lists.entitlements`; `Info.plist`. Cross-read the
audit inputs (`data-integrity.md`, `concurrency.md`, `local-first-sync.md`) and the handoff.
**Confirmed by grep:** the App Group id and `lists://` scheme have **zero** code references (both dead
scaffolding); `recurrence`/`rrule` appears only in models + capture UI with **no expander** anywhere;
`Item.createdBy` already exists and defaults to `"human"`; TASK-1 is logged at `audit/_PROGRESS.md:33`.
**Did not run the app** (read-only audit); the concurrency/claim conclusions are reasoned from the code
and the prior audits, not observed at runtime.
