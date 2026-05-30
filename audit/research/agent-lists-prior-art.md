# External prior art & patterns for the "agent list" idea — Research

## Bottom line (3–5 sentences, plain English, for a non-technical product owner)

The "files-as-the-interface for agents" idea is genuinely mainstream in May 2026 — `AGENTS.md`, Claude Code's markdown plans/tasks, and `todo.md`-driven agents all prove that plain files are a great, durable way to coordinate an AI worker, so the instinct is sound. The single biggest risk is not the UX, it's **letting two writers (the app and an external worker) edit the same files** — on a plain filesystem this needs an atomic claim, and over async sync like iCloud it is effectively unsafe (iCloud silently destroys "losing" versions and even renames files to `… 2`, which would orphan your data). The "question / approval" moment is well-studied: copy LangChain's **Agent Inbox** (accept / edit / respond / ignore) and use the handoff's `risk: low|high` to gate *only* the costly actions, because the real failure mode of these systems is **approval fatigue** — people who are asked too often stop reading and rubber-stamp. Reality check: **OpenClaw and Hermes are real tools** (OpenClaw ~247k GitHub stars, creator joined OpenAI in Feb 2026), but neither is a "files-only task-list worker" — OpenClaw is messaging-app-centric — so the honest framing is a *documented file protocol* that real BYO workers (Claude Code headless, Aider, OpenHands) can be scripted against, not a partnership with a named product. Given that "Agent integrations" is already on the Deferred list and the data is local-only today, this is a strong *future* direction, not a now-thing.

## What the landscape / best practice looks like (May 2026)

### 1. Markdown / file-as-agent-interface — proven and ascendant
- **`AGENTS.md`** is now a de-facto standard: a root markdown file telling agents how to build/test/navigate a repo. Reported adoption in **60,000+ open-source projects**, supported by VS Code (1.105+), Copilot, Cursor, Windsurf, Gemini CLI, Zed, Warp, Aider, RooCode. In **Dec 2025 it was donated to the Agentic AI Foundation** (Linux Foundation), alongside Anthropic's MCP and Block's Goose. ([augmentcode.com][agentsmd], [github spec-kit][speckit])
- **Claude Code's own state lives in files.** A "plan" is literally a markdown file Claude writes to a plans folder in plan mode, then reads back to execute. Its **Tasks** feature persists work as markdown and — crucially for the agent-list idea — supports a **DAG where one task can `block` another** (Task 3 can't start until Tasks 1 & 2 finish). Plans/todos are deliberately persisted so they survive context compaction. ([code.claude.com plan][ccplan], [VentureBeat tasks][cctasks], [Ronacher][planmode])
- **`todo.md`-as-attention-anchor** is a documented technique: agents like Manus keep a `todo.md`, checking items off as they go, specifically to re-focus the model and preserve state. ([Ronacher][planmode])
- **Spec-driven development (SDD)** generalises this: an executable, version-controlled spec is the single source of truth; the agent derives a plan, atomises tasks, then writes code, updating the spec to "reflect reality" as it works. ([thebcms][sdd], [github spec-kit][speckit])
- **What works about files:** durability (survives crashes/restarts), inspectability (a human can read/diff them), tool-agnosticism (any worker can read/write them), and they double as an audit log via version history. This is exactly the bet Lists already makes ("files are the source of truth").

### 2. Human-in-the-loop / agent-inbox UX — mature patterns to copy
- **LangChain Agent Inbox** is the reference UX. An agent `interrupt()`s; the human sees a queued item and chooses from a small, explicit verb set: **Accept** (run as proposed), **Edit** (change the args first), **Respond** (free-text reply / "ask user"), **Ignore** (dismiss). Each interrupt carries `action_request` (name + args, name becomes the header), a `config` of boolean flags (which verbs are allowed *for this interrupt*), and an optional **markdown `description`** for context. It's a **pull-based inbox**, explicitly built to avoid the notification overload of Slack-style pings. ([github agent-inbox][inbox], [langchain HITL][lchitl], [ambient agents][ambient])
- **LangGraph HITL middleware** pauses on tool calls matching an `interrupt_on` policy and resumes with approve/edit/reject/respond — i.e. you choose *which* tools require a human, not all of them. ([langchain HITL][lchitl])
- **Devin's "ask" flow** is confidence-gated: it asks clarifying questions when its confidence isn't "green," waits for approval when unsure about a plan, and otherwise proceeds and accepts async feedback. Lesson: **uncertainty, not a fixed rule, triggers the question.** ([cognition devin2.1][devin21], [devin docs][devindocs])
- **Cloud background agents (OpenAI Codex, Cursor)** run async in sandboxed VMs and hand back a PR — the human reviews at the *commit/PR boundary*, not every step. Codex disables internet during a run; Cursor (Feb 2026) added Computer-Use so agents verify their own UI changes. ([nxcode codex-vs-cursor][nxcode], [morph cursor][morph])
- **Risk-tiered confirmation** is an established design (directly maps to the handoff's `risk: low|high`). A common taxonomy: **Tier 0 auto-execute** (reads/idempotent), **Tier 1 notify-don't-block** (drafts, internal notes — review in a digest), **Tier 2 synchronous approval** (sends, deletes, bulk writes), **Tier 3 multi-party** (payments, contracts). ([truto][truto])
- **The dominant failure mode is approval fatigue:** "when users are bombarded with approval requests, they stop reading the payloads and blindly click Approve." It's now framed as a *security bug*, not a UX nit. Mitigations: auto-allow low-risk inside policy, group medium-risk, **interrupt only at commit points, show structured evidence, expire grants, and treat denial as a normal path.** Progressive autonomy (agents earn wider permissions as they prove reliable) is the trajectory. ([changkun][changkun], [aipatternbook][fatigue], [developersdigest][secbug], [mindstudio progressive][progressive])

### 3. Claim / lease / lock for shared-file coordination — **lead with this; it's the trap**
The handoff's claim model (`claimed_by` + `claimed_at`, stale auto-release) is a **time-bound lease**, and the canonical literature says leases alone are unsafe for protecting a shared resource:
- **Kleppmann's "How to do distributed locking"** is the definitive warning. A worker can acquire a claim, then be paused (GC, a network stall — a real GitHub incident saw a **90-second** pause) past the lease expiry; a second worker claims it; **both now believe they hold it and corrupt the shared data.** Timeouts can't prevent this. The fix is a **fencing token**: a monotonically increasing number issued on each claim, where the *resource itself* rejects any write carrying a stale token. ([kleppmann][kleppmann])
- Lease mechanics: a lease is a TTL grant kept alive by **heartbeats**; deadlines must use a **monotonic clock** (wall-clock NTP jumps break them). ([singhajit lease][lease], [systemoverflow fencing][fencing])
- **The decisive problem for Lists: a plain filesystem (and especially iCloud) gives you no atomic compare-and-swap and no fencing.** Two writers editing the same `.md` cannot be safely arbitrated by "I wrote `claimed_by` first," because there's no atomic test-and-set on a file's contents. The safe-ish primitive is **atomic `rename()`** (write a temp file, then rename over the target — readers see old-or-new, never half-written), but rename only gives atomicity *on one local volume*, not coordination across two independent writers, and not across a sync boundary. ([lwn atomic writes][lwn], [occ wikipedia][occ])
- **iCloud / async sync is the sharp edge.** A May-2026 paper ("Why iCloud Fails", arXiv 2602.19433) documents that cloud sync projects a distributed event graph onto a single linear timeline and **silently destroys information**. Concrete, directly-relevant failure modes:
  - **Last-writer-wins by timestamp**: concurrent edits → the "losing" version is deleted with no record; identical timestamps → arbitrary winner.
  - **Lock-file propagation**: a git `index.lock` synced to another device makes the repo refuse all operations — i.e. a naïve `claimed_by`/lock *file* could itself jam every device.
  - **Numbered-suffix corruption**: on detecting a conflict iCloud renames to `… 2`, which (for git) orphans commits invisibly — an item file renamed to `task 2.md` would silently leave the list.
  - **Non-atomic packages / intermediate-state leakage**: multi-file or mid-save states propagate partially, so a folder-as-list could sync in an inconsistent state. ([icloud paper][icloudpaper], [Apple TN2336][tn2336])
- **Optimistic concurrency** (compare a version/`modified_at` token before writing; if it changed, reconcile) is the realistic software-level mitigation, but it needs a writer who *checks before writing* — which an external worker, by definition, you don't fully control. ([occ wikipedia][occ], [solr occ][solrocc])

### 4. Liveness / heartbeat (the `_status.md` freshness dot)
The handoff's `last_active` → green/amber/red dot is a textbook **heartbeat/liveness** indicator and is the *right* shape: cheap, file-driven, no model calls. Standard caveats apply: it tells you the worker *was* alive at `last_active`, not that its claim is still valid (see fencing above), and freshness math must tolerate clock skew between the worker's host and the iOS device. Don't infer "safe to take over" purely from a stale dot. ([lease][lease], [kleppmann][kleppmann])

### 5. Reality check — what's real vs hypothetical
- **OpenClaw — REAL.** Open-source (MIT), created by **Peter Steinberger** (Nov 2025 as "Clawdbot" → Moltbot → OpenClaw Jan 2026); **~247k GitHub stars by Mar 2026**; Steinberger **joined OpenAI in Feb 2026** with a foundation taking stewardship. **But:** it's a **messaging-centric** self-hosted gateway (WhatsApp/Telegram/Slack/Discord/Signal/iMessage…) connecting chat apps to an LLM with a skills system; its workspace is `~/.openclaw/workspace` with `AGENTS.md`/`SOUL.md`/`TOOLS.md`. It runs headless (launchd/systemd) and reads/writes files in its workspace — but it is **not** a "watch a list folder and work the tasks" product. ([wikipedia openclaw][openclaw], [github openclaw][ocgh], [kdnuggets][kdn])
- **Hermes (Nous Research) — REAL.** Open-source (MIT), released Feb 2026; an autonomous background agent with persistent memory and self-created skills, designed to run on a VPS unattended; multi-platform (Telegram/Discord/Slack/CLI). Again messaging/skill-centric, not a list-file worker. ([hermes-agent.org][hermes], [nous github][hermesgh])
- **So who would a real "BYO worker" be?** The honest answer is the headless coding/agent CLIs that already read & write local files:
  - **Claude Code headless** (`claude -p …`, non-interactive, scriptable, file-based plans/tasks). ([code.claude.com headless][cchl])
  - **Aider** (Apache-2.0, ~41k stars, edits files via diffs directly on the filesystem, no container). ([frontman][frontman])
  - **OpenHands** (mount your dir to `/workspace`; CLI + headless SDK; can run on local models). ([openhands][openhands])
  - Others in the terminal-agent ecosystem: Goose, OpenCode, Gemini CLI, Codex CLI. ([awesome-cli][awesomecli])
  - **Implication:** market the agent-list as "point *any* file-capable agent at this folder via a documented protocol," not "works with OpenClaw/Hermes." Using those two names verbatim risks looking like a misread of what they are.

### 6. Multi-agent on a shared workspace — the trend is *isolation*, not shared-write
"Git worktrees per agent" became load-bearing for AI coding in **Q1 2026**: when multiple agents share one working directory they overwrite each other, so each agent gets **its own worktree/branch sharing one `.git`**. Tools: **Claude Code** built-in worktree support (`isolation: worktree` on a subagent); **Conductor** (Melty Labs, Mac app orchestrating parallel Claude Code/Codex agents in isolated worktrees); **Claude Squad** (Go TUI managing Claude/Codex/Aider/Gemini, one worktree each). The lesson for the agent-list: **the industry's answer to "multiple writers" is to give each writer its own space and merge later — not to add a lock to a shared folder.** ([code.claude.com worktrees][ccwt], [nimbalyst][nimbalyst], [conductor][conductor], [claudesquad][squad])

## Implications for Lists ← the most important section

**Framing first.** "Agent integrations inside the app" is already in PRODUCT-SPEC's **Deferred** list, and today's data is app-private (not Files.app/iCloud-visible). That's the correct posture: this is a strong *future* direction, and the deferral is protective, because the moment a list folder becomes reachable by an external worker you inherit every concurrency hazard above. Pressure-test, don't build yet.

1. **Lead with the two-writer problem — it's the load-bearing risk.** A claim written as a plain frontmatter field (`claimed_by`/`claimed_at`) is a lease without a fence; on a plain volume it's racy, and over iCloud it's unsafe (silent last-writer-wins, `… 2` renames that would orphan an item out of its list, `index.lock`-style jams). **Recommendation:** (a) keep agent lists **strictly single-writer at a time** and **local-only** — never run the worker against an iCloud-synced copy; (b) require all writes (app *and* worker) to use **write-temp-then-atomic-`rename`**; (c) make the claim **advisory + optimistic**: a worker must re-read and check `modified_at`/a `claim_seq` *immediately before* each write and abort on mismatch — your existing `modified_at` field is the natural concurrency anchor; (d) if you ever want true safety, the worker needs a **fencing/sequence token** that the app's writer also honours. Frame to Saxon as: *"Two programs editing the same files is like two people editing the same paper doc with no track-changes — someone's edit silently vanishes. We avoid it by letting only one work at a time, on this device only, and by writing files in a way that can't half-save."*

2. **Borrow the Agent-Inbox vocabulary for the `question` item, and make `risk` gate friction, not noise.** The handoff's question type (`yes_no`/`choice`/`text`, tick/cross, chips, expandable "other") is well-aligned with Agent Inbox's **Accept / Edit / Respond / Ignore** and `description`-as-markdown. Map cleanly: `yes_no`→Accept/Reject, `choice`→chips, `text`→Respond, always-available "other"→Edit/Respond. **Use `risk: high` only to add a confirm step on costly/irreversible answers** — because the #1 documented failure is **approval fatigue**: ask too often and Saxon rubber-stamps. Practically: default most questions to `low` (one-tap), reserve `high` for destructive/external effects, **batch low-risk questions** in the "Needs Attention" section, and show **structured evidence** (what will happen) rather than raw payloads. The four-section layout (Needs Attention → Working → Scheduled → Completed) is essentially a per-list Agent Inbox and is a good, native fit.

3. **Lean into what Lists already has; don't reinvent it.** `created_by` (already defaults to `"human"`) is your **agent-provenance** field — set it to the worker id so agent-made items are visibly attributable and filterable. `parentId`/`parent` already supports **question-as-child-of-task** exactly as sketched. Tombstones already exist for delete reconciliation. Habit recurrence can drive **recurring agent jobs** as proposed (each fire spawns a child task → normal Working→Completed history) — that reuse is clean. Consider adopting **Claude Code's `block`/DAG idea**: a parent task in "Needs Attention" is simply *blocked by* an unanswered `question` child; answering unblocks it. This gives you precise, file-expressible dependencies without new machinery.

4. **`_status.md` heartbeat: keep it, but be honest about what it proves.** Green/amber/red from `last_active` is the right, cheap, file-only liveness cue. **Don't let a stale dot auto-authorise takeover of a claim** (that's the fencing trap). Tolerate clock skew between the worker's machine and the iOS device in the freshness thresholds. Reading the file directly on change (no model calls) is correct and on-brand for "calm/native/private."

5. **Position as worker-agnostic against *real* BYO agents; drop the brandnames.** Ship a documented **file protocol** (frontmatter fields + section semantics + claim/heartbeat rules) and validate it by scripting **Claude Code headless / Aider / OpenHands** at a list folder. Saying "works with OpenClaw/Hermes" is inaccurate — those are messaging-app agents, not list-file workers — and would undercut credibility. `worker_type: local_byo | hosted` is fine, but note **`hosted` reintroduces the network/sync two-writer hazard** and should be gated behind the (paid, future) sync work, not local mode.

6. **Sequencing.** This rides on top of the deferred **Lists Sync** decision and an eventual decision to expose files. Order: (i) finalize the **single-writer, atomic-rename, optimistic-check** contract on local files; (ii) prototype the **question/Needs-Attention inbox UX** with a scripted headless worker; (iii) only then consider `hosted`/sync, with fencing tokens, as part of paid sync.

## Open questions / things to validate

- **Where does the worker run relative to the files?** On-device background execution is constrained on iOS; the realistic v1 is a worker on a Mac/VPS pointed at an *exported / synced* copy — which is exactly the unsafe path. Is the intended v1 actually "Mac companion app reads the same folder"? That choice decides whether the concurrency risk is theoretical or immediate.
- **Is there ever genuine concurrency, or can it be serialised?** If the app and worker never write at the same instant (e.g., worker only writes when the app is backgrounded, app only when worker is idle), most of the hazard evaporates. Can a simple "whose turn" token enforce that cheaply?
- **Fencing without a server:** is a monotonically-increasing `claim_seq` in frontmatter, honoured by *both* writers, "good enough" given there's no central authority — or does honest safety require the future sync service to act as the arbiter?
- **iOS background-execution limits** for any on-device worker, and whether `last_active` can even be updated reliably while the app isn't foregrounded.
- **Does exposing agent-written files break the privacy promise?** A hosted worker = data leaves the device. Confirm `hosted` is strictly opt-in and ideally bundled with the paid-sync trust boundary.
- **Validate the OpenClaw/Hermes capabilities first-hand** before any public claim — both are young (released late-2025/early-2026) and moving fast; their file/headless stories may change.

## Sources
- [How to Build Your AGENTS.md (2026) — Augment Code][agentsmd]
- [github/spec-kit AGENTS.md][speckit]
- [Spec-Driven Development — BCMS][sdd]
- [Claude Code plan mode docs][ccplan]
- [What Actually Is Claude Code's Plan Mode — Armin Ronacher][planmode]
- [Claude Code Tasks update — VentureBeat][cctasks]
- [Run Claude Code programmatically (headless) — Claude Code Docs][cchl]
- [Run parallel sessions with worktrees — Claude Code Docs][ccwt]
- [LangChain Agent Inbox README][inbox]
- [LangChain Human-in-the-loop docs][lchitl]
- [Introducing ambient agents — LangChain][ambient]
- [Devin 2.1 — Cognition][devin21]
- [Ask Devin — Devin Docs][devindocs]
- [OpenAI Codex vs Cursor 2026 — NxCode][nxcode]
- [Cursor Background Agents — Morph][morph]
- [HITL approval workflows / risk tiers — Truto][truto]
- [Confirmation Fatigue and the Protocol Gap — Changkun][changkun]
- [Approval Fatigue — Encyclopedia of Agentic Coding Patterns][fatigue]
- [Approval Fatigue Is an Agent Security Bug — Developers Digest][secbug]
- [Progressive Autonomy for AI Agents — MindStudio][progressive]
- [How to do distributed locking — Martin Kleppmann][kleppmann]
- [Lease Pattern in Distributed Systems — Ajit Singh][lease]
- [Fencing Tokens — System Overflow][fencing]
- [A way to do atomic writes — LWN][lwn]
- [Optimistic concurrency control — Wikipedia][occ]
- [Optimistic Concurrency — Solr][solrocc]
- [Why iCloud Fails (arXiv 2602.19433)][icloudpaper]
- [Apple TN2336 — Handling version conflicts in iCloud][tn2336]
- [OpenClaw — Wikipedia][openclaw]
- [OpenClaw — GitHub][ocgh]
- [OpenClaw Explained — KDnuggets][kdn]
- [Hermes Agent — official site][hermes]
- [Hermes Agent — Nous Research GitHub][hermesgh]
- [Aider/OpenHands & open-source coding tools — Frontman][frontman]
- [OpenHands — official site][openhands]
- [awesome-cli-coding-agents — GitHub][awesomecli]
- [Best Git Worktree Tools for AI Coding 2026 — Nimbalyst][nimbalyst]
- [Conductor.build intro — CodePick][conductor]
- [Claude Squad — DEV Community][squad]

[agentsmd]: https://www.augmentcode.com/guides/how-to-build-agents-md
[speckit]: https://github.com/github/spec-kit/blob/main/AGENTS.md
[sdd]: https://thebcms.com/blog/spec-driven-development
[ccplan]: https://codewithmukesh.com/blog/plan-mode-claude-code/
[planmode]: https://lucumr.pocoo.org/2025/12/17/what-is-plan-mode/
[cctasks]: https://venturebeat.com/orchestration/claude-codes-tasks-update-lets-agents-work-longer-and-coordinate-across
[cchl]: https://code.claude.com/docs/en/headless
[ccwt]: https://code.claude.com/docs/en/worktrees
[inbox]: https://github.com/langchain-ai/agent-inbox/blob/main/README.md
[lchitl]: https://docs.langchain.com/oss/python/langchain/human-in-the-loop
[ambient]: https://blog.langchain.com/introducing-ambient-agents/
[devin21]: https://cognition.ai/blog/devin-2-1
[devindocs]: https://docs.devin.ai/work-with-devin/ask-devin
[nxcode]: https://www.nxcode.io/resources/news/openai-codex-vs-cursor-which-coding-agent-2026
[morph]: https://www.morphllm.com/cursor-background-agents
[truto]: https://truto.one/blog/implementing-human-in-the-loop-approval-workflows-for-consequential-saas-api-actions/
[changkun]: https://changkun.de/blog/ideas/human-in-the-loop-agents/
[fatigue]: https://aipatternbook.com/approval-fatigue
[secbug]: https://www.developersdigest.tech/blog/approval-fatigue-agent-security-bug
[progressive]: https://www.mindstudio.ai/blog/progressive-autonomy-ai-agents-safe-deployment
[kleppmann]: https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html
[lease]: https://singhajit.com/distributed-systems/lease/
[fencing]: https://www.systemoverflow.com/learn/distributed-primitives/distributed-locks/fencing-tokens-preventing-split-brain-operations
[lwn]: https://lwn.net/Articles/789600/
[occ]: https://en.wikipedia.org/wiki/Optimistic_concurrency_control
[solrocc]: https://yonik.com/solr/optimistic-concurrency/
[icloudpaper]: https://arxiv.org/html/2602.19433v3
[tn2336]: https://developer.apple.com/library/archive/technotes/tn2336/_index.html
[openclaw]: https://en.wikipedia.org/wiki/OpenClaw
[ocgh]: https://github.com/openclaw/openclaw
[kdn]: https://www.kdnuggets.com/openclaw-explained-the-free-ai-agent-tool-going-viral-already-in-2026
[hermes]: https://hermes-agent.org/
[hermesgh]: https://github.com/nousresearch/hermes-agent
[frontman]: https://frontman.sh/blog/best-open-source-ai-coding-tools-2026/
[openhands]: https://www.openhands.dev/
[awesomecli]: https://github.com/bradAGI/awesome-cli-coding-agents
[nimbalyst]: https://nimbalyst.com/blog/best-git-worktree-tools-ai-coding-2026/
[conductor]: https://codepick.dev/en/guides/conductor-build-intro
[squad]: https://dev.to/stevengonsalvez/claude-squad-run-multiple-ai-agents-in-parallel-without-the-mess-1hfl
