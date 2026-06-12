# Local-first architecture & the future sync layer — Research

## Bottom line (for a non-technical product owner)
Lists has already made the single most important sync decision correctly: files are the source of truth, each item is one Markdown file, and deletes leave a "tombstone" so a future sync can tell "deleted" apart from "never existed." That foundation is sound and worth keeping. The recommended path is **CloudKit via CKSyncEngine** as the v1 paid "Lists Sync" — it's free to run (it uses each user's own iCloud storage), Apple-native, works offline, and is the obvious fit for an Apple-only indie. You do **not** need the heavy machinery (CRDTs like Automerge/Yjs) that the collaborative-editing world uses — that's built for many people typing in the same document at once, which Lists is not. The one real data-loss risk to fix is the **note body**: if the same note is edited on two offline devices, a naive "newest file wins" rule silently throws away one person's edits. The cheap insurance to add now is (a) keep an unbreakable stable ID per item, (b) bump a reliable `modified_at` on every change, and (c) plan to merge the Markdown body as text (the way Obsidian does) while letting the structured fields use simple last-write-wins.

## What the landscape / best practice looks like (May 2026)

### The local-first movement still endorses "files + simple sync," not "CRDTs for everyone"
The founding Ink & Switch essay (Kleppmann, Wiggins, van Hardenberg, McGranaghan) still frames local-first as a *spectrum*, not a single technology: "Some apps use peer-to-peer, others use a server with end-to-end encryption, while others still just have a partial cache on the client." ([Ink & Switch](https://www.inkandswitch.com/essay/local-first/), [PowerSync history](https://powersync.com/blog/local-first-software-origins-and-evolution)) CRDTs are presented as a *promising foundation* for the hardest case (real-time multi-writer collaboration), explicitly not a requirement for owning your data offline.

The most useful recent signal is a team that **abandoned CRDTs**. Cinapse moved off Automerge because, for field-based data (their app edited "individual properties or fields," not collaborative prose), per-character conflict resolution was "overkill," the accumulated edit history blew past WebAssembly's 4GB memory ceiling, and some customers cost "$1,000/month on Automerge sync servers." Switching to a server-authoritative model cut hosting 66% and support tickets 89%. Their conclusion: CRDTs are appropriate for "text editing and smaller, simpler data structures — not [large] enterprise … datasets." ([PowerSync / Cinapse](https://powersync.com/blog/why-cinapse-moved-away-from-crdts-for-sync)) That maps almost exactly onto Lists: the YAML frontmatter is *fields* (CRDT is overkill); only the freeform Markdown *body* is text where a smart merge matters.

### CRDTs (Automerge / Yjs) — strong tech, wrong weight class for single-user
- **Automerge 3.0** (2025) fixed the historical memory problem: pasting *Moby Dick* into a doc went from ~700MB (Automerge 2) to ~1.3MB. Automerge 2's binary format already stored full history with only ~30% overhead — under one byte per character — versus 1,300 bytes/char in the old JSON encoding. ([Automerge 2](https://automerge.org/blog/automerge-2/), [Automerge 3 / BigGo](https://biggo.com/news/202508071934_Automerge_3.0_Memory_Improvements))
- **Yjs** is the most battle-tested for live collaborative editors but carries per-version overhead (a Version Vector + Delete Set per saved version) on top of document size. ([crdt-benchmarks](https://github.com/dmonad/crdt-benchmarks), [Yjs](https://github.com/yjs/yjs))
- **Fit with file-per-item:** poor as a *storage* format. A CRDT document is an opaque binary blob carrying full edit history; storing one per item destroys the "plain Markdown you own and can read in any editor" promise that is core to Lists. CRDTs would have to live *beside* the files, not *as* the files — extra complexity for a single-user app. They are also pure-JS/WASM (Automerge, Yjs); using them from Swift means embedding a runtime, which clashes with the founder's "native-only, no third-party editor libs" rule. **Verdict: defer; only revisit if Lists ever ships real-time multi-user collaboration.**

### Option 1 — iCloud / CloudKit (CKSyncEngine) — recommended v1
- **What it is:** Apple's sync framework (introduced iOS 17, mature on the iOS 26 target). The CloudKit *private database* "goes against the user's account quota" — so **Apple hosts it for free to the developer**; the user spends their own iCloud storage. Apple's published free dev-tier ceilings (40 req/s, 100MB shared DB, 10GB assets) scale per user. ([Apple CloudKit](https://developer.apple.com/icloud/cloudkit/), [Apple Forums – pricing](https://developer.apple.com/forums/thread/715649))
- **Conflict handling:** CloudKit uses **record change tags**; when you push a record whose tag is stale, the server rejects it as a conflict and hands you the newest version "asking you what you want to do." There is **no built-in three-way merge** — you write the policy per field. You *can* fetch the `ancestorRecord` to do a true three-way merge, though Apple's sample doesn't. ([Superwall](https://superwall.com/blog/syncing-data-with-cloudkit-in-your-ios-app-using-cksyncengine-and-swift-and-swiftui/), [Christian Selig](https://christianselig.com/2026/01/cksyncengine/))
- **Deletes/tombstones:** CKSyncEngine "will trust you know what you are doing and just delete it" — it does **not** auto-reconcile deletes. **This is exactly why Lists' existing `deletedAt` tombstone is the right design** — Lists already has the deletion-intent record CKSyncEngine won't compute for you. ([Christian Selig](https://christianselig.com/2026/01/cksyncengine/))
- **Offline:** changes enqueue locally and replay on reconnect; engine state survives crashes ("if your app crashes part way through … it will simply be restored"). ([Christian Selig](https://christianselig.com/2026/01/cksyncengine/))
- **E2E encryption:** standard CloudKit is encrypted in transit/at rest but **Apple holds the keys** — not true zero-knowledge E2E unless the user has Advanced Data Protection enabled (then CloudKit private DBs become E2E for free, no work from Lists). So Lists can *honestly* say "syncs through your private iCloud, Apple-grade encryption," and gets true E2E automatically for ADP users. ([Apple CloudKit](https://developer.apple.com/icloud/cloudkit/))
- **Dev cost / gotchas:** Moderate. You must persist `CKRecord` system fields locally (to keep change tags), avoid enums on synced values (forward-compat), and handle `quotaExceeded` by re-queuing. Requires a **paid Apple Developer Program membership** to enable the CloudKit entitlement — a real gating cost given the repo currently signs with a free Personal Team. ([Christian Selig](https://christianselig.com/2026/01/cksyncengine/), [Ryan Ashcraft](https://ryanashcraft.com/what-i-learned-writing-my-own-cloudkit-sync-library/))

### Option 2 — Obsidian Sync model (the closest real-world analogue)
Obsidian syncs a *folder of Markdown files* — the same shape as Lists — and is the best template for *conflict UX*:
- **Markdown bodies are merged** with Google's **`diff-match-patch`** algorithm (a text three-way merge that combines both sides' changes). **"Last modified wins" applies only to non-Markdown files.** ([DeepWiki – Obsidian Sync](https://deepwiki.com/obsidianmd/obsidian-help/2-obsidian-sync-service), [Obsidian Forum](https://forum.obsidian.md/t/encryption-version-conflicts/81339))
- Since v1.9.7 the user can choose **auto-merge (default)** or **"create a conflict file"** for manual review — a calm, data-safe fallback. ([Obsidian Forum – manual resolve](https://forum.obsidian.md/t/option-to-let-user-manually-resolve-sync-conflicts/94468))
- **E2E:** AES-256-GCM, "Obsidian servers never see the plaintext or the key." Some *metadata* (uploading device, timestamp, path↔content mapping, file size) is **not** E2E because it's needed to coordinate sync/version history. ([Obsidian – verify encryption](https://obsidian.md/blog/verify-obsidian-sync-encryption/), [DeepWiki – security](https://deepwiki.com/obsidianmd/obsidian-help/2.2-security-and-encryption))
- **Pricing (proves the paid model):** Sync Standard ~$4/mo (1GB, 1-month history); Sync Plus ~$10/mo (10–100GB, 12-month history). ([DeepWiki – Obsidian Sync](https://deepwiki.com/obsidianmd/obsidian-help/2-obsidian-sync-service))
- **Takeaway for Lists:** copy the *policy*, not the *backend*. "Merge the text body, last-write-wins the structured fields, optionally drop a conflict copy" is the gold-standard pattern for a Markdown-file app — and it works regardless of whether the transport is CloudKit, git, or a custom server.

### Option 3 — git-based (Working Copy on iOS)
Power users already git-sync Obsidian vaults on iOS via Working Copy + Shortcuts (Working Copy Pro to push). git's 3-way merge handles non-overlapping edits well, but **overlapping edits produce conflict markers the user must resolve by hand**, and the whole flow (pull → resolve → commit → push) is manual unless automated; tools like GitSync add interval auto-commit + an on-device merge UI. ([Megan Sullivan](https://meganesulli.com/blog/sync-obsidian-vault-iphone-ipad/), [Obsidian Forum – Working Copy](https://forum.obsidian.md/t/mobile-setting-up-ios-git-based-syncing-with-mobile-app-using-working-copy/16499), [GitSync](https://gitsync.viscouspotenti.al/)) **Fit:** great as an *optional power-user backup/export/version-history* path (and a strong "you truly own your data" story), poor as the *default consumer sync* — too technical, conflict markers are hostile to a "calm" app. It also presupposes Files.app/folder visibility, which the repo deliberately does not expose today.

### Option 4 — custom server sync
Maximum control (true E2E, cross-platform when Android/desktop arrive, your own pricing). But it means running, securing, and paying for infrastructure, plus building auth, encryption, and conflict logic from scratch — heavy for a solo dev, and it forfeits CloudKit's free per-user storage. Server-authoritative replication products (PowerSync, etc.) reduce the build but reintroduce hosting cost. ([PowerSync / Cinapse](https://powersync.com/blog/why-cinapse-moved-away-from-crdts-for-sync)) **Fit:** only justified later if (a) cross-platform sync becomes a priority or (b) zero-knowledge E2E becomes a paid selling point Apple's stack can't deliver.

### iCloud Drive "Documents" (folder-of-files) — a tempting trap
Letting the OS sync `Documents/Lists/` via iCloud Drive sounds free, but Apple's own guidance requires routing *every* read/write through `NSFileCoordinator` and resolving `NSFileVersion` conflict versions yourself; developers widely call the API "too low level," with conflict frameworks that "require custom implementation for file-based sync." ([Apple TN2336](https://developer.apple.com/library/archive/technotes/tn2336/_index.html), [objc.io](https://www.objc.io/issues/10-syncing-data/icloud-document-store/), [Zottmann deep dive](https://zottmann.org/2025/09/08/ios-icloud-drive-synchronization-deep.html)) You'd still have to write the same merge logic as CKSyncEngine but with a clunkier API and silent file-coordination footguns. **Prefer CKSyncEngine over raw iCloud Drive document sync.**

## Implications for Lists ← most important

**Recommended order:**
1. **NOW (cheap insurance, no backend):** make the data sync-ready and lock the merge contract.
2. **v1 paid "Lists Sync": CloudKit + CKSyncEngine.** Free hosting, native, offline, Apple-grade encryption, true E2E for Advanced-Data-Protection users at no extra effort. Adopt Obsidian's policy: **merge the Markdown body as text; last-write-wins per structured field; optional "conflicted copy" item.**
3. **Optional power-user track:** expose the library to Files.app/iCloud Drive (and document a Working Copy/git workflow) for the "you own your data / version history" crowd — additive, not the default.
4. **Defer:** CRDTs (only if real-time multi-user collaboration ships) and a custom server (only if cross-platform or zero-knowledge E2E becomes a paid differentiator).

**Do these NOW so you don't paint into a corner:**
- **Keep the stable per-item UUID and the `id`-named file** — this is the join key every sync backend needs. (Already true.) ✅
- **Keep tombstones (`deletedAt`)** — every option that doesn't auto-reconcile deletes (CKSyncEngine, git, custom) needs them, and they're already in the frontmatter and purged at 30 days. ✅ Just confirm tombstones survive long enough: a device offline for >30 days could miss a delete. Consider making the purge window configurable / longer once sync ships.
- **Guarantee `modified_at` is bumped on *every* mutation** and is monotonic. The store sets `modifiedAt = .now` on writes, soft-deletes, and restores — audit that *all* paths (tag edits, reorder/`sortIndex`, section edits, habit `completionLog` increments) update it, because LWW is only as good as the timestamp it trusts.
- **Decide the merge granularity per field, on paper, before writing sync code.** Whole-file LWW is the data-loss landmine: editing a note's body on two offline devices means one device's prose vanishes silently. The body needs *text merge*; fields are safe with LWW. Writing this contract down now shapes how you store/compare records later.
- **`completion_log` is the one field that must NOT be LWW** — it's a dictionary of per-day habit counts. Two devices logging different days must *union/sum*, not overwrite. Treat it as a mergeable map (a tiny, hand-rolled CRDT-like rule), not a scalar. This is the single highest-value design call hiding in the current model.
- **Avoid raw enums on anything you'll sync** (forward-compat per CKSyncEngine guidance) — already mostly fine since enums encode to stable strings, but keep decoders permissive (they already default unknown/missing keys). ✅
- **Get the paid Apple Developer Program account before committing to the CloudKit path** — the CloudKit entitlement requires it; the repo currently uses a free Personal Team.

**Is the tombstone approach enough — or do they need per-field timestamps / CRDTs?**
- **Tombstones: enough for deletes.** They're the correct, minimal mechanism and already implemented; no CRDT needed for deletion.
- **Per-field timestamps: not required for v1, but per-field *merge policy* is.** You don't need a timestamp on every field, but you do need to decide *which* fields are LWW (most), which merge as text (the body), and which union (`completion_log`, `tags`). That's a small rules table, not CRDTs.
- **CRDTs: not needed** for a single-user app — confirmed by both the Ink & Switch framing and the Cinapse retreat. They'd break the "files are plain Markdown" promise and add a JS/WASM runtime the native-only rule rejects. Keep them on the shelf for a hypothetical collaboration feature only.

## Open questions / things to validate
- **Body-merge implementation in Swift:** is there a maintained `diff-match-patch` (or similar 3-way text merge) the founder will accept, given the "no third-party libs" stance? diff-match-patch is an *algorithm*, not an editor lib — a small native port may be acceptable where a CRDT runtime is not. Validate appetite.
- **Does Lists want true zero-knowledge E2E as a paid promise?** If yes, standard CloudKit isn't enough for non-ADP users; that pushes toward a custom encrypted server (heavier) or relying on Advanced Data Protection adoption.
- **Tombstone retention vs. long-offline devices:** confirm 30 days is safe once sync exists, or lengthen/condition it on sync being enabled.
- **Multi-file atomicity:** today each file is written atomically (temp+rename) but a single user action can touch several files (cascade delete, reparenting, reorder). Under sync these can arrive partially on another device. Decide whether per-file eventual consistency is acceptable (likely yes) or whether some actions need a grouped "transaction" marker.
- **CloudKit free-tier headroom at scale:** per-user private DB is free, but the *shared* container limits (req/s, public assets) need a back-of-envelope check if onboarding spikes.

## Sources
- [Ink & Switch — Local-first software: You own your data, in spite of the cloud](https://www.inkandswitch.com/essay/local-first/)
- [PowerSync — Local-First Software: Origins and Evolution](https://powersync.com/blog/local-first-software-origins-and-evolution)
- [PowerSync — Why Cinapse Moved Away From CRDTs For Sync](https://powersync.com/blog/why-cinapse-moved-away-from-crdts-for-sync)
- [Automerge 2.0 announcement](https://automerge.org/blog/automerge-2/)
- [BigGo — Automerge 3.0 Cuts Memory Usage by 10x](https://biggo.com/news/202508071934_Automerge_3.0_Memory_Improvements)
- [dmonad/crdt-benchmarks](https://github.com/dmonad/crdt-benchmarks)
- [Yjs (GitHub)](https://github.com/yjs/yjs)
- [Apple — CloudKit](https://developer.apple.com/icloud/cloudkit/)
- [Apple Developer Forums — Current CloudKit pricing](https://developer.apple.com/forums/thread/715649)
- [Apple — sample-cloudkit-sync-engine](https://github.com/apple/sample-cloudkit-sync-engine)
- [Superwall — Syncing data with CloudKit using CKSyncEngine and Swift](https://superwall.com/blog/syncing-data-with-cloudkit-in-your-ios-app-using-cksyncengine-and-swift-and-swiftui/)
- [Christian Selig — CKSyncEngine questions and answers](https://christianselig.com/2026/01/cksyncengine/)
- [Ryan Ashcraft — What I Learned Writing My Own CloudKit Syncing Library](https://ryanashcraft.com/what-i-learned-writing-my-own-cloudkit-sync-library/)
- [DeepWiki — Obsidian Sync Service](https://deepwiki.com/obsidianmd/obsidian-help/2-obsidian-sync-service)
- [DeepWiki — Obsidian Security and Encryption](https://deepwiki.com/obsidianmd/obsidian-help/2.2-security-and-encryption)
- [Obsidian — How to verify Obsidian Sync's end-to-end encryption](https://obsidian.md/blog/verify-obsidian-sync-encryption/)
- [Obsidian Forum — Encryption & Version Conflicts](https://forum.obsidian.md/t/encryption-version-conflicts/81339)
- [Obsidian Forum — Option to let user manually resolve sync conflicts](https://forum.obsidian.md/t/option-to-let-user-manually-resolve-sync-conflicts/94468)
- [Megan Sullivan — Sync your Obsidian Vault on iOS with GitHub, Working Copy, and Apple Shortcuts](https://meganesulli.com/blog/sync-obsidian-vault-iphone-ipad/)
- [Obsidian Forum — iOS git-based syncing with Working Copy](https://forum.obsidian.md/t/mobile-setting-up-ios-git-based-syncing-with-mobile-app-using-working-copy/16499)
- [GitSync — Mobile Git Client](https://gitsync.viscouspotenti.al/)
- [Apple — TN2336: Handling version conflicts in the iCloud environment](https://developer.apple.com/library/archive/technotes/tn2336/_index.html)
- [objc.io — Mastering the iCloud Document Store](https://www.objc.io/issues/10-syncing-data/icloud-document-store/)
- [Carlo Zottmann — iOS iCloud Drive Synchronization Deep Dive](https://zottmann.org/2025/09/08/ios-icloud-drive-synchronization-deep.html)
